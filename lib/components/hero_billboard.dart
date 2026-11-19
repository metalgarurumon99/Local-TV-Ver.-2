import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/media_item.dart';
import '../services/preview_player_service.dart';
import '../services/thumbnail_service.dart';
import '../services/watch_history_service.dart';
import '../utils/media_ui_helpers.dart';
import 'hover_animated_widget.dart';
import 'vertical_preview_volume.dart';

class HeroBillboard extends StatefulWidget {
  final MediaItem featuredItem;
  final bool isActive;
  final bool isConnected;
  final VoidCallback onPlay;
  final VoidCallback onMoreInfo;
  final int currentIndex;
  final int totalCount;
  final VoidCallback? onNext;
  final VoidCallback? onPrev;
  final ValueChanged<int>? onSelectIndex;
  final ValueNotifier<bool>? isVisibleNotifier;

  const HeroBillboard({
    super.key,
    required this.featuredItem,
    this.isActive = true,
    this.isConnected = true,
    required this.onPlay,
    required this.onMoreInfo,
    this.currentIndex = 0,
    this.totalCount = 1,
    this.onNext,
    this.onPrev,
    this.onSelectIndex,
    this.isVisibleNotifier,
  });

  @override
  State<HeroBillboard> createState() => _HeroBillboardState();
}

class _HeroBillboardState extends State<HeroBillboard> {
  Timer? _previewTimer;
  late final String _ownerId;

  @override
  void initState() {
    super.initState();
    _ownerId = 'hero-${widget.featuredItem.id}-${identityHashCode(this)}';
    widget.isVisibleNotifier?.addListener(_handleVisibilityChanged);
    final bool isVisible = widget.isVisibleNotifier?.value ?? true;
    if (widget.isActive && isVisible) {
      _schedulePreview();
    }
  }

  void _handleVisibilityChanged() {
    final bool isVisible = widget.isVisibleNotifier?.value ?? true;
    if (!isVisible) {
      _stopPreview();
    } else if (widget.isActive && widget.isConnected) {
      _schedulePreview();
    }
  }

