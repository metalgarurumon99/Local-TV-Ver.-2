import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/media_item.dart';
import '../services/debug_logger.dart';
import '../services/library_service.dart';
import '../services/preview_player_service.dart';
import '../services/thumbnail_service.dart';
import '../services/watch_history_service.dart';
import '../utils/media_ui_helpers.dart';
import 'edit_metadata_dialog.dart';
import 'hover_animated_widget.dart';
import 'in_app_player.dart';
import 'vertical_preview_volume.dart';
import 'video_card.dart';

class ItemDetailDialog extends StatefulWidget {
  final MediaItem item;
  final VoidCallback onPlay;
  final VoidCallback? onClose;
  final ValueChanged<MediaItem>? onItemUpdated;
  final ValueChanged<Episode>? onPlayEpisode;
  final List<MediaItem> similarItems;
  final ValueChanged<MediaItem>? onSelectItem;
  final bool isConnected;

  const ItemDetailDialog({
    super.key,
    required this.item,
    required this.onPlay,
    this.onClose,
    this.onItemUpdated,
    this.onPlayEpisode,
    this.similarItems = const [],
    this.onSelectItem,
    this.isConnected = true,
  });

  @override
  State<ItemDetailDialog> createState() => _ItemDetailDialogState();
}

class _ItemDetailDialogState extends State<ItemDetailDialog> {
  late MediaItem _item;
  Timer? _previewTimer;
  late String _selectedSeason;
  String? _extractedLocalBackdrop;
  bool _isClosing = false;
  final FocusNode _dialogFocusNode = FocusNode();

  String get _ownerId => 'dialog-${_item.id}';

  void _cleanUpResources() {
    _isClosing = true;
    _previewTimer?.cancel();
    _previewTimer = null;
    VideoCard.closeActivePopover();
    PreviewPlayerService.instance.stopAll();
    LocalThumbnailService.cancelPendingExtractions();
  }

