import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class WatchHistoryEntry {
  final String mediaId;
  final String mediaTitle;
  final String videoPath;
  final String thumbnailPath;
  final String category;
  final bool isSeries;
  final String? episodeId;
  final int? episodeNumber;
  final String? episodeTitle;
  final int positionMs;
  final int durationMs;
  final DateTime lastWatchedAt;
  final bool isCompleted;

  const WatchHistoryEntry({
    required this.mediaId,
    required this.mediaTitle,
    required this.videoPath,
    required this.thumbnailPath,
    this.category = 'films',
    this.isSeries = false,
    this.episodeId,
    this.episodeNumber,
    this.episodeTitle,
    required this.positionMs,
    required this.durationMs,
    required this.lastWatchedAt,
    this.isCompleted = false,
  });

  double get progress {
    if (durationMs <= 0) return 0.0;
    return (positionMs / durationMs).clamp(0.0, 1.0);
  }

  String get formattedRemainingTime {
    if (durationMs <= 0) return '';
    final remMs = durationMs - positionMs;
    if (remMs <= 0) return 'Selesai';
    final duration = Duration(milliseconds: remMs);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) {
      return 'Sisa $hours j $minutes m';
    }
    return 'Sisa $minutes m';
  }

  Map<String, dynamic> toJson() => {
    'mediaId': mediaId,
    'mediaTitle': mediaTitle,
    'videoPath': videoPath,
    'thumbnailPath': thumbnailPath,
    'category': category,
    'isSeries': isSeries,
    'episodeId': episodeId,
    'episodeNumber': episodeNumber,
    'episodeTitle': episodeTitle,
    'positionMs': positionMs,
    'durationMs': durationMs,
    'lastWatchedAt': lastWatchedAt.toIso8601String(),
    'isCompleted': isCompleted,
  };

  factory WatchHistoryEntry.fromJson(Map<String, dynamic> json) => WatchHistoryEntry(
    mediaId: json['mediaId'] as String? ?? '',
    mediaTitle: json['mediaTitle'] as String? ?? '',
    videoPath: json['videoPath'] as String? ?? '',
    thumbnailPath: json['thumbnailPath'] as String? ?? '',
    category: json['category'] as String? ?? 'films',
    isSeries: json['isSeries'] as bool? ?? false,
    episodeId: json['episodeId'] as String?,
    episodeNumber: (json['episodeNumber'] as num?)?.toInt(),
    episodeTitle: json['episodeTitle'] as String?,
    positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
    durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
    lastWatchedAt: json['lastWatchedAt'] != null
        ? DateTime.tryParse(json['lastWatchedAt'] as String) ?? DateTime.now()
        : DateTime.now(),
    isCompleted: json['isCompleted'] as bool? ?? false,
  );
}

class WatchHistoryService {
  static const String _cacheFileName = 'watch_history.json';

  static File _getHistoryFile() {
    final cacheDir = Directory('.cache');
    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }
    return File('.cache/$_cacheFileName');
  }

  /// Get all watch history entries ordered by last watched descending
  static Future<List<WatchHistoryEntry>> getRecentHistory({int limit = 30}) async {
    try {
      final file = _getHistoryFile();
      if (!await file.exists()) return [];

      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];

      final List<dynamic> list = jsonDecode(content);
      final entries = list
          .map((item) => WatchHistoryEntry.fromJson(item as Map<String, dynamic>))
          .where((e) => File(e.videoPath).existsSync()) // verify file still exists
          .toList();

      entries.sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
      if (entries.length > limit) {
        return entries.sublist(0, limit);
      }
      return entries;
    } catch (e) {
      debugPrint('Error reading watch history: $e');
      return [];
    }
  }

  /// Get specific progress for an item
  static Future<WatchHistoryEntry?> getProgress(String mediaId, {String? episodeId}) async {
    final all = await getRecentHistory();
    for (final entry in all) {
      if (entry.mediaId == mediaId) {
        if (episodeId == null || entry.episodeId == episodeId) {
          return entry;
        }
      }
    }
    return null;
  }

  /// Save or update watching progress
  static Future<void> saveProgress({
    required String mediaId,
    required String mediaTitle,
    required String videoPath,
    required String thumbnailPath,
    String category = 'films',
    bool isSeries = false,
    String? episodeId,
    int? episodeNumber,
    String? episodeTitle,
    required int positionMs,
    required int durationMs,
  }) async {
    try {
      if (durationMs <= 0 || positionMs < 2000) {
        return; // don't save if video just started (< 2s)
      }

      final file = _getHistoryFile();
      List<WatchHistoryEntry> currentEntries = [];
      if (await file.exists()) {
        try {
          final content = await file.readAsString();
          if (content.trim().isNotEmpty) {
            final List<dynamic> list = jsonDecode(content);
            currentEntries = list
                .map((it) => WatchHistoryEntry.fromJson(it as Map<String, dynamic>))
                .toList();
          }
        } catch (_) {}
      }

      final bool isCompleted = durationMs > 0 && (positionMs / durationMs) >= 0.95;

      final updatedEntry = WatchHistoryEntry(
        mediaId: mediaId,
        mediaTitle: mediaTitle,
        videoPath: videoPath,
        thumbnailPath: thumbnailPath,
        category: category,
        isSeries: isSeries,
        episodeId: episodeId,
        episodeNumber: episodeNumber,
        episodeTitle: episodeTitle,
        positionMs: positionMs,
        durationMs: durationMs,
        lastWatchedAt: DateTime.now(),
        isCompleted: isCompleted,
      );

      // Remove existing entry for the same media
      currentEntries.removeWhere((it) => it.mediaId == mediaId);

      // Insert at the front
      currentEntries.insert(0, updatedEntry);

      // Keep max 50 items
      if (currentEntries.length > 50) {
        currentEntries = currentEntries.sublist(0, 50);
      }

      await file.writeAsString(
        jsonEncode(currentEntries.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('Error saving watch history: $e');
    }
  }

  /// Remove single media from history
  static Future<void> removeEntry(String mediaId) async {
    try {
      final file = _getHistoryFile();
      if (!await file.exists()) return;
      final all = await getRecentHistory();
      all.removeWhere((e) => e.mediaId == mediaId);
      await file.writeAsString(jsonEncode(all.map((e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint('Error removing history entry: $e');
    }
  }

  /// Clear all history
  static Future<void> clearHistory() async {
    try {
      final file = _getHistoryFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Error clearing watch history: $e');
    }
  }
}
