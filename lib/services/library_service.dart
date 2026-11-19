import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import '../models/media_item.dart';
import 'metadata_service.dart';
import 'thumbnail_service.dart';
import 'watch_history_service.dart';

class _AsyncLock {
  Future<void>? _lastOp;

  Future<T> synchronized<T>(Future<T> Function() action) async {
    final prevOp = _lastOp;
    final completer = Completer<void>();
    _lastOp = completer.future;

    if (prevOp != null) {
      try {
        await prevOp;
      } catch (_) {}
    }

    try {
      return await action();
    } finally {
      completer.complete();
    }
  }
}

class LocalLibraryService {
  static const Set<String> supportedVideoExtensions = {
    '.mp4',
    '.mkv',
    '.avi',
    '.mov',
    '.webm',
    '.ts',
    '.m4v',
    '.flv',
    '.wmv',
  };

  // Real-time folder watchers (debounced auto-detect when new video files are added/removed)
  static final List<StreamSubscription<FileSystemEvent>> _folderWatchSubs = [];
  static Timer? _watchDebounceTimer;
  static List<String> _watchedFolderPaths = const [];

  /// Start watching [folders] for new/deleted/moved video files and invoke [onChanged]
  /// after a 3-second debounce so bulk file copies only trigger a single scan.
  static void startWatchingFolders(List<String> folders, VoidCallback onChanged) {
    final normalized = folders.map((f) => f.trim()).where((f) => f.isNotEmpty).toList()..sort();
    if (_watchedFolderPaths.length == normalized.length &&
        _watchedFolderPaths.asMap().entries.every((e) => e.value == normalized[e.key])) {
      return; // Already watching the exact same folder set
    }

    stopWatchingFolders();
    _watchedFolderPaths = normalized;

    for (final folder in normalized) {
      try {
        final dir = Directory(resolveFolderPath(folder));
        if (!dir.existsSync()) continue;
        final sub = dir.watch(recursive: true).listen(
          (event) {
            final lower = event.path.toLowerCase();
            final isVideo = supportedVideoExtensions.any((ext) => lower.endsWith(ext));
            if (!isVideo && event.type != FileSystemEvent.delete && event.type != FileSystemEvent.move) {
              return;
            }
            _watchDebounceTimer?.cancel();
            _watchDebounceTimer = Timer(const Duration(seconds: 3), onChanged);
          },
          onError: (Object e) {
            debugPrint('Folder watch error on $folder: $e');
          },
          cancelOnError: false,
        );
        _folderWatchSubs.add(sub);
      } catch (e) {
        debugPrint('Could not watch folder $folder: $e');
      }
    }
  }

  /// Stop all active real-time folder watchers.
  static void stopWatchingFolders() {
    _watchDebounceTimer?.cancel();
    _watchDebounceTimer = null;
    for (final sub in _folderWatchSubs) {
      sub.cancel();
    }
    _folderWatchSubs.clear();
    _watchedFolderPaths = const [];
  }

  static File _resolveAppFile(String relativeName) {
    final direct = File(relativeName);
    if (direct.existsSync()) return direct;

    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final resolved = File('$exeDir${Platform.pathSeparator}$relativeName');
      if (resolved.existsSync()) return resolved;
      if (!kDebugMode) return resolved;
    } catch (_) {}