  void _cleanUpAndClose() {
    DebugLogger.log('ItemDetailDialog _cleanUpAndClose CALLED: ownerId=$_ownerId, isClosing=$_isClosing, mounted=$mounted');
    if (_isClosing) return;
    _cleanUpResources();
    if (widget.onClose != null) {
      widget.onClose!();
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    DebugLogger.log('ItemDetailDialog initState: ownerId=$_ownerId, title=${_item.title}');
    final seasons = _item.availableSeasonNames;
    _selectedSeason = seasons.isNotEmpty ? seasons.first : 'Season 1';

    // If backdrop is missing online, extract local backdrop from video on demand (Rule 5)
    if (_item.backdropUrl == null || _item.backdropUrl!.isEmpty) {
      final vPath = _resolveVideoPath();
      if (vPath.isNotEmpty) {
        LocalThumbnailService.extractBackdrop(vPath).then((extracted) {
          if (mounted && extracted != null) {
            setState(() => _extractedLocalBackdrop = extracted);
          }
        });
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isClosing) {
        _dialogFocusNode.requestFocus();
      }
    });

    if (widget.isConnected) {
      _previewTimer = Timer(const Duration(milliseconds: 900), () {
        if (_isClosing || !mounted) return;
        final path = _resolveVideoPath();
        if (path.isNotEmpty) {
          PreviewPlayerService.instance.requestPreview(
            ownerId: _ownerId,
            videoPath: path,
            allowAudio: true,
            maxDuration: const Duration(seconds: 30),
          );
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant ItemDetailDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.item != oldWidget.item) {
      _item = widget.item;
      final seasons = _item.availableSeasonNames;
      if (!seasons.contains(_selectedSeason)) {
        _selectedSeason = seasons.isNotEmpty ? seasons.first : 'Season 1';
      }
    }
  }

  @override
  void dispose() {
    DebugLogger.log('ItemDetailDialog dispose: ownerId=$_ownerId');
    _isClosing = true;
    _previewTimer?.cancel();
    _previewTimer = null;
    _dialogFocusNode.dispose();
    // Release only our own preview so switching directly to another ItemDetailDialog
    // via "Tontonan Lainnya" doesn't cancel the newly mounted dialog's preview/extractions.
    PreviewPlayerService.instance.releasePreview(_ownerId);
    super.dispose();
  }

  String _resolveVideoPath() {
    if (_item.videoPath.isNotEmpty &&
        !_item.videoPath.startsWith('asset:')) {
      return _item.videoPath;
    }
    if (_item.episodes.isNotEmpty) {
      return _item.episodes.first.videoPath;
    }
    return '';
  }

  Widget _buildBackdropImage() {
    final imagePath = (_item.backdropUrl != null && _item.backdropUrl!.isNotEmpty)
        ? _item.backdropUrl!
        : (_item.customThumbnail ?? '');

    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return Image.network(
        imagePath,
        fit: BoxFit.cover,
        cacheWidth: 1000,
        errorBuilder: (_, _, _) => _buildPlaceholder(),
      );
    }
    if (imagePath.isNotEmpty &&
        LocalThumbnailService.fileExistsCached(imagePath)) {
      return Image.file(
        File(imagePath),
        fit: BoxFit.cover,
        cacheWidth: 1000,
        errorBuilder: (_, _, _) => _buildPlaceholder(),
      );
    }
    if (_extractedLocalBackdrop != null &&
        LocalThumbnailService.fileExistsCached(_extractedLocalBackdrop!)) {
      return Image.file(
        File(_extractedLocalBackdrop!),
        fit: BoxFit.cover,
        cacheWidth: 1000,
        errorBuilder: (_, _, _) => _buildPlaceholder(),
      );
    }
    if (_item.largePosterPath.isNotEmpty) {
      return Image.asset(
        _item.largePosterPath,
        fit: BoxFit.cover,
        cacheWidth: 720,
        errorBuilder: (_, _, _) => _buildPlaceholder(),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFF222222),
      child: const Center(
        child: Icon(Icons.movie, size: 60, color: Colors.white24),
      ),
    );
  }

  String? _resolveLogoPath() {
    if (_item.logoUrl != null && _item.logoUrl!.isNotEmpty) {
      final p = _item.logoUrl!;
      if (p.startsWith('http://') || p.startsWith('https://')) {
        return p;
      }
      if (LocalThumbnailService.fileExistsCached(p)) {
        return p;
      }
    }
    return null;
  }

  Widget _buildBannerLogoOrTitle() {
    final logoPath = _resolveLogoPath();
    if (logoPath != null && logoPath.isNotEmpty) {
      if (logoPath.startsWith('http://') || logoPath.startsWith('https://')) {
        return ConstrainedBox(
          constraints: const BoxConstraints(
            maxHeight: 95,
            maxWidth: 380,
          ),
          child: Image.network(
            logoPath,
            fit: BoxFit.contain,
            cacheWidth: 420,
            alignment: Alignment.bottomLeft,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => _buildBannerTitleFallback(),
          ),
        );
      }
      if (LocalThumbnailService.fileExistsCached(logoPath)) {
        return ConstrainedBox(
          constraints: const BoxConstraints(
            maxHeight: 95,
            maxWidth: 380,
          ),
          child: Image.file(
            LocalThumbnailService.resolveFile(logoPath),
            fit: BoxFit.contain,
            cacheWidth: 420,
            alignment: Alignment.bottomLeft,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => _buildBannerTitleFallback(),
          ),
        );
      }
    }
    return _buildBannerTitleFallback();
  }

  Widget _buildBannerTitleFallback() {
    return Text(
      _item.title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 28,
        fontWeight: FontWeight.w900,
        shadows: [
          Shadow(color: Colors.black, blurRadius: 10, offset: Offset(0, 2)),
        ],
      ),
    );
  }

  String _getVideoResolution(MediaItem item) => MediaUiHelpers.resolveVideoResolutionLabel(item);

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final previewService = PreviewPlayerService.instance;
    final seasonNames = _item.availableSeasonNames;
    final activeSeason = seasonNames.contains(_selectedSeason)
        ? _selectedSeason
        : (seasonNames.isNotEmpty ? seasonNames.first : 'Season 1');
    final List<Episode> filteredEpisodes = (_item.isSeries && _item.episodes.isNotEmpty)
        ? _item.episodes.where((ep) {
            if (seasonNames.length <= 1) return true;
            return ep.seasonName == activeSeason;
          }).toList()
        : const [];

    return Focus(
      focusNode: _dialogFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          DebugLogger.log('ItemDetailDialog ESC pressed');
          _cleanUpAndClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        color: Colors.transparent,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Full-screen translucent black scrim barrier — clicking anywhere outside closes identically to X button
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                DebugLogger.log('ItemDetailDialog Outside Barrier clicked');
                _cleanUpAndClose();
              },
              child: const ColoredBox(color: Color(0x99000000)),
            ),

