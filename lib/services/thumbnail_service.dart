import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';

class FfmpegRunResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  const FfmpegRunResult(this.exitCode, this.stdout, this.stderr);
}

class _QueuedExtraction {
  final Future<void> Function() run;
  final void Function() cancel;
  _QueuedExtraction(this.run, this.cancel);
}

class LocalThumbnailService {
  static Directory _resolveAppDirectory(String relativeName) {
    final direct = Directory(relativeName);
    if (direct.existsSync()) return direct;

    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final resolved = Directory('$exeDir${Platform.pathSeparator}$relativeName');
      if (resolved.existsSync()) return resolved;
      if (!kDebugMode) return resolved;
    } catch (_) {}

    return direct;
  }

  static Directory? _cachedThumbDir;
  static Directory? _cachedPosterDir;
  static Directory? _cachedLogoDir;

  static Directory get _thumbDir => _cachedThumbDir ??= _resolveAppDirectory('.cache/thumbnails');
  static Directory get _posterDir => _cachedPosterDir ??= _resolveAppDirectory('.cache/posters');
  static Directory get _logoDir => _cachedLogoDir ??= _resolveAppDirectory('.cache/logos');
  static bool _dirsInitialized = false;

  /// Run ffmpeg with a hard timeout, killing the child process if it hangs.
  static Future<FfmpegRunResult?> runFfmpegWithTimeout(
    String executable,
    List<String> args, {
    Duration timeout = const Duration(seconds: 25),
  }) async {
    Process? process;
    try {
      process = await Process.start(executable, args);
      final stdoutFuture = process.stdout.transform(utf8.decoder).join();
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode.timeout(timeout);
      final out = await stdoutFuture;
      final err = await stderrFuture;
      return FfmpegRunResult(exitCode, out, err);
    } on TimeoutException {
      debugPrint('ffmpeg timed out after ${timeout.inSeconds}s, killing process');
      try {
        process?.kill(ProcessSignal.sigkill);
      } catch (_) {}
      return null;
    } catch (e) {
      debugPrint('ffmpeg process error: $e');
      try {
        process?.kill();
      } catch (_) {}
      return null;
    }
  }

  /// In-memory cache of file existence checks to avoid synchronous disk I/O
  /// (`File.existsSync()`) inside widget `build()` methods during scrolling.
  static final Map<String, bool> _fileExistsCache = <String, bool>{};
  static final Map<String, Future<String?>> _inFlight = <String, Future<String?>>{};
  static final List<_QueuedExtraction> _extractionQueue = [];
  static bool _isProcessingExtractionQueue = false;

  /// Enqueue an ffmpeg extraction job to prevent concurrent disk I/O thrashing.
  static Future<T?> _enqueueExtraction<T>(Future<T?> Function() job) {
    final completer = Completer<T?>();
    _extractionQueue.add(
      _QueuedExtraction(
        () async {
          if (completer.isCompleted) return;
          try {
            final result = await job();
            if (!completer.isCompleted) completer.complete(result);
          } catch (e, st) {
            if (!completer.isCompleted) completer.completeError(e, st);
          }
        },
        () {
          if (!completer.isCompleted) completer.complete(null);
        },
      ),
    );
    _drainExtractionQueue();
    return completer.future;
  }

  static Future<void> _drainExtractionQueue() async {
    if (_isProcessingExtractionQueue) return;
    _isProcessingExtractionQueue = true;
    while (_extractionQueue.isNotEmpty) {
      final job = _extractionQueue.removeAt(0);
      try {
        await job.run();
      } catch (_) {}
    }
    _isProcessingExtractionQueue = false;
  }

  /// Cancel all pending extraction jobs when leaving a dialog/screen,
  /// completing their futures with null so callers and `_inFlight` never leak.
  static void cancelPendingExtractions() {
    final pending = List<_QueuedExtraction>.from(_extractionQueue);
    _extractionQueue.clear();
    for (final item in pending) {
      item.cancel();
    }
  }

  /// Fast cached check whether a local file exists.
  static bool fileExistsCached(String? path) {
    if (path == null || path.isEmpty) return false;
    final cached = _fileExistsCache[path];
    if (cached != null) return cached;
    final file = resolveFile(path);
    final exists = file.existsSync();
    _fileExistsCache[path] = exists;
    return exists;
  }

  /// Robust resolution of cached image paths (handles relative .cache paths across working directory shifts).
  static File resolveFile(String rawPath) {
    if (rawPath.isEmpty) return File('');
    final normalized = rawPath.replaceAll('/', Platform.pathSeparator).replaceAll('\\', Platform.pathSeparator);
    final direct = File(normalized);
    if (direct.existsSync()) return direct;

    if (!direct.isAbsolute) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final resolved = File('$exeDir${Platform.pathSeparator}$normalized');
      if (resolved.existsSync()) return resolved;
    }

    return direct;
  }

  /// Update or invalidate the file existence cache for a path.
  static void markFileExists(String path, [bool exists = true]) {
    if (path.isNotEmpty) {
      _fileExistsCache[path] = exists;
    }
  }

  /// Clear cached file existence entries (e.g., on manual rescan).
  static void clearExistenceCache() {
    _fileExistsCache.clear();
  }

  /// Ensure local cache directories exist
  static Future<void> init() async {
    if (_dirsInitialized) return;
    try {
      if (!await _thumbDir.exists()) {
        await _thumbDir.create(recursive: true);
      }
      if (!await _posterDir.exists()) {
        await _posterDir.create(recursive: true);
      }
      if (!await _logoDir.exists()) {
        await _logoDir.create(recursive: true);
      }
      _dirsInitialized = true;
    } catch (e) {
      debugPrint('Error creating cache directories: $e');
    }
  }

  /// Get the local file path for a video thumbnail
  static String getThumbnailPath(String videoPath) {
    final hash = videoPath.toLowerCase().hashCode.abs();
    return '${_thumbDir.path}${Platform.pathSeparator}thumb_$hash.jpg';
  }

  /// Check if local thumbnail already exists for a video (cached in memory)
  static bool hasThumbnail(String videoPath) {
    if (videoPath.isEmpty) return false;
    final path = getThumbnailPath(videoPath);
    return fileExistsCached(path);
  }

  static String? _resolvedFfmpegPath;

  /// Find and return valid ffmpeg command or absolute executable path
  static Future<String?> getFfmpegExecutable() async {
    if (_resolvedFfmpegPath != null) return _resolvedFfmpegPath;

    // 1. Try global PATH command
    try {
      final res = await Process.run('ffmpeg', ['-version']);
      if (res.exitCode == 0) {
        _resolvedFfmpegPath = 'ffmpeg';
        return 'ffmpeg';
      }
    } catch (_) {}

    // 2. Try common system/software installation paths on Windows
    final candidates = [
      r'C:\Program Files (x86)\XDM\ffmpeg.exe',
      r'C:\Program Files\ffmpeg\bin\ffmpeg.exe',
      r'C:\ffmpeg\bin\ffmpeg.exe',
      r'C:\ProgramData\chocolatey\bin\ffmpeg.exe',
    ];

    for (final path in candidates) {
      if (File(path).existsSync()) {
        try {
          final res = await Process.run(path, ['-version']);
          if (res.exitCode == 0) {
            _resolvedFfmpegPath = path;
            return path;
          }
        } catch (_) {}
      }
    }

    return null;
  }

  /// Check if ffmpeg is accessible on system
  static Future<bool> isFfmpegAvailable() async {
    final exec = await getFfmpegExecutable();
    return exec != null;
  }

  static final Map<String, String> _videoDurationCache = {};

  /// Extract video duration directly from the video file using ffmpeg
  static Future<String?> getVideoDuration(String videoPath) async {
    if (videoPath.isEmpty || videoPath.startsWith('asset:')) return null;
    if (_videoDurationCache.containsKey(videoPath)) {
      return _videoDurationCache[videoPath];
    }

    final ffmpegExec = await getFfmpegExecutable();
    if (ffmpegExec == null) return null;

    try {
      final res = await Process.run(ffmpegExec, ['-i', videoPath]);
      final output = res.stderr.toString();
      final match = RegExp(r'Duration:\s*(\d{2}):(\d{2}):(\d{2})').firstMatch(output);
      if (match != null) {
        final hours = int.tryParse(match.group(1)!) ?? 0;
        final minutes = int.tryParse(match.group(2)!) ?? 0;
        final seconds = int.tryParse(match.group(3)!) ?? 0;

        String formatted;
        if (hours > 0) {
          formatted = '${hours}h ${minutes}m';
        } else if (minutes > 0) {
          formatted = '${minutes}m';
        } else {
          formatted = '${seconds}s';
        }
        _videoDurationCache[videoPath] = formatted;
        return formatted;
      }
    } catch (_) {}
    return null;
  }

  /// Extract local thumbnail frame at 40s from video file.
  /// Deduplicates in-flight extractions for identical video paths.
  static Future<String?> extractThumbnail(
    String videoPath, {
    bool allowPlayerFallback = false,
  }) async {
    if (videoPath.isEmpty || videoPath.startsWith('asset:')) return null;

    final inFlightFuture = _inFlight[videoPath];
    if (inFlightFuture != null) {
      return inFlightFuture;
    }

    final future = _enqueueExtraction(() => _doExtractThumbnail(videoPath, allowPlayerFallback: allowPlayerFallback));
    _inFlight[videoPath] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(videoPath);
    }
  }

  static Future<String?> _doExtractThumbnail(
    String videoPath, {
    bool allowPlayerFallback = false,
  }) async {
    if (!fileExistsCached(videoPath)) return null;

    await init();
    final outPath = getThumbnailPath(videoPath);

    if (fileExistsCached(outPath)) {
      return outPath;
    }

    final outFile = File(outPath);
    if (await outFile.exists() && await outFile.length() > 0) {
      markFileExists(outPath, true);
      return outPath;
    }

    // 1. Fast local extraction with ffmpeg (if installed on system)
    final ffmpegExec = await getFfmpegExecutable();
    if (ffmpegExec != null) {
      try {
        final res = await runFfmpegWithTimeout(ffmpegExec, [
          '-ss',
          '00:00:40',
          '-i',
          videoPath,
          '-vframes',
          '1',
          '-q:v',
          '3',
          '-vf',
          'scale=480:-1',
          outPath,
          '-y',
        ]);
        if (res != null && res.exitCode == 0 && await outFile.exists() && await outFile.length() > 0) {
          markFileExists(outPath, true);
          return outPath;
        }

        // Retry at 10s if 40s was beyond duration or failed
        final retry = await runFfmpegWithTimeout(ffmpegExec, [
          '-ss',
          '00:00:10',
          '-i',
          videoPath,
          '-vframes',
          '1',
          '-q:v',
          '3',
          '-vf',
          'scale=480:-1',
          outPath,
          '-y',
        ]);
        if (retry != null && retry.exitCode == 0 && await outFile.exists() && await outFile.length() > 0) {
          markFileExists(outPath, true);
          return outPath;
        }
      } catch (e) {
        debugPrint('ffmpeg extraction failed: $e');
      }
    }

    // 2. Fallback extraction using media_kit screenshot (only when explicitly allowed)
    if (!allowPlayerFallback) {
      return null;
    }

    Player? player;
    try {
      player = Player();
      await player.open(Media(videoPath), play: false);
      await player.seek(const Duration(seconds: 40));
      await Future.delayed(const Duration(milliseconds: 250));
      final bytes = await player.screenshot(format: 'image/jpeg');

      if (bytes != null && bytes.isNotEmpty) {
        await outFile.writeAsBytes(bytes);
        markFileExists(outPath, true);
        return outPath;
      }
    } catch (e) {
      debugPrint('MediaKit screenshot extraction failed: $e');
    } finally {
      await player?.dispose();
    }

    return null;
  }

  /// Extract a high quality 16:9 local backdrop image from video file (at ~15% or 60s)
  static Future<String?> extractBackdrop(String videoPath) async {
    if (videoPath.isEmpty || videoPath.startsWith('asset:')) return null;
    if (!fileExistsCached(videoPath)) return null;

    await init();
    final hash = videoPath.toLowerCase().hashCode.abs();
    final outPath = '${_posterDir.path}${Platform.pathSeparator}backdrop_$hash.jpg';

    if (fileExistsCached(outPath)) {
      return outPath;
    }
    final outFile = File(outPath);
    if (await outFile.exists() && await outFile.length() > 0) {
      markFileExists(outPath, true);
      return outPath;
    }

    final inFlightFuture = _inFlight['backdrop-$videoPath'];
    if (inFlightFuture != null) {
      return inFlightFuture;
    }

    final future = _enqueueExtraction(() => _doExtractBackdrop(videoPath, outPath, outFile));
    _inFlight['backdrop-$videoPath'] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove('backdrop-$videoPath');
    }
  }

  static Future<String?> _doExtractBackdrop(String videoPath, String outPath, File outFile) async {
    final ffmpegExec = await getFfmpegExecutable();
    if (ffmpegExec != null) {
      try {
        final res = await Process.run(ffmpegExec, [
          '-ss',
          '00:01:30',
          '-i',
          videoPath,
          '-vframes',
          '1',
          '-q:v',
          '2',
          '-vf',
          "scale='min(1280,iw)':-2",
          outPath,
          '-y',
        ]);
        if (res.exitCode == 0 && await outFile.exists() && await outFile.length() > 0) {
          markFileExists(outPath, true);
          return outPath;
        }

        // Retry at 20s if 1:30 was beyond duration
        final retry = await Process.run(ffmpegExec, [
          '-ss',
          '00:00:20',
          '-i',
          videoPath,
          '-vframes',
          '1',
          '-q:v',
          '2',
          '-vf',
          "scale='min(1280,iw)':-2",
          outPath,
          '-y',
        ]);
        if (retry.exitCode == 0 && await outFile.exists() && await outFile.length() > 0) {
          markFileExists(outPath, true);
          return outPath;
        }
      } catch (e) {
        debugPrint('ffmpeg backdrop extraction failed: $e');
      }
    }
    return null;
  }

  /// Download and cache online poster to local disk so it loads in 1ms without internet
  static Future<String?> cachePoster(String? url) async {
    return _cacheAndOptimizeImage(url, dir: _posterDir, prefix: 'poster');
  }

  /// Download and cache online backdrop/banner to local disk
  static Future<String?> cacheBackdrop(String? url) async {
    return _cacheAndOptimizeImage(url, dir: _posterDir, prefix: 'backdrop');
  }

  /// Download and cache online episode still thumbnail to local disk
  static Future<String?> cacheEpisodeStill(String? url) async {
    return _cacheAndOptimizeImage(url, dir: _thumbDir, prefix: 'still');
  }

  /// Download and cache online logo (transparent PNG) to local disk
  static Future<String?> cacheLogo(String? url) async {
    return _cacheAndOptimizeImage(url, dir: _logoDir, prefix: 'logo');
  }

  static Future<String?> _cacheAndOptimizeImage(
    String? url, {
    required Directory dir,
    required String prefix,
  }) async {
    if (url == null || url.isEmpty) return null;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return url; // Already local file
    }

    await init();
    final hash = url.hashCode.abs();
    final isPng = url.toLowerCase().contains('.png');
    final localPath = '${dir.path}${Platform.pathSeparator}${prefix}_$hash.${isPng ? "png" : "jpg"}';

    if (fileExistsCached(localPath)) {
      return localPath;
    }

    // Also check alternate extension if previously saved as .jpg or .png
    final altPath = '${dir.path}${Platform.pathSeparator}${prefix}_$hash.${isPng ? "jpg" : "png"}';
    if (fileExistsCached(altPath)) {
      return altPath;
    }

    final file = File(localPath);
    if (await file.exists() && await file.length() > 0) {
      markFileExists(localPath, true);
      return localPath;
    }

    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        await file.writeAsBytes(res.bodyBytes);
        markFileExists(localPath, true);
        return localPath;
      }
    } catch (e) {
      debugPrint('Error caching image from $url: $e');
    }

    return url; // Fallback to network URL if download failed
  }
}
