import 'package:flutter/material.dart';
import '../services/library_service.dart';

class ManageFoldersDialog extends StatefulWidget {
  final VoidCallback onLibraryUpdated;

  const ManageFoldersDialog({
    super.key,
    required this.onLibraryUpdated,
  });

  @override
  State<ManageFoldersDialog> createState() => _ManageFoldersDialogState();
}

class _ManageFoldersDialogState extends State<ManageFoldersDialog> {
  List<String> _folders = [];
  bool _isLoading = true;
  bool _isScanning = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    final list = await LocalLibraryService.getConnectedFolders();
    if (mounted) {
      setState(() {
        _folders = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _addFolder() async {
    final added = await LocalLibraryService.pickAndAddFolder();
    if (added != null) {
      await _loadFolders();
      widget.onLibraryUpdated();
    }
  }

  Future<void> _removeFolder(String path) async {
    await LocalLibraryService.removeFolder(path);
    await _loadFolders();
    widget.onLibraryUpdated();
  }

  Future<void> _rescanAll() async {
    setState(() {
      _isScanning = true;
      _statusMessage = 'Memindai semua folder & mengambil metadata online...';
    });

    try {
      await LocalLibraryService.scanAllFolders(
        fetchOnlineMetadata: true,
        onProgress: (msg) {
          if (mounted) setState(() => _statusMessage = msg);
        },
      );
      widget.onLibraryUpdated();
      if (mounted) {
        setState(() {
          _statusMessage = 'Pemindaian selesai!';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _statusMessage = 'Gagal memindai: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF181818),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.folder_copy_rounded, color: Color(0xFFE50914), size: 26),
                const SizedBox(width: 10),
                const Text(
                  'Kelola Folder Koleksi Video',
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

            const Text(
              'Folder yang terhubung disimpan permanen dan tidak akan hilang saat aplikasi ditutup.',
              style: TextStyle(color: Colors.white60, fontSize: 13),
            ),
            const SizedBox(height: 16),

            // Folders List
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(color: Color(0xFFE50914)),
                ),
              )
            else if (_folders.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.folder_off_outlined, color: Colors.white38, size: 48),
                    const SizedBox(height: 12),
                    const Text(
                      'Belum Ada Folder Terhubung',
                      style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Klik tombol di bawah untuk menambahkan folder film pertama Anda.',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
              )
            else
              Container(
                constraints: const BoxConstraints(maxHeight: 260),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _folders.length,
                  separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 1),
                  itemBuilder: (ctx, index) {
                    final folder = _folders[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.folder, color: Color(0xFFE50914)),
                      title: Text(
                        folder,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                        tooltip: 'Hapus folder ini',
                        onPressed: () => _removeFolder(folder),
                      ),
                    );
                  },
                ),
              ),

            if (_statusMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _statusMessage!,
                style: const TextStyle(color: Colors.amber, fontSize: 12),
              ),
            ],

            const SizedBox(height: 24),
            const Divider(color: Colors.white12),

            // Actions
            Row(
              children: [
                // Rescan button
                OutlinedButton.icon(
                  onPressed: _isScanning ? null : _rescanAll,
                  icon: _isScanning
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.refresh, size: 16, color: Colors.white70),
                  label: Text(
                    _isScanning ? 'Memindai...' : 'Scan Ulang Metadata',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const Spacer(),

                // Add Folder Button
                ElevatedButton.icon(
                  onPressed: _addFolder,
                  icon: const Icon(Icons.add, color: Colors.white, size: 18),
                  label: const Text(
                    '+ Hubungkan Folder Baru',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE50914),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