            // Centered Modal Dialog Card
            Center(
              child: GestureDetector(
                onTap: () {}, // Prevent clicks inside dialog from propagating to barrier
                child: Dialog(
                  backgroundColor: const Color(0xFF181818),
                  insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  clipBehavior: Clip.antiAlias,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 720,
                      maxHeight: screenHeight * 0.9,
                    ),
                    child: CustomScrollView(
                      shrinkWrap: true,
                      slivers: [
                        SliverToBoxAdapter(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                        // Top Backdrop Image & Shared Hardware Video Preview
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildBackdropImage(),
                        ListenableBuilder(
                          listenable: previewService,
                          builder: (context, _) {
                            final bool isReady = previewService.isOwnerReady(_ownerId);
                            if (!isReady || previewService.controller == null) {
                              return const SizedBox.shrink();
                            }
                            return Video(
                              controller: previewService.controller!,
                              fit: BoxFit.cover,
                              controls: NoVideoControls,
                              subtitleViewConfiguration: const SubtitleViewConfiguration(
                                visible: false,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  // Gradient Vignette - Rich Netflix transition with solid opaque bottom for buttons & seamless merge
                  const Positioned(
                    left: -2,
                    right: -2,
                    bottom: -3,
                    top: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Color(0x40181818),
                            Color(0xCC181818),
                            Color(0xFF181818),
                            Color(0xFF181818),
                          ],
                          stops: [0.25, 0.55, 0.80, 0.92, 1.0],
                        ),
                      ),
                    ),
                  ),

                  // Solid bottom seal bar to eliminate any subpixel gap between backdrop and metadata section
                  const Positioned(
                    left: -2,
                    right: -2,
                    bottom: -3,
                    height: 14,
                    child: ColoredBox(
                      color: Color(0xFF181818),
                    ),
                  ),

                  // Top-Left Edit Info & Poster Button (Icon only, aligned with close button)
                  Positioned(
                    top: 16,
                    left: 16,
                    child: Tooltip(
                      message: 'Edit Info & Poster',
                      child: HoverAnimatedWidget(
                        hoverScale: 1.12,
                        onTap: () async {
                          _previewTimer?.cancel();
                          previewService.releasePreview(_ownerId);
                          final updated = await showDialog<MediaItem?>(
                            context: context,
                            builder: (_) => EditMetadataDialog(
                              item: _item,
                              onSave: (updatedItem) async {
                                await LocalLibraryService.saveCustomMetadata(updatedItem.id, updatedItem);
                                widget.onItemUpdated?.call(updatedItem);
                              },
                            ),
                          );
                          if (updated != null && mounted) {
                            setState(() {
                              _item = updated;
                            });
                          }
                          if (mounted && !_isClosing) {
                            _dialogFocusNode.requestFocus();
                          }
                        },
                        builder: (context, isHovered) {
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: isHovered ? const Color(0xCC222222) : Colors.black54,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isHovered ? Colors.white54 : Colors.transparent,
                                width: 0.8,
                              ),
                            ),
                            child: const Icon(Icons.edit_note_rounded, color: Colors.white, size: 20),
                          );
                        },
                      ),
                    ),
                  ),

                  // Close Button
                  Positioned(
                    top: 16,
                    right: 16,
                    child: HoverAnimatedWidget(
                      hoverScale: 1.12,
                      onTap: () {
                        DebugLogger.log('ItemDetailDialog X button tapped');
                        _cleanUpAndClose();
                      },
                      builder: (context, isHovered) {
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: isHovered ? const Color(0xFFE50914) : Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, color: Colors.white, size: 20),
                        );
                      },
                    ),
                  ),

