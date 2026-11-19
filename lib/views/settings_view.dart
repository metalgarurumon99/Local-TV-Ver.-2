import 'dart:io';
import 'package:flutter/material.dart';
import '../services/app_settings_service.dart';
import '../services/library_service.dart';
import '../services/metadata_service.dart';
import '../components/hover_animated_widget.dart';

class SettingsView extends StatefulWidget {
  final VoidCallback onLibraryUpdated;
  final void Function(String folderPath)? onFolderAdded;
  final VoidCallback? onPickLocalFile;
  final VoidCallback? onSyncLibrary;

  const SettingsView({
    super.key,
    required this.onLibraryUpdated,
    this.onFolderAdded,
    this.onPickLocalFile,
    this.onSyncLibrary,
  });

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  int _selectedTabIndex = 0;

  // Folder state
  List<String> _folders = [];
  Map<String, bool> _folderOnlineStatus = {};
  bool _isLoadingFolders = true;

  // TMDB API Key UI state
  late final TextEditingController _tmdbKeyController;
  bool _obscureTmdbKey = true;

  // Persisted playback & subtitle settings synced with AppSettingsService
  AppSettingsService get _settings => AppSettingsService.instance;
  bool get _volumeBoostEnabled => _settings.volumeBoostEnabled;
  bool get _continuousAutoplay => _settings.continuousAutoplay;
  double get _defaultPlaybackSpeed => _settings.defaultPlaybackSpeed;
  int get _subtitleSize => _settings.subtitleSize;
  String get _preferredSubtitleLanguage => _settings.preferredSubtitleLanguage;

  @override
  void initState() {
    super.initState();
    _tmdbKeyController = TextEditingController(text: _settings.tmdbApiKey);
    _loadFolders();
  }