  @override
  void didUpdateWidget(covariant HeroBillboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isVisibleNotifier != widget.isVisibleNotifier) {
      oldWidget.isVisibleNotifier?.removeListener(_handleVisibilityChanged);
      widget.isVisibleNotifier?.addListener(_handleVisibilityChanged);
    }
    final bool isVisible = widget.isVisibleNotifier?.value ?? true;
    if (!widget.isActive || !isVisible || !widget.isConnected) {
      _stopPreview();
      return;
    }
    if (oldWidget.featuredItem.id != widget.featuredItem.id ||
        oldWidget.featuredItem.videoPath != widget.featuredItem.videoPath ||
        (!oldWidget.isActive && widget.isActive) ||
        (!oldWidget.isConnected && widget.isConnected)) {
      _stopPreview();
      _schedulePreview();
    }
  }

  @override
  void dispose() {
    widget.isVisibleNotifier?.removeListener(_handleVisibilityChanged);
    _stopPreview();
    super.dispose();
  }

  void _schedulePreview() {
    _previewTimer?.cancel();
    if (!widget.isConnected || !widget.isActive) return;
    final bool isVisible = widget.isVisibleNotifier?.value ?? true;
    if (!isVisible) return;

    // 2.5 seconds delay so the backdrop/poster is displayed first before preview starts
    _previewTimer = Timer(const Duration(milliseconds: 2500), () {
      if (!mounted || !widget.isActive) return;
      final bool currentVisible = widget.isVisibleNotifier?.value ?? true;
      if (!currentVisible) return;

      final activeOwner = PreviewPlayerService.instance.activeOwnerId;
      if (activeOwner != null && !activeOwner.startsWith('hero-')) return;

      final path = _resolveVideoPath();
      if (path.isNotEmpty) {
        PreviewPlayerService.instance.requestPreview(
          ownerId: _ownerId,
          videoPath: path,
          allowAudio: true,
          maxDuration: const Duration(seconds: 40),
        );
      }
    });
  }

  void _stopPreview() {
    _previewTimer?.cancel();
    PreviewPlayerService.instance.releasePreview(_ownerId);
  }

  String? _resolveLogoPath() {
    if (widget.featuredItem.logoUrl != null && widget.featuredItem.logoUrl!.isNotEmpty) {
      final p = widget.featuredItem.logoUrl!;
      if (p.startsWith('http://') || p.startsWith('https://')) {
        return p;
      }
      if (LocalThumbnailService.fileExistsCached(p)) {
        return p;
      }
    }
    return null;
  }

  String _resolveVideoPath() {
    if (widget.featuredItem.videoPath.isNotEmpty &&
        !widget.featuredItem.videoPath.startsWith('asset:')) {
      return widget.featuredItem.videoPath;
    }
    if (widget.featuredItem.episodes.isNotEmpty) {
      return widget.featuredItem.episodes.first.videoPath;
    }
    return '';
  }

  Widget _buildBackgroundImage() {
    // Cascading candidate lookup: backdropUrl -> customThumbnail -> episode thumbnail
    String? chosenImage;
    final candidates = <String?>[
      widget.featuredItem.backdropUrl,
      widget.featuredItem.customThumbnail,
      ...widget.featuredItem.episodes.map((e) => e.thumbnail),
    ];

    for (final c in candidates) {
      if (c == null || c.isEmpty) continue;
      final net = c.startsWith('http://') || c.startsWith('https://');
      if (net || LocalThumbnailService.fileExistsCached(c)) {
        chosenImage = c;
        break;
      }
    }

    if (chosenImage != null && chosenImage.isNotEmpty) {
      Widget imageWidget(
        BoxFit fit,
        Alignment alignment, {
        double? width,
        double? height,
        int cacheWidth = 1280,
      }) {
        if (chosenImage!.startsWith('http://') || chosenImage.startsWith('https://')) {
          return Image.network(
            chosenImage,
            fit: fit,
            alignment: alignment,
            width: width,
            height: height,
            cacheWidth: cacheWidth,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, _, _) => _buildFallbackImage(),
          );
        }
        if (LocalThumbnailService.fileExistsCached(chosenImage)) {
          return Image.file(
            File(chosenImage),
            fit: fit,
            alignment: alignment,
            width: width,
            height: height,
            cacheWidth: cacheWidth,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, _, _) => _buildFallbackImage(),
          );
        }
        return _buildFallbackImage();
      }

      final isBackdrop = widget.featuredItem.backdropUrl != null &&
          widget.featuredItem.backdropUrl!.isNotEmpty &&
          chosenImage == widget.featuredItem.backdropUrl;

      return RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Ambient Blurred Layer (low-res 240px source + modest sigma so GPU caches & composites at 144fps)
            Positioned.fill(
              child: RepaintBoundary(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 16, sigmaY: 16, tileMode: TileMode.decal),
                  child: Opacity(
                    opacity: 0.35,
                    child: imageWidget(
                      BoxFit.cover,
                      Alignment.center,
                      cacheWidth: 240,
                    ),
                  ),
                ),
              ),
            ),

            // 2. Artwork on the RIGHT (Uncropped backdrop/poster with smooth left feather fade)
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              width: isBackdrop ? 880 : 720,
              child: RepaintBoundary(
                child: ShaderMask(
                  shaderCallback: (rect) {
                    return const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Colors.transparent, Colors.black, Colors.black],
                      stops: [0.0, 0.28, 1.0],
                    ).createShader(rect);
                  },
                  blendMode: BlendMode.dstIn,
                  child: imageWidget(
                    isBackdrop ? BoxFit.cover : BoxFit.contain,
                    Alignment.centerRight,
                    cacheWidth: 1280,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return _buildFallbackImage();
  }

  Widget _buildFallbackImage() {
    return Container(
      color: const Color(0xFF141414),
      child: const Center(
        child: Icon(Icons.movie, size: 80, color: Colors.white24),
      ),
    );
  }

  Widget _buildTextTitle() {
    return Text(
      widget.featuredItem.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 40,
        fontWeight: FontWeight.w900,
        height: 1.1,
        letterSpacing: -0.5,
        shadows: [
          Shadow(
            color: Colors.black,
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleLogo() {
    final logoPath = _resolveLogoPath();
    if (logoPath != null && logoPath.isNotEmpty) {
      if (logoPath.startsWith('http://') || logoPath.startsWith('https://')) {
        return ConstrainedBox(
          constraints: const BoxConstraints(
            maxHeight: 110,
            maxWidth: 420,
          ),
          child: Image.network(
            logoPath,
            fit: BoxFit.contain,
            cacheWidth: 480,
            alignment: Alignment.centerLeft,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => _buildTextTitle(),
          ),
        );
      }
      if (LocalThumbnailService.fileExistsCached(logoPath)) {
        return ConstrainedBox(
          constraints: const BoxConstraints(
            maxHeight: 110,
            maxWidth: 420,
          ),
          child: Image.file(
            File(logoPath),
            fit: BoxFit.contain,
            cacheWidth: 480,
            alignment: Alignment.centerLeft,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, _, _) => _buildTextTitle(),
          ),
        );
      }
    }
    return _buildTextTitle();
  }

  Widget _buildMetadataRow() {
    final item = widget.featuredItem;
    final List<Widget> metaItems = [];

    // Offline / Disconnected Badge
    if (!widget.isConnected) {
      metaItems.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xE61A1A1A),
            border: Border.all(color: Colors.white30, width: 0.8),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.cloud_off_rounded, color: Colors.white70, size: 12),
              SizedBox(width: 4),
              Text(
                'Folder Terputus',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Rating
    final rating = item.rating;
    if (rating != null && rating.isNotEmpty && rating != '0' && rating != '0.0') {
      metaItems.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '★',
              style: TextStyle(
                color: Color(0xFFE50914),
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              rating,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    // Year
    final year = item.year;
    if (year != null && year.isNotEmpty) {
      metaItems.add(
        Text(
          year,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    // Series/Movie Type (Movie or Series)
    metaItems.add(
      Text(
        item.isSeries ? 'Series' : 'Movie',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.85),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    // Genres (first 2)
    if (item.genre.isNotEmpty) {
      final genres = item.genre
          .split(',')
          .map((g) => g.trim())
          .where((g) => g.isNotEmpty)
          .take(2);
      for (final g in genres) {
        metaItems.add(
          Text(
            g,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }
    }

    // Quality Badge (Resolution e.g. 1080p, 720p, 4K)
    final resolution = _getVideoResolution(item);
    metaItems.add(
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white60, width: 1),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          resolution,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );

    // Build children with dot separators
    final List<Widget> rowChildren = [];
    for (int i = 0; i < metaItems.length; i++) {
      rowChildren.add(metaItems[i]);
      if (i < metaItems.length - 1) {
        rowChildren.add(
          Text(
            '•',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      }
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: rowChildren,
    );
  }

  String _getVideoResolution(MediaItem item) => MediaUiHelpers.resolveVideoResolutionLabel(item);

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double billboardHeight = (screenHeight * 0.65).clamp(420.0, 620.0);
    final previewService = PreviewPlayerService.instance;

    return SizedBox(
      height: billboardHeight,
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 1. Static Poster / Backdrop Background on the Right (Crossfade Transition)
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              child: KeyedSubtree(
                key: ValueKey<String>('hero-bg-${widget.featuredItem.id}-${widget.featuredItem.videoPath}'),
                child: SizedBox.expand(child: _buildBackgroundImage()),
              ),
            ),
          ),

          // 2. Full-Billboard Video Preview Layer (Plays after 2-3 seconds, fills entire hero billboard)
          ListenableBuilder(
            listenable: previewService,
            builder: (context, _) {
              final bool isReady = previewService.isOwnerReady(_ownerId);
              final controller = previewService.controller;

              // Only mount Video when this HeroBillboard owns the shared VideoController
              // to prevent flashing another card's video and avoid D3D11 texture contention.
              return Positioned.fill(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  child: (isReady && controller != null)
                      ? Video(
                          key: ValueKey<String>('hero-video-${widget.featuredItem.id}'),
                          controller: controller,
                          fit: BoxFit.cover,
                          controls: NoVideoControls,
                          subtitleViewConfiguration: const SubtitleViewConfiguration(
                            visible: false,
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey<String>('hero-video-idle')),
                ),
              );
            },
          ),

          // 3. Dark Vignette Gradients Overlay (Netflix style for text legibility)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.black.withValues(alpha: 0.88),
                    Colors.black.withValues(alpha: 0.40),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.48, 1.0],
                ),
              ),
            ),
          ),

          // Top Navbar Legibility Gradient
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 100,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x99111111),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Bottom Shelf Transition Gradient (Smooth Netflix blend with 100% solid bottom)
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
                    Color(0x33111111),
                    Color(0xB3111111),
                    Color(0xFF111111),
                    Color(0xFF111111),
                  ],
                  stops: [0.35, 0.60, 0.82, 0.94, 1.0],
                ),
              ),
            ),
          ),

          // Solid bottom seal bar to completely block any subpixel bleed of background video/image
          const Positioned(
            left: -2,
            right: -2,
            bottom: -3,
            height: 12,
            child: ColoredBox(
              color: Color(0xFF111111),
            ),
          ),

          // 4. Content Callout (Title, Genre Badge, Synopsis, Cast, Buttons)
          Positioned(
            left: 50,
            bottom: 40,
            width: 580,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Logo Artwork (or Title fallback)
                _buildTitleLogo(),
                const SizedBox(height: 16),

                // 2. Metadata Row: ★ Rating • Year • Type (Series/Movie) • Genre • FHD
                _buildMetadataRow(),
                const SizedBox(height: 14),

                // 4. Synopsis Text (Blurb)
                Text(
                  widget.featuredItem.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 14,
                    height: 1.45,
                    shadows: const [
                      Shadow(color: Colors.black, blurRadius: 8),
                    ],
                  ),
                ),

                // 5. Cast preview (Uses standard body font to match synopsis)
                if (widget.featuredItem.cast.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'Pemeran: ',
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        TextSpan(
                          text: widget.featuredItem.cast.take(5).join(', '),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.normal,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 20),

                // Action Buttons (Play & More Info)
                Builder(
                  builder: (context) {
                    final progress = WatchHistoryService.getProgressSync(widget.featuredItem.id)?.progress ?? 0.0;
                    final isWatched = progress > 0.02;
                    final isConnected = widget.isConnected;
                    final playLabel = !isConnected
                        ? 'Folder Terputus'
                        : (isWatched ? 'Lanjutkan Menonton' : 'Tonton Sekarang');
                    final playIcon = !isConnected
                        ? Icons.cloud_off_rounded
                        : Icons.play_arrow_rounded;

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        HoverAnimatedWidget(
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
                                              'Folder penyimpanan untuk "${widget.featuredItem.title}" sedang tidak terhubung. Sambungkan drive atau periksa folder di Pengaturan.',
                                              style: const TextStyle(color: Colors.white, fontSize: 13),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                _stopPreview();
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
                        ),
                        const SizedBox(width: 14),
                        HoverAnimatedWidget(
                          hoverScale: 1.04,
                          builder: (context, isHovered) {
                            return ElevatedButton.icon(
                              onPressed: () {
                                _stopPreview();
                                widget.onMoreInfo();
                              },
                              icon: const Icon(Icons.info_outline_rounded, color: Colors.white, size: 22),
                              label: const Text(
                                'Selengkapnya',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  height: 1.0,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white.withValues(alpha: isHovered ? 0.40 : 0.28),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shadowColor: Colors.transparent,
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
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),

          // 5. Dynamic Carousel Navigation (Stationary at right: 105, bottom: 45)
          if (widget.totalCount > 1)
            Positioned(
              right: 105,
              bottom: 45,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.onPrev != null)
                    HoverAnimatedWidget(
                      hoverScale: 1.15,
                      onTap: () {
                        _stopPreview();
                        widget.onPrev!();
                      },
                      builder: (context, isHovered) {
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: isHovered ? 0.80 : 0.55),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isHovered ? Colors.white70 : Colors.white24,
                              width: 0.8,
                            ),
                          ),
                          child: const Icon(Icons.arrow_back_ios_new_rounded, size: 13, color: Colors.white),
                        );
                      },
                    ),
                  const SizedBox(width: 8),
                  // Progress / Index indicator bars
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(widget.totalCount, (index) {
                      final isActive = index == widget.currentIndex;
                      return GestureDetector(
                        onTap: () {
                          if (index != widget.currentIndex) {
                            _stopPreview();
                            widget.onSelectIndex?.call(index);
                          }
                        },
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: isActive ? 24 : 8,
                            height: 4,
                            decoration: BoxDecoration(
                              color: isActive ? const Color(0xFFE50914) : Colors.white38,
                              borderRadius: BorderRadius.circular(2),
                              boxShadow: isActive
                                  ? [
                                      BoxShadow(
                                        color: const Color(0xFFE50914).withValues(alpha: 0.7),
                                        blurRadius: 6,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(width: 8),
                  if (widget.onNext != null)
                    HoverAnimatedWidget(
                      hoverScale: 1.15,
                      onTap: () {
                        _stopPreview();
                        widget.onNext!();
                      },
                      builder: (context, isHovered) {
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: isHovered ? 0.80 : 0.55),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isHovered ? Colors.white70 : Colors.white24,
                              width: 0.8,
                            ),
                          ),
                          child: const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: Colors.white),
                        );
                      },
                    ),
                ],
              ),
            ),

          // 6. Netflix-Style Audio Volume Pill Slider (Stationary at right: 50, bottom: 45)
          ListenableBuilder(
            listenable: previewService,
            builder: (context, _) {
              final bool isReady = previewService.isOwnerReady(_ownerId);

              return Positioned(
                right: 50,
                bottom: 45,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: isReady ? 1.0 : 0.0,
                  child: IgnorePointer(
                    ignoring: !isReady,
                    child: VerticalPreviewVolumeControl(
                      iconSize: 20,
                      buttonPadding: 8,
                      sliderHeight: 75,
                      direction: VolumeSliderDirection.up,
                      buttonBackgroundColor: Colors.black.withValues(alpha: 0.6),
                      buttonBorder: Border.all(color: Colors.white38, width: 1.0),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