                  // Netflix-Style Vertical Volume Control on Backdrop (Bottom-Right, Expands Upward)
                  Positioned(
                    bottom: 24,
                    right: 24,
                    child: ListenableBuilder(
                      listenable: previewService,
                      builder: (context, _) {
                        if (!previewService.isOwnerReady(_ownerId)) {
                          return const SizedBox.shrink();
                        }
                        return const VerticalPreviewVolumeControl(
                          iconSize: 20,
                          buttonPadding: 7,
                          sliderHeight: 70,
                          direction: VolumeSliderDirection.up,
                          buttonBackgroundColor: Colors.black54,
                          buttonBorder: null,
                        );
                      },
                    ),
                  ),

                  // Title & Action on Backdrop
                  Positioned(
                    left: 32,
                    bottom: 24,
                    right: 80,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!widget.isConnected) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xE61E1E1E),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFFFF5252), width: 0.8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.cloud_off_rounded, color: Color(0xFFFF5252), size: 14),
                                SizedBox(width: 5),
                                Text(
                                  'Folder Terputus',
                                  style: TextStyle(
                                    color: Color(0xFFFF8A80),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        _buildBannerLogoOrTitle(),
                        const SizedBox(height: 14),
                        Builder(
                          builder: (context) {
                            final progress = WatchHistoryService.getProgressSync(_item.id)?.progress ?? 0.0;
                            final isWatched = progress > 0.02;
                            final isConnected = widget.isConnected;
                            final playLabel = !isConnected
                                ? 'Folder Terputus'
                                : (isWatched ? 'Lanjutkan Menonton' : 'Tonton Sekarang');
                            final playIcon = !isConnected
                                ? Icons.cloud_off_rounded
                                : Icons.play_arrow_rounded;

                            return HoverAnimatedWidget(
                              hoverScale: 1.04,
                              builder: (context, isHovered) {
                                return ElevatedButton.icon(
                                  onPressed: () {
                                    if (!isConnected) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          backgroundColor: const Color(0xFF222222),
                                          behavior: SnackBarBehavior.floating,
                                          duration: const Duration(seconds: 4),
                                          content: Row(
                                            children: [
                                              const Icon(Icons.cloud_off_rounded, color: Color(0xFFE50914), size: 20),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  'Folder penyimpanan untuk "${_item.title}" sedang tidak terhubung. Sambungkan drive atau periksa folder di Pengaturan.',
                                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    _cleanUpResources();
                                    widget.onPlay();
                                  },
                                  icon: Icon(playIcon, color: !isConnected ? Colors.white70 : Colors.black, size: !isConnected ? 20 : 26),
                                  label: Text(
                                    playLabel,
                                    style: TextStyle(
                                      color: !isConnected ? Colors.white70 : Colors.black,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      height: 1.0,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: !isConnected
                                        ? const Color(0xFF333333)
                                        : (isHovered ? const Color(0xFFEAEAEA) : Colors.white),
                                    foregroundColor: !isConnected ? Colors.white70 : Colors.black,
                                    elevation: isHovered ? 8 : 0,
                                    shadowColor: Colors.white38,
                                    fixedSize: const Size.fromHeight(42),
                                    minimumSize: const Size(0, 42),
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    padding: const EdgeInsets.symmetric(horizontal: 22),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Metadata & Description Details
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 14, 32, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Metadata Tags Row: Maturity • Year • Rating • Resolution • Episodes/Film • Genre
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white54),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text(
                            '${_item.maturity}+',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (_item.year != null && _item.year!.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Text(
                            _item.year!,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        if (_item.rating != null && _item.rating!.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Row(
                            children: [
                              const Text(
                                '★',
                                style: TextStyle(
                                  color: Color(0xFFFFB800),
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _item.rating!,
                                style: const TextStyle(
                                  color: Color(0xFFFFB800),
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white38),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text(
                            _getVideoResolution(_item),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _item.isSeries ? '${_item.episodes.length} Episode' : 'Film',
                          style: const TextStyle(
                            color: Color(0xFF46D369),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // 2-Column Section (Screenshot 3): Left is Title & Synopsis, Right is Cast & Genre & Director
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left Column (Title & Synopsis)
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _item.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                _item.description,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 32),

                        // Right Column (Pemeran, Genre, Sutradara - font matches synopsis)
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_item.cast.isNotEmpty) ...[
                                Text.rich(
                                  TextSpan(
                                    children: [
                                      const TextSpan(
                                        text: 'Pemeran: ',
                                        style: TextStyle(
                                          color: Colors.white54,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                          height: 1.4,
                                        ),
                                      ),
                                      TextSpan(
                                        text: _item.cast.join(', '),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.normal,
                                          fontSize: 13,
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              if (_item.genre.isNotEmpty) ...[
                                Text.rich(
                                  TextSpan(
                                    children: [
                                      const TextSpan(
                                        text: 'Genre: ',
                                        style: TextStyle(
                                          color: Colors.white54,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                          height: 1.4,
                                        ),
                                      ),
                                      TextSpan(
                                        text: _item.genre,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.normal,
                                          fontSize: 13,
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              if (_item.director != null && _item.director!.isNotEmpty) ...[
                                Text.rich(
                                  TextSpan(
                                    children: [
                                      const TextSpan(
                                        text: 'Sutradara: ',
                                        style: TextStyle(
                                          color: Colors.white54,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                          height: 1.4,
                                        ),
                                      ),
                                      TextSpan(
                                        text: _item.director!,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.normal,
                                          fontSize: 13,
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),

                    // Episodes Section Header for Series with Netflix-Style Season / Arc Selector
                    if (_item.isSeries && _item.episodes.isNotEmpty) ...[
                      const SizedBox(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Text(
                                    'Episodes',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  if (seasonNames.length > 1)
                                    Flexible(
                                      child: PopupMenuButton<String>(
                                        color: const Color(0xFF242424),
                                        constraints: const BoxConstraints(maxWidth: 340),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(6),
                                          side: const BorderSide(color: Colors.white24, width: 0.8),
                                        ),
                                        offset: const Offset(0, 42),
                                        onSelected: (val) {
                                          setState(() => _selectedSeason = val);
                                        },
                                        itemBuilder: (ctx) {
                                          return seasonNames.map((s) {
                                            final epCount = _item.episodes.where((e) => e.seasonName == s).length;
                                            final isCurrent = s == activeSeason;
                                            return PopupMenuItem<String>(
                                              value: s,
                                              child: Text(
                                                '${InAppPlayer.formatSeasonDisplay(s, seasonNames)} ($epCount Episode)',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: isCurrent ? const Color(0xFFE50914) : Colors.white,
                                                  fontSize: 14,
                                                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                                                ),
                                              ),
                                            );
                                          }).toList();
                                        },
                                        child: HoverAnimatedWidget(
                                          hoverScale: 1.03,
                                          builder: (context, isHovered) {
                                            return AnimatedContainer(
                                              duration: const Duration(milliseconds: 160),
                                              constraints: const BoxConstraints(maxWidth: 300),
                                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                              decoration: BoxDecoration(
                                                color: isHovered ? const Color(0xFF2E2E2E) : const Color(0xFF242424),
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(
                                                  color: isHovered ? Colors.white54 : Colors.white24,
                                                  width: 0.8,
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      '${InAppPlayer.formatSeasonDisplay(activeSeason, seasonNames)} (${filteredEpisodes.length} Episode)',
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  const Icon(Icons.arrow_drop_down, color: Colors.white, size: 20),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    )
                                  else
                                    Flexible(
                                      child: Text(
                                        '${_item.episodes.length} Episode',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 14),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),

        // Virtualized Episode SliverList (only builds visible episode rows!)
        if (_item.isSeries && filteredEpisodes.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            sliver: SliverList.separated(
              itemCount: filteredEpisodes.length,
              separatorBuilder: (_, _) => const Divider(color: Colors.white12, height: 12),
              itemBuilder: (ctx, index) {
                                  final ep = filteredEpisodes[index];
                                  final epIndexDisplay = ep.episodeNumber;
                                  final durationLabel = ep.duration ?? '';

                                  final hasTitle = ep.title.isNotEmpty &&
                                      ep.title.toLowerCase() != 'episode $epIndexDisplay' &&
                                      ep.title.toLowerCase() != 'ep $epIndexDisplay';
                                  final hasSynopsis = ep.synopsis != null && ep.synopsis!.trim().isNotEmpty;
                                  final displayTitle = hasTitle ? ep.title : 'Episode $epIndexDisplay';

                                  return HoverAnimatedWidget(
                                    hoverScale: 1.01,
                                    onTap: () {
                                      if (!widget.isConnected) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            backgroundColor: const Color(0xFF222222),
                                            behavior: SnackBarBehavior.floating,
                                            duration: const Duration(seconds: 4),
                                            content: Row(
                                              children: [
                                                const Icon(Icons.cloud_off_rounded, color: Color(0xFFE50914), size: 20),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Text(
                                                    'Folder penyimpanan untuk "${_item.title}" sedang tidak terhubung. Sambungkan drive atau periksa folder di Pengaturan.',
                                                    style: const TextStyle(color: Colors.white, fontSize: 13),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                      _cleanUpResources();
                                      if (widget.onPlayEpisode != null) {
                                        widget.onPlayEpisode!(ep);
                                      } else {
                                        widget.onPlay();
                                      }
                                    },
                                    builder: (context, isHovered) {
                                      return AnimatedContainer(
                                        duration: const Duration(milliseconds: 160),
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: isHovered ? const Color(0xFF242424) : Colors.transparent,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: isHovered ? Colors.white24 : Colors.transparent,
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            // Episode Number Index
                                            SizedBox(
                                              width: 40,
                                              child: Text(
                                                '$epIndexDisplay',
                                                style: TextStyle(
                                                  color: isHovered ? Colors.white : Colors.white54,
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),

                                            // Episode 16:9 Thumbnail with On-Demand Local Extraction
                                            _EpisodeThumbnailWidget(
                                              episode: ep,
                                              fallbackPoster: _item.customThumbnail,
                                              episodeNumber: epIndexDisplay,
                                            ),
                                            const SizedBox(width: 16),

                                            // Episode Info (Baris 1: Langsung Judul Episode & Durasi, Baris 2: Sinopsis)
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  // Baris 1: Judul Episode & Durasi
                                                  Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    crossAxisAlignment: CrossAxisAlignment.center,
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          displayTitle,
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: TextStyle(
                                                            color: isHovered ? const Color(0xFFE50914) : Colors.white,
                                                            fontSize: 14.5,
                                                            fontWeight: FontWeight.bold,
                                                            letterSpacing: 0.1,
                                                          ),
                                                        ),
                                                      ),
                                                      if (durationLabel.isNotEmpty) ...[
                                                        const SizedBox(width: 12),
                                                        Text(
                                                          durationLabel,
                                                          style: const TextStyle(
                                                            color: Colors.white60,
                                                            fontSize: 13,
                                                            fontWeight: FontWeight.w500,
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                  // Baris 2: Sinopsis episode (jika ada)
                                                  if (hasSynopsis) ...[
                                                    const SizedBox(height: 5),
                                                    Text(
                                                      ep.synopsis!,
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        color: Colors.white54,
                                                        fontSize: 12,
                                                        height: 1.4,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
          ),

        // Section "Tontonan Lainnya" (Max 6 cards, 2 rows x 3 columns grid)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
          sliver: SliverToBoxAdapter(
            child: widget.similarItems.isNotEmpty
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 36),
                      const Text(
                        'Tontonan Lainnya',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 16),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final cardWidth = ((constraints.maxWidth - 24) / 3).clamp(0.0, double.infinity);
                          final itemsToShow = widget.similarItems.take(6).toList();

                          return Wrap(
                            spacing: 12,
                            runSpacing: 14,
                            children: itemsToShow.map((other) {
                              return SizedBox(
                                width: cardWidth,
                                child: _SimilarItemCard(
                                  item: other,
                                  onTap: () {
                                    if (widget.onSelectItem != null) {
                                      widget.onSelectItem!(other);
                                    }
                                  },
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    ),
  ),
),
),
),
],
),
),
);
  }
}

class _EpisodeThumbnailWidget extends StatefulWidget {
  final Episode episode;
  final String? fallbackPoster;
  final int episodeNumber;

  const _EpisodeThumbnailWidget({
    required this.episode,
    required this.fallbackPoster,
    required this.episodeNumber,
  });

  @override
  State<_EpisodeThumbnailWidget> createState() => _EpisodeThumbnailWidgetState();
}

class _EpisodeThumbnailWidgetState extends State<_EpisodeThumbnailWidget> {
  String? _resolvedThumb;
  bool _isExtracting = false;

  @override
  void initState() {
    super.initState();
    _checkAndExtractThumb();
  }

  @override
  void didUpdateWidget(covariant _EpisodeThumbnailWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.episode.videoPath != widget.episode.videoPath ||
        oldWidget.episode.thumbnail != widget.episode.thumbnail) {
      _resolvedThumb = null;
      _isExtracting = false;
      _checkAndExtractThumb();
    }
  }

  void _checkAndExtractThumb() {
    final targetVideoPath = widget.episode.videoPath;

    // 1. Check if episode already has an existing thumbnail file
    final epThumb = widget.episode.thumbnail;
    if (epThumb != null &&
        epThumb.isNotEmpty &&
        !epThumb.startsWith('http://') &&
        !epThumb.startsWith('https://') &&
        LocalThumbnailService.fileExistsCached(epThumb)) {
      _resolvedThumb = epThumb;
      return;
    }

    // 2. Check if local thumbnail already exists on disk
    if (LocalThumbnailService.hasThumbnail(targetVideoPath)) {
      _resolvedThumb = LocalThumbnailService.getThumbnailPath(targetVideoPath);
      return;
    }

    // 3. Trigger fast on-demand background extraction via ffmpeg
    if (!_isExtracting && targetVideoPath.isNotEmpty) {
      _isExtracting = true;
      LocalThumbnailService.extractThumbnail(targetVideoPath).then((path) {
        if (!mounted || widget.episode.videoPath != targetVideoPath) return;
        if (path != null && path.isNotEmpty) {
          setState(() {
            _resolvedThumb = path;
            _isExtracting = false;
          });
        } else {
          setState(() => _isExtracting = false);
        }
      }).catchError((_) {
        if (mounted && widget.episode.videoPath == targetVideoPath) {
          setState(() => _isExtracting = false);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final thumb = _resolvedThumb ?? widget.episode.thumbnail;
    final hasThumb = thumb != null && thumb.isNotEmpty;
    final isNetwork = hasThumb && (thumb.startsWith('http://') || thumb.startsWith('https://'));
    final isLocalFile = hasThumb && !isNetwork && LocalThumbnailService.fileExistsCached(thumb);

    Widget content;
    if (isLocalFile) {
      content = Image.file(
        File(thumb),
        fit: BoxFit.cover,
        cacheWidth: 260,
        errorBuilder: (_, _, _) => _buildFallback(),
      );
    } else if (isNetwork) {
      content = Image.network(
        thumb,
        fit: BoxFit.cover,
        cacheWidth: 260,
        errorBuilder: (_, _, _) => _buildFallback(),
      );
    } else {
      content = _buildFallback();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 130,
        height: 75,
        color: const Color(0xFF282828),
        child: Stack(
          fit: StackFit.expand,
          children: [
            content,
            Center(
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.5),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEpisodeNumberTile() {
    return Container(
      color: const Color(0xFF222222),
      child: Center(
        child: Text(
          '${widget.episodeNumber}',
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildFallback() {
    final fb = widget.fallbackPoster;
    if (fb != null && fb.isNotEmpty) {
      final isNet = fb.startsWith('http://') || fb.startsWith('https://');
      final isLocal = !isNet && LocalThumbnailService.fileExistsCached(fb);
      if (isLocal || isNet) {
        return Stack(
          fit: StackFit.expand,
          children: [
            if (isLocal)
              Image.file(
                LocalThumbnailService.resolveFile(fb),
                fit: BoxFit.cover,
                cacheWidth: 260,
                errorBuilder: (_, _, _) => _buildEpisodeNumberTile(),
              )
            else
              Image.network(
                fb,
                fit: BoxFit.cover,
                cacheWidth: 260,
                errorBuilder: (_, _, _) => _buildEpisodeNumberTile(),
              ),
            Container(color: Colors.black54),
          ],
        );
      }
    }
    return _buildEpisodeNumberTile();
  }
}

/// Netflix-Style Similar Item Card for "Tontonan Lainnya" (Matches Screenshot 4)
class _SimilarItemCard extends StatelessWidget {
  final MediaItem item;
  final VoidCallback onTap;

  const _SimilarItemCard({
    required this.item,
    required this.onTap,
  });

  String _getResolution() => MediaUiHelpers.resolveVideoResolutionLabel(item);

  @override
  Widget build(BuildContext context) {
    final epCount = item.isSeries ? '${item.episodes.length} Episode' : 'Film';
    final resolution = _getResolution();

    return HoverAnimatedWidget(
      hoverScale: 1.025,
      onTap: onTap,
      builder: (context, isHovered) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: isHovered ? const Color(0xFF2B2B2B) : const Color(0xFF242424),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isHovered ? Colors.white38 : Colors.white10,
              width: 0.8,
            ),
            boxShadow: isHovered
                ? const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 12,
                      offset: Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top 16:9 Thumbnail / Backdrop with Episode/Duration badge
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(5.2)),
                      child: _buildThumb(),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: Colors.white24, width: 0.6),
                        ),
                        child: Text(
                          epCount,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Bottom details section (Screenshot 4)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Metadata row: Maturity • Resolution • Year • Selengkapnya Button
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white54, width: 0.8),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text(
                            '${item.maturity}+',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white38, width: 0.8),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text(
                            resolution,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (item.year != null && item.year!.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(
                            item.year!,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const Spacer(),
                        Tooltip(
                          message: 'Selengkapnya',
                          waitDuration: const Duration(milliseconds: 500),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isHovered ? const Color(0xFF333333) : const Color(0xFF282828),
                              border: Border.all(
                                color: isHovered ? Colors.white : Colors.white54,
                                width: isHovered ? 1.4 : 1.1,
                              ),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isHovered ? const Color(0xFFE50914) : Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildThumb() {
    final image = (item.backdrop2Url != null && item.backdrop2Url!.isNotEmpty)
        ? item.backdrop2Url
        : (item.backdropUrl ?? item.customThumbnail);
    if (image != null && image.isNotEmpty) {
      if (image.startsWith('http://') || image.startsWith('https://')) {
        return Image.network(image, fit: BoxFit.cover, cacheWidth: 320, errorBuilder: (_, _, _) => _fallback());
      }
      if (LocalThumbnailService.fileExistsCached(image)) {
        return Image.file(
          LocalThumbnailService.resolveFile(image),
          fit: BoxFit.cover,
          cacheWidth: 320,
          errorBuilder: (_, _, _) => _fallback(),
        );
      }
    }
    return _fallback();
  }

  Widget _fallback() {
    return Container(
      color: const Color(0xFF1E1E1E),
      child: const Center(child: Icon(Icons.movie, size: 36, color: Colors.white24)),
    );
  }
}