    return direct;
  }

  static File get _configFile => _resolveAppFile('library_config.json');
  static final _configLock = _AsyncLock();

  /// Cancellation token for background scanning
  static int _currentScanId = 0;

  /// Immediately cancel any in-progress scan
  static void cancelScan() {
    _currentScanId++;
  }

  /// In-memory cache of the parsed configuration to prevent redundant 1MB+ JSON disk reads/parses.
  static Map<String, dynamic>? _memoryConfig;
  static List<MediaItem>? _memoryCachedItems;

  /// Read the full persistent library configuration (cached in memory after first load)
  static Future<Map<String, dynamic>> _readConfig({bool forceReload = false}) async {
    return _configLock.synchronized(() async {
      if (_memoryConfig != null && !forceReload) {
        return _memoryConfig!;
      }
      try {
        final file = _configFile;
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

        if (content != null && content.trim().isNotEmpty) {
          final parsed = content.length > 50000
              ? await Isolate.run(() => jsonDecode(content!) as Map<String, dynamic>)
              : jsonDecode(content) as Map<String, dynamic>;
          _memoryConfig = parsed;
          return parsed;
        }
      } catch (e) {
        debugPrint('Error reading library config: $e');
      }

      // If reading from disk failed but we already have an in-memory config with folders, PRESERVE IT!
      if (_memoryConfig != null && (_memoryConfig!['folders'] as List?)?.isNotEmpty == true) {
        return _memoryConfig!;
      }

      final empty = <String, dynamic>{
        'folders': <String>[],
        'customMetadata': <String, dynamic>{},
        'cachedItems': <dynamic>[],
      };
      _memoryConfig = empty;
      return empty;
    });
  }

  /// Save full configuration to disk asynchronously with safe Atomic Write (.tmp -> rename)
  static Future<void> _writeConfig(Map<String, dynamic> config) async {
    return _configLock.synchronized(() async {
      _memoryConfig = config;
      try {
        // Encode synchronously on snapshot or deep copy to avoid ConcurrentModificationError across isolates
        final encoded = jsonEncode(config);
        final file = _configFile;
        final tmpFile = File('${file.path}.tmp');
        await tmpFile.writeAsString(encoded, flush: true);
        if (await tmpFile.exists() && (await tmpFile.length()) > 0) {
          try {
            await tmpFile.rename(file.path);
          } catch (_) {
            // Windows fallback: move existing file to .bak before renaming .tmp so we never lose data
            final bakFile = File('${file.path}.bak');
            if (await file.exists()) {
              if (await bakFile.exists()) await bakFile.delete();
              await file.rename(bakFile.path);
            }
            await tmpFile.rename(file.path);
            if (await bakFile.exists()) {
              try {
                await bakFile.delete();
              } catch (_) {}
            }
          }
        }
      } catch (e) {
        debugPrint('Error writing library config: $e');
      }
    });
  }

  /// Trailing-separator-safe Windows path containment check (avoids D:\Movies matching D:\Movies2)
  static bool _isPathUnderFolder(String filePath, String folderPath) {
    if (filePath.isEmpty || folderPath.isEmpty) return false;
    final np = filePath.replaceAll('/', '\\').toLowerCase().trim();
    var nf = folderPath.replaceAll('/', '\\').toLowerCase().trim();
    if (np == nf) return true;
    if (!nf.endsWith('\\')) nf = '$nf\\';
    return np.startsWith(nf);
  }

  /// Helper to determine whether an item belongs to any currently connected folders
  static bool _isItemInFolders(MediaItem item, List<String> folders) {
    if (folders.isEmpty) return false;

    bool matches(String path) {
      if (path.isEmpty) return false;
      return folders.any((f) => _isPathUnderFolder(path, f));
    }

    if (item.videoPath.isNotEmpty && matches(item.videoPath)) return true;
    for (final ep in item.episodes) {
      if (matches(ep.videoPath)) return true;
    }
    return false;
  }

  /// Attempts to relocate a folder if its drive letter has changed on Windows.
  /// E.g., 'D:\Anime' might have become 'E:\Anime' if user unplugged and re-plugged external HDD.
  static String resolveFolderPath(String originalPath) {
    final clean = originalPath.trim();
    if (clean.isEmpty) return clean;

    // 1. Direct check
    if (Directory(clean).existsSync()) return clean;

    // 2. Windows drive letter reallocation check (e.g., D:\ -> E:\)
    final driveMatch = RegExp(r'^([a-zA-Z]):(\\|/)(.*)$').firstMatch(clean);
    if (driveMatch != null) {
      final subPath = driveMatch.group(3) ?? '';
      final separator = Platform.pathSeparator;
      for (final letter in 'CDEFGHIJKLMNOPQRSTUVWXYZ'.split('')) {
        final candidate = '$letter:$separator$subPath';
        if (Directory(candidate).existsSync()) {
          debugPrint('Drive relocation detected: $clean -> $candidate');
          return candidate;
        }
      }
    }

    return clean;
  }

  /// Remap drive letters across saved cached items and custom metadata
  static void _remapDriveLettersInConfig(
    Map<String, dynamic> config,
    List<String> oldFolders,
    List<String> newFolders,
  ) {
    if (oldFolders.length != newFolders.length) return;

    for (int i = 0; i < oldFolders.length; i++) {
      final oldF = oldFolders[i].toLowerCase();
      final newF = newFolders[i];
      if (oldF == newF.toLowerCase()) continue;

      if (config['cachedItems'] is List) {
        for (final item in config['cachedItems']) {
          if (item is Map<String, dynamic>) {
            final vp = (item['videoPath'] as String? ?? '').toLowerCase();
            if (vp.startsWith(oldF)) {
              item['videoPath'] = newF + item['videoPath'].toString().substring(oldF.length);
            }
            final fp = (item['folderPath'] as String? ?? '').toLowerCase();
            if (fp.startsWith(oldF)) {
              item['folderPath'] = newF + item['folderPath'].toString().substring(oldF.length);
            }
            if (item['episodes'] is List) {
              for (final ep in item['episodes']) {
                if (ep is Map<String, dynamic>) {
                  final epVp = (ep['videoPath'] as String? ?? '').toLowerCase();
                  if (epVp.startsWith(oldF)) {
                    ep['videoPath'] = newF + ep['videoPath'].toString().substring(oldF.length);
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  /// Read all folders configured by the user. NEVER deletes folders automatically!
  static Future<List<String>> getAllConfiguredFolders() async {
    final config = await _readConfig();
    final rawList = config['folders'] as List<dynamic>? ?? [];
    return rawList.map((e) => e.toString().trim()).where((p) => p.isNotEmpty).toList();
  }

  /// Get cached media items from last session for instant (0ms) app startup.
  /// Does NOT wipe items when an external drive is temporarily unplugged!
  static Future<List<MediaItem>> getCachedItems({bool forceReload = false}) async {
    final configuredFolders = await getAllConfiguredFolders();
    if (configuredFolders.isEmpty) {
      _memoryCachedItems = [];
      return [];
    }

    if (_memoryCachedItems != null && !forceReload) {
      return List<MediaItem>.from(_memoryCachedItems!);
    }

    final config = await _readConfig(forceReload: forceReload);
    final rawList = config['cachedItems'] as List<dynamic>? ?? [];
    final items = rawList
        .map((e) {
          try {
            return MediaItem.fromJson(e as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<MediaItem>()
        .toList();

    _memoryCachedItems = items;
    return List<MediaItem>.from(items);
  }

  /// Get accessible connected folders. Automatically resolves Windows drive changes.
  /// NEVER deletes unplugged/offline folders from configuration!
  static Future<List<String>> getConnectedFolders() async {
    final config = await _readConfig();
    final rawList = config['folders'] as List<dynamic>? ?? [];
    final folders = rawList.map((e) => e.toString().trim()).where((p) => p.isNotEmpty).toList();

    bool hasRelocation = false;
    final List<String> resolvedFolders = [];
    final List<String> accessibleFolders = [];

    for (final f in folders) {
      final resolved = resolveFolderPath(f);
      resolvedFolders.add(resolved);
      if (resolved.toLowerCase() != f.toLowerCase()) {
        hasRelocation = true;
      }
      if (Directory(resolved).existsSync()) {
        accessibleFolders.add(resolved);
      }
    }

    // If drive letters changed (e.g. D: -> E:), update the saved paths gracefully
    if (hasRelocation) {
      config['folders'] = resolvedFolders;
      _remapDriveLettersInConfig(config, folders, resolvedFolders);
      await _writeConfig(config);
    }

    return accessibleFolders;
  }

  static final Map<String, bool> _pathExistenceCache = {};
  static DateTime _lastExistenceCacheTime = DateTime.fromMillisecondsSinceEpoch(0);

  /// Check whether a video file is currently accessible on disk (cached for 2 seconds to keep 60 FPS scroll)
  static bool isItemFileAccessible(String videoPath) {
    if (videoPath.trim().isEmpty) return false;
    final now = DateTime.now();
    if (now.difference(_lastExistenceCacheTime).inSeconds > 2) {
      _pathExistenceCache.clear();
      _lastExistenceCacheTime = now;
    }

    if (_pathExistenceCache.containsKey(videoPath)) {
      return _pathExistenceCache[videoPath]!;
    }

    final clean = videoPath.trim();
    // Fast Windows drive letter check (e.g. F:\)
    if (clean.length >= 2 && clean[1] == ':') {
      final drive = '${clean.substring(0, 2)}\\';
      if (!Directory(drive).existsSync()) {
        _pathExistenceCache[videoPath] = false;
        return false;
      }
    }

    final exists = File(clean).existsSync();
    _pathExistenceCache[videoPath] = exists;
    return exists;
  }

  /// Determines if a MediaItem is connected and available to play.
  /// If [connectedFolders] is provided and empty, returns false (all external storage disconnected).
  static bool isMediaItemConnected(MediaItem item, {List<String>? connectedFolders}) {
    if (connectedFolders != null && connectedFolders.isEmpty) {
      return false;
    }

    final path = item.videoPath.isNotEmpty
        ? item.videoPath
        : (item.episodes.isNotEmpty ? item.episodes.first.videoPath : '');
    if (path.isEmpty) return false;

    if (connectedFolders != null && connectedFolders.isNotEmpty) {
      final bool isUnderActive = connectedFolders.any((f) => _isPathUnderFolder(path, f));
      if (!isUnderActive) {
        return false;
      }
    }

    return isItemFileAccessible(path);
  }

  /// Add a new folder to connected list
  static Future<bool> addFolder(String folderPath) async {
    final cleanPath = folderPath.trim();
    if (cleanPath.isEmpty) return false;

    final config = await _readConfig();
    final List<String> folders = (config['folders'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();

    if (!folders.contains(cleanPath)) {
      folders.add(cleanPath);
      config['folders'] = folders;
      await _writeConfig(config);
      return true;
    }
    return false;
  }

  /// Remove a folder from connected list and immediately purge cached items & metadata
  /// that belonged to that removed folder.
  static Future<void> removeFolder(String folderPath) async {
    // 1. Immediately abort any running scan
    cancelScan();

    final cleanPath = folderPath.trim().replaceAll('/', '\\').toLowerCase();
    final config = await _readConfig();
    final List<String> folders = (config['folders'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();

    folders.removeWhere((f) => f.trim().replaceAll('/', '\\').toLowerCase() == cleanPath);
    config['folders'] = folders;

    if (folders.isEmpty) {
      config['cachedItems'] = <dynamic>[];
      config['customMetadata'] = <String, dynamic>{};
      config['noOnlineInfoTitles'] = <dynamic>[];
      _memoryCachedItems = [];
    } else {
      // Purge cached items from this removed folder
      if (config['cachedItems'] is List) {
        final rawList = config['cachedItems'] as List<dynamic>;
        config['cachedItems'] = rawList.where((raw) {
          try {
            final it = MediaItem.fromJson(raw as Map<String, dynamic>);
            return _isItemInFolders(it, folders);
          } catch (_) {
            return false;
          }
        }).toList();
      }

      // Purge memory cache
      if (_memoryCachedItems != null) {
        _memoryCachedItems!.removeWhere((it) => !_isItemInFolders(it, folders));
      }

      // Purge custom metadata for videos/shows under this removed folder
      if (config['customMetadata'] is Map) {
        final meta = config['customMetadata'] as Map<String, dynamic>;
        meta.removeWhere((key, val) {
          if (val is Map<String, dynamic>) {
            try {
              final it = MediaItem.fromJson(val);
              return !_isItemInFolders(it, folders);
            } catch (_) {
              return true;
            }
          }
          final kl = key.replaceAll('/', '\\').toLowerCase();
          return kl.startsWith(cleanPath) || !folders.any((f) => kl.startsWith(f.replaceAll('/', '\\').toLowerCase()));
        });
      }
    }

    await _writeConfig(config);

    // Clean up orphaned poster, thumbnail, and preview files from disk cache
    await cleanOrphanedCache();
    await WatchHistoryService.pruneDisconnectedHistory(folders);
  }

  /// Completely clean up orphaned posters, thumbnails, and preview clips from `.cache/`
  /// that are no longer referenced by any currently connected media item.
  static Future<void> cleanOrphanedCache() async {
    try {
      final configuredFolders = await getAllConfiguredFolders();
      final items = await getCachedItems();

      final activePosterPaths = <String>{};
      final activeThumbPaths = <String>{};

      for (final it in items) {
        if (it.customThumbnail != null &&
            it.customThumbnail!.isNotEmpty &&
            !it.isNetworkImage) {
          activePosterPaths.add(it.customThumbnail!.replaceAll('/', '\\').toLowerCase().trim());
        }
        if (it.backdropUrl != null &&
            it.backdropUrl!.isNotEmpty &&
            !it.backdropUrl!.startsWith('http')) {
          activePosterPaths.add(it.backdropUrl!.replaceAll('/', '\\').toLowerCase().trim());
        }
        if (it.backdrop2Url != null &&
            it.backdrop2Url!.isNotEmpty &&
            !it.backdrop2Url!.startsWith('http')) {
          activePosterPaths.add(it.backdrop2Url!.replaceAll('/', '\\').toLowerCase().trim());
        }
        if (it.logoUrl != null &&
            it.logoUrl!.isNotEmpty &&
            !it.logoUrl!.startsWith('http')) {
          activePosterPaths.add(it.logoUrl!.replaceAll('/', '\\').toLowerCase().trim());
        }
        if (it.videoPath.isNotEmpty) {
          activeThumbPaths.add(LocalThumbnailService.getThumbnailPath(it.videoPath).replaceAll('/', '\\').toLowerCase().trim());
        }
        for (final ep in it.episodes) {
          if (ep.thumbnail != null && ep.thumbnail!.isNotEmpty && !ep.thumbnail!.startsWith('http')) {
            activeThumbPaths.add(ep.thumbnail!.replaceAll('/', '\\').toLowerCase().trim());
          }
          if (ep.videoPath.isNotEmpty) {
            activeThumbPaths.add(LocalThumbnailService.getThumbnailPath(ep.videoPath).replaceAll('/', '\\').toLowerCase().trim());
          }
        }
      }

      Directory resolveCacheSubdir(String sub) {
        final direct = Directory('.cache/$sub');
        if (direct.existsSync()) return direct;
        try {
          final exeDir = File(Platform.resolvedExecutable).parent.path;
          final resolved = Directory('$exeDir${Platform.pathSeparator}.cache${Platform.pathSeparator}$sub');
          if (resolved.existsSync()) return resolved;
        } catch (_) {}
        return direct;
      }

      // 1. Posters & Backdrops
      final posterDir = resolveCacheSubdir('posters');
      if (posterDir.existsSync()) {
        for (final entity in posterDir.listSync()) {
          if (entity is File) {
            final np = entity.path.replaceAll('/', '\\').toLowerCase().trim();
            if (configuredFolders.isEmpty || !activePosterPaths.contains(np)) {
              try { entity.deleteSync(); } catch (_) {}
            }
          }
        }
      }

      // 2. Logos
      final logoDir = resolveCacheSubdir('logos');
      if (logoDir.existsSync()) {
        for (final entity in logoDir.listSync()) {
          if (entity is File) {
            final np = entity.path.replaceAll('/', '\\').toLowerCase().trim();
            if (configuredFolders.isEmpty || !activePosterPaths.contains(np)) {
              try { entity.deleteSync(); } catch (_) {}
            }
          }
        }
      }

      // 3. Thumbnails
      final thumbDir = resolveCacheSubdir('thumbnails');
      if (thumbDir.existsSync()) {
        for (final entity in thumbDir.listSync()) {
          if (entity is File) {
            final np = entity.path.replaceAll('/', '\\').toLowerCase().trim();
            if (configuredFolders.isEmpty || !activeThumbPaths.contains(np)) {
              try { entity.deleteSync(); } catch (_) {}
            }
          }
        }
      }

      // 4. Previews - Clear legacy 360p clips to reclaim disk space (Direct hardware playback is now used)
      final previewDir = resolveCacheSubdir('previews');
      if (previewDir.existsSync()) {
        for (final entity in previewDir.listSync()) {
          if (entity is File) {
            try { entity.deleteSync(); } catch (_) {}
          }
        }
      }

      // 5. Trickplay sprites when all folders removed
      if (configuredFolders.isEmpty) {
        final trickplayDir = resolveCacheSubdir('trickplay');
        if (trickplayDir.existsSync()) {
          for (final entity in trickplayDir.listSync()) {
            if (entity is File) {
              try { entity.deleteSync(); } catch (_) {}
            }
          }
        }
      }

      LocalThumbnailService.clearExistenceCache();
    } catch (e) {
      debugPrint('Error cleaning orphaned cache: $e');
    }
  }

  /// Save manual or custom metadata for a specific media item (by item id or title)
  static Future<void> saveCustomMetadata(String key, MediaItem item) async {
    final config = await _readConfig();
    final Map<String, dynamic> metaMap = Map<String, dynamic>.from(
      config['customMetadata'] as Map<String, dynamic>? ?? {},
    );

    metaMap[key] = item.toJson();
    if (item.videoPath.isNotEmpty) {
      metaMap[item.videoPath] = item.toJson();
    }
    config['customMetadata'] = metaMap;

    if (_memoryCachedItems != null) {
      final idx = _memoryCachedItems!.indexWhere(
        (it) => it.id == item.id || it.title == item.title,
      );
      if (idx != -1) {
        _memoryCachedItems![idx] = item;
      } else {
        _memoryCachedItems!.add(item);
      }
      config['cachedItems'] = _memoryCachedItems!.map((e) => e.toJson()).toList();
    }

    await _writeConfig(config);
  }

  /// Open native Windows folder picker dialog and add folder
  static Future<String?> pickAndAddFolder() async {
    try {
      final selectedDirectory = await FilePicker.getDirectoryPath(
        dialogTitle: 'Pilih Folder Koleksi Film / Serial',
      );

      if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
        await addFolder(selectedDirectory);
        return selectedDirectory;
      }
    } catch (e) {
      debugPrint('Error picking folder: $e');
    }
    return null;
  }

  /// Scan all connected folders and group videos PER TITLE / SHOW.
  /// Heavy file system traversal and regex parsing run in a background Isolate
  /// so the UI thread remains 100% smooth at 60/120fps.
  static Future<List<MediaItem>> scanAllFolders({
    bool fetchOnlineMetadata = true,
    bool extractThumbnails = false,
    bool quickDiffCheck = false,
    List<String>? onlyFolders,
    void Function(String message)? onProgress,
    void Function(List<MediaItem> currentItems, MediaItem readyItem)? onItemReady,
  }) async {
    final int scanId = ++_currentScanId;
    bool isCancelled() => scanId != _currentScanId;

    final allConnectedFolders = await getConnectedFolders();
    final bool isIncrementalFolderScan = onlyFolders != null && onlyFolders.isNotEmpty;
    final List<String> folders = isIncrementalFolderScan
        ? onlyFolders
            .map(resolveFolderPath)
            .where((p) => p.isNotEmpty && Directory(p).existsSync())
            .toList()
        : allConnectedFolders;

    if (folders.isEmpty || isCancelled()) {
      if (!isIncrementalFolderScan && allConnectedFolders.isEmpty) {
        _memoryCachedItems = [];
      }
      return isIncrementalFolderScan ? await getCachedItems() : [];
    }

    final config = await _readConfig();
    final existingCached = await getCachedItems();
    if (isCancelled()) return [];

    // Run recursive directory traversal and regex grouping inside a background Isolate
    final Map<String, _ParsedGroup> groups = await Isolate.run(
      () => _discoverAndGroupInIsolate(folders),
    );

    if (groups.isEmpty || isCancelled()) {
      if (isIncrementalFolderScan) {
        return existingCached;
      }
      if (groups.isEmpty) _memoryCachedItems = [];
      return [];
    }

    // Fast path: if quickDiffCheck is enabled and we already have cached items,
    // check if the exact set of video files on disk in connected folders is unchanged.
    if (quickDiffCheck && !isIncrementalFolderScan && existingCached.isNotEmpty) {
      final Set<String> diskPaths = {};
      for (final g in groups.values) {
        for (final ep in g.episodes) {
          diskPaths.add(ep.videoPath.toLowerCase().trim());
        }
      }
      final Set<String> cachedPathsInConnectedFolders = {};
      for (final item in existingCached) {
        if (!_isItemInFolders(item, folders)) continue;
        if (item.episodes.isNotEmpty) {
          for (final ep in item.episodes) {
            cachedPathsInConnectedFolders.add(ep.videoPath.toLowerCase().trim());
          }
        } else if (item.videoPath.isNotEmpty) {
          cachedPathsInConnectedFolders.add(item.videoPath.toLowerCase().trim());
        }
      }

      if (diskPaths.length == cachedPathsInConnectedFolders.length &&
          diskPaths.containsAll(cachedPathsInConnectedFolders)) {
        return existingCached;
      }
    }

    final Map<String, dynamic> customMetadataMap = Map<String, dynamic>.from(
      config['customMetadata'] as Map<String, dynamic>? ?? {},
    );

    // Persistent negative cache for titles known to have no info online, so we NEVER query internet again!
    final Set<String> noOnlineInfoTitles = Set<String>.from(
      (config['noOnlineInfoTitles'] as List<dynamic>? ?? []).map((e) => e.toString().toLowerCase().trim()),
    );

    // Also index existing cached items by id, title, and videoPath so we don't re-fetch online metadata unnecessarily
    final Map<String, MediaItem> existingCachedByKey = {};
    for (final it in existingCached) {
      existingCachedByKey[it.id] = it;
      existingCachedByKey[it.title] = it;
      if (it.videoPath.isNotEmpty) {
        existingCachedByKey[it.videoPath] = it;
      }
    }

    final List<MediaItem> resultItems = [];
    final bool canUseFfmpeg = await LocalThumbnailService.isFfmpegAvailable();

    // Process already-cached groups first so existing library items remain visible immediately,
    // then stream each newly discovered series/movie one by one as soon as it finishes scanning.
    bool isGroupCached(MapEntry<String, _ParsedGroup> e) {
      final gk = e.key;
      final g = e.value;
      final pv = g.episodes.isNotEmpty ? g.episodes.first.videoPath : '';
      final cid = 'title-${g.cleanTitle.toLowerCase().hashCode.abs()}';
      return customMetadataMap.containsKey(gk) ||
          customMetadataMap.containsKey(g.cleanTitle) ||
          customMetadataMap.containsKey(pv) ||
          existingCachedByKey.containsKey(cid) ||
          existingCachedByKey.containsKey(g.cleanTitle) ||
          existingCachedByKey.containsKey(pv);
    }

    final orderedEntries = groups.entries.toList()
      ..sort((a, b) {
        final aCached = isGroupCached(a) ? 0 : 1;
        final bCached = isGroupCached(b) ? 0 : 1;
        return aCached.compareTo(bCached);
      });

    // Hoist folder lists & offline item snapshot outside the scan loop to avoid O(N^2) disk I/O
    final configuredFoldersAtStart = await getAllConfiguredFolders();
    final preservedConnectedItems = isIncrementalFolderScan
        ? existingCached.where((it) {
            final inConnected = _isItemInFolders(it, allConnectedFolders);
            final inTarget = _isItemInFolders(it, folders);
            return inConnected && !inTarget;
          }).toList()
        : <MediaItem>[];
    final offlineItemsSnapshot = existingCached.where((it) {
      final inConfigured = _isItemInFolders(it, configuredFoldersAtStart);
      final inConnected = _isItemInFolders(it, allConnectedFolders);
      return inConfigured && !inConnected;
    }).toList();
    int itemsSinceLastWrite = 0;
    DateTime lastWriteTime = DateTime.now();

    for (final entry in orderedEntries) {
      if (isCancelled()) return [];

      final isStillConnected = folders.any(
        (f) => _isPathUnderFolder(entry.value.folderPath, f) || _isPathUnderFolder(f, entry.value.folderPath),
      );
      if (!isStillConnected) continue;

      final groupKey = entry.key;
      final group = entry.value;

      group.episodes.sort((a, b) {
        final aSeasonOrder = a.season == 0 ? 9999 : a.season;
        final bSeasonOrder = b.season == 0 ? 9999 : b.season;
        if (aSeasonOrder != bSeasonOrder) return aSeasonOrder.compareTo(bSeasonOrder);
        return a.episodeNumber.compareTo(b.episodeNumber);
      });

      final isShow = group.isSeries || group.episodes.length > 1;
      final firstMainEp = group.episodes.firstWhere(
        (ep) => ep.season >= 1,
        orElse: () => group.episodes.first,
      );
      final primaryVideoPath = group.episodes.isNotEmpty ? firstMainEp.videoPath : '';
      final computedId = 'title-${group.cleanTitle.toLowerCase().hashCode.abs()}';

      // Check saved custom metadata or previously cached item
      MediaItem? existingItem;
      if (customMetadataMap.containsKey(groupKey)) {
        try {
          existingItem = MediaItem.fromJson(customMetadataMap[groupKey] as Map<String, dynamic>);
        } catch (_) {}
      } else if (customMetadataMap.containsKey(group.cleanTitle)) {
        try {
          existingItem = MediaItem.fromJson(customMetadataMap[group.cleanTitle] as Map<String, dynamic>);
        } catch (_) {}
      } else if (customMetadataMap.containsKey(primaryVideoPath)) {
        try {
          existingItem = MediaItem.fromJson(customMetadataMap[primaryVideoPath] as Map<String, dynamic>);
        } catch (_) {}
      } else {
        existingItem = existingCachedByKey[computedId] ??
            existingCachedByKey[group.cleanTitle] ??
            existingCachedByKey[primaryVideoPath];
      }

      String defaultDesc;
      if (isShow) {
        defaultDesc = 'Serial TV / Anime (${group.episodes.length} Episode)\nFolder: ${group.folderPath}';
      } else {
        final ep = group.episodes.first;
        final sizeMb = ((ep.fileSize ?? 0) / (1024 * 1024)).toStringAsFixed(1);
        defaultDesc = 'Film Layar Lebar\nUkuran: $sizeMb MB\nLokasi: ${ep.videoPath}';
      }

      // Preserve existing episode metadata (titles/synopses/thumbnails) where videoPath matches
      // OR fallback by season and episode number if the video was moved to another folder or renamed!
      final Map<String, Episode> oldEpByPath = {};
      final Map<String, Episode> oldEpBySeasonNum = {};
      if (existingItem != null) {
        for (final oldEp in existingItem.episodes) {
          oldEpByPath[oldEp.videoPath.toLowerCase().trim()] = oldEp;
          oldEpBySeasonNum['${oldEp.season}:${oldEp.episodeNumber}'] = oldEp;
        }
      }

      bool hasReparsedEpisodeNumbers = false;
      final List<Episode> mergedEpisodes = group.episodes.map((ep) {
        final prevByPath = oldEpByPath[ep.videoPath.toLowerCase().trim()];
        if (prevByPath != null) {
          final bool sameSlot = prevByPath.season == ep.season && prevByPath.episodeNumber == ep.episodeNumber;
          if (!sameSlot) {
            hasReparsedEpisodeNumbers = true;
            // Episode number changed (e.g., parser improvement): preserve local duration,
            // but drop stale title/synopsis/thumbnail from the previously misparsed episode slot.
            return ep.copyWith(
              duration: prevByPath.duration ?? ep.duration,
            );
          }
          return ep.copyWith(
            title: prevByPath.title.isNotEmpty ? prevByPath.title : ep.title,
            synopsis: (prevByPath.synopsis != null && prevByPath.synopsis!.isNotEmpty) ? prevByPath.synopsis : ep.synopsis,
            thumbnail: (prevByPath.thumbnail != null && prevByPath.thumbnail!.isNotEmpty) ? prevByPath.thumbnail : ep.thumbnail,
            duration: prevByPath.duration ?? ep.duration,
            seasonName: ep.seasonName.isNotEmpty ? ep.seasonName : prevByPath.seasonName,
          );
        }
        final prevBySlot = oldEpBySeasonNum['${ep.season}:${ep.episodeNumber}'];
        if (prevBySlot != null) {
          return ep.copyWith(
            title: prevBySlot.title.isNotEmpty ? prevBySlot.title : ep.title,
            synopsis: (prevBySlot.synopsis != null && prevBySlot.synopsis!.isNotEmpty) ? prevBySlot.synopsis : ep.synopsis,
            thumbnail: (prevBySlot.thumbnail != null && prevBySlot.thumbnail!.isNotEmpty) ? prevBySlot.thumbnail : ep.thumbnail,
            duration: prevBySlot.duration ?? ep.duration,
            seasonName: ep.seasonName.isNotEmpty ? ep.seasonName : prevBySlot.seasonName,
          );
        }
        return ep;
      }).toList();

      final effectiveTitle = (existingItem != null && !_hasMojibake(existingItem.title))
          ? existingItem.title
          : group.cleanTitle;

      var item = MediaItem(
        id: existingItem?.id ?? computedId,
        title: effectiveTitle,
        description: (existingItem?.description.isNotEmpty ?? false) ? existingItem!.description : defaultDesc,
        genre: existingItem?.genre ?? (isShow ? 'Serial TV' : 'Film'),
        maturity: existingItem?.maturity ?? '13',
        category: isShow ? 'series' : 'films',
        videoPath: primaryVideoPath,
        customThumbnail: existingItem?.customThumbnail,
        backdropUrl: existingItem?.backdropUrl,
        backdrop2Url: existingItem?.backdrop2Url,
        logoUrl: existingItem?.logoUrl,
        cast: existingItem?.cast ?? const [],
        director: existingItem?.director,
        year: existingItem?.year ?? group.year,
        rating: existingItem?.rating,
        isManualEdit: existingItem?.isManualEdit ?? false,
        isOnlineChecked: existingItem?.isOnlineChecked ?? false,
        folderPath: group.folderPath,
        isSeries: isShow,
        episodes: mergedEpisodes,
      );

      final cleanTitleLower = group.cleanTitle.toLowerCase().trim();
      final effectiveTitleLower = effectiveTitle.toLowerCase().trim();
      final groupKeyLower = groupKey.toLowerCase().trim();

      final bool isKnownNoOnlineInfo = noOnlineInfoTitles.contains(cleanTitleLower) ||
          noOnlineInfoTitles.contains(effectiveTitleLower) ||
          noOnlineInfoTitles.contains(groupKeyLower);

      // Once an item has been checked online, do NOT repeatedly query the internet on every app launch / sync!
      // Exception: if episode numbers were just corrected by an improved parser, re-fetch episode metadata once.
      final bool alreadyChecked = !hasReparsedEpisodeNumbers &&
          ((item.isOnlineChecked || existingItem?.isOnlineChecked == true) ||
              isKnownNoOnlineInfo ||
              item.isManualEdit ||
              existingItem?.isManualEdit == true);

      // Fetch online metadata per Title via TMDB ONLY if API key is configured and never checked before
      if (fetchOnlineMetadata && OnlineMetadataService.hasApiKey && !alreadyChecked) {
        try {
          onProgress?.call('Mencari info online: ${item.title}');
          final localSeasons = item.isSeries
              ? item.episodes.map((e) => e.season).where((s) => s > 0).toSet()
              : null;
          final online = await OnlineMetadataService.searchMetadata(
            item.title,
            isSeries: item.isSeries,
            localSeasons: localSeasons,
          );
          if (online != null) {
            List<Episode> updatedEpisodes = item.episodes;
            if (online.episodes.isNotEmpty) {
              final List<Episode> mapped = [];
              for (final localEp in item.episodes) {
                if (localEp.season == 0) {
                  // Keep local extra/OVA titles (e.g. NCED, NCOP, Specials) intact
                  mapped.add(localEp);
                  continue;
                }
                final match = online.episodes.firstWhere(
                  (oe) => oe.season == localEp.season && oe.episodeNumber == localEp.episodeNumber,
                  orElse: () {
                    // Only fallback by 0-based index for Season 1 so Season 2+ never steals Season 1 titles
                    if (localEp.season == 1) {
                      final idx = localEp.episodeNumber - 1;
                      if (idx >= 0 && idx < online.episodes.length && online.episodes[idx].season == 1) {
                        return online.episodes[idx];
                      }
                    }
                    return const EpisodeOnlineMetadata(
                      season: 1,
                      episodeNumber: 1,
                      title: '',
                      synopsis: '',
                    );
                  },
                );

                if (match.title.isNotEmpty) {
                  String? stillPath = localEp.thumbnail;
                  if (match.thumbnailUrl != null) {
                    stillPath = await LocalThumbnailService.cacheEpisodeStill(match.thumbnailUrl);
                  }
                  mapped.add(localEp.copyWith(
                    title: match.title,
                    synopsis: match.synopsis.isNotEmpty ? match.synopsis : localEp.synopsis,
                    thumbnail: stillPath ?? match.thumbnailUrl ?? localEp.thumbnail,
                    // Never take duration from TMDB; always derive duration from the actual local video file
                    duration: localEp.duration,
                  ));
                } else {
                  mapped.add(localEp);
                }
              }
              updatedEpisodes = mapped;
            }

            String? localBackdrop;
            if (online.bannerUrl != null) {
              localBackdrop = await LocalThumbnailService.cacheBackdrop(online.bannerUrl);
            }

            String? localBackdrop2;
            if (online.banner2Url != null) {
              localBackdrop2 = await LocalThumbnailService.cacheBackdrop(online.banner2Url);
            }

            // Only cache poster if backdrop is completely missing from online provider
            String? localPoster;
            if ((localBackdrop == null || localBackdrop.isEmpty) && online.posterUrl != null) {
              localPoster = await LocalThumbnailService.cachePoster(online.posterUrl);
            }

            String? localLogo = online.logoUrl;
            if (online.logoUrl != null) {
              localLogo = await LocalThumbnailService.cacheLogo(online.logoUrl);
            }

            item = item.copyWith(
              title: online.title,
              description: online.blurb,
              customThumbnail: localPoster ?? (localBackdrop == null ? online.posterUrl : null),
              backdropUrl: localBackdrop ?? online.bannerUrl ?? item.backdropUrl,
              backdrop2Url: localBackdrop2 ?? online.banner2Url ?? item.backdrop2Url,
              logoUrl: localLogo ?? online.logoUrl ?? item.logoUrl,
              year: online.year ?? item.year,
              rating: online.rating ?? item.rating,
              genre: online.genre ?? item.genre,
              cast: online.cast.isNotEmpty ? online.cast : item.cast,
              director: online.director ?? item.director,
              isOnlineChecked: true,
              episodes: updatedEpisodes,
            );
            customMetadataMap[groupKey] = item.toJson();
            customMetadataMap[item.title] = item.toJson();
            customMetadataMap[group.cleanTitle] = item.toJson();
          } else {
            // Online search returned nothing! Mark permanently so we NEVER search again on startup
            item = item.copyWith(isOnlineChecked: true);
            noOnlineInfoTitles.add(cleanTitleLower);
            noOnlineInfoTitles.add(effectiveTitleLower);
            noOnlineInfoTitles.add(groupKeyLower);
            customMetadataMap[groupKey] = item.toJson();
            customMetadataMap[item.title] = item.toJson();
            customMetadataMap[group.cleanTitle] = item.toJson();
            customMetadataMap[primaryVideoPath] = item.toJson();
          }
        } catch (e) {
          // Do NOT permanently blacklist titles on transient network/timeout errors
          debugPrint('Online metadata fetch failed (will retry on future scan) for ${item.title}: $e');
        }
      }

      // 1. Ensure remote backdrop is cached locally
      if (item.backdropUrl != null &&
          (item.backdropUrl!.startsWith('http://') || item.backdropUrl!.startsWith('https://'))) {
        final cached = await LocalThumbnailService.cacheBackdrop(item.backdropUrl);
        if (cached != null && cached != item.backdropUrl) {
          item = item.copyWith(backdropUrl: cached);
          customMetadataMap[groupKey] = item.toJson();
        }
      }
      if (item.backdrop2Url != null &&
          (item.backdrop2Url!.startsWith('http://') || item.backdrop2Url!.startsWith('https://'))) {
        final cached2 = await LocalThumbnailService.cacheBackdrop(item.backdrop2Url);
        if (cached2 != null && cached2 != item.backdrop2Url) {
          item = item.copyWith(backdrop2Url: cached2);
          customMetadataMap[groupKey] = item.toJson();
        }
      }
      if ((item.backdropUrl == null || item.backdropUrl!.isEmpty) && canUseFfmpeg) {
        // Fallback: If backdrop is not found online, extract 16:9 backdrop from local video
        final videoSource = item.videoPath.isNotEmpty
            ? item.videoPath
            : (item.episodes.isNotEmpty ? item.episodes.first.videoPath : '');
        if (videoSource.isNotEmpty) {
          final localBackdrop = await LocalThumbnailService.extractBackdrop(videoSource);
          if (localBackdrop != null) {
            item = item.copyWith(backdropUrl: localBackdrop);
            customMetadataMap[groupKey] = item.toJson();
          }
        }
      }

      // 2. Only cache remote poster if backdrop is completely missing
      if ((item.backdropUrl == null || item.backdropUrl!.isEmpty) &&
          item.customThumbnail != null &&
          (item.customThumbnail!.startsWith('http://') || item.customThumbnail!.startsWith('https://'))) {
        final cached = await LocalThumbnailService.cachePoster(item.customThumbnail);
        if (cached != null && cached != item.customThumbnail) {
          item = item.copyWith(customThumbnail: cached);
          customMetadataMap[groupKey] = item.toJson();
        }
      }

      if (item.logoUrl != null &&
          (item.logoUrl!.startsWith('http://') || item.logoUrl!.startsWith('https://'))) {
        final cached = await LocalThumbnailService.cacheLogo(item.logoUrl);
        if (cached != null && cached != item.logoUrl) {
          item = item.copyWith(logoUrl: cached);
          customMetadataMap[groupKey] = item.toJson();
        }
      }

      // 3. Generate/Attach Local Thumbnails for EVERY Episode of this title
      final List<Episode> withThumbnails = [];
      for (int epIdx = 0; epIdx < item.episodes.length; epIdx++) {
        if (isCancelled()) return [];
        final ep = item.episodes[epIdx];
        var thumbPath = ep.thumbnail;
        if (thumbPath == null || thumbPath.isEmpty || !LocalThumbnailService.fileExistsCached(thumbPath)) {
          if (LocalThumbnailService.hasThumbnail(ep.videoPath)) {
            thumbPath = LocalThumbnailService.getThumbnailPath(ep.videoPath);
          } else if (canUseFfmpeg) {
            onProgress?.call('Membuat thumbnail (${epIdx + 1}/${item.episodes.length}): ${item.title}');
            thumbPath = await LocalThumbnailService.extractThumbnail(ep.videoPath);
          }
        }
        var epDuration = ep.duration;
        if (canUseFfmpeg && (extractThumbnails || epDuration == null || epDuration.isEmpty)) {
          final probed = await LocalThumbnailService.getVideoDuration(ep.videoPath);
          if (probed != null && probed.isNotEmpty) {
            epDuration = probed;
          }
        }
        withThumbnails.add(ep.copyWith(
          thumbnail: thumbPath,
          duration: epDuration ?? ep.duration,
        ));
      }
      item = item.copyWith(episodes: withThumbnails);

      if (isCancelled()) return [];

      // 4. All assets for this title are 100% ready! Save and emit to Home screen
      customMetadataMap[groupKey] = item.toJson();
      customMetadataMap[item.title] = item.toJson();
      resultItems.add(item);

      // Batch incremental writes to library_config.json (every 10 items or 2.5s) instead of O(N^2) rewrite per item
      itemsSinceLastWrite++;
      final now = DateTime.now();
      if (itemsSinceLastWrite >= 10 || now.difference(lastWriteTime).inMilliseconds >= 2500) {
        itemsSinceLastWrite = 0;
        lastWriteTime = now;
        final mergedConnected = isIncrementalFolderScan
            ? _mergePreservedAndScanned(preservedConnectedItems, resultItems)
            : resultItems;
        final allSavedItems = [...mergedConnected, ...offlineItemsSnapshot];
        config['noOnlineInfoTitles'] = noOnlineInfoTitles.toList();
        config['customMetadata'] = customMetadataMap;
        config['cachedItems'] = allSavedItems.map((e) => e.toJson()).toList();
        await _writeConfig(config);
      }

      // Immediately display the completed title on Home screen
      if (onItemReady != null) {
        final snapshot = isIncrementalFolderScan
            ? _mergePreservedAndScanned(preservedConnectedItems, resultItems)
            : (List<MediaItem>.from(resultItems)
              ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase())));
        _memoryCachedItems = [...snapshot, ...offlineItemsSnapshot];
        onItemReady(snapshot, item);
      }
    }

    final mergedConnected = isIncrementalFolderScan
        ? _mergePreservedAndScanned(preservedConnectedItems, resultItems)
        : (List<MediaItem>.from(resultItems)
          ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase())));

    final allFinalItems = [...mergedConnected, ...offlineItemsSnapshot];
    _memoryCachedItems = allFinalItems;
    config['noOnlineInfoTitles'] = noOnlineInfoTitles.toList();
    config['customMetadata'] = customMetadataMap;
    config['cachedItems'] = allFinalItems.map((e) => e.toJson()).toList();
    await _writeConfig(config);

    // Note: cleanOrphanedCache() is NEVER run during normal scanning!
    // Assets are only purged when a user explicitly removes a folder in Settings.

    return List<MediaItem>.from(mergedConnected);
  }

  /// Merges untouched items from previously scanned folders with newly scanned items
  /// from an incremental folder scan. If a series spans multiple folders, merges episodes cleanly.
  static List<MediaItem> _mergePreservedAndScanned(
    List<MediaItem> preserved,
    List<MediaItem> scanned,
  ) {
    final Map<String, MediaItem> byId = {};
    for (final item in preserved) {
      byId[item.id] = item;
    }
    for (final item in scanned) {
      final existing = byId[item.id];
      if (existing != null && (existing.isSeries || item.isSeries)) {
        final Map<String, Episode> epByPath = {};
        for (final ep in existing.episodes) {
          epByPath[ep.videoPath.toLowerCase().trim()] = ep;
        }
        for (final ep in item.episodes) {
          epByPath[ep.videoPath.toLowerCase().trim()] = ep;
        }
        final mergedEps = epByPath.values.toList()
          ..sort((a, b) {
            final aS = a.season == 0 ? 9999 : a.season;
            final bS = b.season == 0 ? 9999 : b.season;
            if (aS != bS) return aS.compareTo(bS);
            return a.episodeNumber.compareTo(b.episodeNumber);
          });
        byId[item.id] = existing.copyWith(
          isSeries: true,
          category: 'series',
          episodes: mergedEps,
        );
      } else {
        byId[item.id] = item;
      }
    }
    final list = byId.values.toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return list;
  }

  /// Runs inside a background Isolate to avoid blocking the main UI thread.
  static Map<String, _ParsedGroup> _discoverAndGroupInIsolate(List<String> folders) {
    final List<File> videoFiles = [];
    final Set<String> seenPaths = {};

    for (final folderPath in folders) {
      final dir = Directory(folderPath);
      if (!dir.existsSync()) continue;

      try {
        final entities = dir.listSync(recursive: true, followLinks: false);
        for (final entity in entities) {
          if (entity is File) {
            final pLower = entity.path.toLowerCase();
            final hasExt = supportedVideoExtensions.any((ext) => pLower.endsWith(ext));
            final fileName = entity.path.split(Platform.pathSeparator).last;
            if (hasExt && !seenPaths.contains(entity.path) && !fileName.startsWith('.')) {
              seenPaths.add(entity.path);
              videoFiles.add(entity);
            }
          }
        }
      } catch (_) {}
    }

    final Map<String, _ParsedGroup> groups = {};
    for (final file in videoFiles) {
      final info = _parseVideoFile(file);
      final groupKey = info.groupKey;

      if (!groups.containsKey(groupKey)) {
        groups[groupKey] = _ParsedGroup(
          cleanTitle: info.cleanTitle,
          year: info.year,
          folderPath: file.parent.path,
          isSeries: info.isSeries,
        );
      } else if (info.isSeries) {
        groups[groupKey]!.isSeries = true;
      }

      int fileSize = 0;
      try {
        fileSize = file.lengthSync();
      } catch (_) {}

      groups[groupKey]!.episodes.add(Episode(
        id: 'ep-${file.path.hashCode.abs()}',
        title: info.episodeLabel,
        videoPath: file.path,
        season: info.season,
        episodeNumber: info.episodeNumber,
        fileSize: fileSize,
        seasonName: info.seasonName,
      ));
    }

    // Disambiguate seasonName ONLY if the title/seasonName is literally identical across distinct root folders!
    // (e.g. two "Season 1" from two different folders). If one is "Season 1" and the other is "OVA", their titles
    // are already distinct so keep them clean without [Folder: ...].
    for (final group in groups.values) {
      if (group.episodes.length <= 1) continue;

      // Group episodes by their effective base seasonName:
      final Map<String, Set<String>> rootsBySeasonName = {};
      final Set<String> allRoots = {};
      for (final ep in group.episodes) {
        final baseSeason = ep.seasonName.isNotEmpty ? ep.seasonName : 'Season ${ep.season}';
        final root = _getSeriesRootFolder(ep.videoPath);
        allRoots.add(root);
        rootsBySeasonName.putIfAbsent(baseSeason, () => {}).add(root);
      }

      // Find ONLY seasonNames that appear in more than 1 distinct root folder!
      final Set<String> collidingSeasonNames = rootsBySeasonName.entries
          .where((entry) => entry.value.length > 1)
          .map((entry) => entry.key)
          .toSet();

      if (collidingSeasonNames.isEmpty) continue;

      final Map<String, String> rootBadges = {};
      for (final root in allRoots) {
        rootBadges[root] = _getFolderBadge(root, allRoots, group.cleanTitle);
      }

      final List<Episode> updatedList = [];
      for (final ep in group.episodes) {
        final baseSeason = ep.seasonName.isNotEmpty ? ep.seasonName : 'Season ${ep.season}';
        if (collidingSeasonNames.contains(baseSeason)) {
          final root = _getSeriesRootFolder(ep.videoPath);
          final badge = rootBadges[root];
          if (badge != null && badge.isNotEmpty) {
            updatedList.add(ep.copyWith(
              seasonName: '$baseSeason [Folder: $badge]',
            ));
            continue;
          }
        }
        updatedList.add(ep);
      }
      group.episodes
        ..clear()
        ..addAll(updatedList);
    }

    return groups;
  }

  /// Find root series folder ignoring subfolders like "Season 1", "Specials", "Extras", etc.
  /// Note: Movie is deliberately excluded so movie subfolders maintain their own identity and don't merge into TV series!
  static String _getSeriesRootFolder(String videoPath) {
    try {
      final parent = File(videoPath).parent;
      final parentName = parent.path.split(Platform.pathSeparator).last;
      final isSubdir = RegExp(
        r'^(?:\[|\()?(?:Season\s*\d+|S\d+|Extras?|Specials?|SP|OVA|OAD|NC(?:OP|ED)|Bonus|Arc|Part|Cour)(?:\]|\))?$',
        caseSensitive: false,
      ).hasMatch(parentName.trim());
      if (isSubdir && parent.parent.path.isNotEmpty) {
        return parent.parent.path;
      }
      return parent.path;
    } catch (_) {
      return '';
    }
  }

  /// Generate concise and distinct badge name for a root folder
  static String _getFolderBadge(String rootPath, Set<String> allRootPaths, String groupCleanTitle) {
    if (rootPath.isEmpty) return '';
    final parts = rootPath.split(Platform.pathSeparator).where((p) => p.isNotEmpty && !p.contains(':')).toList();
    if (parts.isEmpty) return rootPath;
    final leaf = parts.last;

    final otherLeaves = allRootPaths.where((p) => p != rootPath).map((p) {
      final sub = p.split(Platform.pathSeparator).where((s) => s.isNotEmpty && !s.contains(':')).toList();
      return sub.isNotEmpty ? sub.last : p;
    }).toSet();

    final cleanTitleLower = groupCleanTitle.toLowerCase().trim();
    final parent = parts.length >= 2 ? parts[parts.length - 2] : '';

    if (otherLeaves.contains(leaf) && parent.isNotEmpty) {
      return parent;
    }

    if (parent.isNotEmpty && leaf.toLowerCase().contains(cleanTitleLower) && !leaf.contains('[')) {
      return parent;
    }

    return leaf;
  }

  /// Parse a video file and extract its show title, season, and episode number
  static _ParsedFileInfo _parseVideoFile(File file) {
    final fileName = file.path.split(Platform.pathSeparator).last;
    final parentDir = file.parent;
    final parentDirName = parentDir.path.split(Platform.pathSeparator).last;
    final grandParentDir = parentDir.parent;
    final grandParentDirName = grandParentDir.path.split(Platform.pathSeparator).last;

    String cleanName = fileName;
    final dotIndex = cleanName.lastIndexOf('.');
    if (dotIndex != -1) {
      cleanName = cleanName.substring(0, dotIndex);
    }

    int season = 1;
    int episodeNumber = 1;
    bool isSeries = false;
    String? year;
    String cleanTitle = '';
    String seasonName = 'Season 1';

    final yearMatch = RegExp(r'[\(\[\.]?(19\d{2}|20\d{2})[\)\]\.]?').firstMatch(cleanName);
    if (yearMatch != null) {
      year = yearMatch.group(1);
    }

    final bool hasExplicitSeasonEpisode = RegExp(r'[sS]\d{1,2}[eE]\d{1,3}\b').hasMatch(cleanName) ||
        RegExp(r'\b\d{1,2}x\d{1,3}\b').hasMatch(cleanName);

    // Detect movie tag: e.g. [Movie], (Movie), [Film], (Film), " The Movie ", or folder named Movie/Movies/Film/Films
    final bool isMovieTag = !hasExplicitSeasonEpisode && (
      RegExp(r'(?:\[|\(|\b)(?:the\s+)?(?:movie|film)s?(?:\s*\d+)?(?:\]|\)|\b)', caseSensitive: false).hasMatch(parentDirName) ||
      RegExp(r'(?:\[|\(|\b)(?:the\s+)?(?:movie|film)s?(?:\s*\d+)?(?:\]|\)|\b)', caseSensitive: false).hasMatch(cleanName)
    );

    // Check if the file is inside a subfolder like "Extras", "Special", "OVA", "Arc" (Movies are excluded!)
    final bool isExtrasDir = !isMovieTag && (
      RegExp(r'\b(?:Extras?|Specials?|SP|OVA|OAD|NC(?:OP|ED)|Bonus)\b', caseSensitive: false).hasMatch(parentDirName) ||
      parentDirName.toLowerCase().contains('special') ||
      parentDirName.toLowerCase().contains('extra')
    );
    final seasonDirMatch = RegExp(r'(?:^|\[|\()\s*(?:Season|S)\s*(\d{1,2})\s*(?:$|\]|\))', caseSensitive: false).firstMatch(parentDirName);
    final arcDirMatch = RegExp(r'\b(?:Arc|Part|Cour)\b', caseSensitive: false).firstMatch(parentDirName);

    // Extract title prefix before " - " or "_-_" if present
    // e.g., "[smol] Onii-chan wa Oshimai! - NCED...", "[DB]Azumanga Daiou_-_01_(Dual Audio...)"
    final titleDashMatch = RegExp(r'^(\[[^\]]+\][\s_]*)?(.+?)[\s_]+[-–—][\s_]+(.+)$').firstMatch(cleanName);
    String? titleFromDash;
    String remainder = cleanName;
    bool foundEpisodeNumber = false;
    if (titleDashMatch != null) {
      titleFromDash = _cleanTitleString(titleDashMatch.group(2)!);
      remainder = titleDashMatch.group(3)!;

      // 1. If titleFromDash ends with an episode number (e.g., "Show Name 01", "Show Name - E02")
      final trailingEpMatch = RegExp(r'^(.*?)\s+(?:e|ep|eps|episode)?\s*(\d{1,4})$', caseSensitive: false).firstMatch(titleFromDash);
      if (trailingEpMatch != null) {
        final parsedEp = int.tryParse(trailingEpMatch.group(2)!);
        final baseTitle = trailingEpMatch.group(1)!.trim();
        if (parsedEp != null && baseTitle.length >= 2) {
          titleFromDash = baseTitle;
          episodeNumber = parsedEp;
          foundEpisodeNumber = true;
          isSeries = true;
        }
      }

      // 2. If titleFromDash starts with an episode marker (e.g., "E1 Confession", "01")
      // Avoid misclassifying year-prefixed movies like "2001 - A Space Odyssey" or "1917 - ..."
      final leadingEpMatch = RegExp(r'^(e|ep|eps|episode)?\s*(\d{1,4})\b', caseSensitive: false).firstMatch(titleFromDash);
      if (leadingEpMatch != null && (parentDirName.length > 2 && !parentDirName.contains(':'))) {
        final hasExplicitPrefix = leadingEpMatch.group(1) != null;
        final parsedEp = int.tryParse(leadingEpMatch.group(2)!);
        final isLikelyYear = !hasExplicitPrefix && parsedEp != null && parsedEp >= 1900 && parsedEp <= 2099;
        final isPureNumberOrPrefixed = hasExplicitPrefix || titleFromDash.trim() == leadingEpMatch.group(2);
        if (parsedEp != null && parsedEp > 0 && !isLikelyYear && isPureNumberOrPrefixed) {
          episodeNumber = parsedEp;
          foundEpisodeNumber = true;
          isSeries = true;
          // Use parent directory name as show title
          titleFromDash = _cleanTitleString(parentDirName);
        }
      }
    }

    if (isMovieTag) {
      isSeries = false;
      season = 1;
      episodeNumber = 1;
      seasonName = 'Film';

      final cleanedCleanName = _cleanTitleString(cleanName);
      final cleanedParent = _cleanTitleString(parentDirName);
      final cleanedGrandParent = (grandParentDirName.length > 2 && !grandParentDirName.contains(':'))
          ? _cleanTitleString(grandParentDirName)
          : '';

      bool isGeneric(String s) => s.isEmpty ||
          RegExp(r'^(?:movie|film|movies|films|the movie|the film)(?:\s*\d+)?$', caseSensitive: false).hasMatch(s.trim());

      String candidate = '';
      if (!isGeneric(cleanedCleanName)) {
        if (cleanedGrandParent.isNotEmpty &&
            !cleanedCleanName.toLowerCase().contains(cleanedGrandParent.toLowerCase()) &&
            cleanedCleanName.toLowerCase().startsWith('movie')) {
          candidate = '$cleanedGrandParent $cleanedCleanName';
        } else {
          candidate = cleanedCleanName;
        }
      } else if (!isGeneric(cleanedParent)) {
        candidate = cleanedParent;
      } else if (cleanedGrandParent.isNotEmpty) {
        candidate = '$cleanedGrandParent Movie';
      } else {
        candidate = cleanedCleanName.isNotEmpty ? cleanedCleanName : cleanedParent;
      }
      cleanTitle = candidate;
    } else if (isExtrasDir) {
      season = 0;
      isSeries = true;
      seasonName = _cleanTitleString(parentDirName);
      if (seasonName.isEmpty || seasonName.toLowerCase().contains('extra') || seasonName.toLowerCase().contains('special')) {
        seasonName = 'Extras / Spesial';
      }
      if (grandParentDirName.length > 2 && !grandParentDirName.contains(':')) {
        cleanTitle = _cleanTitleString(grandParentDirName);
      } else {
        cleanTitle = titleFromDash ?? _cleanTitleString(parentDirName);
      }
    } else if (seasonDirMatch != null) {
      season = int.tryParse(seasonDirMatch.group(1)!) ?? 1;
      isSeries = true;
      seasonName = 'Season $season';
      final cleanParent = _cleanTitleString(parentDirName);
      if (titleFromDash != null && titleFromDash.isNotEmpty) {
        cleanTitle = titleFromDash;
      } else if (cleanParent.isNotEmpty && !cleanParent.toLowerCase().startsWith('season')) {
        cleanTitle = cleanParent;
      } else {
        cleanTitle = _cleanTitleString(grandParentDirName);
      }
    } else if (arcDirMatch != null) {
      isSeries = true;
      seasonName = _cleanTitleString(parentDirName);
      cleanTitle = titleFromDash ?? _cleanTitleString(grandParentDirName);
    }

    if (!isMovieTag) {
      final seSource = remainder.isNotEmpty ? remainder : cleanName;
      final seMatch = RegExp(r'[sS](\d{1,2})[eE](\d{1,3})').firstMatch(seSource);
      if (seMatch != null) {
        final parsedSeason = int.tryParse(seMatch.group(1)!);
        if (parsedSeason != null && !isExtrasDir) {
          season = parsedSeason;
          if (seasonDirMatch == null && arcDirMatch == null) {
            seasonName = 'Season $season';
          }
        }
        episodeNumber = int.tryParse(seMatch.group(2)!) ?? 1;
        foundEpisodeNumber = true;
        isSeries = true;
        if (cleanTitle.isEmpty) {
          cleanTitle = titleFromDash ?? _cleanTitleString(seSource.substring(0, seMatch.start));
        }
      }

      if (!foundEpisodeNumber && (!isSeries || !isExtrasDir)) {
        final nxmMatch = RegExp(r'\b(\d{1,2})x(\d{1,3})\b', caseSensitive: false).firstMatch(cleanName);
        if (nxmMatch != null) {
          season = int.tryParse(nxmMatch.group(1)!) ?? season;
          episodeNumber = int.tryParse(nxmMatch.group(2)!) ?? 1;
          foundEpisodeNumber = true;
          isSeries = true;
          if (seasonDirMatch == null && arcDirMatch == null && !isExtrasDir) {
            seasonName = 'Season $season';
          }
          if (cleanTitle.isEmpty) {
            cleanTitle = titleFromDash ?? _cleanTitleString(cleanName.substring(0, nxmMatch.start));
          }
        }
      }

      if (!foundEpisodeNumber && (!isSeries || !isExtrasDir)) {
        final epMatch = RegExp(r'(?:^|[\s_\.\-\(\[])(?:EP|E|Episode|Eps)[\s_]?(\d{1,3})(?=$|[\s_\.\-\)\]])', caseSensitive: false).firstMatch(cleanName);
        if (epMatch != null) {
          episodeNumber = int.tryParse(epMatch.group(1)!) ?? 1;
          foundEpisodeNumber = true;
          isSeries = true;
          if (cleanTitle.isEmpty) {
            cleanTitle = titleFromDash ?? _cleanTitleString(cleanName.substring(0, epMatch.start));
          }
        }
      }

      // Anime naming convention: "Title - 01", "Title_-_02_(...)", "Title - 02v2", etc.
      if (!foundEpisodeNumber && (!isSeries || !isExtrasDir)) {
        final dashNumMatch = RegExp(
          r'(?:^|[-–—][\s_]*)(\d{1,4})(?:v\d+)?(?=$|[\s_\.\-\(\[\]])',
        ).firstMatch(remainder.isNotEmpty ? remainder : cleanName);
        if (dashNumMatch != null) {
          final parsedEp = int.tryParse(dashNumMatch.group(1)!);
          final isLikelyYearOrRes = parsedEp != null &&
              ((parsedEp >= 1900 && parsedEp <= 2099) ||
                  parsedEp == 480 ||
                  parsedEp == 720 ||
                  parsedEp == 1080 ||
                  parsedEp == 2160);
          if (parsedEp != null && parsedEp > 0 && !isLikelyYearOrRes) {
            episodeNumber = parsedEp;
            foundEpisodeNumber = true;
            isSeries = true;
          }
        }
      }

      // Anime naming convention without dash: "[Group] Title 01 [Tags]", "Title_01_(Tags)", or "Title 01 [Tags]"
      if (!foundEpisodeNumber && (!isSeries || !isExtrasDir)) {
        final strippedLeading = cleanName.replaceFirst(RegExp(r'^\[[^\]]+\][\s_]*'), '');
        final spaceNumMatch = RegExp(
          r'^(.*?)[\s_]+(\d{1,3})(?:v\d+)?(?:\s*\[|\s*\(|\s*_|\s*$)',
          caseSensitive: false,
        ).firstMatch(strippedLeading);

        if (spaceNumMatch != null) {
          final candidateTitle = spaceNumMatch.group(1)!.trim();
          final epCandidate = int.tryParse(spaceNumMatch.group(2)!);
          if (candidateTitle.length >= 2 && epCandidate != null && epCandidate > 0) {
            episodeNumber = epCandidate;
            foundEpisodeNumber = true;
            isSeries = true;
            if (cleanTitle.isEmpty) {
              final cleanParent = _cleanTitleString(parentDirName);
              if (cleanParent.toLowerCase().contains(candidateTitle.toLowerCase()) &&
                  !cleanParent.toLowerCase().contains('season') &&
                  !cleanParent.toLowerCase().contains('episode')) {
                cleanTitle = cleanParent;
              } else {
                cleanTitle = titleFromDash ?? _cleanTitleString(candidateTitle);
              }
            }
          }
        }
      }

      if (!foundEpisodeNumber && !isSeries) {
        final bracketMatch = RegExp(r'\[(\d{1,3})(?:v\d)?\]').firstMatch(cleanName);
        if (bracketMatch != null) {
          episodeNumber = int.tryParse(bracketMatch.group(1)!) ?? 1;
          foundEpisodeNumber = true;
          isSeries = true;
        }
      }
    }

    if (cleanTitle.isEmpty) {
      cleanTitle = titleFromDash ?? '';
    }

    if (cleanTitle.isEmpty) {
      if (parentDirName.length > 2 && !parentDirName.contains(':')) {
        cleanTitle = _cleanTitleString(parentDirName);
      } else {
        cleanTitle = _cleanTitleString(cleanName);
      }
    }

    if (cleanTitle.isEmpty) {
      cleanTitle = cleanName;
    }

    String episodeLabel;
    if (isExtrasDir) {
      final cleanEp = _cleanTitleString(remainder.isNotEmpty ? remainder : cleanName);
      episodeLabel = cleanEp.isNotEmpty ? cleanEp : 'Ekstra $episodeNumber';
    } else if (isSeries) {
      episodeLabel = season > 1 ? 'Season $season Episode $episodeNumber' : 'Episode $episodeNumber';
    } else {
      episodeLabel = 'Putar Film';
    }

    final String groupKey = isSeries
        ? 'series_${cleanTitle.toLowerCase().replaceAll(RegExp(r'\s+'), '_')}'
        : 'film_${cleanTitle.toLowerCase().replaceAll(RegExp(r'\s+'), '_')}';

    return _ParsedFileInfo(
      cleanTitle: cleanTitle,
      year: year,
      season: season,
      episodeNumber: episodeNumber,
      episodeLabel: episodeLabel,
      isSeries: isSeries,
      groupKey: groupKey,
      seasonName: seasonName,
    );
  }

  /// Clean title string removing release tags, brackets, and separators
  static String _cleanTitleString(String raw) {
    String text = raw;

    // Strip only known video extensions (preserves titles like "Dr. No", "Mr. Robot", "Steins;Gate 0.5")
    text = text.replaceAll(
      RegExp(r'\.(mp4|mkv|avi|mov|wmv|flv|webm|ts|m4v|mpg|mpeg|3gp)$', caseSensitive: false),
      '',
    );

    // Clean common mojibake sequences and noisy symbols
    text = text
        .replaceAll('â˜†', ' ')
        .replaceAll('â˜…', ' ')
        .replaceAll('☆', ' ')
        .replaceAll('★', ' ')
        .replaceAll('â€¢', ' ')
        .replaceAll('•', ' ')
        .replaceAll('â€™', "'")
        .replaceAll('â€œ', '"')
        .replaceAll('â€\u009d', '"')
        .replaceAll('â€”', ' ')
        .replaceAll('â€“', ' ')
        .replaceAll('â€¦', ' ')
        .replaceAll('Ã—', 'x')
        .replaceAll('Â', '');

    text = text.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
    text = text.replaceAll(RegExp(r'\{[^\}]*\}'), ' ');
    text = text.replaceAll(RegExp(r'\([^\)]*\)'), ' ');

    text = text.replaceAll(RegExp(r'[\._\-]'), ' ');

    final stopWords = RegExp(
      r'\b(2160p|1080p|720p|480p|4k|uhd|fhd|bluray|blu-ray|web-dl|webdl|webrip|hdrip|dvdrip|h264|x264|h265|x265|hevc|av1|10bit|aac|ac3|dts|remux|yts|yify|rarbg|eztv|repack|proper|complete|sub|dub|v\d+)\b',
      caseSensitive: false,
    );
    text = text.replaceAll(stopWords, ' ');
    text = text.replaceAll(RegExp(r'\s+v\d+$', caseSensitive: false), ' ');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (text.isNotEmpty) {
      text = text.split(' ').map((word) {
        if (word.isEmpty) return word;
        return word[0].toUpperCase() + (word.length > 1 ? word.substring(1) : '');
      }).join(' ');
    }

    return text;
  }

  /// Check if a title string contains corrupted mojibake characters
  static bool _hasMojibake(String text) {
    if (text.isEmpty) return false;
    return text.contains('ãu') ||
        text.contains('â€') ||
        text.contains('â˜') ||
        text.contains('ï¿½') ||
        text.contains('Ã') ||
        text.contains('Â') ||
        RegExp(r'[ãâæéäï][”Ÿ•—‚Šº®¤«œ±¿¥%~+]+').hasMatch(text);
  }

  /// Public helper to clean title for single file picker
  static String cleanVideoTitle(String rawFileName) {
    return _cleanTitleString(rawFileName);
  }

  /// Exposes filename parsing result for unit tests.
  static ({String cleanTitle, int season, int episodeNumber, bool isSeries}) parseVideoFileMetadata(String filePath) {
    final info = _parseVideoFile(File(filePath));
    return (
      cleanTitle: info.cleanTitle,
      season: info.season,
      episodeNumber: info.episodeNumber,
      isSeries: info.isSeries,
    );
  }
}

class _ParsedFileInfo {
  final String cleanTitle;
  final String? year;
  final int season;
  final int episodeNumber;
  final String episodeLabel;
  final bool isSeries;
  final String groupKey;
  final String seasonName;

  _ParsedFileInfo({
    required this.cleanTitle,
    this.year,
    required this.season,
    required this.episodeNumber,
    required this.episodeLabel,
    required this.isSeries,
    required this.groupKey,
    this.seasonName = 'Season 1',
  });
}

class _ParsedGroup {
  final String cleanTitle;
  final String? year;
  final String folderPath;
  bool isSeries;
  final List<Episode> episodes = [];

  _ParsedGroup({
    required this.cleanTitle,
    this.year,
    required this.folderPath,
    this.isSeries = false,
  });
}
