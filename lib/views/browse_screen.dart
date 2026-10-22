import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/media_item.dart';
import '../data/sample_media.dart';
import '../services/library_service.dart';
import '../components/netflix_navbar.dart';
import '../components/hero_billboard.dart';
import '../components/content_row.dart';
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
  bool _isScanningFolders = false;
  String? _scanStatus;

  @override
  void initState() {
    super.initState();
    _loadInitialLibrary();
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
        }
      });
    }

    if (folders.isNotEmpty) {
      final shouldShowBlockingScan = (cached.isEmpty && _localItems.isEmpty) || forceFullRescan;
      if (shouldShowBlockingScan && mounted) {
        setState(() {
          _isScanningFolders = true;
          _scanStatus = 'Memindai folder film & serial Anda...';
        });
      }

      // Background non-blocking sync
      _runBackgroundScan(shouldShowBlockingScan: shouldShowBlockingScan);
    }
  }

  Future<void> _runBackgroundScan({required bool shouldShowBlockingScan}) async {
    try {
      final items = await LocalLibraryService.scanAllFolders(
        fetchOnlineMetadata: true,
        onProgress: (msg) {
          if (mounted && shouldShowBlockingScan) {
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
      if (mounted && shouldShowBlockingScan) {
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

  MediaItem? get _featuredItem {
    if (_localItems.isNotEmpty) {
      if (_activeCategory == 'series') {
        final seriesList = _localItems.where((it) => it.isSeries).toList();
        if (seriesList.isNotEmpty) return seriesList.first;
      } else if (_activeCategory == 'films') {
        final filmList = _localItems.where((it) => !it.isSeries).toList();
        if (filmList.isNotEmpty) return filmList.first;
      }
      return _localItems.first;
    }
    // Only return sample item if absolutely no local items exist
    return SampleMediaData.allItems.isNotEmpty ? SampleMediaData.allItems.first : null;
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
    // If playing, show full embedded player overlay
    if (_currentlyPlaying != null) {
      return InAppPlayer(
        item: _currentlyPlaying!,
        playlist: _currentPlayingPlaylist.isNotEmpty ? _currentPlayingPlaylist : [_currentlyPlaying!],
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
        },
      );
    }

    final displayGroups = _buildDisplayGroups();
    final featured = _featuredItem;

    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      body: Stack(
        children: [
          // Scrollable Content Catalog
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Scanning status banner
                if (_isScanningFolders && _scanStatus != null)
                  Container(
                    width: double.infinity,
                    color: const Color(0xFFE50914),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    margin: const EdgeInsets.only(top: 70),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _scanStatus!,
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),

                // Hero Banner (Featured item from user's local collection)
                if (_searchQuery.trim().length < 2 && featured != null && _localItems.isNotEmpty)
                  HeroBillboard(
                    featuredItem: featured,
                    onPlay: () => _playMedia(featured),
                    onMoreInfo: () => _showItemDetails(featured),
                  )
                else if (_localItems.isNotEmpty)
                  const SizedBox(height: 100)
                else
                  const SizedBox(height: 80),

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
            child: NetflixNavbar(
              activeCategory: _activeCategory,
              folderCount: _connectedFolders.length,
              onCategoryChanged: (cat) {
                setState(() {
                  _activeCategory = cat;
                  _searchQuery = '';
                });
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
        ],
      ),
    );
  }
}
