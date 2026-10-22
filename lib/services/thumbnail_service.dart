import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';

class LocalThumbnailService {
  static final Directory _thumbDir = Directory('.cache/thumbnails');
  static final Directory _posterDir = Directory('.cache/posters');
  static bool _hasFfmpeg = true;
  static bool _checkedFfmpeg = false;

  /// Ensure local cache directories exist
  static Future<void> init() async {
    try {
      if (!await _thumbDir.exists()) {
        await _thumbDir.create(recursive: true);
      }
      if (!await _posterDir.exists()) {
        await _posterDir.create(recursive: true);
      }
    } catch (e) {
      debugPrint('Error creating cache directories: $e');
    }
  }

  /// Get the local file path for a video thumbnail
  static String getThumbnailPath(String videoPath) {
    final hash = videoPath.toLowerCase().hashCode.abs();
    return '${_thumbDir.path}${Platform.pathSeparator}thumb_$hash.jpg';
  }

  /// Check if local thumbnail already exists for a video
  static bool hasThumbnail(String videoPath) {
    final path = getThumbnailPath(videoPath);
    return File(path).existsSync();
  }

  /// Check if ffmpeg is accessible on system
  static Future<bool> _isFfmpegAvailable() async {
    if (_checkedFfmpeg) return _hasFfmpeg;
    try {
      final res = await Process.run('ffmpeg', ['-version']);
      _hasFfmpeg = res.exitCode == 0;
    } catch (_) {
      _hasFfmpeg = false;
    }
    _checkedFfmpeg = true;
    return _hasFfmpeg;
  }

  /// Extract local thumbnail frame at 40s from video file
  static Future<String?> extractThumbnail(String videoPath) async {
    if (videoPath.isEmpty || videoPath.startsWith('asset:')) return null;

    final videoFile = File(videoPath);
    if (!videoFile.existsSync()) return null;

    await init();
    final outPath = getThumbnailPath(videoPath);
    final outFile = File(outPath);

    // If already generated, return instantly!
    if (outFile.existsSync() && outFile.lengthSync() > 0) {
      return outPath;
    }

    // 1. Try fast local extraction with ffmpeg
    if (await _isFfmpegAvailable()) {
      try {
        final res = await Process.run('ffmpeg', [
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
        if (res.exitCode == 0 && outFile.existsSync()) {
          return outPath;
        }
      } catch (e) {
        debugPrint('ffmpeg extraction failed: $e');
      }
    }

    // 2. Fallback extraction using media_kit screenshot
    try {
      final player = Player();
      await player.open(Media(videoPath), play: false);
      await player.seek(const Duration(seconds: 40));
      // Give libmpv a few milliseconds to decode frame
      await Future.delayed(const Duration(milliseconds: 300));
      final bytes = await player.screenshot(format: 'image/jpeg');
      await player.dispose();

      if (bytes != null && bytes.isNotEmpty) {
        await outFile.writeAsBytes(bytes);
        return outPath;
      }
    } catch (e) {
      debugPrint('MediaKit screenshot extraction failed: $e');
    }

    return null;
  }

  /// Download and cache online poster to local disk so it loads in 1ms without internet
  static Future<String?> cachePoster(String? url) async {
    if (url == null || url.isEmpty) return null;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return url; // Already local file
    }

    await init();
    final hash = url.hashCode.abs();
    final localPath = '${_posterDir.path}${Platform.pathSeparator}poster_$hash.jpg';
    final file = File(localPath);

    if (file.existsSync() && file.lengthSync() > 0) {
      return localPath;
    }

    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        await file.writeAsBytes(res.bodyBytes);
        return localPath;
      }
    } catch (e) {
      debugPrint('Error caching poster from $url: $e');
    }

    return url; // Fallback to network URL if download failed
  }
}
