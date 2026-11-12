import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'thumbnail_service.dart';

class VideoChapter {
  final String title;
  final Duration start;
  final Duration end;

  const VideoChapter({
    required this.title,
    required this.start,
    required this.end,
  });

  bool get isIntro {
    final t = title.toLowerCase().trim();
    return t.contains('intro') ||
        t.contains('opening') ||
        t == 'op' ||
        t.startsWith('op ') ||
        t.endsWith(' op') ||
        t.contains('ncop');
  }

  bool get isEnding {
    final t = title.toLowerCase().trim();
    return t.contains('ending') ||
        t.contains('credit') ||
        t == 'ed' ||
        t.startsWith('ed ') ||
        t.endsWith(' ed') ||
        t.contains('nced');
  }

  @override
  String toString() => 'VideoChapter(title: $title, start: $start, end: $end)';
}

class ChapterService {
  ChapterService._();
  static final ChapterService instance = ChapterService._();

  static final Map<String, List<VideoChapter>> _cache = {};

  /// Extract embedded chapter markers from video file using fast ffmpeg container inspection
  Future<List<VideoChapter>> getChapters(String videoPath) async {
    if (videoPath.isEmpty || videoPath.startsWith('asset:')) return [];
    if (_cache.containsKey(videoPath)) {
      return _cache[videoPath]!;
    }

    final ffmpegExec = await LocalThumbnailService.getFfmpegExecutable();
    if (ffmpegExec == null) return [];

    try {
      final res = await Process.run(ffmpegExec, ['-i', videoPath]);
      final output = res.stderr.toString();
      final chapters = parseChaptersFromFfmpegOutput(output);
      _cache[videoPath] = chapters;
      return chapters;
    } catch (e) {
      debugPrint('Error extracting chapters: $e');
      return [];
    }
  }

  static List<VideoChapter> parseChaptersFromFfmpegOutput(String output) {
    final List<VideoChapter> result = [];
    final lines = const LineSplitter().convert(output);

    Duration? currentStart;
    Duration? currentEnd;
    String? currentTitle;

    final startEndRegex = RegExp(r'Chapter #\d+:\d+: start ([\d.]+), end ([\d.]+)');
    final titleRegex = RegExp(r'title\s*:\s*(.+)');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      final match = startEndRegex.firstMatch(line);
      if (match != null) {
        if (currentStart != null && currentEnd != null) {
          result.add(
            VideoChapter(
              title: currentTitle ?? 'Chapter ${result.length + 1}',
              start: currentStart,
              end: currentEnd,
            ),
          );
        }

        final startSec = double.tryParse(match.group(1)!) ?? 0.0;
        final endSec = double.tryParse(match.group(2)!) ?? 0.0;
        currentStart = Duration(milliseconds: (startSec * 1000).toInt());
        currentEnd = Duration(milliseconds: (endSec * 1000).toInt());
        currentTitle = null;
        continue;
      }

      if (currentStart != null) {
        final tMatch = titleRegex.firstMatch(line);
        if (tMatch != null) {
          currentTitle = tMatch.group(1)!.trim();
        }
      }
    }

    if (currentStart != null && currentEnd != null) {
      result.add(
        VideoChapter(
          title: currentTitle ?? 'Chapter ${result.length + 1}',
          start: currentStart,
          end: currentEnd,
        ),
      );
    }

    return result;
  }
}

