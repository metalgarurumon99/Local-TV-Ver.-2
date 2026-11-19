import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/media_item.dart';
import '../services/debug_logger.dart';
import '../services/preview_player_service.dart';
import '../services/thumbnail_service.dart';
import '../services/watch_history_service.dart';
import 'hover_animated_widget.dart';
import 'vertical_preview_volume.dart';

class VideoCard extends StatefulWidget {
  final MediaItem item;
  final VoidCallback onPlay;
  final VoidCallback onSelect;
  final VoidCallback? onEdit;
  final bool isConnected;

  const VideoCard({
    super.key,
    required this.item,
    required this.onPlay,
    required this.onSelect,
    this.onEdit,
    this.isConnected = true,
  });

  static final ValueNotifier<Widget?> activePopoverNotifier = ValueNotifier<Widget?>(null);

  static void closeActivePopover() {
    _VideoCardState._closeActivePopover?.call();
    _VideoCardState._closeActivePopover = null;
    if (activePopoverNotifier.value != null) {
      activePopoverNotifier.value = null;
    }
  }

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  /// Ensures only one expanded Netflix popover card is visible across the entire screen
  static VoidCallback? _closeActivePopover;

  Timer? _hoverTimer;
  bool _isPopoverOpen = false;
  int _hoverScrollGen = 0;

  late final String _ownerId = 'card-${widget.item.id}-${identityHashCode(this)}';

  @override
  void dispose() {
    _hoverTimer?.cancel();
    _removePopover(deferNotifierReset: true);
    super.dispose();
  }

  String _resolveVideoPath() {
    if (widget.item.videoPath.isNotEmpty &&
        !widget.item.videoPath.startsWith('asset:')) {
      return widget.item.videoPath;
    }
    if (widget.item.episodes.isNotEmpty) {
      return widget.item.episodes.first.videoPath;
    }
    return '';
  }

