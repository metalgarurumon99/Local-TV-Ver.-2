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
  String _activeCategory = 'films';
  String _searchQuery = '';
  MediaItem? _currentlyPlaying;

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

  Future<void> _loadInitialLibrary() async {
    final folders = await LocalLibraryService.getConnectedFolders();
    if (mounted) {
      setState(() {
        _connectedFolders = folders;
      });
    }

    if (folders.isNotEmpty) {
      setState(() {
        _isScanningFolders = true;
        _scanStatus = 'Memuat koleksi film & metadata online...';
      });

      final items = await LocalLibraryService.scanAllFolders(
        fetchOnlineMetadata: true,
        onProgress: (msg) {
          if (mounted) setState(() => _scanStatus = msg);
        },
      );

      if (mounted) {
        setState(() {
          _localItems = items;
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
          await LocalLibraryService.saveCustomMetadata(updatedItem.videoPath, updatedItem);
          setState(() {
            final idx = _localItems.indexWhere((it) => it.videoPath == updatedItem.videoPath);
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

  MediaItem get _featuredItem {
    if (_activeCategory == 'local' && _localItems.isNotEmpty) {
      return _localItems.first;
    }
    final list = SampleMediaData.allItems
        .where((i) => i.category == _activeCategory)
        .toList();
    if (list.isNotEmpty) return list.first;
    if (_localItems.isNotEmpty) return _localItems.first;
    return SampleMediaData.allItems.first;
  }

  void _playMedia(MediaItem item) {
    setState(() {
      _currentlyPlaying = item;
    });
  }

  void _showItemDetails(MediaItem item) {
    showDialog(
      context: context,
      builder: (_) => ItemDetailDialog(
        item: item,
        onPlay: () => _playMedia(item),
        onEdit: () => _openEditMetadataDialog(item),
      ),
    );
  }

  Future<void> _pickLocalFile() async {
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: 'Pilih File Video untuk Diputar',
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
          category: _activeCategory,
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

  @override
  Widget build(BuildContext context) {
    // If playing, show full embedded player overlay
    if (_currentlyPlaying != null) {
      return InAppPlayer(
        item: _currentlyPlaying!,
        playlist: _localItems.isNotEmpty ? _localItems : SampleMediaData.allItems,
        onMediaChanged: (newItem) {
          setState(() {
            _currentlyPlaying = newItem;
          });
        },
        onClose: () {
          setState(() {
            _currentlyPlaying = null;
          });
        },
      );
    }

    // Determine content to display
    Map<String, List<MediaItem>> displayGroups = {};

    if (_searchQuery.trim().length >= 2) {
      final q = _searchQuery.toLowerCase();
      final allAvailable = [..._localItems, ...SampleMediaData.allItems];
      final filtered = allAvailable.where((item) {
        return item.title.toLowerCase().contains(q) ||
            item.genre.toLowerCase().contains(q) ||
            item.description.toLowerCase().contains(q);
      }).toList();

      displayGroups = {'Hasil Pencarian "$_searchQuery"': filtered};
    } else if (_activeCategory == 'local') {
      if (_localItems.isNotEmpty) {
        displayGroups = {
          'Semua Film & Serial di Folder Lokal (${_localItems.length})': _localItems,
        };
      }
    } else {
      displayGroups = Map.from(SampleMediaData.getGrouped(_activeCategory));
      if (_localItems.isNotEmpty) {
        displayGroups = {
          '📁 Koleksi Folder Lokal Saya (${_localItems.length})': _localItems,
          ...displayGroups,
        };
      }
    }

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

                // Hero Banner
                if (_searchQuery.trim().length < 2 && _activeCategory != 'local')
                  HeroBillboard(
                    featuredItem: _featuredItem,
                    onPlay: () => _playMedia(_featuredItem),
                    onMoreInfo: () => _showItemDetails(_featuredItem),
                  )
                else
                  const SizedBox(height: 100),

                // Special Banner for Local Category if empty
                if (_activeCategory == 'local' && _localItems.isEmpty)
                  Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
                      padding: const EdgeInsets.all(40),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.folder_open_rounded, size: 64, color: Color(0xFFE50914)),
                          const SizedBox(height: 16),
                          const Text(
                            'Belum Ada Folder Film yang Terhubung',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Hubungkan satu atau beberapa folder koleksi video Anda di komputer.\nSemua film akan otomatis dimuat dan metadata/posternya diambil secara otomatis.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white60, fontSize: 14),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: _openManageFoldersDialog,
                            icon: const Icon(Icons.folder_copy_rounded, color: Colors.white),
                            label: const Text(
                              'Kelola & Tambah Folder Film',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE50914),
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Content Rows
                if (displayGroups.isNotEmpty)
                  Transform.translate(
                    offset: (_searchQuery.trim().length < 2 && _activeCategory != 'local')
                        ? const Offset(0, -60)
                        : Offset.zero,
                    child: Column(
                      children: displayGroups.entries.map((entry) {
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

                const SizedBox(height: 50),
              ],
            ),
          ),

          // Floating Top Navbar
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
            ),
          ),
        ],
      ),
    );
  }
}
