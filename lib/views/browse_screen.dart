import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/media_item.dart';
import '../services/debug_logger.dart';
import '../services/library_service.dart';
import '../services/preview_player_service.dart';
import '../services/thumbnail_service.dart';
import '../services/watch_history_service.dart';
import '../components/hero_billboard.dart';
import '../components/content_row.dart';
import '../components/continue_watching_row.dart';
import '../components/custom_app_title_bar.dart';
import '../components/in_app_player.dart';
import '../components/item_detail_dialog.dart';
import '../components/video_card.dart';
import '../components/edit_metadata_dialog.dart';
import '../utils/media_ui_helpers.dart';
import 'catalog_browse_view.dart';
import 'settings_view.dart';

class BrowseScreen extends StatefulWidget {
  final List<String> initialFolders;
  final List<MediaItem> initialItems;
  final List<WatchHistoryEntry> initialHistory;

  const BrowseScreen({
    super.key,
    this.initialFolders = const [],
    this.initialItems = const [],
    this.initialHistory = const [],
  });

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  String _activeCategory = 'all'; // 'all', 'films', 'series'
  String _searchQuery = '';
  bool _isSearchOpen = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final GlobalKey _searchBarKey = GlobalKey();
  MediaItem? _currentlyPlaying;
  List<MediaItem> _currentPlayingPlaylist = [];
  bool _isMiniplayer = false;

  // Local files and multi-folder state
  List<String> _connectedFolders = [];
  List<MediaItem> _localItems = [];
  List<WatchHistoryEntry> _watchHistory = [];
  bool _isScanningFolders = false;
  int _scanGeneration = 0;
  final ValueNotifier<String?> _scanStatusNotifier = ValueNotifier<String?>(null);

  // Memoized catalog data to avoid recomputing on every frame
  List<MapEntry<String, List<MediaItem>>> _cachedGroupEntries = [];
  List<MediaItem> _cachedFeaturedCandidates = [];
  final int _sessionShuffleSeed = DateTime.now().microsecondsSinceEpoch;

  // Scroll controller for the main catalog
  final ScrollController _catalogScrollController = ScrollController();

  // Active modal dialog item (rendered directly in BrowseScreen Stack to avoid Navigator DialogRoute frame freeze)
  MediaItem? _activeDetailItem;
  List<MediaItem> _cachedSimilarItems = const [];
  int _featuredIndex = 0;
  final ValueNotifier<bool> _isHeroVisibleNotifier = ValueNotifier<bool>(true);
  Timer? _featuredRotationTimer;
  Timer? _searchDebounceTimer;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
    _connectedFolders = List<String>.from(widget.initialFolders);
    _localItems = List<MediaItem>.from(widget.initialItems);
    _watchHistory = _normalizeHistoryWithCatalog(
      List<WatchHistoryEntry>.from(widget.initialHistory),
      _localItems,
    );

    _recomputeCatalogGroups();
    if (_cachedFeaturedCandidates.isNotEmpty) {
      _featuredIndex = math.Random().nextInt(_cachedFeaturedCandidates.length);
    }

    _catalogScrollController.addListener(_onCatalogScroll);
    _startFeaturedRotation();