  void _onBaseHoverEnter() {
    DebugLogger.log('VideoCard hoverEnter: item=${widget.item.title}, ownerId=$_ownerId');

    if (_isPopoverOpen) return;

    // Immediately close any active popover from another card so audio/UI never lingers
    if (_closeActivePopover != null && _closeActivePopover != _removePopover) {
      VideoCard.closeActivePopover();
    }

    _hoverTimer?.cancel();
    _hoverScrollGen = PreviewPlayerService.instance.scrollGeneration;

    // Wait 450ms while cursor stays still on the same card before expanding
    _hoverTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      // Do not expand if user scrolled during the wait
      if (PreviewPlayerService.instance.scrollGeneration != _hoverScrollGen) {
        return;
      }
      _showExpandedPopover();
    });
  }

  void _onBaseHoverExit() {
    _hoverTimer?.cancel();
  }

  void _showExpandedPopover() {
    DebugLogger.log('VideoCard showExpandedPopover: item=${widget.item.title}, ownerId=$_ownerId');

    if (!mounted || _isPopoverOpen) return;

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached) {
      DebugLogger.log('VideoCard showExpandedPopover ABORTED: renderBox not attached');
      return;
    }

    // Close any previously open popover from another card
    if (_closeActivePopover != null && _closeActivePopover != _removePopover) {
      _closeActivePopover?.call();
    }

    final Offset cardTopLeft = renderBox.localToGlobal(Offset.zero);
    final Size cardSize = renderBox.size;
    final Size screenSize = MediaQuery.of(context).size;

    const double expandedWidth = 312.0;
    const double expandedHeight = 288.0;

    // Center expanded card horizontally over base card and align top with slight 8px elevation
    double left = cardTopLeft.dx - (expandedWidth - cardSize.width) / 2;
    double top = cardTopLeft.dy - 8.0;

    left = left.clamp(16.0, (screenSize.width - expandedWidth - 16.0).clamp(16.0, double.infinity));
    top = top.clamp(48.0, (screenSize.height - expandedHeight - 16.0).clamp(48.0, double.infinity));

    DebugLogger.log('VideoCard showExpandedPopover COORDS: left=$left, top=$top, cardTopLeft=$cardTopLeft, screen=$screenSize');

    _isPopoverOpen = true;
    _closeActivePopover = _removePopover;

    // Start 30-second video preview immediately as the card expands (only if storage is connected)
    if (widget.isConnected) {
      final path = _resolveVideoPath();
      if (path.isNotEmpty) {
        PreviewPlayerService.instance.requestPreview(
          ownerId: _ownerId,
          videoPath: path,
          allowAudio: true,
          maxDuration: const Duration(seconds: 30),
        );
      }
    }

    VideoCard.activePopoverNotifier.value = _NetflixExpandedCardPopover(
      key: ValueKey<String>('popover-$_ownerId'),
      left: left,
      top: top,
      width: expandedWidth,
      height: expandedHeight,
      item: widget.item,
      isConnected: widget.isConnected,
      ownerId: _ownerId,
      thumbnailBuilder: () => _buildThumbnail(cacheWidth: 480),
      onClose: () {
        DebugLogger.log('VideoCard popover onClose triggered: ownerId=$_ownerId');
        _removePopover();
      },
      onPlay: () {
        _removePopover();
        widget.onPlay();
      },
      onSelect: () {
        _removePopover();
        widget.onSelect();
      },
      onEdit: widget.onEdit != null
          ? () {
              _removePopover();
              widget.onEdit!();
            }
          : null,
    );
    WidgetsBinding.instance.scheduleFrame();
  }

  void _removePopover({bool deferNotifierReset = false}) {
    DebugLogger.log('VideoCard _removePopover CALLED: ownerId=$_ownerId, wasOpen=$_isPopoverOpen');
    _hoverTimer?.cancel();
    _hoverTimer = null;
    final bool wasOpen = _isPopoverOpen;
    _isPopoverOpen = false;
    final bool shouldClear = _closeActivePopover == _removePopover || wasOpen;
    if (_closeActivePopover == _removePopover) {
      _closeActivePopover = null;
    }
    if (shouldClear) {
      if (deferNotifierReset) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_closeActivePopover == null) {
            VideoCard.activePopoverNotifier.value = null;
          }
        });
      } else {
        VideoCard.activePopoverNotifier.value = null;
      }
    }
    PreviewPlayerService.instance.releasePreview(_ownerId);
  }

  Widget _buildFallbackCard() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2B1115),
            Color(0xFF1C1C1C),
            Color(0xFF121212),
          ],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Center(
        child: Text(
          widget.item.title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 15,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  String? _resolveLogoPath() {
    if (widget.item.logoUrl != null && widget.item.logoUrl!.isNotEmpty) {
      final p = widget.item.logoUrl!;
      if (p.startsWith('http://') || p.startsWith('https://')) {
        return p;
      }
      if (LocalThumbnailService.fileExistsCached(p)) {
        return p;
      }
    }
    return null;
  }

  Widget _buildCardLogoOrTitle() {
    final logoPath = _resolveLogoPath();
    if (logoPath != null && logoPath.isNotEmpty) {
      if (logoPath.startsWith('http://') || logoPath.startsWith('https://')) {
        return ConstrainedBox(
          constraints: const BoxConstraints(
            maxHeight: 46,
            maxWidth: 180,
          ),
          child: Image.network(
            logoPath,
            fit: BoxFit.contain,
            alignment: Alignment.bottomLeft,
            cacheWidth: 320,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, _, _) => _buildCardTitleFallback(),
          ),
        );
      }
      if (LocalThumbnailService.fileExistsCached(logoPath)) {
        return ConstrainedBox(
          constraints: const BoxConstraints(
            maxHeight: 46,
            maxWidth: 180,
          ),
          child: Image.file(
            File(logoPath),
            fit: BoxFit.contain,
            alignment: Alignment.bottomLeft,
            cacheWidth: 320,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, _, _) => _buildCardTitleFallback(),
          ),
        );
      }
    }
    return _buildCardTitleFallback();
  }

  Widget _buildCardTitleFallback() {
    return Text(
      widget.item.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w900,
        height: 1.15,
        shadows: [
          Shadow(color: Colors.black, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
    );
  }

  Widget _buildThumbnail({int cacheWidth = 600}) {
    // 1. Prefer backdrop2Url (Secondary Backdrop) for Home Catalog Cards
    // so cards display alternate scenes and don't duplicate the primary Billboard backdrop!
    final backdrop = (widget.item.backdrop2Url != null && widget.item.backdrop2Url!.isNotEmpty)
        ? widget.item.backdrop2Url
        : widget.item.backdropUrl;
    if (backdrop != null && backdrop.isNotEmpty) {
      if (backdrop.startsWith('http://') || backdrop.startsWith('https://')) {
        return Image.network(
          backdrop,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          cacheWidth: cacheWidth,
          gaplessPlayback: true,
          filterQuality: FilterQuality.low,
          errorBuilder: (_, _, _) => _buildPosterOrFallback(cacheWidth),
        );
      }
      if (LocalThumbnailService.fileExistsCached(backdrop)) {
        return Image.file(
          File(backdrop),
          fit: BoxFit.cover,
          alignment: Alignment.center,
          cacheWidth: cacheWidth,
          gaplessPlayback: true,
          filterQuality: FilterQuality.low,
          errorBuilder: (_, _, _) => _buildPosterOrFallback(cacheWidth),
        );
      }
    }

    return _buildPosterOrFallback(cacheWidth);
  }

  Widget _buildPosterOrFallback(int cacheWidth) {
    // 2. Fallback to poster if backdrop is unavailable
    final custom = widget.item.customThumbnail;
    if (custom != null && custom.isNotEmpty) {
      if (custom.startsWith('http://') || custom.startsWith('https://')) {
        return Image.network(
          custom,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          cacheWidth: cacheWidth,
          gaplessPlayback: true,
          filterQuality: FilterQuality.low,
          errorBuilder: (_, _, _) => _buildLocalThumbnailOrFallback(cacheWidth),
        );
      }
      if (LocalThumbnailService.fileExistsCached(custom)) {
        return Image.file(
          File(custom),
          fit: BoxFit.cover,
          alignment: Alignment.center,
          cacheWidth: cacheWidth,
          gaplessPlayback: true,
          filterQuality: FilterQuality.low,
          errorBuilder: (_, _, _) => _buildLocalThumbnailOrFallback(cacheWidth),
        );
      }
    }

    // 3. Fallback to local video frame thumbnail
    return _buildLocalThumbnailOrFallback(cacheWidth);
  }

  Widget _buildLocalThumbnailOrFallback(int cacheWidth) {
    final videoPath = _resolveVideoPath();
    if (videoPath.isNotEmpty && LocalThumbnailService.hasThumbnail(videoPath)) {
      final thumbPath = LocalThumbnailService.getThumbnailPath(videoPath);
      return Image.file(
        File(thumbPath),
        fit: BoxFit.cover,
        alignment: Alignment.center,
        cacheWidth: cacheWidth,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
        errorBuilder: (_, _, _) => _buildFallbackCard(),
      );
    }
    return _buildFallbackCard();
  }

  @override
  Widget build(BuildContext context) {
    final rating = widget.item.rating;
    final year = widget.item.year;

    return Padding(
      padding: const EdgeInsets.only(right: 14, top: 4, bottom: 4),
      child: MouseRegion(
        onEnter: (_) => _onBaseHoverEnter(),
        onHover: (_) {
          if (!_isPopoverOpen && (_hoverTimer == null || !_hoverTimer!.isActive)) {
            _onBaseHoverEnter();
          }
        },
        onExit: (_) => _onBaseHoverExit(),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            _hoverTimer?.cancel();
            _removePopover();
            if (!widget.isConnected) {
              _showDisconnectedToast(context, widget.item.title);
              return;
            }
            widget.onSelect();
          },
          child: SizedBox(
            width: 280,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. 16:9 Landscape Backdrop Card
                Container(
                  width: 280,
                  height: 158,
                  decoration: BoxDecoration(
                    color: const Color(0xFF181818),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12, width: 0.8),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black45,
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7.2),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // 1. 16:9 Landscape Backdrop Image (Zero Cropping!)
                        _buildThumbnail(),

                        // 1b. Dimming overlay for disconnected / offline items
                        if (!widget.isConnected)
                          Positioned.fill(
                            child: Container(
                              color: Colors.black.withValues(alpha: 0.36),
                            ),
                          ),

                        // 2. Bottom Dark Gradient for Logo/Title legibility (tight edge-to-edge coverage)
                        const Positioned(
                          left: -2,
                          right: -2,
                          bottom: -2,
                          height: 95,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Color(0x59000000),
                                  Color(0xCC000000),
                                  Color(0xFF000000),
                                ],
                                stops: [0.0, 0.40, 0.72, 1.0],
                              ),
                            ),
                          ),
                        ),

                        // 3a. Top-Left Offline Badge (if folder/drive is disconnected)
                        if (!widget.isConnected)
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: const Color(0xE6141414),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(color: Colors.white24, width: 0.6),
                                boxShadow: const [
                                  BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 1)),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: const [
                                  Icon(
                                    Icons.cloud_off_rounded,
                                    color: Colors.white70,
                                    size: 11,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Terputus',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.2,
                                      height: 1.0,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // 3. Top-Right Badge (TMDB Rating if available)
                        if (rating != null &&
                            rating.isNotEmpty &&
                            rating != '0' &&
                            rating != '0.0')
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.72),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(color: Colors.white24, width: 0.6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const Text(
                                    '★',
                                    style: TextStyle(
                                      color: Color(0xFFFFB800),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      height: 1.0,
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    rating,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      height: 1.0,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // 4. Bottom-Left Logo (Matching Screenshot 2)
                        Positioned(
                          left: 12,
                          bottom: 10,
                          right: 48,
                          child: _buildCardLogoOrTitle(),
                        ),

                        // 5. Watched Red Progress Bar at very bottom (if partially watched)
                        Builder(
                          builder: (context) {
                            final progress = WatchHistoryService.getProgressSync(widget.item.id)?.progress ?? 0.0;
                            if (progress <= 0.02) return const SizedBox.shrink();
                            return Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              height: 3.5,
                              child: FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: progress.clamp(0.02, 1.0),
                                child: Container(
                                  color: const Color(0xFFE50914),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // 2. Title Below Backdrop Card
                Text(
                  widget.item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    height: 1.2,
                  ),
                ),

                const SizedBox(height: 3),

                // 3. Year, Category, and Episode Info Below Title
                // Format: [Year] • [Movie/Series] • [XX Episode]
                Builder(
                  builder: (context) {
                    final parts = <String>[];
                    if (year != null && year.isNotEmpty) {
                      parts.add(year);
                    }
                    parts.add(widget.item.isSeries ? 'Series' : 'Movie');
                    if (widget.item.isSeries && widget.item.episodes.isNotEmpty) {
                      parts.add('${widget.item.episodes.length} Episode');
                    }
                    return Text(
                      parts.join(' • '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDisconnectedToast(BuildContext context, String title) {
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
                'Folder penyimpanan untuk "$title" sedang tidak terhubung. Sambungkan drive atau periksa folder di Pengaturan.',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Floating Expanded Netflix Preview Card that scales out over surrounding rows
/// when the user rests the mouse cursor on a card for 1 second.
class _NetflixExpandedCardPopover extends StatefulWidget {
  final double left;
  final double top;
  final double width;
  final double height;
  final MediaItem item;
  final bool isConnected;
  final String ownerId;
  final Widget Function() thumbnailBuilder;
  final VoidCallback onClose;
  final VoidCallback onPlay;
  final VoidCallback onSelect;
  final VoidCallback? onEdit;

  const _NetflixExpandedCardPopover({
    super.key,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.item,
    this.isConnected = true,
    required this.ownerId,
    required this.thumbnailBuilder,
    required this.onClose,
    required this.onPlay,
    required this.onSelect,
    this.onEdit,
  });

  @override
  State<_NetflixExpandedCardPopover> createState() => _NetflixExpandedCardPopoverState();
}

class _NetflixExpandedCardPopoverState extends State<_NetflixExpandedCardPopover> {
  WatchHistoryEntry? _historyEntry;

  @override
  void initState() {
    super.initState();
    DebugLogger.log('Popover initState: ownerId=${widget.ownerId}');
    _historyEntry = WatchHistoryService.getProgressSync(widget.item.id);
    _loadWatchProgress();
  }

  @override
  void dispose() {
    DebugLogger.log('Popover dispose: ownerId=${widget.ownerId}');
    super.dispose();
  }

  void _loadWatchProgress() async {
    final entry = await WatchHistoryService.getProgress(widget.item.id);
    if (mounted) {
      setState(() {
        _historyEntry = entry;
      });
    }
  }

  String _buildEpisodeSubtitle() {
    if (widget.item.isSeries && widget.item.episodes.isNotEmpty) {
      Episode targetEp = widget.item.episodes.first;
      if (_historyEntry != null) {
        for (final ep in widget.item.episodes) {
          if (ep.videoPath == _historyEntry!.videoPath ||
              ep.id == _historyEntry!.episodeId ||
              (ep.episodeNumber == _historyEntry!.episodeNumber &&
                  (_historyEntry!.seasonNumber == null || ep.season == _historyEntry!.seasonNumber))) {
            targetEp = ep;
            break;
          }
        }
      }
      final epNum = targetEp.episodeNumber.toString().padLeft(2, '0');
      final rawTitle = targetEp.title.trim();
      final isGenericTitle = rawTitle.isEmpty ||
          rawTitle.toLowerCase() == 'episode ${targetEp.episodeNumber}' ||
          rawTitle.toLowerCase() == 'episode $epNum' ||
          rawTitle.toLowerCase() == 'ep ${targetEp.episodeNumber}';
      if (!isGenericTitle) {
        return 'Episode $epNum - $rawTitle';
      }
      return 'Episode $epNum';
    }
    final yearPart = widget.item.year != null ? '${widget.item.year} • ' : '';
    return '${yearPart}Film Layar Lebar (${widget.item.maturity}+)';
  }

  @override
  Widget build(BuildContext context) {
    final previewService = PreviewPlayerService.instance;

    return Positioned(
      left: widget.left,
      top: widget.top,
      width: widget.width,
      height: widget.height,
      child: MouseRegion(
        hitTestBehavior: HitTestBehavior.opaque,
        onEnter: (_) {
          DebugLogger.log('Popover MouseRegion onEnter: ownerId=${widget.ownerId}');
        },
        onExit: (_) {
          DebugLogger.log('Popover MouseRegion onExit: ownerId=${widget.ownerId}');
          widget.onClose();
        },
        child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.72, end: 1.0),
            duration: const Duration(milliseconds: 190),
            curve: Curves.easeOutCubic,
            builder: (context, scale, child) {
              return Transform.scale(
                scale: scale,
                child: child,
              );
            },
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF181818),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12, width: 0.8),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xE6000000),
                    blurRadius: 28,
                    spreadRadius: 4,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Top 16:9 Video Preview Area (320 x 180)
                    SizedBox(
                      width: widget.width,
                      height: 180,
                      child: GestureDetector(
                        onTap: () {
                          if (!widget.isConnected) {
                            _showDisconnectedToast(context, widget.item.title);
                            return;
                          }
                          widget.onPlay();
                        },
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Static Backdrop Poster
                            widget.thumbnailBuilder(),

                            // Dimming layer if disconnected
                            if (!widget.isConnected)
                              Positioned.fill(
                                child: Container(
                                  color: Colors.black.withValues(alpha: 0.36),
                                ),
                              ),

                            // Live 30s Video Preview Layer (only if connected)
                            if (widget.isConnected)
                              ListenableBuilder(
                                listenable: previewService,
                                builder: (context, _) {
                                  final bool isReady = previewService.isOwnerReady(widget.ownerId);
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

                            // Top-Left Terputus badge
                            if (!widget.isConnected)
                              Positioned(
                                top: 8,
                                left: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xE6141414),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(color: Colors.white24, width: 0.6),
                                    boxShadow: const [
                                      BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 1)),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      Icon(Icons.cloud_off_rounded, color: Colors.white70, size: 11),
                                      SizedBox(width: 4),
                                      Text(
                                        'Terputus',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            // Bottom Gradient for Title & Mute Button
                            const Positioned(
                              left: -2,
                              right: -2,
                              bottom: -2,
                              height: 120,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Color(0x80181818),
                                      Color(0xFF181818),
                                      Color(0xFF181818),
                                    ],
                                    stops: [0.0, 0.45, 0.88, 1.0],
                                  ),
                                ),
                              ),
                            ),
                            const Positioned(
                              left: -2,
                              right: -2,
                              bottom: -2,
                              height: 6,
                              child: ColoredBox(
                                color: Color(0xFF181818),
                              ),
                            ),

                            // Top-Right Red Brand Watermark ('N' / 'L')
                            const Positioned(
                              top: 10,
                              right: 12,
                              child: Text(
                                'L',
                                style: TextStyle(
                                  color: Color(0xFFE50914),
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  shadows: [
                                    Shadow(color: Colors.black87, blurRadius: 6),
                                  ],
                                ),
                              ),
                            ),

                            // Bottom-Left Stylized Title inside Video Preview (matches "Better Late Than Single")
                            Positioned(
                              left: 14,
                              right: 54,
                              bottom: 10,
                              child: Text(
                                widget.item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  height: 1.1,
                                  shadows: [
                                    Shadow(color: Colors.black, blurRadius: 8, offset: Offset(0, 2)),
                                  ],
                                ),
                              ),
                            ),

                            // Bottom-Right Netflix-Style Volume Pill Slider
                            Positioned(
                              right: 12,
                              bottom: 10,
                              child: VerticalPreviewVolumeControl(
                                iconSize: 16,
                                buttonPadding: 6,
                                sliderHeight: 65,
                                direction: VolumeSliderDirection.up,
                                buttonBackgroundColor: const Color(0x8C181818),
                                buttonBorder: Border.all(color: Colors.white54, width: 1.0),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 2. Bottom Metadata & Action Bar (matches Netflix expanded card layout)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Action Buttons Row (Circular Icon Buttons with Interactive Hover Animation)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Play / Resume Circular Icon Button
                                _CircleActionButton(
                                  icon: !widget.isConnected ? Icons.cloud_off_rounded : Icons.play_arrow_rounded,
                                  iconColor: !widget.isConnected ? Colors.white70 : Colors.black,
                                  backgroundColor: !widget.isConnected ? const Color(0xFF2A2A2A) : Colors.white,
                                  borderColor: !widget.isConnected ? Colors.white24 : null,
                                  size: 34,
                                  iconSize: !widget.isConnected ? 18 : 22,
                                  tooltip: !widget.isConnected
                                      ? 'Folder Tidak Terhubung'
                                      : ((_historyEntry != null &&
                                              _historyEntry!.progress > 0 &&
                                              !_historyEntry!.isCompleted)
                                          ? 'Lanjutkan Menonton'
                                          : 'Tonton Sekarang'),
                                  onTap: () {
                                    if (!widget.isConnected) {
                                      _showDisconnectedToast(context, widget.item.title);
                                      return;
                                    }
                                    widget.onPlay();
                                  },
                                ),

                                const Spacer(),

                                // More Info / Episodes (Chevron Down) Circular Icon Button
                                _CircleActionButton(
                                  icon: Icons.keyboard_arrow_down_rounded,
                                  iconColor: Colors.white,
                                  backgroundColor: const Color(0xFF232323),
                                  borderColor: Colors.white54,
                                  size: 34,
                                  iconSize: 22,
                                  tooltip: 'Episode & Info Lengkap',
                                  onTap: widget.onSelect,
                                ),
                              ],
                            ),

                            // 1. Episode XX - Episode Title (no redundant "Sisa X m")
                            Text(
                              _buildEpisodeSubtitle(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),

                            // 2. Conditional: If watched -> Real Red Progress Bar; If unwatched -> Clean Netflix Metadata Row
                            if (_historyEntry != null && _historyEntry!.progress > 0) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      height: 3.5,
                                      decoration: BoxDecoration(
                                        color: Colors.white24,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                      child: FractionallySizedBox(
                                        alignment: Alignment.centerLeft,
                                        widthFactor: _historyEntry!.progress.clamp(0.02, 1.0),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFE50914),
                                            borderRadius: BorderRadius.circular(2),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    _historyEntry!.formattedRemainingTime,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ] else ...[
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.white54, width: 0.8),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      widget.item.maturity.isNotEmpty ? '${widget.item.maturity}+' : '13+',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  if (widget.item.year != null && widget.item.year!.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      widget.item.year!,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(width: 8),
                                  if (widget.item.isSeries && widget.item.episodes.isNotEmpty) ...[
                                    Text(
                                      '${widget.item.episodes.length} Episode',
                                      style: const TextStyle(
                                        color: Color(0xFF46D369),
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (widget.item.genre.isNotEmpty && widget.item.genre != 'Serial TV') ...[
                                      const SizedBox(width: 6),
                                      const Text(
                                        '•',
                                        style: TextStyle(color: Colors.white38, fontSize: 10),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          widget.item.genre.split(',').take(2).join(', ').trim(),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ] else ...[
                                      const Spacer(),
                                    ],
                                  ] else ...[
                                    Expanded(
                                      child: Text(
                                        widget.item.genre.split(',').take(2).join(', ').trim(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFF46D369),
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showDisconnectedToast(BuildContext context, String title) {
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
                'Folder penyimpanan untuk "$title" sedang tidak terhubung. Sambungkan drive atau periksa folder di Pengaturan.',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleActionButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final Color? borderColor;
  final double size;
  final double iconSize;
  final String tooltip;
  final VoidCallback onTap;

  const _CircleActionButton({
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    this.borderColor,
    this.size = 34,
    this.iconSize = 20,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: HoverAnimatedWidget(
        hoverScale: 1.12,
        onTap: onTap,
        builder: (context, isHovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isHovered && backgroundColor == Colors.white
                ? const Color(0xFFE6E6E6)
                : isHovered
                    ? const Color(0xFF333333)
                    : backgroundColor,
            border: borderColor != null
                ? Border.all(
                    color: isHovered ? Colors.white : borderColor!,
                    width: isHovered ? 1.6 : 1.2,
                  )
                : null,
            boxShadow: isHovered
                ? [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.22),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Icon(
              icon,
              color: iconColor,
              size: iconSize,
            ),
          ),
        ),
      ),
    );
  }
}