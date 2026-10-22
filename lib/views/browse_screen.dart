import 'dart:async';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/media_item.dart';
import '../data/sample_media.dart';
import '../services/library_service.dart';
import '../services/watch_history_service.dart';
import '../components/netflix_navbar.dart';
import '../components/hero_billboard.dart';
import '../components/content_row.dart';
import '../components/continue_watching_row.dart';
import '../components/custom_app_title_bar.dart';
import '../components/in_app_player.dart';
import '../components/item_detail_dialog.dart';
import '../components/edit_metadata_dialog.dart';
import '../components/manage_folders_dialog.dart';

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  String _activeCategory = 'all'; // 'all', 'films', 'series'
  String _searchQuery = '';
  MediaItem? _currentlyPlaying;
  List<MediaItem> _currentPlayingPlaylist = [];

  // Local files and multi-folder state
  List<String> _connectedFolders = [];
  List<MediaItem> _localItems = [];
  List<WatchHistoryEntry> _watchHistory = [];
  bool _isScanningFolders = false;
  String? _scanStatus;

  // Dynamic Featured Rotation State
  int _featuredIndex = 0;
  Timer? _featuredRotationTimer;

  @override
  void initState() {
    super.initState();
    _loadInitialLibrary();
    _loadWatchHistory();
    _startFeaturedRotation();
  }

  @override
  void dispose() {
    _featuredRotationTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadWatchHistory() async {
    final history = await WatchHistoryService.getRecentHistory();
    if (mounted) {
      setState(() => _watchHistory = history);
    }
  }

  void _resumeFromHistory(WatchHistoryEntry entry) {
    MediaItem? matched;
    for (final it in _localItems) {
      if (it.id == entry.mediaId || it.videoPath == entry.videoPath) {
        matched = it;
        break;
      }
    }
    if (matched != null) {
      _playMedia(matched);
    } else {
      final fallback = MediaItem(
        id: entry.mediaId,
        title: entry.mediaTitle,
        description: '',
        genre: '',
        maturity: '',
        slug: '',
        category: entry.category,
        videoPath: entry.videoPath,
        customThumbnail: entry.thumbnailPath,
        isSeries: entry.isSeries,
      );
      _playMedia(fallback);
    }
  }

  /// Instant Cache-First Startup + Non-blocking Background Sync
  Future<void> _loadInitialLibrary({bool forceFullRescan = false}) async {
    final folders = await LocalLibraryService.getConnectedFolders();
    final cached = await LocalLibraryService.getCachedItems();

    if (mounted) {
      setState(() {
        _connectedFolders = folders;
        if (cached.isNotEmpty && !forceFullRescan) {
          _localItems = cached;
          final candidates = _featuredCandidates;
          if (candidates.isNotEmpty) {
            _featuredIndex = math.Random().nextInt(candidates.length);
          }
        }
      });
      _startFeaturedRotation();
    }

    if (folders.isNotEmpty) {
      if (mounted) {
        setState(() {
          _isScanningFolders = true;
          _scanStatus = 'Memeriksa folder & video...';
        });
      }

      // Background non-blocking sync: user can explore immediately
      _runBackgroundScan();
    }
  }

  Future<void> _runBackgroundScan() async {
    try {
      final items = await LocalLibraryService.scanAllFolders(
        fetchOnlineMetadata: true,
        extractThumbnails: true,
        onProgress: (msg) {
          if (mounted) {
            setState(() => _scanStatus = msg);
          }
        },
      );

      if (mounted) {
        setState(() {
          _localItems = items;
          _isScanningFolders = false;
          _scanStatus = null;
        });
      }
    } catch (e) {
      debugPrint('Background sync error: $e');
      if (mounted) {
        setState(() {
          _isScanningFolders = false;
          _scanStatus = null;
        });
      }
    }
  }

  Future<void> _openManageFoldersDialog() async {
    await showDialog(
      context: context,
      builder: (_) => ManageFoldersDialog(
        onLibraryUpdated: () {
          _loadInitialLibrary();
        },
      ),
    );
    // Reload folder list
    final folders = await LocalLibraryService.getConnectedFolders();
    if (mounted) {
      setState(() {
        _connectedFolders = folders;
      });
    }
  }

  void _openEditMetadataDialog(MediaItem item) {
    showDialog(
      context: context,
      builder: (_) => EditMetadataDialog(
        item: item,
        onSave: (updatedItem) async {
          await LocalLibraryService.saveCustomMetadata(updatedItem.id, updatedItem);
          setState(() {
            final idx = _localItems.indexWhere((it) => it.id == updatedItem.id || it.title == updatedItem.title);
            if (idx != -1) {
              _localItems[idx] = updatedItem;
            } else {
              _localItems.add(updatedItem);
            }
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: const Color(0xFFE50914),
                content: Text('Informasi "${updatedItem.title}" berhasil disimpan!'),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        },
      ),
    );
  }

  List<MediaItem> get _featuredCandidates {
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

    if (source.isEmpty) {
      source = SampleMediaData.allItems;
    }

    return source.take(8).toList();
  }

  MediaItem? get _featuredItem {
    final candidates = _featuredCandidates;
    if (candidates.isEmpty) return null;
    final safeIndex = _featuredIndex.clamp(0, candidates.length - 1);
    return candidates[safeIndex];
  }

  void _startFeaturedRotation() {
    _featuredRotationTimer?.cancel();
    _featuredRotationTimer = Timer.periodic(const Duration(seconds: 18), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final candidates = _featuredCandidates;
      if (_currentlyPlaying == null && _searchQuery.isEmpty && candidates.length > 1) {
        setState(() {
          _featuredIndex = (_featuredIndex + 1) % candidates.length;
        });
      }
    });
  }

  void _nextFeatured() {
    final candidates = _featuredCandidates;
    if (candidates.isEmpty) return;
    setState(() {
      _featuredIndex = (_featuredIndex + 1) % candidates.length;
    });
    _startFeaturedRotation();
  }

  void _prevFeatured() {
    final candidates = _featuredCandidates;
    if (candidates.isEmpty) return;
    setState(() {
      _featuredIndex = (_featuredIndex - 1 + candidates.length) % candidates.length;
    });
    _startFeaturedRotation();
  }

  void _selectFeaturedIndex(int index) {
    final candidates = _featuredCandidates;
    if (candidates.isEmpty) return;
    setState(() {
      _featuredIndex = index.clamp(0, candidates.length - 1);
    });
    _startFeaturedRotation();
  }

  void _playMedia(MediaItem item) {
    List<MediaItem> playlist = [];

    if (item.isSeries && item.episodes.isNotEmpty) {
      // Build playlist containing each episode of this series
      playlist = item.episodes.map((ep) {
        final epDesc = (ep.synopsis != null && ep.synopsis!.isNotEmpty)
            ? ep.synopsis!
            : item.description;
        final epThumb = ep.thumbnail ?? item.customThumbnail;

        return MediaItem(
          id: ep.id,
          title: ep.title.isNotEmpty ? ep.title : '${item.title} - Episode ${ep.episodeNumber}',
          description: epDesc,
          genre: item.genre,
          maturity: item.maturity,
          slug: item.slug,
          category: item.category,
          videoPath: ep.videoPath,
          customThumbnail: epThumb,
          year: item.year,
          rating: item.rating,
          isSeries: true,
          episodes: item.episodes,
        );
      }).toList();

      final firstEp = item.episodes.first;
      final firstEpDesc = (firstEp.synopsis != null && firstEp.synopsis!.isNotEmpty)
          ? firstEp.synopsis!
          : item.description;
      final firstEpThumb = firstEp.thumbnail ?? item.customThumbnail;

      final playItem = MediaItem(
        id: firstEp.id,
        title: firstEp.title.isNotEmpty ? firstEp.title : '${item.title} - Episode ${firstEp.episodeNumber}',
        description: firstEpDesc,
        genre: item.genre,
        maturity: item.maturity,
        slug: item.slug,
        category: item.category,
        videoPath: firstEp.videoPath,
        customThumbnail: firstEpThumb,
        year: item.year,
        rating: item.rating,
        isSeries: true,
        episodes: item.episodes,
      );

      setState(() {
        _currentlyPlaying = playItem;
        _currentPlayingPlaylist = playlist;
      });
    } else {
      // Standalone movie: playlist is all movies in library
      final movies = _localItems.where((it) => !it.isSeries).toList();
      playlist = movies.isNotEmpty ? movies : [item];

      setState(() {
        _currentlyPlaying = item;
        _currentPlayingPlaylist = playlist;
      });
    }
  }

  void _playSpecificEpisode(MediaItem parentItem, Episode episode) {
    final playlist = parentItem.episodes.map((ep) {
      return MediaItem(
        id: ep.id,
        title: '${parentItem.title} - ${ep.title}',
        description: parentItem.description,
        genre: parentItem.genre,
        maturity: parentItem.maturity,
        slug: parentItem.slug,
        category: parentItem.category,
        videoPath: ep.videoPath,
        customThumbnail: parentItem.customThumbnail,
        year: parentItem.year,
        rating: parentItem.rating,
        isSeries: true,
      );
    }).toList();

    final playItem = MediaItem(
      id: episode.id,
      title: '${parentItem.title} - ${episode.title}',
      description: parentItem.description,
      genre: parentItem.genre,
      maturity: parentItem.maturity,
      slug: parentItem.slug,
      category: parentItem.category,
      videoPath: episode.videoPath,
      customThumbnail: parentItem.customThumbnail,
      year: parentItem.year,
      rating: parentItem.rating,
      isSeries: true,
    );

    setState(() {
      _currentlyPlaying = playItem;
      _currentPlayingPlaylist = playlist;
    });
  }

  void _showItemDetails(MediaItem item) {
    showDialog(
      context: context,
      builder: (_) => ItemDetailDialog(
        item: item,
        onPlay: () => _playMedia(item),
        onPlayEpisode: (ep) => _playSpecificEpisode(item, ep),
        onEdit: () => _openEditMetadataDialog(item),
      ),
    );
  }

  Future<void> _pickLocalFile() async {
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: 'Pilih File Video untuk Diputar Langsung',
        type: FileType.custom,
        allowedExtensions: ['mp4', 'mkv', 'avi', 'mov', 'webm', 'ts', 'm4v'],
      );

      if (files.isNotEmpty && files.first.path != null) {
        final filePath = files.first.path!;
        final fileName = files.first.name;
        final cleanTitle = LocalLibraryService.cleanVideoTitle(fileName);

        final localItem = MediaItem(
          id: 'single-${DateTime.now().millisecondsSinceEpoch}',
          title: cleanTitle,
          description: 'File video lokal:\n$filePath',
          genre: 'File Lokal',
          maturity: '13',
          slug: 'local-file',
          category: 'films',
          videoPath: filePath,
        );

        setState(() {
          if (!_localItems.any((it) => it.videoPath == filePath)) {
            _localItems.insert(0, localItem);
          }
        });

        _playMedia(localItem);
      }
    } catch (e) {
      debugPrint('Error picking file: $e');
    }
  }

  Map<String, List<MediaItem>> _buildDisplayGroups() {
    // 1. Search filter
    if (_searchQuery.trim().length >= 2) {
      final q = _searchQuery.toLowerCase();
      final filtered = _localItems.where((item) {
        final matchesTitle = item.title.toLowerCase().contains(q);
        final matchesGenre = item.genre.toLowerCase().contains(q);
        final matchesDesc = item.description.toLowerCase().contains(q);
        final matchesEpisodes = item.episodes.any((ep) => ep.title.toLowerCase().contains(q));
        final matchesYear = item.year != null && item.year!.contains(q);
        return matchesTitle || matchesGenre || matchesDesc || matchesEpisodes || matchesYear;
      }).toList();

      return {'Hasil Pencarian "$_searchQuery" (${filtered.length})': filtered};
    }

    // 2. If user has local items: group user items exclusively
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

      // 'all' / Home category: Show clean rows
      final Map<String, List<MediaItem>> groups = {};

      if (seriesList.isNotEmpty) {
        groups['📺 Serial TV & Anime (${seriesList.length})'] = seriesList;
      }
      if (filmsList.isNotEmpty) {
        groups['🎬 Film Layar Lebar (${filmsList.length})'] = filmsList;
      }

      // Add genre specific rows if there are multiple items
      final genreGroups = _groupByGenre(_localItems, '');
      genreGroups.forEach((k, v) {
        if (!groups.containsKey(k) && v.isNotEmpty) {
          groups[k] = v;
        }
      });

      return groups;
    }

    // 3. If no local items connected, return empty (empty state banner will be rendered)
    return {};
  }

  Map<String, List<MediaItem>> _groupByGenre(List<MediaItem> items, String prefix) {
    final Map<String, List<MediaItem>> map = {};
    for (final item in items) {
      // Split comma-separated genres if any
      final g = item.genre.split(',').first.trim();
      final key = prefix.isNotEmpty ? '$prefix • $g' : g;
      map.putIfAbsent(key, () => []).add(item);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final displayGroups = _buildDisplayGroups();
    final featured = _featuredItem;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOutQuad,
      switchOutCurve: Curves.easeInQuad,
      child: _currentlyPlaying != null
          ? KeyedSubtree(
              key: const ValueKey('in_app_player_view'),
              child: InAppPlayer(
                item: _currentlyPlaying!,
                playlist: _currentPlayingPlaylist.isNotEmpty
                    ? _currentPlayingPlaylist
                    : [_currentlyPlaying!],
                allLibraryItems: _localItems,
                onMediaChanged: (newItem) {
                  setState(() {
                    _currentlyPlaying = newItem;
                  });
                },
                onClose: () {
                  setState(() {
                    _currentlyPlaying = null;
                    _currentPlayingPlaylist = [];
                  });
                  _loadWatchHistory();
                },
              ),
            )
          : KeyedSubtree(
              key: const ValueKey('catalog_scaffold_view'),
              child: Scaffold(
                backgroundColor: const Color(0xFF111111),
      body: Column(
        children: [
          const RepaintBoundary(child: CustomAppTitleBar()),
          Expanded(
            child: Stack(
              children: [
                // Scrollable Content Catalog
                SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Hero Banner (Featured item from user's local collection)
                      if (_searchQuery.trim().length < 2 && featured != null && _localItems.isNotEmpty)
                        RepaintBoundary(
                          child: HeroBillboard(
                            featuredItem: featured,
                            onPlay: () => _playMedia(featured),
                            onMoreInfo: () => _showItemDetails(featured),
                            currentIndex: _featuredIndex.clamp(0, (_featuredCandidates.length - 1).clamp(0, 999)),
                            totalCount: _featuredCandidates.length,
                            onNext: _nextFeatured,
                            onPrev: _prevFeatured,
                            onSelectIndex: _selectFeaturedIndex,
                          ),
                        )
                      else if (_localItems.isNotEmpty)
                        const SizedBox(height: 100)
                      else
                        const SizedBox(height: 80),

                      // Continue Watching Row (if there is history)
                      if (_watchHistory.isNotEmpty && _searchQuery.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: ContinueWatchingRow(
                            items: _watchHistory,
                            onResume: _resumeFromHistory,
                            onRemove: (entry) async {
                              await WatchHistoryService.removeEntry(entry.mediaId);
                              _loadWatchHistory();
                            },
                          ),
                        ),

                // Empty State if no folder connected or no items found
                if (_localItems.isEmpty && !_isScanningFolders)
                  Center(
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
                            onPressed: _openManageFoldersDialog,
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

                // Content Rows from User Library
                if (displayGroups.isNotEmpty)
                  Transform.translate(
                    offset: (_searchQuery.trim().length < 2 && featured != null && _localItems.isNotEmpty)
                        ? const Offset(0, 16)
                        : Offset.zero,
                    child: Column(
                      children: displayGroups.entries.map((entry) {
                        if (entry.value.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Tidak ada video dalam kategori "${entry.key}".',
                                style: const TextStyle(color: Colors.white38, fontSize: 14),
                              ),
                            ),
                          );
                        }
                        return ContentRow(
                          title: entry.key,
                          items: entry.value,
                          onPlay: _playMedia,
                          onSelect: _showItemDetails,
                          onEdit: _openEditMetadataDialog,
                        );
                      }).toList(),
                    ),
                  ),

                const SizedBox(height: 60),
              ],
            ),
          ),

          // Floating Top Netflix Navbar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: RepaintBoundary(
              child: NetflixNavbar(
                activeCategory: _activeCategory,
                folderCount: _connectedFolders.length,
                isScanning: _isScanningFolders,
                onCategoryChanged: (cat) {
                  setState(() {
                    _activeCategory = cat;
                    _searchQuery = '';
                    _featuredIndex = 0;
                  });
                  _startFeaturedRotation();
                },
                onSearchChanged: (query) {
                  setState(() {
                    _searchQuery = query;
                  });
                },
                onPickLocalFile: _pickLocalFile,
                onManageFolders: _openManageFoldersDialog,
                onSyncLibrary: () => _loadInitialLibrary(forceFullRescan: true),
              ),
            ),
          ),

          // Non-blocking floating scan progress toast at bottom right
          if (_isScanningFolders && _scanStatus != null)
            Positioned(
              bottom: 24,
              right: 28,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E).withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: const Color(0xFFE50914), width: 1.2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.8),
                        blurRadius: 18,
                        offset: const Offset(0, 4),
                      ),
                    ],
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
                        _scanStatus!,
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
            ),
        ],
      ),
    ),
  ],
),
),
),
);
  }
}
