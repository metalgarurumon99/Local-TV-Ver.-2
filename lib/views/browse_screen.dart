import 'dart:io';
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

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  String _activeCategory = 'films';
  String _searchQuery = '';
  MediaItem? _currentlyPlaying;

  // Local files and folder
  String? _connectedFolderPath;
  List<MediaItem> _localItems = [];
  bool _isScanningFolder = false;

  @override
  void initState() {
    super.initState();
    _loadInitialLibrary();
  }

  Future<void> _loadInitialLibrary() async {
    final savedPath = await LocalLibraryService.getSavedFolderPath();
    if (savedPath != null && mounted) {
      setState(() {
        _connectedFolderPath = savedPath;
        _isScanningFolder = true;
      });

      final items = await LocalLibraryService.scanFolder(savedPath);
      if (mounted) {
        setState(() {
          _localItems = items;
          _isScanningFolder = false;
        });
      }
    }
  }

  Future<void> _connectFolder() async {
    setState(() => _isScanningFolder = true);
    final items = await LocalLibraryService.pickFolderAndScan();
    final savedPath = await LocalLibraryService.getSavedFolderPath();

    if (mounted) {
      setState(() {
        _isScanningFolder = false;
        if (items.isNotEmpty || savedPath != null) {
          _connectedFolderPath = savedPath;
          _localItems = items;
          _activeCategory = 'local';
        }
      });

      if (items.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFE50914),
            content: Text(
              'Berhasil menghubungkan folder! Ditemukan ${items.length} file video.',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
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

    final folderBaseName = _connectedFolderPath
        ?.split(Platform.pathSeparator)
        .where((s) => s.isNotEmpty)
        .lastOrNull;

    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      body: Stack(
        children: [
          // Scrollable Content Catalog
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                            'Hubungkan folder di komputer Anda yang berisi file film (.mp4, .mkv, .avi, .webm).\nSemua film akan otomatis terdeteksi dan siap diputar kapan saja.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white60, fontSize: 14),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: _isScanningFolder ? null : _connectFolder,
                            icon: _isScanningFolder
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.drive_folder_upload, color: Colors.white),
                            label: Text(
                              _isScanningFolder ? 'Sedang Memindai Folder...' : 'Pilih Folder Film Sekarang',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
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
              connectedFolderName: folderBaseName,
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
              onConnectFolder: _connectFolder,
            ),
          ),
        ],
      ),
    );
  }
}