  @override
  void dispose() {
    _tmdbKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadFolders() async {
    final list = await LocalLibraryService.getAllConfiguredFolders();
    final Map<String, bool> onlineMap = {};
    for (final folder in list) {
      final resolved = LocalLibraryService.resolveFolderPath(folder);
      onlineMap[folder] = await Directory(resolved).exists();
    }
    if (mounted) {
      setState(() {
        _folders = list;
        _folderOnlineStatus = onlineMap;
        _isLoadingFolders = false;
      });
    }
  }

  Future<void> _addFolder() async {
    final added = await LocalLibraryService.pickAndAddFolder();
    if (!mounted) return;
    if (added != null) {
      await _loadFolders();
      if (!mounted) return;
      if (widget.onFolderAdded != null) {
        widget.onFolderAdded!(added);
      } else {
        widget.onLibraryUpdated();
      }
    }
  }

  Future<void> _removeFolder(String path) async {
    LocalLibraryService.cancelScan();
    await LocalLibraryService.removeFolder(path);
    if (!mounted) return;
    await _loadFolders();
    if (!mounted) return;
    widget.onLibraryUpdated();
  }

  Future<void> _confirmDeleteFolder(String folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          width: 480,
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            color: const Color(0xFF181818),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12, width: 1.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.7),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE50914).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE50914).withValues(alpha: 0.35), width: 1),
                    ),
                    child: const Icon(Icons.delete_forever_rounded, color: Color(0xFFE50914), size: 24),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hapus Folder dari Pustaka?',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.2,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Konfirmasi penghapusan pustaka',
                          style: TextStyle(color: Colors.white38, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'Folder berikut akan dilepaskan dari Local TV:',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.folder_rounded, color: Color(0xFFE50914), size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        folder,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontFamily: 'Consolas',
                          fontFamilyFallback: ['monospace'],
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Catatan: File video asli di komputer Anda TIDAK akan terhapus. Hanya metadata dan thumbnail pada aplikasi yang akan dibersihkan.',
                style: TextStyle(color: Colors.white38, fontSize: 11.5, height: 1.4),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text(
                      'Batal',
                      style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 10),
                  HoverAnimatedWidget(
                    hoverScale: 1.04,
                    onTap: () => Navigator.of(ctx).pop(true),
                    builder: (context, isHovered) => AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                      decoration: BoxDecoration(
                        color: isHovered ? const Color(0xFFFF1A25) : const Color(0xFFE50914),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFE50914).withValues(alpha: isHovered ? 0.45 : 0.2),
                            blurRadius: isHovered ? 12 : 6,
                            offset: Offset(0, isHovered ? 3 : 1),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.delete_rounded, color: Colors.white, size: 16),
                          SizedBox(width: 6),
                          Text(
                            'Hapus Folder',
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true) {
      await _removeFolder(folder);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF111111),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left Navigation Sidebar - Docked directly to the left edge of the screen
          Container(
            width: 255,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
            decoration: const BoxDecoration(
              color: Color(0xFF141414),
              border: Border(right: BorderSide(color: Color(0xFF242424), width: 1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sidebar Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE50914).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE50914).withValues(alpha: 0.4), width: 1),
                      ),
                      child: const Icon(Icons.settings_rounded, color: Color(0xFFE50914), size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Settings',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.2,
                          ),
                        ),
                        Text(
                          'Konfigurasi Aplikasi',
                          style: TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Divider(color: Colors.white10, height: 1),
                const SizedBox(height: 16),

                // Nav Items
                _buildSidebarItem(0, Icons.folder_copy_rounded, 'Perpustakaan & Folder'),
                const SizedBox(height: 6),
                _buildSidebarItem(1, Icons.play_circle_outline_rounded, 'Pemutar & Audio'),
                const SizedBox(height: 6),
                _buildSidebarItem(2, Icons.subtitles_outlined, 'Teks & Subtitle'),
                const SizedBox(height: 6),
                _buildSidebarItem(3, Icons.info_outline_rounded, 'Tentang & Sistem'),

                const Spacer(),

                // System Card at bottom of sidebar
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.desktop_windows_rounded, color: Colors.white38, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Local TV v2.0\nRelease Build',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 10.5,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Right Content Panel - Full-width clean container
          Expanded(
            child: ColoredBox(
              color: const Color(0xFF0F0F0F),
              child: _buildCurrentTab(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentTab() {
    switch (_selectedTabIndex) {
      case 0:
        return _buildLibraryTab();
      case 1:
        return _buildPlaybackTab();
      case 2:
        return _buildSubtitlesTab();
      case 3:
        return _buildAboutTab();
      default:
        return _buildLibraryTab();
    }
  }

  Widget _buildSidebarItem(int index, IconData icon, String title) {
    final isSelected = _selectedTabIndex == index;

    return HoverAnimatedWidget(
      hoverScale: 1.01,
      onTap: () => setState(() => _selectedTabIndex = index),
      builder: (context, isHovered) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFE50914).withValues(alpha: 0.16)
                : (isHovered ? Colors.white.withValues(alpha: 0.05) : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFFE50914).withValues(alpha: 0.6)
                  : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected ? const Color(0xFFE50914) : (isHovered ? Colors.white : Colors.white60),
                size: 19,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: isSelected ? Colors.white : (isHovered ? Colors.white : Colors.white70),
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // TAB 1: Perpustakaan & Folder
  Widget _buildLibraryTab() {
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Folder Koleksi Film & Serial',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                Text(
                  'Semua file video di dalam folder terhubung akan otomatis dipindai dan dikelompokkan',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
            HoverAnimatedWidget(
              hoverScale: 1.04,
              onTap: _addFolder,
              builder: (context, isHovered) => AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                decoration: BoxDecoration(
                  color: isHovered ? const Color(0xFFFF1A25) : const Color(0xFFE50914),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE50914).withValues(alpha: isHovered ? 0.45 : 0.2),
                      blurRadius: isHovered ? 14 : 6,
                      offset: Offset(0, isHovered ? 4 : 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_rounded,
                      color: Colors.white,
                      size: isHovered ? 20 : 18,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Tambah Folder',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // Folders List
        if (_isLoadingFolders)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(color: Color(0xFFE50914), strokeWidth: 2.5),
            ),
          )
        else if (_folders.isEmpty)
          Container(
            padding: const EdgeInsets.all(36),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              children: [
                const Icon(Icons.folder_off_outlined, color: Colors.white38, size: 48),
                const SizedBox(height: 12),
                const Text(
                  'Belum Ada Folder Terhubung',
                  style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Klik tombol "+ Tambah Folder" di atas untuk menghubungkan harddisk atau folder video Anda.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _folders.length,
              separatorBuilder: (_, _) => const Divider(color: Colors.white10, height: 1),
              itemBuilder: (ctx, index) {
                final folder = _folders[index];
                final isOnline = _folderOnlineStatus[folder] ?? false;

                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Icon(
                    isOnline ? Icons.folder_rounded : Icons.folder_off_rounded,
                    color: isOnline ? const Color(0xFFE50914) : Colors.amber.shade700,
                    size: 26,
                  ),
                  title: Text(
                    folder,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    isOnline ? 'Terhubung (Online)' : 'Perangkat Terputus / Harddisk Belum Terpasang',
                    style: TextStyle(
                      color: isOnline ? Colors.greenAccent.shade400 : Colors.amber.shade300,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.white54, size: 20),
                    tooltip: 'Hapus folder ini dari pustaka',
                    onPressed: () => _confirmDeleteFolder(folder),
                  ),
                );
              },
            ),
          ),

        const SizedBox(height: 28),
        const Divider(color: Colors.white12, height: 1),
        const SizedBox(height: 20),

        // Quick Actions
        const Text(
          'Tindakan Cepat Pustaka',
          style: TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 14),

        Row(
          children: [
            Expanded(
              child: _buildActionCard(
                icon: Icons.file_open_rounded,
                title: 'Buka File Tunggal',
                subtitle: 'Putar langsung 1 file video dari komputer tanpa memasukkan foldernya ke pustaka.',
                buttonText: 'Pilih File Video',
                onTap: () {
                  widget.onPickLocalFile?.call();
                },
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildActionCard(
                icon: Icons.sync_rounded,
                title: 'Pindai Ulang Pustaka',
                subtitle: 'Muat ulang seluruh folder untuk mencari episode baru atau memperbarui metadata.',
                buttonText: 'Pindai Sekarang',
                onTap: () {
                  widget.onSyncLibrary?.call();
                },
              ),
            ),
          ],
        ),

        const SizedBox(height: 28),
        const Divider(color: Colors.white12, height: 1),
        const SizedBox(height: 20),

        // TMDB API Key Configuration (Portable & Secure — never hardcoded in source)
        Row(
          children: [
            const Text(
              'TMDB API Key (Metadata Online)',
              style: TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: OnlineMetadataService.hasApiKey
                    ? Colors.greenAccent.withValues(alpha: 0.14)
                    : Colors.amber.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                OnlineMetadataService.isUsingCustomKey
                    ? 'AKTIF (KUSTOM)'
                    : (OnlineMetadataService.hasBuiltInKey ? 'AKTIF (BAWAAN)' : 'BELUM DIATUR'),
                style: TextStyle(
                  color: OnlineMetadataService.hasApiKey ? Colors.greenAccent : Colors.amber.shade300,
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          OnlineMetadataService.hasBuiltInKey && !OnlineMetadataService.isUsingCustomKey
              ? 'Metadata online TMDB sudah aktif otomatis dari build rilis. Anda hanya perlu mengisi kolom di bawah jika ingin memakai API Key pribadi.'
              : 'Masukkan API Key v3 gratis dari themoviedb.org untuk mengunduh poster, backdrop, logo, dan sinopsis episode secara otomatis. Disimpan lokal di .cache/app_settings.json.',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _tmdbKeyController,
                obscureText: _obscureTmdbKey,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Masukkan TMDB API Key (opsional jika sudah di-set saat build)...',
                  hintStyle: const TextStyle(color: Colors.white30, fontSize: 12.5),
                  filled: true,
                  fillColor: Colors.black38,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.white12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.white12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE50914)),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureTmdbKey ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                      color: Colors.white54,
                      size: 18,
                    ),
                    onPressed: () => setState(() => _obscureTmdbKey = !_obscureTmdbKey),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: () async {
                await _settings.setTmdbApiKey(_tmdbKeyController.text);
                if (!mounted) return;
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: const Color(0xFF222222),
                    behavior: SnackBarBehavior.floating,
                    content: Text(
                      OnlineMetadataService.hasApiKey
                          ? 'TMDB API Key berhasil disimpan!'
                          : 'TMDB API Key dikosongkan.',
                      style: const TextStyle(color: Colors.white),
                    ),
                    duration: const Duration(seconds: 3),
                  ),
                );
              },
              icon: const Icon(Icons.save_rounded, size: 16, color: Colors.white),
              label: const Text('Simpan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE50914),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // TAB 2: Pemutar & Audio
  Widget _buildPlaybackTab() {
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        const Text(
          'Pengaturan Pemutar & Suara',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'Sesuaikan perilaku engine pemutar video dan amplifikasi audio',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 22),

        // 1. Audio Boost 130%
        _buildSettingToggle(
          title: 'Audio Boost hingga 130% (Native MPV)',
          subtitle: 'Mengizinkan slider volume dan scroll mouse menaikkan volume melebihi 100% untuk video bersuara pelan.',
          value: _volumeBoostEnabled,
          onChanged: (val) async {
            await _settings.setVolumeBoostEnabled(val);
            if (mounted) setState(() {});
          },
        ),
        const SizedBox(height: 14),

        // 2. Continuous Autoplay
        _buildSettingToggle(
          title: 'Mode Tidur & Putar Otomatis',
          subtitle: 'Otomatis memutar episode berikutnya saat video selesai, atau beralih ke judul acak lain saat serial habis.',
          value: _continuousAutoplay,
          onChanged: (val) async {
            await _settings.setContinuousAutoplay(val);
            if (mounted) setState(() {});
          },
        ),
        const SizedBox(height: 14),

        // 3. Hardware Video Acceleration
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.speed_rounded, color: Colors.greenAccent, size: 22),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Akselerasi Perangkat Keras (GPU Decoding)',
                          style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'AKTIF (D3D11VA)',
                          style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Memanfaatkan GPU untuk decoding video 1080p dan 4K tanpa membebani prosesor (CPU).',
                      style: TextStyle(color: Colors.white54, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 4. Playback Speed
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kecepatan Putar Default',
                      style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Kecepatan awal saat pertama kali membuka video',
                      style: TextStyle(color: Colors.white54, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              DropdownButton<double>(
                value: _defaultPlaybackSpeed,
                dropdownColor: const Color(0xFF222222),
                underline: const SizedBox.shrink(),
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                items: const [
                  DropdownMenuItem(value: 0.75, child: Text('0.75x')),
                  DropdownMenuItem(value: 1.0, child: Text('1.0x (Normal)')),
                  DropdownMenuItem(value: 1.25, child: Text('1.25x')),
                  DropdownMenuItem(value: 1.5, child: Text('1.5x')),
                ],
                onChanged: (val) async {
                  if (val != null) {
                    await _settings.setDefaultPlaybackSpeed(val);
                    if (mounted) setState(() {});
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // TAB 3: Teks & Subtitle
  Widget _buildSubtitlesTab() {
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        const Text(
          'Preferensi Teks & Subtitle',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'Atur tampilan subtitle, bahasa bawaan, dan ukuran font untuk kenyamanan membaca',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 22),

        // 1. Language
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bahasa Subtitle Prioritas',
                      style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Secara otomatis memilih track bahasa ini jika tersedia di dalam file video',
                      style: TextStyle(color: Colors.white54, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              DropdownButton<String>(
                value: _preferredSubtitleLanguage,
                dropdownColor: const Color(0xFF222222),
                underline: const SizedBox.shrink(),
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                items: const [
                  DropdownMenuItem(value: 'id', child: Text('Bahasa Indonesia')),
                  DropdownMenuItem(value: 'en', child: Text('English')),
                  DropdownMenuItem(value: 'auto', child: Text('Track Default Video')),
                ],
                onChanged: (val) async {
                  if (val != null) {
                    await _settings.setPreferredSubtitleLanguage(val);
                    if (mounted) setState(() {});
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 2. Font Size
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ukuran Font Subtitle',
                      style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Tingkat keterbacaan teks di layar saat memutar video',
                      style: TextStyle(color: Colors.white54, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              DropdownButton<int>(
                value: _subtitleSize,
                dropdownColor: const Color(0xFF222222),
                underline: const SizedBox.shrink(),
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                items: const [
                  DropdownMenuItem(value: 44, child: Text('Kecil (44 pt)')),
                  DropdownMenuItem(value: 55, child: Text('Sedang (55 pt - Rekomendasi)')),
                  DropdownMenuItem(value: 68, child: Text('Besar (68 pt)')),
                ],
                onChanged: (val) async {
                  if (val != null) {
                    await _settings.setSubtitleSize(val);
                    if (mounted) setState(() {});
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 3. Subtitle Preview Box
        Container(
          height: 120,
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F0F),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Text(
                  'Pratinjau Subtitle: "Local TV menghadirkan tontonan terbaik."',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: _subtitleSize * 0.32,
                    fontWeight: FontWeight.bold,
                    shadows: const [
                      Shadow(color: Colors.black, blurRadius: 4, offset: Offset(0, 1.5)),
                      Shadow(color: Colors.black, blurRadius: 8, offset: Offset(0, 2)),
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: 8,
                right: 12,
                child: Text(
                  'Render Libass Engine',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 10.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // TAB 4: Tentang & Sistem
  Widget _buildAboutTab() {
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        const Text(
          'Tentang Local TV',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 18),

        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE50914),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'LOCAL TV',
                      style: TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'v2.0 Release',
                      style: TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Aplikasi pemutar media lokal cerdas dengan antarmuka modern ala streaming service. Dilengkapi pengelompokan serial otomatis, unduhan metadata online, pratinjau video, dan integrasi engine MPV berkinerja tinggi.',
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 18),
              const Divider(color: Colors.white10),
              const SizedBox(height: 14),
              _buildInfoRow('Engine Video', 'LibMPV Texture Render + Hardware D3D11VA'),
              const SizedBox(height: 10),
              _buildInfoRow('Format Didukung', 'MP4, MKV, AVI, MOV, WEBM, TS, M4V, FLV'),
              const SizedBox(height: 10),
              _buildInfoRow('Lokasi Konfigurasi', 'library_config.json (Folder Portable)'),
            ],
          ),
        ),
        const SizedBox(height: 18),

        OutlinedButton.icon(
          onPressed: () async {
            if (!Platform.isWindows) return;
            try {
              final appDir = File(Platform.resolvedExecutable).parent.path;
              await Process.run('explorer.exe', [appDir]);
            } catch (e) {
              debugPrint('Error opening app directory: $e');
            }
          },
          icon: const Icon(Icons.folder_open_rounded, size: 17, color: Colors.white70),
          label: const Text('Buka Folder Aplikasi di File Explorer', style: TextStyle(color: Colors.white70, fontSize: 12.5)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.white24),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String buttonText,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFFE50914), size: 22),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white54, fontSize: 11.5, height: 1.35),
          ),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            child: Text(buttonText, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingToggle({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 11.5),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: const Color(0xFFE50914),
            activeTrackColor: const Color(0xFFE50914).withValues(alpha: 0.45),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

