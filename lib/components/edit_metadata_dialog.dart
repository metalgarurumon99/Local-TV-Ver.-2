import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/media_item.dart';
import '../services/metadata_service.dart';

class EditMetadataDialog extends StatefulWidget {
  final MediaItem item;
  final ValueChanged<MediaItem> onSave;

  const EditMetadataDialog({
    super.key,
    required this.item,
    required this.onSave,
  });

  @override
  State<EditMetadataDialog> createState() => _EditMetadataDialogState();
}

class _EditMetadataDialogState extends State<EditMetadataDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _blurbController;
  late final TextEditingController _posterUrlController;
  late final TextEditingController _genreController;
  late final TextEditingController _yearController;

  bool _isSearchingOnline = false;
  String? _onlineSearchStatus;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.item.title);
    _blurbController = TextEditingController(text: widget.item.description);
    _posterUrlController = TextEditingController(text: widget.item.customThumbnail ?? '');
    _genreController = TextEditingController(text: widget.item.genre);
    _yearController = TextEditingController(text: widget.item.year ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _blurbController.dispose();
    _posterUrlController.dispose();
    _genreController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  Future<void> _pickLocalPosterImage() async {
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: 'Pilih File Gambar Poster (.jpg, .png, .webp)',
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      );

      if (files.isNotEmpty && files.first.path != null) {
        setState(() {
          _posterUrlController.text = files.first.path!;
        });
      }
    } catch (e) {
      debugPrint('Error picking poster image: $e');
    }
  }

  Future<void> _fetchOnlineInfo() async {
    final query = _titleController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearchingOnline = true;
      _onlineSearchStatus = 'Mencari di TVMaze & AniList...';
    });

    try {
      final result = await OnlineMetadataService.searchMetadata(query);
      if (result != null && mounted) {
        setState(() {
          _titleController.text = result.title;
          _blurbController.text = result.blurb;
          if (result.posterUrl != null) {
            _posterUrlController.text = result.posterUrl!;
          }
          if (result.genre != null) {
            _genreController.text = result.genre!;
          }
          if (result.year != null) {
            _yearController.text = result.year!;
          }
          _onlineSearchStatus = 'Ditemukan dari ${result.source}!';
        });
      } else if (mounted) {
        setState(() {
          _onlineSearchStatus = 'Info online tidak ditemukan untuk judul ini.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _onlineSearchStatus = 'Gagal mencari online: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSearchingOnline = false;
        });
      }
    }
  }

  Widget _buildPosterPreview() {
    final path = _posterUrlController.text.trim();
    Widget imageWidget;

    if (path.startsWith('http://') || path.startsWith('https://')) {
      imageWidget = Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildPlaceholder(),
      );
    } else if (path.isNotEmpty && File(path).existsSync()) {
      imageWidget = Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildPlaceholder(),
      );
    } else if (widget.item.customThumbnail != null &&
        File(widget.item.customThumbnail!).existsSync()) {
      imageWidget = Image.file(
        File(widget.item.customThumbnail!),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildPlaceholder(),
      );
    } else {
      imageWidget = Image.asset(
        widget.item.thumbnailPath,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildPlaceholder(),
      );
    }

    return Container(
      width: 140,
      height: 200,
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: imageWidget,
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFF222222),
      child: const Center(
        child: Icon(Icons.movie_filter_rounded, color: Colors.white24, size: 40),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF181818),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 650,
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const Icon(Icons.edit_note_rounded, color: Color(0xFFE50914), size: 28),
                  const SizedBox(width: 10),
                  const Text(
                    'Edit Informasi Video',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white60),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(color: Colors.white12, height: 24),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Poster Preview Column
                  Column(
                    children: [
                      _buildPosterPreview(),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _pickLocalPosterImage,
                        icon: const Icon(Icons.folder_open, size: 14, color: Colors.white70),
                        label: const Text(
                          'Pilih Poster',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 20),

                  // Form Fields Column
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title Field with Online Search Button
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _titleController,
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                                decoration: _buildInputDecoration('Judul Film / Serial'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: _isSearchingOnline ? null : _fetchOnlineInfo,
                              icon: _isSearchingOnline
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.travel_explore, size: 16, color: Colors.white),
                              label: const Text('Cari Online', style: TextStyle(color: Colors.white, fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE50914),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                              ),
                            ),
                          ],
                        ),

                        if (_onlineSearchStatus != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            _onlineSearchStatus!,
                            style: const TextStyle(color: Colors.amber, fontSize: 12),
                          ),
                        ],

                        const SizedBox(height: 14),

                        // Blurb / Sinopsis
                        TextField(
                          controller: _blurbController,
                          maxLines: 4,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: _buildInputDecoration('Blurb / Sinopsis Cerita'),
                        ),

                        const SizedBox(height: 14),

                        // Poster URL or Path
                        TextField(
                          controller: _posterUrlController,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          decoration: _buildInputDecoration('URL Poster (https://...) atau Path File'),
                        ),

                        const SizedBox(height: 14),

                        // Genre & Year Row
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: _genreController,
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                decoration: _buildInputDecoration('Genre (misal: Action, Drama)'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 1,
                              child: TextField(
                                controller: _yearController,
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                decoration: _buildInputDecoration('Tahun (misal: 2024)'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),
              const Divider(color: Colors.white12),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Batal', style: TextStyle(color: Colors.white60)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      final updated = widget.item.copyWith(
                        title: _titleController.text.trim(),
                        description: _blurbController.text.trim(),
                        customThumbnail: _posterUrlController.text.trim().isNotEmpty
                            ? _posterUrlController.text.trim()
                            : null,
                        genre: _genreController.text.trim().isNotEmpty
                            ? _genreController.text.trim()
                            : widget.item.genre,
                        year: _yearController.text.trim().isNotEmpty
                            ? _yearController.text.trim()
                            : widget.item.year,
                        isManualEdit: true,
                      );
                      widget.onSave(updated);
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.check, color: Colors.white, size: 18),
                    label: const Text(
                      'Simpan Perubahan',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE50914),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
      filled: true,
      fillColor: Colors.black38,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Colors.white12),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Color(0xFFE50914)),
      ),
    );
  }
}
