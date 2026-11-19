import 'dart:async';
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
  final int? seasonNumber;
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
    this.seasonNumber,
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

  String get formattedSubtitle {
    final rem = formattedRemainingTime;
    if (isSeries) {
      final s = seasonNumber ?? 1;
      if (episodeNumber != null) {
        final epLabel = s > 1 ? 'S$s:E$episodeNumber' : 'E$episodeNumber';
        return rem.isNotEmpty ? '$epLabel • $rem' : epLabel;
      }
      if (episodeTitle != null && episodeTitle!.isNotEmpty) {
        return rem.isNotEmpty ? '${episodeTitle!} • $rem' : episodeTitle!;
      }
    }
    return rem;
  }

  WatchHistoryEntry copyWith({
    String? mediaId,
    String? mediaTitle,
    String? videoPath,
    String? thumbnailPath,
    String? category,
    bool? isSeries,
    String? episodeId,
    int? seasonNumber,
    int? episodeNumber,
    String? episodeTitle,
    int? positionMs,
    int? durationMs,
    DateTime? lastWatchedAt,
    bool? isCompleted,
  }) {
    return WatchHistoryEntry(
      mediaId: mediaId ?? this.mediaId,
      mediaTitle: mediaTitle ?? this.mediaTitle,
      videoPath: videoPath ?? this.videoPath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      category: category ?? this.category,
      isSeries: isSeries ?? this.isSeries,
      episodeId: episodeId ?? this.episodeId,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      episodeTitle: episodeTitle ?? this.episodeTitle,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      lastWatchedAt: lastWatchedAt ?? this.lastWatchedAt,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }

  Map<String, dynamic> toJson() => {
    'mediaId': mediaId,
    'mediaTitle': mediaTitle,
    'videoPath': videoPath,
    'thumbnailPath': thumbnailPath,
    'category': category,
    'isSeries': isSeries,
    'episodeId': episodeId,
    'seasonNumber': seasonNumber,
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
    seasonNumber: (json['seasonNumber'] as num?)?.toInt(),
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
  static List<WatchHistoryEntry>? _memoryEntries;
  static Future<void> _ioQueue = Future<void>.value();

  static Future<T> _synchronized<T>(Future<T> Function() action) {
    final prev = _ioQueue;
    final completer = Completer<void>();
    _ioQueue = completer.future;
    return prev.then((_) async {
      try {
        return await action();
      } finally {
        completer.complete();
      }
    });
  }

  static Directory? _cachedCacheDir;

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

  static File _getHistoryFile() {
    final cacheDir = _cachedCacheDir ??= _resolveAppDirectory('.cache');
    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }
    return File('${cacheDir.path}${Platform.pathSeparator}$_cacheFileName');
  }

  /// Compute a canonical grouping key so 1 Series only ever occupies 1 slot
  /// in "Lanjutkan Menonton" without colliding distinct series stored in the same flat folder.
  static String _seriesSlotKey(WatchHistoryEntry entry) {
    if (entry.mediaId.isNotEmpty) {
      return 'id:${entry.mediaId}';
    }
    if (entry.isSeries && entry.videoPath.isNotEmpty) {
      try {
        final parentPath = File(entry.videoPath).parent.path.toLowerCase();
        if (parentPath.isNotEmpty) {
          return 'series-dir:$parentPath';
        }
      } catch (_) {}
    }
    return 'path:${entry.videoPath.toLowerCase()}';
  }

  static List<WatchHistoryEntry> _deduplicateBySeries(List<WatchHistoryEntry> sortedEntries) {
    final Set<String> seenSlotKeys = {};
    final Set<String> seenMediaIds = {};
    final List<WatchHistoryEntry> deduplicated = [];

    for (final entry in sortedEntries) {
      final slotKey = _seriesSlotKey(entry);
      if (seenSlotKeys.contains(slotKey) || seenMediaIds.contains(entry.mediaId)) {
        continue;
      }
      seenSlotKeys.add(slotKey);
      seenMediaIds.add(entry.mediaId);
      deduplicated.add(entry);
    }
    return deduplicated;
  }

  /// Get all watch history entries ordered by last watched descending (1 slot per series).
  /// Preserves entries from temporarily offline drives instead of deleting them.
  static Future<List<WatchHistoryEntry>> getRecentHistory({int limit = 30}) async {
    return _synchronized(() async {
      try {
        if (_memoryEntries != null) {
          final valid = _deduplicateBySeries(_memoryEntries!);
          if (valid.length > limit) {
            return valid.sublist(0, limit);
          }
          return valid;
        }

        final file = _getHistoryFile();
        final tmpFile = File('${file.path}.tmp');
        String? content;
        if (await file.exists()) {
          try {
            content = await file.readAsString();
          } catch (_) {}
        }
        if ((content == null || content.trim().isEmpty) && await tmpFile.exists()) {
          try {
            content = await tmpFile.readAsString();
          } catch (_) {}
        }
        if (content == null) {
          _memoryEntries = [];
          return [];
        }

        content = content.replaceAll('\u0000', '').trim();
        if (content.isEmpty) {
          _memoryEntries = [];
          return [];
        }

        final List<dynamic> list = jsonDecode(content);
        final rawEntries = list
            .whereType<Map<String, dynamic>>()
            .map(WatchHistoryEntry.fromJson)
            .toList();

        rawEntries.sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
        final entries = _deduplicateBySeries(rawEntries);
        _memoryEntries = entries;

        // If legacy duplicate entries were cleaned up, persist the cleaned list
        if (entries.length != rawEntries.length) {
          await _writeHistoryFileUnlocked(entries);
        }

        if (entries.length > limit) {
          return entries.sublist(0, limit);
        }
        return List<WatchHistoryEntry>.from(entries);
      } catch (e) {
        // Never wipe watch_history.json on a transient read/parse error; preserve user data on disk.
        debugPrint('Error reading watch history (preserving file on disk): $e');
        return _memoryEntries != null ? List<WatchHistoryEntry>.from(_memoryEntries!) : [];
      }
    });
  }

  /// Write entries safely to disk using atomic rename (caller must hold [_synchronized] lock).
  static Future<void> _writeHistoryFileUnlocked(List<WatchHistoryEntry> entries) async {
    try {
      final file = _getHistoryFile();
      final tempFile = File('${file.path}.tmp');
      final jsonStr = jsonEncode(entries.map((e) => e.toJson()).toList());
      await tempFile.writeAsString(jsonStr, flush: true);
      if (await tempFile.exists() && (await tempFile.length()) > 0) {
        try {
          await tempFile.rename(file.path);
        } catch (_) {
          // Windows fallback if target exists and cannot be directly overwritten by rename
          final bakFile = File('${file.path}.bak');
          if (await file.exists()) {
            if (await bakFile.exists()) await bakFile.delete();
            await file.rename(bakFile.path);
          }
          await tempFile.rename(file.path);
          if (await bakFile.exists()) {
            try {
              await bakFile.delete();
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('Error writing watch history: $e');
    }
  }

  static Future<void> _writeHistoryFile(List<WatchHistoryEntry> entries) {
    return _synchronized(() => _writeHistoryFileUnlocked(entries));
  }

  /// Remove history entries for videos whose folders are no longer connected
  static Future<void> pruneDisconnectedHistory(List<String> connectedFolders) async {
    try {
      if (connectedFolders.isEmpty) {
        await clearHistory();
        return;
      }
      final all = await getRecentHistory(limit: 100);
      final normFolders = connectedFolders
          .map((f) => f.replaceAll('/', '\\').toLowerCase().trim())
          .where((f) => f.isNotEmpty)
          .toList();

      final beforeCount = all.length;
      all.removeWhere((e) {
        final np = e.videoPath.replaceAll('/', '\\').toLowerCase().trim();
        return !normFolders.any((f) => np.startsWith(f));
      });

      if (all.length != beforeCount) {
        _memoryEntries = all;
        await _writeHistoryFile(all);
      }
    } catch (e) {
      debugPrint('Error pruning disconnected history: $e');
    }
  }

  /// Synchronize in-memory entries with catalog-normalized entries from BrowseScreen
  static void updateMemoryEntries(List<WatchHistoryEntry> entries) {
    _memoryEntries = List<WatchHistoryEntry>.from(entries);
  }

  /// Synchronous zero-allocation memory lookup for UI scroll rendering (VideoCard & HeroBillboard)
  static WatchHistoryEntry? getProgressSync(
    String mediaId, {
    String? episodeId,
    String? videoPath,
  }) {
    final entries = _memoryEntries;
    if (entries == null || entries.isEmpty) return null;
    if (videoPath != null && videoPath.isNotEmpty) {
      for (final entry in entries) {
        if (entry.videoPath == videoPath) return entry;
      }
      return null;
    }
    for (final entry in entries) {
      if (entry.mediaId == mediaId) {
        if (episodeId == null || entry.episodeId == episodeId) {
          return entry;
        }
      }
    }
    return null;
  }

  /// Get specific progress for an item / video file
  static Future<WatchHistoryEntry?> getProgress(
    String mediaId, {
    String? episodeId,
    String? videoPath,
  }) async {
    final all = await getRecentHistory(limit: 50);
    if (videoPath != null && videoPath.isNotEmpty) {
      for (final entry in all) {
        if (entry.videoPath == videoPath) {
          return entry;
        }
      }
      // If a specific videoPath was requested (e.g., an episode of a series)
      // and the stored entry is for a DIFFERENT episode of that series,
      // do not return the other episode's timestamp.
      return null;
    }
    for (final entry in all) {
      if (entry.mediaId == mediaId) {
        if (episodeId == null || entry.episodeId == episodeId) {
          return entry;
        }
      }
    }
    return null;
  }

  /// Save or update watching progress (replaces any existing slot for the same series)
  static Future<void> saveProgress({
    required String mediaId,
    required String mediaTitle,
    required String videoPath,
    required String thumbnailPath,
    String category = 'films',
    bool isSeries = false,
    String? episodeId,
    int? seasonNumber,
    int? episodeNumber,
    String? episodeTitle,
    required int positionMs,
    required int durationMs,
  }) async {
    try {
      if (durationMs <= 0 || positionMs < 2000) {
        return; // don't save if video just started (< 2s)
      }

      List<WatchHistoryEntry> currentEntries = _memoryEntries != null
          ? List<WatchHistoryEntry>.from(_memoryEntries!)
          : await getRecentHistory(limit: 50);

      final bool isCompleted = durationMs > 0 && (positionMs / durationMs) >= 0.95;

      final updatedEntry = WatchHistoryEntry(
        mediaId: mediaId,
        mediaTitle: mediaTitle,
        videoPath: videoPath,
        thumbnailPath: thumbnailPath,
        category: category,
        isSeries: isSeries,
        episodeId: episodeId,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        episodeTitle: episodeTitle,
        positionMs: positionMs,
        durationMs: durationMs,
        lastWatchedAt: DateTime.now(),
        isCompleted: isCompleted,
      );

      final newSlotKey = _seriesSlotKey(updatedEntry);
      currentEntries.removeWhere(
        (it) =>
            it.mediaId == mediaId ||
            it.videoPath == videoPath ||
            _seriesSlotKey(it) == newSlotKey,
      );
      currentEntries.insert(0, updatedEntry);

      if (currentEntries.length > 50) {
        currentEntries = currentEntries.sublist(0, 50);
      }

      _memoryEntries = currentEntries;
      await _writeHistoryFile(currentEntries);
    } catch (e) {
      debugPrint('Error saving watch history: $e');
    }
  }

  /// Remove single media or series from history
  static Future<void> removeEntry(String mediaId, {String? videoPath}) async {
    try {
      final all = await getRecentHistory(limit: 50);
      String? targetDir;
      if (videoPath != null && videoPath.isNotEmpty) {
        try {
          targetDir = File(videoPath).parent.path.toLowerCase();
        } catch (_) {}
      }
      all.removeWhere((e) {
        if (e.mediaId == mediaId) return true;
        if (videoPath != null && e.videoPath == videoPath) return true;
        if (targetDir != null && e.isSeries) {
          try {
            return File(e.videoPath).parent.path.toLowerCase() == targetDir;
          } catch (_) {}
        }
        return false;
      });
      _memoryEntries = all;
      await _writeHistoryFile(all);
    } catch (e) {
      debugPrint('Error removing history entry: $e');
    }
  }

  /// Clear all history
  static Future<void> clearHistory() async {
    try {
      _memoryEntries = [];
      final file = _getHistoryFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Error clearing watch history: $e');
    }
  }
}
