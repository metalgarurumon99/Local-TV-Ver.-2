import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'thumbnail_service.dart';

class TrickplayData {
  final String imagePath;
  final int cols;
  final int rows;
  final int totalTiles;
  final double tileWidth;
  final double tileHeight;
  final Duration totalDuration;
  final double intervalSec;
  ui.Image? decodedImage;

  TrickplayData({
    required this.imagePath,
    this.cols = 10,
    this.rows = 10,
    this.tileWidth = 160.0,
    this.tileHeight = 90.0,
    required this.totalDuration,
    double? intervalSec,
    this.decodedImage,
  })  : totalTiles = cols * rows,
        intervalSec = intervalSec ??
            (totalDuration.inSeconds > 0
                ? math.max(0.2, totalDuration.inSeconds / (cols * rows))
                : 1.0);

  Rect getTileRect(Duration position) {
    if (totalDuration.inMilliseconds <= 0 || totalTiles <= 0) return Rect.zero;
    final double posSec = (position.inMilliseconds / 1000.0).clamp(0.0, totalDuration.inMilliseconds / 1000.0);
    final int index = (posSec / intervalSec).floor().clamp(0, totalTiles - 1);
    final col = index % cols;
    final row = index ~/ cols;
    return Rect.fromLTWH(col * tileWidth, row * tileHeight, tileWidth, tileHeight);
  }

  void dispose() {
    decodedImage?.dispose();
    decodedImage = null;
  }
}

class TrickplayService {
  TrickplayService._();
  static final TrickplayService instance = TrickplayService._();

  static const int _maxCachedSprites = 6;
  static final LinkedHashMap<String, TrickplayData> _memoryCache = LinkedHashMap<String, TrickplayData>();
  static final Map<String, Future<TrickplayData?>> _inFlight = {};
  static Directory? _cachedTrickplayDir;

  static Directory get _trickplayDir {
    if (_cachedTrickplayDir != null) return _cachedTrickplayDir!;
    final direct = Directory('.cache/trickplay');
    if (direct.existsSync()) {
      _cachedTrickplayDir = direct;
      return direct;
    }
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final resolved = Directory('$exeDir${Platform.pathSeparator}.cache${Platform.pathSeparator}trickplay');
      if (resolved.existsSync() || !kDebugMode) {
        _cachedTrickplayDir = resolved;
        return resolved;
      }
    } catch (_) {}
    _cachedTrickplayDir = direct;
    return direct;
  }

  static void _putInCache(String key, TrickplayData data) {
    final existing = _memoryCache.remove(key);
    if (existing != null && !identical(existing, data)) {
      existing.dispose();
    }
    _memoryCache[key] = data;
    while (_memoryCache.length > _maxCachedSprites) {
      final oldestKey = _memoryCache.keys.first;
      final evicted = _memoryCache.remove(oldestKey);
      evicted?.dispose();
    }
  }

  static String _getSpritePath(String videoPath) {
    final hash = videoPath.toLowerCase().hashCode.abs();
    return '${_trickplayDir.path}${Platform.pathSeparator}sprite_$hash.jpg';
  }

  /// Get or asynchronously generate trickplay sprite sheet for seekbar preview
  Future<TrickplayData?> getOrGenerateTrickplay(String videoPath, Duration duration) async {
    if (videoPath.isEmpty || videoPath.startsWith('asset:') || duration.inSeconds < 10) {
      return null;
    }

    if (_memoryCache.containsKey(videoPath)) {
      final cached = _memoryCache.remove(videoPath)!;
      _memoryCache[videoPath] = cached; // Mark as most recently used
      if (cached.decodedImage != null) return cached;
      if (await File(cached.imagePath).exists()) {
        cached.decodedImage = await _decodeImageFile(File(cached.imagePath));
        return cached;
      }
    }

    final inFlight = _inFlight[videoPath];
    if (inFlight != null) return inFlight;

    final future = _processTrickplay(videoPath, duration);
    _inFlight[videoPath] = future;
    try {
      final res = await future;
      if (res != null) {
        _putInCache(videoPath, res);
      }
      return res;
    } finally {
      _inFlight.remove(videoPath);
    }
  }

  Future<TrickplayData?> _processTrickplay(String videoPath, Duration duration) async {
    try {
      if (!await _trickplayDir.exists()) {
        await _trickplayDir.create(recursive: true);
      }

      final outPath = _getSpritePath(videoPath);
      final outFile = File(outPath);

      const int cols = 10;
      const int rows = 10;
      const int totalFrames = cols * rows;
      // Cover the entire video duration cleanly (minimum 0.2s interval for short clips, no 60s upper cap for >100min movies)
      final double intervalSec = math.max(0.2, duration.inSeconds / totalFrames);

      if (!await outFile.exists() || (await outFile.length()) == 0) {
        final ffmpeg = await LocalThumbnailService.getFfmpegExecutable();
        if (ffmpeg == null) return null;

        final fpsArg = 'fps=1/$intervalSec,scale=160:90,tile=${cols}x$rows';

        final res = await LocalThumbnailService.runFfmpegWithTimeout(
          ffmpeg,
          [
            '-skip_frame', 'nokey',
            '-i', videoPath,
            '-vf', fpsArg,
            '-frames:v', '1',
            '-q:v', '4',
            outPath,
            '-y',
          ],
          timeout: const Duration(seconds: 60),
        );

        if (res == null || res.exitCode != 0 || !await outFile.exists() || (await outFile.length()) == 0) {
          debugPrint('Trickplay ffmpeg failed: ${res?.stderr ?? "timeout"}');
          return null;
        }
      }

      final decoded = await _decodeImageFile(outFile);
      if (decoded == null) return null;

      return TrickplayData(
        imagePath: outPath,
        cols: cols,
        rows: rows,
        tileWidth: 160.0,
        tileHeight: 90.0,
        totalDuration: duration,
        intervalSec: intervalSec,
        decodedImage: decoded,
      );
    } catch (e) {
      debugPrint('Trickplay error: $e');
      return null;
    }
  }

  static Future<ui.Image?> _decodeImageFile(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final completer = Completer<ui.Image>();
      ui.decodeImageFromList(bytes, (img) => completer.complete(img));
      return await completer.future;
    } catch (e) {
      debugPrint('Failed to decode trickplay image: $e');
      return null;
    }
  }
}

/// Painter to draw a single 160x90 tile from the 10x10 trickplay sprite sheet
class TrickplayTilePainter extends CustomPainter {
  final ui.Image spriteImage;
  final Rect srcRect;

  TrickplayTilePainter({required this.spriteImage, required this.srcRect});

  @override
  void paint(Canvas canvas, Size size) {
    final destRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()..filterQuality = FilterQuality.medium;
    canvas.drawImageRect(spriteImage, srcRect, destRect, paint);
  }

  @override
  bool shouldRepaint(covariant TrickplayTilePainter oldDelegate) {
    return oldDelegate.spriteImage != spriteImage || oldDelegate.srcRect != srcRect;
  }
}
