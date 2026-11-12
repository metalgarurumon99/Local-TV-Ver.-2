import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
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
  ui.Image? decodedImage;

  TrickplayData({
    required this.imagePath,
    this.cols = 10,
    this.rows = 10,
    this.tileWidth = 160.0,
    this.tileHeight = 90.0,
    required this.totalDuration,
    this.decodedImage,
  }) : totalTiles = cols * rows;

  Rect getTileRect(Duration position) {
    if (totalDuration.inMilliseconds <= 0 || totalTiles <= 0) return Rect.zero;
    final fraction = (position.inMilliseconds / totalDuration.inMilliseconds).clamp(0.0, 0.9999);
    final index = (fraction * totalTiles).floor().clamp(0, totalTiles - 1);
    final col = index % cols;
    final row = index ~/ cols;
    return Rect.fromLTWH(col * tileWidth, row * tileHeight, tileWidth, tileHeight);
  }
}

class TrickplayService {
  TrickplayService._();
  static final TrickplayService instance = TrickplayService._();

  static final Map<String, TrickplayData> _memoryCache = {};
  static final Map<String, Future<TrickplayData?>> _inFlight = {};

  static Directory get _trickplayDir {
    final direct = Directory('.cache/trickplay');
    if (direct.existsSync()) return direct;
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final resolved = Directory('$exeDir${Platform.pathSeparator}.cache${Platform.pathSeparator}trickplay');
      if (resolved.existsSync()) return resolved;
    } catch (_) {}
    return direct;
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
      final cached = _memoryCache[videoPath]!;
      if (cached.decodedImage != null) return cached;
      // Load decoded image if needed
      if (File(cached.imagePath).existsSync()) {
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
        _memoryCache[videoPath] = res;
      }
      return res;
    } finally {
      _inFlight.remove(videoPath);
    }
  }

  Future<TrickplayData?> _processTrickplay(String videoPath, Duration duration) async {
    try {
      if (!_trickplayDir.existsSync()) {
        await _trickplayDir.create(recursive: true);
      }

      final outPath = _getSpritePath(videoPath);
      final outFile = File(outPath);

      const int cols = 10;
      const int rows = 10;
      const int totalFrames = cols * rows;

      if (!outFile.existsSync() || (await outFile.length()) == 0) {
        final ffmpeg = await LocalThumbnailService.getFfmpegExecutable();
        if (ffmpeg == null) return null;

        // Calculate sample interval in seconds so totalFrames covers the entire duration
        final double intervalSec = (duration.inSeconds / totalFrames).clamp(1.0, 60.0);
        final fpsArg = 'fps=1/$intervalSec,scale=160:90,tile=${cols}x$rows';

        final res = await Process.run(
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
        );

        if (res.exitCode != 0 || !outFile.existsSync() || (await outFile.length()) == 0) {
          debugPrint('Trickplay ffmpeg failed: ${res.stderr}');
          return null;
        }
      }

      final decoded = await _decodeImageFile(outFile);
      if (decoded == null) return null;

      final data = TrickplayData(
        imagePath: outPath,
        cols: cols,
        rows: rows,
        tileWidth: 160.0,
        tileHeight: 90.0,
        totalDuration: duration,
        decodedImage: decoded,
      );

      return data;
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