    // Precache visible card backdrops & logos into GPU image cache right after first frame so initial scroll has zero decode stutter
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prewarmCatalogImages();
    });

    // Load or sync library in background without blocking initial render
    _loadInitialLibrary(hasPreloadedCache: _localItems.isNotEmpty || _connectedFolders.isNotEmpty);
    _loadWatchHistory();
  }

  void _prewarmCatalogImages() {
    if (!mounted) return;
    for (final item in _localItems.take(24)) {
      final backdrop = item.backdropUrl;
      if (backdrop != null && backdrop.isNotEmpty && !backdrop.startsWith('http')) {
        if (LocalThumbnailService.fileExistsCached(backdrop)) {
          precacheImage(
            ResizeImage(FileImage(File(backdrop)), width: 600),
            context,
          );
        }
      }
      final logo = item.logoUrl;
      if (logo != null && logo.isNotEmpty && !logo.startsWith('http')) {
        if (LocalThumbnailService.fileExistsCached(logo)) {
          precacheImage(
            ResizeImage(FileImage(File(logo)), width: 320),
            context,
          );
        }
      }
    }
  }

  @override
  void dispose() {
    LocalLibraryService.stopWatchingFolders();
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    _featuredRotationTimer?.cancel();
    _searchDebounceTimer?.cancel();
    _catalogScrollController.removeListener(_onCatalogScroll);
    _catalogScrollController.dispose();
    _isHeroVisibleNotifier.dispose();
    _scanStatusNotifier.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    // Do not intercept keyboard shortcuts if full-screen video is playing or detail dialog is active
    if ((_currentlyPlaying != null && !_isMiniplayer) || _activeDetailItem != null) return false;

    final isCtrlPressed = HardwareKeyboard.instance.isControlPressed;
    // Ctrl + F or F3: toggle / open search
    if ((isCtrlPressed && event.logicalKey == LogicalKeyboardKey.keyF) ||
        event.logicalKey == LogicalKeyboardKey.f3) {
      if (!_isSearchOpen) {
        setState(() => _isSearchOpen = true);
        Future.delayed(const Duration(milliseconds: 60), () {
          if (mounted) {
            _searchFocusNode.requestFocus();
            if (_searchController.text.isNotEmpty) {
              _searchController.selection = TextSelection(
                baseOffset: 0,
                extentOffset: _searchController.text.length,
              );
            }
          }
        });
        return true;
      } else {
        // Toggle close
        setState(() {
          _isSearchOpen = false;
          _searchController.clear();
          _searchQuery = '';
          _recomputeCatalogGroups();
        });
        _searchFocusNode.unfocus();
        return true;
      }
    }

    // Escape: close search if currently open
    if (event.logicalKey == LogicalKeyboardKey.escape && (_isSearchOpen || _searchQuery.isNotEmpty)) {
      setState(() {
        _isSearchOpen = false;
        _searchController.clear();
        _searchQuery = '';
        _recomputeCatalogGroups();
      });
      _searchFocusNode.unfocus();
      return true;
    }

    return false;
  }

  void _onCatalogScroll() {
    if (!_catalogScrollController.hasClients) return;
    VideoCard.closeActivePopover();
    PreviewPlayerService.instance.notifyScrollActivity();
    final offset = _catalogScrollController.offset;
    final bool isVisible = offset < 60.0;
    if (_isHeroVisibleNotifier.value != isVisible) {
      _isHeroVisibleNotifier.value = isVisible;
    }
    if (offset > 60.0) {
      final owner = PreviewPlayerService.instance.activeOwnerId;
      if (owner != null && owner.startsWith('hero-')) {
        PreviewPlayerService.instance.releasePreview(owner);
      }
    }
  }

  /// Normalize & deduplicate watch history against the library catalog so that
  /// 1 Series only ever occupies 1 slot in "Lanjutkan Menonton" (showing the
  /// series title, last episode played, and last timestamp played).
  List<WatchHistoryEntry> _normalizeHistoryWithCatalog(
    List<WatchHistoryEntry> entries,
    List<MediaItem> catalog,
  ) {
    if (entries.isEmpty || catalog.isEmpty) return [];
    final Set<String> seenSeriesOrMediaIds = {};
    final List<WatchHistoryEntry> result = [];

    for (final entry in entries) {
      WatchHistoryEntry? normalized;
      for (final item in catalog) {
        if (item.isSeries && item.episodes.isNotEmpty) {
          Episode? matchedEp;
          for (final ep in item.episodes) {
            if (ep.videoPath == entry.videoPath ||
                ep.id == entry.episodeId ||
                ep.id == entry.mediaId) {
              matchedEp = ep;
              break;
            }
          }
          if (matchedEp != null || item.id == entry.mediaId) {
            final ep = matchedEp ?? item.episodes.first;
            final regularEps = item.episodes.where((e) => e.season != 0).toList();
            final lastEp = regularEps.isNotEmpty ? regularEps.last : item.episodes.last;
            final bool isLastEpisode = ep.id == lastEp.id || ep.videoPath == lastEp.videoPath;
            final bool isFinished = entry.isCompleted || entry.progress >= 0.95;

            if (isFinished && isLastEpisode) {
              // Series finished to the end: remove from "Lanjutkan Menonton"
              WatchHistoryService.removeEntry(item.id, videoPath: entry.videoPath);
              normalized = null;
              break;
            }

            normalized = entry.copyWith(
              mediaId: item.id,
              mediaTitle: item.title,
              isSeries: true,
              episodeId: ep.id,
              seasonNumber: ep.season,
              episodeNumber: ep.episodeNumber,
              episodeTitle: ep.title,
              thumbnailPath: (ep.thumbnail != null && ep.thumbnail!.isNotEmpty)
                  ? ep.thumbnail!
                  : (item.customThumbnail ?? entry.thumbnailPath),
            );
            break;
          }
        } else if (item.id == entry.mediaId || item.videoPath == entry.videoPath) {
          final bool isFinished = entry.isCompleted || entry.progress >= 0.95;
          if (isFinished) {
            // Movie finished: remove from "Lanjutkan Menonton"
            WatchHistoryService.removeEntry(item.id, videoPath: entry.videoPath);
            normalized = null;
            break;
          }
          normalized = entry.copyWith(
            mediaId: item.id,
            mediaTitle: item.title,
            isSeries: false,
            thumbnailPath: item.customThumbnail ?? entry.thumbnailPath,
          );
          break;
        }
      }

      if (normalized == null) {
        // Video does not belong to any active item in the catalog
        continue;
      }

      if (seenSeriesOrMediaIds.contains(normalized.mediaId)) {
        continue;
      }
      seenSeriesOrMediaIds.add(normalized.mediaId);
      result.add(normalized);
    }
    WatchHistoryService.updateMemoryEntries(result);
    return result;
  }

  Future<void> _loadWatchHistory() async {
    final history = await WatchHistoryService.getRecentHistory();
    if (mounted) {
      setState(() {
        _watchHistory = _normalizeHistoryWithCatalog(history, _localItems);
      });
    }
  }

  void _resumeFromHistory(WatchHistoryEntry entry) {
    // 1. Check if the entry belongs to a Series in our library
    for (final it in _localItems) {
      if (it.isSeries && it.episodes.isNotEmpty) {
        Episode? matchedEp;
        for (final ep in it.episodes) {
          if (ep.videoPath == entry.videoPath ||
              ep.id == entry.episodeId ||
              ep.id == entry.mediaId) {
            matchedEp = ep;
            break;
          }
        }
        if (matchedEp != null || it.id == entry.mediaId) {
          _playSpecificEpisode(it, matchedEp ?? it.episodes.first);
          return;
        }
      }
    }

    // 2. Check if the entry matches a Movie in our library
    for (final it in _localItems) {
      if (it.id == entry.mediaId || it.videoPath == entry.videoPath) {
        _playMedia(it);
        return;
      }
    }

    // 3. Fallback for direct standalone video files
    final fallback = MediaItem(
      id: entry.mediaId,
      title: entry.mediaTitle,
      description: '',
      genre: '',
      maturity: '',
      category: entry.category,
      videoPath: entry.videoPath,
      customThumbnail: entry.thumbnailPath,
      isSeries: entry.isSeries,
    );
    _playMedia(fallback);
  }

  /// Instant Cache-First Startup + Non-blocking Background Sync
  Future<void> _loadInitialLibrary({
    bool forceFullRescan = false,
    bool hasPreloadedCache = false,
  }) async {
    if (!hasPreloadedCache || forceFullRescan) {
      final folders = await LocalLibraryService.getConnectedFolders();
      final cached = await LocalLibraryService.getCachedItems(forceReload: forceFullRescan);

      if (mounted) {
        setState(() {
          _connectedFolders = folders;
          if (forceFullRescan || _localItems.isEmpty || cached.length != _localItems.length) {
            _localItems = cached;
            _watchHistory = _normalizeHistoryWithCatalog(_watchHistory, _localItems);
            _recomputeCatalogGroups();
            if (_cachedFeaturedCandidates.isNotEmpty) {
              _featuredIndex = math.Random().nextInt(_cachedFeaturedCandidates.length);
            }
          }
        });
        _startFeaturedRotation();
      }
    }

    if (_connectedFolders.isNotEmpty) {
      LocalLibraryService.startWatchingFolders(_connectedFolders, () {
        if (mounted && !_isScanningFolders) {
          _runBackgroundScan(forceFullRescan: false);
        }
      });
      if (!forceFullRescan && _localItems.isNotEmpty) {
        // Defer lightweight diff check slightly so startup animations and initial scroll are 100% untouched
        await Future.delayed(const Duration(milliseconds: 1200));
        if (!mounted) return;
      }
      _runBackgroundScan(forceFullRescan: forceFullRescan);
    } else if (mounted) {
      LocalLibraryService.stopWatchingFolders();
      LocalLibraryService.cancelScan();
      final configuredFolders = await LocalLibraryService.getAllConfiguredFolders();
      if (!mounted) return;
      if (configuredFolders.isEmpty) {
        setState(() {
          _connectedFolders = [];
          _localItems = [];
          _isScanningFolders = false;
          _recomputeCatalogGroups();
        });
        _scanStatusNotifier.value = null;
        await LocalLibraryService.cleanOrphanedCache();
        await WatchHistoryService.clearHistory();
      } else {
        setState(() {
          _connectedFolders = [];
          _isScanningFolders = false;
          _recomputeCatalogGroups();
        });
        _scanStatusNotifier.value = 'Perangkat eksternal belum terhubung';
      }
    }
  }

  /// Incrementally scan ONLY a newly added folder without touching or rescanning existing folders.
  Future<void> _scanAddedFolder(String folderPath) async {
    final folders = await LocalLibraryService.getConnectedFolders();
    if (!mounted) return;
    setState(() {
      _connectedFolders = folders;
    });
    if (_connectedFolders.isNotEmpty) {
      LocalLibraryService.startWatchingFolders(_connectedFolders, () {
        if (mounted && !_isScanningFolders) {
          _runBackgroundScan(forceFullRescan: false);
        }
      });
    }
    await _runBackgroundScan(
      forceFullRescan: false,
      onlyFolders: [folderPath],
    );
  }

  Future<void> _runBackgroundScan({
    bool forceFullRescan = false,
    List<String>? onlyFolders,
  }) async {
    final bool isIncrementalNewFolder = onlyFolders != null && onlyFolders.isNotEmpty;
    if (_isScanningFolders && !forceFullRescan && !isIncrementalNewFolder) return;
    if ((forceFullRescan || isIncrementalNewFolder) && _isScanningFolders) {
      LocalLibraryService.cancelScan();
    }
    final int myGen = ++_scanGeneration;

    final bool showToast = forceFullRescan || isIncrementalNewFolder || _localItems.isEmpty;
    if (mounted && showToast) {
      setState(() {
        _isScanningFolders = true;
      });
      _scanStatusNotifier.value = isIncrementalNewFolder
          ? 'Memindai folder baru...'
          : 'Memeriksa folder & video...';
    }

    try {
      final items = await LocalLibraryService.scanAllFolders(
        fetchOnlineMetadata: true,
        extractThumbnails: forceFullRescan || isIncrementalNewFolder,
        quickDiffCheck: !forceFullRescan && !isIncrementalNewFolder && _localItems.isNotEmpty,
        onlyFolders: onlyFolders,
        onProgress: (msg) {
          if (mounted && myGen == _scanGeneration) {
            if (!_isScanningFolders) {
              setState(() => _isScanningFolders = true);
            }
            _scanStatusNotifier.value = msg;
          }
        },
        onItemReady: (progressiveItems, readyItem) {
          if (!mounted || myGen != _scanGeneration) return;
          if (progressiveItems.length != _localItems.length ||
              !_sameItemIds(progressiveItems, _localItems)) {
            setState(() {
              _localItems = progressiveItems;
              _watchHistory = _normalizeHistoryWithCatalog(_watchHistory, _localItems);
              _recomputeCatalogGroups();
            });
          }
        },
      );

      if (mounted && myGen == _scanGeneration) {
        final activeFolders = await LocalLibraryService.getConnectedFolders();
        final configuredFolders = await LocalLibraryService.getAllConfiguredFolders();
        if (!mounted || myGen != _scanGeneration) return;
        if (activeFolders.isEmpty && configuredFolders.isEmpty) {
          setState(() {
            _connectedFolders = [];
            _localItems = [];
            _isScanningFolders = false;
            _recomputeCatalogGroups();
          });
          _scanStatusNotifier.value = null;
          return;
        }

        final bool changed = forceFullRescan ||
            items.length != _localItems.length ||
            !_sameItemIds(items, _localItems);
        if (changed || _isScanningFolders) {
          setState(() {
            _localItems = items;
            _watchHistory = _normalizeHistoryWithCatalog(_watchHistory, _localItems);
            _isScanningFolders = false;
            if (changed) {
              _recomputeCatalogGroups();
            }
          });
        }
        _scanStatusNotifier.value = null;
      }
    } catch (e) {
      debugPrint('Background sync error: $e');
      if (mounted && myGen == _scanGeneration) {
        setState(() {
          _isScanningFolders = false;
        });
        _scanStatusNotifier.value = null;
      }
    }
  }

  bool _sameItemIds(List<MediaItem> a, List<MediaItem> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].episodes.length != b[i].episodes.length ||
          a[i].customThumbnail != b[i].customThumbnail) {
        return false;
      }
    }
    return true;
  }

  void _openEditMetadataDialog(MediaItem item) {
    showDialog(
      context: context,
      builder: (_) => EditMetadataDialog(
        item: item,
        onSave: (updatedItem) async {
          await LocalLibraryService.saveCustomMetadata(updatedItem.id, updatedItem);
          if (!mounted) return;
          setState(() {
            final idx = _localItems.indexWhere((it) => it.id == updatedItem.id);
            if (idx != -1) {
              _localItems[idx] = updatedItem;
            } else {
              _localItems.add(updatedItem);
            }
            _watchHistory = _normalizeHistoryWithCatalog(_watchHistory, _localItems);
            _recomputeCatalogGroups();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFFE50914),
              content: Text('Informasi "${updatedItem.title}" berhasil disimpan!'),
              duration: const Duration(seconds: 3),
            ),
          );
        },
      ),
    );
  }

  void _recomputeCatalogGroups() {
    // 1. Recompute featured candidates
    List<MediaItem> source = [];
    if (_localItems.isNotEmpty) {
      if (_activeCategory == 'series') {
        source = _localItems.where((it) => it.isSeries).toList();
      } else if (_activeCategory == 'films') {
        source = _localItems.where((it) => !it.isSeries).toList();
      } else {
        source = List<MediaItem>.from(_localItems);
      }
    }
    if (source.length > 1) {
      source.shuffle(math.Random(_sessionShuffleSeed));
    }
    _cachedFeaturedCandidates = source.take(8).toList();

    // 2. Recompute display groups
    final groups = _buildDisplayGroups();
    _cachedGroupEntries = groups.entries.toList();
  }

  MediaItem? get _featuredItem {
    if (_cachedFeaturedCandidates.isEmpty) return null;
    final safeIndex = _featuredIndex.clamp(0, _cachedFeaturedCandidates.length - 1);
    return _cachedFeaturedCandidates[safeIndex];
  }

  void _startFeaturedRotation() {
    _featuredRotationTimer?.cancel();
    _featuredRotationTimer = Timer.periodic(const Duration(seconds: 35), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final activeOwner = PreviewPlayerService.instance.activeOwnerId;
      final isCardOrDialogActive = activeOwner != null && !activeOwner.startsWith('hero-');
      final isHeroVisible = !_catalogScrollController.hasClients || _catalogScrollController.offset < 400.0;
      if (_currentlyPlaying == null &&
          !isCardOrDialogActive &&
          isHeroVisible &&
          _searchQuery.isEmpty &&
          _cachedFeaturedCandidates.length > 1) {
        setState(() {
          _featuredIndex = (_featuredIndex + 1) % _cachedFeaturedCandidates.length;
        });
      }
    });
  }

  void _nextFeatured() {
    if (_cachedFeaturedCandidates.isEmpty) return;
    setState(() {
      _featuredIndex = (_featuredIndex + 1) % _cachedFeaturedCandidates.length;
    });
    _startFeaturedRotation();
  }

  void _prevFeatured() {
    if (_cachedFeaturedCandidates.isEmpty) return;
    setState(() {
      _featuredIndex = (_featuredIndex - 1 + _cachedFeaturedCandidates.length) % _cachedFeaturedCandidates.length;
    });
    _startFeaturedRotation();
  }

  void _selectFeaturedIndex(int index) {
    if (_cachedFeaturedCandidates.isEmpty) return;
    setState(() {
      _featuredIndex = index.clamp(0, _cachedFeaturedCandidates.length - 1);
    });
    _startFeaturedRotation();
  }

  void _playMedia(MediaItem item) {
    VideoCard.closeActivePopover();
    PreviewPlayerService.instance.suspendAll();

    if (item.isSeries && item.episodes.isNotEmpty) {
      // Check if user has a last-watched episode for this series; if so, resume from that episode!
      Episode targetEpisode = item.episodes.first;
      WatchHistoryEntry? matchedEntry = WatchHistoryService.getProgressSync(item.id);
      if (matchedEntry == null) {
        for (final entry in _watchHistory) {
          if (entry.mediaId == item.id ||
              item.episodes.any((ep) => ep.videoPath == entry.videoPath || ep.id == entry.episodeId)) {
            matchedEntry = entry;
            break;
          }
        }
      }
      if (matchedEntry != null) {
        for (final ep in item.episodes) {
          if (ep.videoPath == matchedEntry.videoPath ||
              ep.id == matchedEntry.episodeId ||
              (matchedEntry.seasonNumber != null &&
                  matchedEntry.episodeNumber != null &&
                  ep.season == matchedEntry.seasonNumber &&
                  ep.episodeNumber == matchedEntry.episodeNumber)) {
            targetEpisode = ep;
            break;
          }
        }
      }
      _playSpecificEpisode(item, targetEpisode);
    } else {
      final movies = _localItems.where((it) => !it.isSeries).toList();
      final playlist = movies.isNotEmpty ? movies : [item];

      setState(() {
        _currentlyPlaying = item;
        _currentPlayingPlaylist = playlist;
      });
    }
  }

  void _playSpecificEpisode(MediaItem parentItem, Episode episode) {
    PreviewPlayerService.instance.suspendAll();
    final playlist = parentItem.episodes
        .map((ep) => MediaUiHelpers.buildEpisodeMediaItem(parent: parentItem, episode: ep))
        .toList();
    final playItem = playlist.firstWhere(
      (it) => it.id == episode.id && it.videoPath == episode.videoPath,
      orElse: () => MediaUiHelpers.buildEpisodeMediaItem(parent: parentItem, episode: episode),
    );

    setState(() {
      _currentlyPlaying = playItem;
      _currentPlayingPlaylist = playlist;
    });
  }

  List<MediaItem> _getSimilarItems(MediaItem item) {
    if (_localItems.isEmpty) return const [];
    final currentGenres = item.genre
        .toLowerCase()
        .split(',')
        .map((g) => g.trim())
        .where((g) => g.isNotEmpty)
        .toSet();

    final candidates = _localItems.where((other) => other.id != item.id).toList();
    if (candidates.isEmpty) return const [];

    candidates.sort((a, b) {
      int scoreA = 0;
      int scoreB = 0;
      if (a.isSeries == item.isSeries) scoreA += 2;
      if (b.isSeries == item.isSeries) scoreB += 2;
      for (final g in a.genre.toLowerCase().split(',')) {
        if (currentGenres.contains(g.trim())) scoreA += 3;
      }
      for (final g in b.genre.toLowerCase().split(',')) {
        if (currentGenres.contains(g.trim())) scoreB += 3;
      }
      return scoreB.compareTo(scoreA);
    });

    return candidates.take(6).toList();
  }

  Future<void> _showItemDetails(MediaItem item) async {
    DebugLogger.log('_showItemDetails START: item=${item.title}, id=${item.id}');
    VideoCard.closeActivePopover();
    PreviewPlayerService.instance.stopAll();
    if (mounted) {
      setState(() {
        _activeDetailItem = item;
        _cachedSimilarItems = _getSimilarItems(item);
      });
    }
  }

  void _closeItemDetails() {
    DebugLogger.log('_closeItemDetails CALLED: current=${_activeDetailItem?.title}');
    VideoCard.closeActivePopover();
    PreviewPlayerService.instance.stopAll();
    if (mounted && _activeDetailItem != null) {
      setState(() {
        _activeDetailItem = null;
        _cachedSimilarItems = const [];
      });
    }
  }

  Future<void> _pickLocalFile() async {
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: 'Pilih File Video untuk Diputar Langsung',
        type: FileType.custom,
        allowedExtensions: ['mp4', 'mkv', 'avi', 'mov', 'webm', 'ts', 'm4v'],
      );

      if (!mounted) return;
      if (files.isNotEmpty && files.first.path != null) {
        final filePath = files.first.path!;
        final fileName = files.first.name;
        final cleanTitle = LocalLibraryService.cleanVideoTitle(fileName);

        final existingIdx = _localItems.indexWhere((it) => it.videoPath == filePath);
        if (existingIdx != -1) {
          _playMedia(_localItems[existingIdx]);
          return;
        }

        final localItem = MediaItem(
          id: 'single-${DateTime.now().millisecondsSinceEpoch}',
          title: cleanTitle,
          description: 'File video lokal:\n$filePath',
          genre: 'File Lokal',
          maturity: '13',
          category: 'films',
          videoPath: filePath,
        );

        setState(() {
          _localItems.insert(0, localItem);
          _recomputeCatalogGroups();
        });

        _playMedia(localItem);
      }
    } catch (e) {
      debugPrint('Error picking file: $e');
    }
  }

  Widget _buildFloatingSearchBar() {
    final isOpen = _isSearchOpen || _searchQuery.isNotEmpty;
    final double barWidth = isOpen ? 340.0 : 46.0;

    return TapRegion(
      groupId: 'browse_floating_search_group',
      onTapOutside: (_) {
        if (_isSearchOpen && _searchController.text.trim().isEmpty) {
          setState(() {
            _isSearchOpen = false;
            _searchController.clear();
            _searchQuery = '';
            _recomputeCatalogGroups();
          });
          _searchFocusNode.unfocus();
        }
      },
      child: AnimatedContainer(
        key: _searchBarKey,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        width: barWidth,
        height: 46,
        decoration: BoxDecoration(
          color: const Color(0xF2181818),
          borderRadius: BorderRadius.circular(23),
          border: Border.all(
            color: isOpen ? const Color(0xFFE50914) : Colors.white24,
            width: 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.65),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: isOpen
              ? Row(
                  children: [
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(
                        Icons.search_rounded,
                        color: Color(0xFFE50914),
                        size: 22,
                      ),
                      splashRadius: 18,
                      tooltip: 'Tutup Pencarian',
                      onPressed: () {
                        if (_searchController.text.trim().isEmpty) {
                          setState(() {
                            _isSearchOpen = false;
                          });
                          _searchFocusNode.unfocus();
                        } else {
                          _searchFocusNode.requestFocus();
                        }
                      },
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                        ),
                        cursorColor: const Color(0xFFE50914),
                        decoration: const InputDecoration(
                          hintText: 'Cari film, serial, anime...',
                          hintStyle: TextStyle(
                            color: Colors.white38,
                            fontSize: 13.5,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (query) {
                          _searchDebounceTimer?.cancel();
                          if (query.trim().isEmpty) {
                            setState(() {
                              _searchQuery = '';
                              _recomputeCatalogGroups();
                            });
                            return;
                          }
                          _searchDebounceTimer = Timer(const Duration(milliseconds: 180), () {
                            if (!mounted) return;
                            setState(() {
                              _searchQuery = query;
                              _recomputeCatalogGroups();
                            });
                          });
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                      splashRadius: 18,
                      tooltip: 'Tutup Pencarian',
                      onPressed: () {
                        setState(() {
                          _searchController.clear();
                          _searchQuery = '';
                          _isSearchOpen = false;
                          _recomputeCatalogGroups();
                        });
                        _searchFocusNode.unfocus();
                      },
                    ),
                    const SizedBox(width: 4),
                  ],
                )
              : InkWell(
                  borderRadius: BorderRadius.circular(23),
                  onTap: () {
                    setState(() {
                      _isSearchOpen = true;
                    });
                    Future.delayed(const Duration(milliseconds: 60), () {
                      if (mounted) {
                        _searchFocusNode.requestFocus();
                        if (_searchController.text.isNotEmpty) {
                          _searchController.selection = TextSelection(
                            baseOffset: 0,
                            extentOffset: _searchController.text.length,
                          );
                        }
                      }
                    });
                  },
                  child: const Center(
                    child: Icon(
                      Icons.search_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Map<String, List<MediaItem>> _buildDisplayGroups() {
    if (_searchQuery.trim().length >= 2) {
      final q = _searchQuery.trim().toLowerCase();
      final filtered = _localItems.where((item) => item.matchesSearchQuery(q)).toList();

      return {'Hasil Pencarian "$_searchQuery" (${filtered.length})': filtered};
    }

    if (_localItems.isNotEmpty) {
      final seriesList = _localItems.where((it) => it.isSeries).toList();
      final filmsList = _localItems.where((it) => !it.isSeries).toList();

      if (_activeCategory == 'films') {
        if (filmsList.isEmpty) {
          return {'Film Layar Lebar': []};
        }
        return _groupByGenre(filmsList, 'Film');
      }

      if (_activeCategory == 'series') {
        if (seriesList.isEmpty) {
          return {'Serial TV & Anime': []};
        }
        return _groupByGenre(seriesList, 'Serial');
      }

      final Map<String, List<MediaItem>> groups = {};

      if (seriesList.isNotEmpty) {
        groups['📺 Serial TV & Anime (${seriesList.length})'] = seriesList;
      }
      if (filmsList.isNotEmpty) {
        groups['🎬 Film Layar Lebar (${filmsList.length})'] = filmsList;
      }

      final genreGroups = _groupByGenre(_localItems, '');
      genreGroups.forEach((k, v) {
        if (!groups.containsKey(k) && v.isNotEmpty) {
          groups[k] = v;
        }
      });

      return groups;
    }

    return {};
  }

  Map<String, List<MediaItem>> _groupByGenre(List<MediaItem> items, String prefix) {
    final Map<String, List<MediaItem>> map = {};
    for (final item in items) {
      final g = item.genre.split(',').first.trim();
      final key = prefix.isNotEmpty ? '$prefix • $g' : g;
      map.putIfAbsent(key, () => []).add(item);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final featured = _featuredItem;
    final bool isPlaying = _currentlyPlaying != null;
    final bool isFullScreenPlaying = isPlaying && !_isMiniplayer;
    final bool isDetailOpen = _activeDetailItem != null;
    final bool showHero = _searchQuery.trim().length < 2 && featured != null && _localItems.isNotEmpty;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (_isSearchOpen && _searchController.text.trim().isEmpty) {
          final renderBox = _searchBarKey.currentContext?.findRenderObject() as RenderBox?;
          if (renderBox != null && renderBox.hasSize) {
            final localOffset = renderBox.globalToLocal(event.position);
            if (!renderBox.paintBounds.contains(localOffset)) {
              setState(() {
                _isSearchOpen = false;
                _searchController.clear();
                _searchQuery = '';
                _recomputeCatalogGroups();
              });
              _searchFocusNode.unfocus();
            }
          }
        }
      },
      child: ColoredBox(
      color: const Color(0xFF111111),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Layer 0: Persistent Catalog View (preserves scroll position & avoids unmount stutter)
          IgnorePointer(
            ignoring: isFullScreenPlaying || isDetailOpen,
            child: ExcludeFocus(
              excluding: isFullScreenPlaying || isDetailOpen,
              child: Scaffold(
                backgroundColor: const Color(0xFF111111),
                body: Column(
                  children: [
                    RepaintBoundary(
                      child: CustomAppTitleBar(
                        activeCategory: _activeCategory,
                        isScanning: _isScanningFolders,
                        onCategoryChanged: (cat) {
                          _searchDebounceTimer?.cancel();
                          _searchController.clear();
                          _searchFocusNode.unfocus();
                          VideoCard.closeActivePopover();
                          setState(() {
                            _activeCategory = cat;
                            _isSearchOpen = false;
                            _searchQuery = '';
                            _featuredIndex = 0;
                            _recomputeCatalogGroups();
                          });
                          if (cat == 'settings') {
                            PreviewPlayerService.instance.suspendAll();
                            _featuredRotationTimer?.cancel();
                          } else if (cat == 'browse') {
                            PreviewPlayerService.instance.stopAll();
                            PreviewPlayerService.instance.resumeFromSuspension();
                            _featuredRotationTimer?.cancel();
                          } else {
                            PreviewPlayerService.instance.resumeFromSuspension();
                            _startFeaturedRotation();
                          }
                        },
                        onSyncLibrary: () => _loadInitialLibrary(forceFullRescan: true),
                      ),
                    ),
                    Expanded(
                      child: IndexedStack(
                        index: _activeCategory == 'settings'
                            ? 2
                            : (_activeCategory == 'browse' ? 1 : 0),
                        children: [
                          // 0: Virtualized Scrollable Content Catalog with Clean Clamping Physics (Home)
                          Stack(
                            children: [
                              PrimaryScrollController(
                                controller: _catalogScrollController,
                                child: CustomScrollView(
                                  controller: _catalogScrollController,
                                  physics: const ClampingScrollPhysics(),
                                  // ignore: deprecated_member_use
                                  cacheExtent: 400.0,
                                  slivers: [
                                    // 1. Hero Banner or Top Spacer
                              SliverToBoxAdapter(
                                child: RepaintBoundary(
                                  child: showHero
                                      ? HeroBillboard(
                                          featuredItem: featured,
                                          isConnected: LocalLibraryService.isMediaItemConnected(
                                            featured,
                                            connectedFolders: _connectedFolders,
                                          ),
                                          isActive: !isPlaying && !isDetailOpen && _activeCategory == 'all',
                                          isVisibleNotifier: _isHeroVisibleNotifier,
                                          onPlay: () => _playMedia(featured),
                                          onMoreInfo: () => _showItemDetails(featured),
                                          currentIndex: _featuredIndex.clamp(
                                            0,
                                            (_cachedFeaturedCandidates.length - 1).clamp(0, 999),
                                          ),
                                          totalCount: _cachedFeaturedCandidates.length,
                                          onNext: _nextFeatured,
                                          onPrev: _prevFeatured,
                                          onSelectIndex: _selectFeaturedIndex,
                                        )
                                      : const SizedBox(height: 20),
                                ),
                              ),

                              // 2. Continue Watching Row (Only displayed if library has active media items)
                              if (_watchHistory.isNotEmpty && _localItems.isNotEmpty && _searchQuery.isEmpty)
                                SliverToBoxAdapter(
                                  child: RepaintBoundary(
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 12, bottom: 8),
                                      child: ContinueWatchingRow(
                                        items: _watchHistory,
                                        onResume: _resumeFromHistory,
                                        onRemove: (entry) async {
                                          await WatchHistoryService.removeEntry(
                                            entry.mediaId,
                                            videoPath: entry.videoPath,
                                          );
                                          _loadWatchHistory();
                                        },
                                      ),
                                    ),
                                  ),
                                ),

                              // 3. Empty State if no folder connected
                              if (_localItems.isEmpty && !_isScanningFolders)
                                SliverToBoxAdapter(
                                  child: Center(
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
                                      padding: const EdgeInsets.all(40),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF181818),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.white12),
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.folder_open_rounded, size: 72, color: Color(0xFFE50914)),
                                          const SizedBox(height: 20),
                                          const Text(
                                            'Selamat Datang di Local TV',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 26,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          const Text(
                                            'Hubungkan folder film atau serial Anda di komputer.\nSetiap film & serial akan otomatis dikelompokkan per judul,\nlengkap dengan poster resmi, sinopsis, dan daftar episode.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(color: Colors.white60, fontSize: 14, height: 1.5),
                                          ),
                                          const SizedBox(height: 28),
                                          ElevatedButton.icon(
                                            onPressed: () {
                                              setState(() {
                                                _activeCategory = 'settings';
                                              });
                                            },
                                            icon: const Icon(Icons.add_to_photos_rounded, color: Colors.white),
                                            label: const Text(
                                              'Hubungkan Folder Film & Serial',
                                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                            ),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFFE50914),
                                              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),

                              // 4. Virtualized Content Rows from User Library
                              if (_cachedGroupEntries.isNotEmpty)
                                SliverPadding(
                                  padding: EdgeInsets.only(top: showHero ? 16.0 : 0.0),
                                  sliver: SliverList.builder(
                                    addAutomaticKeepAlives: false,
                                    itemCount: _cachedGroupEntries.length,
                                    itemBuilder: (context, index) {
                                      final entry = _cachedGroupEntries[index];
                                      if (entry.value.isEmpty) {
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 24),
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              'Tidak ada video dalam kategori "${entry.key}".',
                                              style: const TextStyle(color: Colors.white38, fontSize: 14),
                                            ),
                                          ),
                                        );
                                      }
                                      final bool isSearchRow = _searchQuery.trim().length >= 2;
                                      return ContentRow(
                                        key: ValueKey<String>(isSearchRow ? 'row-search-results' : 'row-${entry.key}'),
                                        title: entry.key,
                                        items: entry.value,
                                        connectedFolders: _connectedFolders,
                                        onPlay: _playMedia,
                                        onSelect: _showItemDetails,
                                        onEdit: _openEditMetadataDialog,
                                      );
                                    },
                                  ),
                                ),

                              const SliverToBoxAdapter(
                                child: SizedBox(height: 60),
                              ),
                            ],
                          ),
                        ),

                        // Isolated non-blocking floating scan progress toast at bottom right
                        Positioned(
                          bottom: 24,
                          right: 28,
                          child: ValueListenableBuilder<String?>(
                            valueListenable: _scanStatusNotifier,
                            builder: (context, statusText, _) {
                              if (!_isScanningFolders || statusText == null) {
                                return const SizedBox.shrink();
                              }
                              return RepaintBoundary(
                                child: Material(
                                  color: Colors.transparent,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xF21E1E1E),
                                      borderRadius: BorderRadius.circular(30),
                                      border: Border.all(color: const Color(0xFFE50914), width: 1.2),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Color(0xFFE50914),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          statusText,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                        // Floating Sticky Search Bar (Top-Right, Below Topbar - Stays visible during full catalog scroll)
                        Positioned(
                          top: 14,
                          right: 28,
                          child: _buildFloatingSearchBar(),
                        ),
                      ],
                    ),

                    // 1: Dedicated Browse View with Filter & Sort (Mounted when active)
                    if (_activeCategory == 'browse')
                      CatalogBrowseView(
                        items: _localItems,
                        connectedFolders: _connectedFolders,
                        onPlay: _playMedia,
                        onSelect: _showItemDetails,
                        onEdit: _openEditMetadataDialog,
                      )
                    else
                      const SizedBox.shrink(),

                    // 2: Full-Page Settings View (Mounted only when active to prevent hidden rebuilds)
                    if (_activeCategory == 'settings')
                      SettingsView(
                        onLibraryUpdated: () => _loadInitialLibrary(forceFullRescan: false),
                        onFolderAdded: _scanAddedFolder,
                        onPickLocalFile: _pickLocalFile,
                        onSyncLibrary: () => _loadInitialLibrary(forceFullRescan: true),
                      )
                    else
                      const SizedBox.shrink(),
                  ],
                ),
              ),
                  ],
                ),
              ),
            ),
          ),

          // Layer 0.5: Dedicated Expanded Card Popover Layer (independent of Navigator Overlay)
          if (!isFullScreenPlaying && !isDetailOpen)
            ValueListenableBuilder<Widget?>(
              valueListenable: VideoCard.activePopoverNotifier,
              builder: (context, popover, _) {
                if (popover == null) return const SizedBox.shrink();
                return Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerSignal: (pointerSignal) {
                    if (pointerSignal is PointerScrollEvent) {
                      VideoCard.closeActivePopover();
                      if (_catalogScrollController.hasClients) {
                        final target = (_catalogScrollController.offset + pointerSignal.scrollDelta.dy).clamp(
                          0.0,
                          _catalogScrollController.position.maxScrollExtent,
                        );
                        _catalogScrollController.jumpTo(target);
                      }
                    }
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [popover],
                  ),
                );
              },
            ),

          // Layer 0.8: Direct In-Tree ItemDetailDialog Overlay (100% unified close behavior for X, Outside Click, and ESC)
          if (!isFullScreenPlaying && isDetailOpen)
            Positioned.fill(
              child: ItemDetailDialog(
                key: ValueKey<String>('detail-dialog-${_activeDetailItem!.id}'),
                item: _activeDetailItem!,
                isConnected: LocalLibraryService.isMediaItemConnected(
                  _activeDetailItem!,
                  connectedFolders: _connectedFolders,
                ),
                similarItems: _cachedSimilarItems,
                onClose: _closeItemDetails,
                onPlay: () {
                  final itemToPlay = _activeDetailItem!;
                  _closeItemDetails();
                  _playMedia(itemToPlay);
                },
                onPlayEpisode: (ep) {
                  final itemToPlay = _activeDetailItem!;
                  _closeItemDetails();
                  _playSpecificEpisode(itemToPlay, ep);
                },
                onItemUpdated: (updatedItem) {
                  setState(() {
                    final idx = _localItems.indexWhere((it) => it.id == updatedItem.id);
                    if (idx != -1) {
                      _localItems[idx] = updatedItem;
                    } else {
                      _localItems.add(updatedItem);
                    }
                    if (_activeDetailItem?.id == updatedItem.id) {
                      _activeDetailItem = updatedItem;
                    }
                    _watchHistory = _normalizeHistoryWithCatalog(_watchHistory, _localItems);
                    _recomputeCatalogGroups();
                  });
                },
                onSelectItem: (other) {
                  _showItemDetails(other);
                },
              ),
            ),

          // Layer 1: Seamless In-App Video Player Overlay (Full or Floating Miniplayer)
          if (isPlaying)
            AnimatedPositioned(
              key: const ValueKey('in_app_player_host_pos'),
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              bottom: _isMiniplayer ? 24 : 0,
              right: _isMiniplayer ? 24 : 0,
              left: _isMiniplayer ? null : 0,
              top: _isMiniplayer ? null : 0,
              width: _isMiniplayer ? 340 : null,
              height: _isMiniplayer ? 192 : null,
              child: InAppPlayer(
                key: const ValueKey('active_in_app_player'),
                item: _currentlyPlaying!,
                playlist: _currentPlayingPlaylist.isNotEmpty
                    ? _currentPlayingPlaylist
                    : [_currentlyPlaying!],
                allLibraryItems: _localItems,
                isMiniplayer: _isMiniplayer,
                onToggleMiniplayer: () {
                  setState(() => _isMiniplayer = !_isMiniplayer);
                },
                onMediaChanged: (newItem) {
                  setState(() {
                    _currentlyPlaying = newItem;
                    if (newItem.isSeries && newItem.episodes.isNotEmpty) {
                      final currentSeriesId = _currentPlayingPlaylist.isNotEmpty
                          ? (_currentPlayingPlaylist.first.seriesId ?? _currentPlayingPlaylist.first.id)
                          : null;
                      final newSeriesId = newItem.seriesId ?? newItem.id;
                      if (currentSeriesId != newSeriesId) {
                        final sTitle = newItem.seriesTitle ?? newItem.title.split(' - ').first;
                        _currentPlayingPlaylist = newItem.episodes
                            .map((ep) => MediaUiHelpers.buildEpisodeMediaItem(
                                  parent: newItem,
                                  episode: ep,
                                  seriesTitleOverride: sTitle,
                                  seriesIdOverride: newSeriesId,
                                ))
                            .toList();
                      }
                    } else {
                      _currentPlayingPlaylist = [newItem];
                    }
                  });
                },
                onClose: () {
                  setState(() {
                    _currentlyPlaying = null;
                    _currentPlayingPlaylist = [];
                    _isMiniplayer = false;
                  });
                  PreviewPlayerService.instance.resumeFromSuspension();
                  _loadWatchHistory();
                },
              ),
            ),
        ],
      ),
    ),
    );
  }
}

