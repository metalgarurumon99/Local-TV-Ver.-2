part of '../in_app_player.dart';

/// Animated "Sedang Diputar" badge with bouncing Netflix-style equalizer bars
class AnimatedNowPlayingBadge extends StatefulWidget {
  final String text;
  final bool isPlaying;
  const AnimatedNowPlayingBadge({
    super.key,
    this.text = 'Sedang Diputar',
    this.isPlaying = true,
  });

  @override
  State<AnimatedNowPlayingBadge> createState() => _AnimatedNowPlayingBadgeState();
}

class _AnimatedNowPlayingBadgeState extends State<AnimatedNowPlayingBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedNowPlayingBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying) {
      if (widget.isPlaying) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.68),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Bouncing equalizer bars (Netflix style)
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final t = _controller.value;
                  final h1 = 4.0 + 8.0 * ((math.sin(t * 2 * math.pi) + 1) / 2);
                  final h2 = 4.0 + 9.5 * ((math.sin((t + 0.33) * 2 * math.pi) + 1) / 2);
                  final h3 = 4.0 + 7.5 * ((math.sin((t + 0.66) * 2 * math.pi) + 1) / 2);
                  return SizedBox(
                    height: 14,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _buildBar(h1),
                        const SizedBox(width: 2),
                        _buildBar(h2),
                        const SizedBox(width: 2),
                        _buildBar(h3),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(width: 5),
              Text(
                widget.text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBar(double height) {
    return Container(
      width: 2.5,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFE50914),
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}

/// Timeline Scrubber with Trickplay Preview Bubble & Chapter Marker Notches
class _PlayerSeekBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final List<VideoChapter> chapters;
  final TrickplayData? trickplayData;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onActivity;

  const _PlayerSeekBar({
    required this.position,
    required this.duration,
    required this.chapters,
    required this.trickplayData,
    required this.onSeek,
    required this.onActivity,
  });

  @override
  State<_PlayerSeekBar> createState() => _PlayerSeekBarState();
}

class _PlayerSeekBarState extends State<_PlayerSeekBar> {
  final ValueNotifier<({double x, Duration duration})?> _hoverNotifier =
      ValueNotifier<({double x, Duration duration})?>(null);

  @override
  void dispose() {
    _hoverNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final durMs = widget.duration.inMilliseconds;
    final posMs = widget.position.inMilliseconds.clamp(0, durMs > 0 ? durMs : 0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        const double horizontalPadding = 24.0;
        final trackWidth = math.max(1.0, totalWidth - (horizontalPadding * 2));

        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // Chapter Notches along track
            if (widget.chapters.isNotEmpty && durMs > 0)
              Positioned(
                left: horizontalPadding,
                right: horizontalPadding,
                height: 4,
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _ChapterNotchesPainter(
                      chapters: widget.chapters,
                      duration: widget.duration,
                    ),
                  ),
                ),
              ),

            // Slider
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: const Color(0xFFE50914),
                inactiveTrackColor: Colors.white24,
                thumbColor: const Color(0xFFE50914),
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: posMs.toDouble(),
                min: 0.0,
                max: durMs > 0 ? durMs.toDouble() : 1.0,
                onChanged: (val) {
                  widget.onSeek(Duration(milliseconds: val.toInt()));
                  widget.onActivity();
                },
              ),
            ),

            // Mouse hover region (updates ONLY preview card via ValueNotifier, zero full seekbar rebuilds)
            Positioned.fill(
              child: MouseRegion(
                opaque: false,
                onHover: (event) {
                  final localX = event.localPosition.dx;
                  final clampedTrackX = (localX - horizontalPadding).clamp(0.0, trackWidth);
                  final fraction = (clampedTrackX / trackWidth).clamp(0.0, 1.0);
                  _hoverNotifier.value = (
                    x: localX,
                    duration: Duration(milliseconds: (fraction * durMs).toInt()),
                  );
                },
                onExit: (_) {
                  _hoverNotifier.value = null;
                },
              ),
            ),

            // Floating Trickplay Preview Card (isolated rebuild on hover)
            ValueListenableBuilder<({double x, Duration duration})?>(
              valueListenable: _hoverNotifier,
              builder: (context, hover, _) {
                if (hover == null || durMs <= 0) return const SizedBox.shrink();
                final hoverDuration = hover.duration;
                VideoChapter? hoverChapter;
                if (widget.chapters.isNotEmpty && hoverDuration > Duration.zero) {
                  for (final ch in widget.chapters) {
                    if (hoverDuration >= ch.start && hoverDuration < ch.end) {
                      hoverChapter = ch;
                      break;
                    }
                  }
                }

                return Positioned(
                  bottom: 34,
                  left: (hover.x - 85).clamp(8.0, math.max(8.0, totalWidth - 178.0)),
                  child: IgnorePointer(
                    child: Container(
                      width: 170,
                      decoration: BoxDecoration(
                        color: const Color(0xFA181818),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white24, width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.75),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.trickplayData?.decodedImage != null)
                            SizedBox(
                              width: 170,
                              height: 96,
                              child: CustomPaint(
                                painter: TrickplayTilePainter(
                                  spriteImage: widget.trickplayData!.decodedImage!,
                                  srcRect: widget.trickplayData!.getTileRect(hoverDuration),
                                ),
                              ),
                            )
                          else
                            Container(
                              width: 170,
                              height: 96,
                              color: Colors.black45,
                              child: const Center(
                                child: Icon(Icons.movie_creation_outlined, color: Colors.white30, size: 30),
                              ),
                            ),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            color: const Color(0xFF1F1F1F),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _formatDurationTopLevel(widget.duration, hoverDuration),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                if (hoverChapter != null && hoverChapter.title.trim().isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    hoverChapter.title.trim(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFFE50914),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

String _formatDurationTopLevel(Duration totalDuration, Duration duration) {
  String twoDigits(int n) => n.toString().padLeft(2, '0');
  final minutes = twoDigits(duration.inMinutes.remainder(60));
  final seconds = twoDigits(duration.inSeconds.remainder(60));
  if (totalDuration.inHours > 0 || duration.inHours > 0) {
    return '${twoDigits(duration.inHours)}:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}

class _ChapterNotchesPainter extends CustomPainter {
  final List<VideoChapter> chapters;
  final Duration duration;

  _ChapterNotchesPainter({required this.chapters, required this.duration});

  @override
  void paint(Canvas canvas, Size size) {
    if (duration.inMilliseconds <= 0 || chapters.isEmpty) return;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;

    final durMs = duration.inMilliseconds.toDouble();
    for (final ch in chapters) {
      if (ch.start <= Duration.zero) continue;
      final startFraction = ch.start.inMilliseconds.toDouble() / durMs;
      if (startFraction > 0.0 && startFraction < 1.0) {
        final x = startFraction * size.width;
        canvas.drawRect(Rect.fromLTWH(x - 1, -2, 2, size.height + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChapterNotchesPainter oldDelegate) {
    return oldDelegate.chapters != chapters || oldDelegate.duration != duration;
  }
}

/// Episode 16:9 Thumbnail Widget with On-Demand Extraction & Fallback
class _PlayerEpisodeThumbnail extends StatefulWidget {
  final Episode? episode;
  final MediaItem item;
  final String? fallbackPoster;

  const _PlayerEpisodeThumbnail({
    required this.episode,
    required this.item,
    this.fallbackPoster,
  });

  @override
  State<_PlayerEpisodeThumbnail> createState() => _PlayerEpisodeThumbnailState();
}

class _PlayerEpisodeThumbnailState extends State<_PlayerEpisodeThumbnail> {
  String? _resolvedThumb;
  bool _isExtracting = false;

  @override
  void initState() {
    super.initState();
    _checkAndExtractThumb();
  }

  @override
  void didUpdateWidget(covariant _PlayerEpisodeThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.videoPath != widget.item.videoPath ||
        oldWidget.episode?.thumbnail != widget.episode?.thumbnail) {
      _resolvedThumb = null;
      _isExtracting = false;
      _checkAndExtractThumb();
    }
  }

  void _checkAndExtractThumb() {
    final vPath = widget.item.videoPath;
    final epThumb = widget.episode?.thumbnail;

    // 1. Direct episode thumbnail file/URL
    if (epThumb != null &&
        epThumb.isNotEmpty &&
        !epThumb.startsWith('http://') &&
        !epThumb.startsWith('https://') &&
        LocalThumbnailService.fileExistsCached(epThumb)) {
      _resolvedThumb = epThumb;
      return;
    }

    // 2. Check if local thumbnail already exists on disk
    if (vPath.isNotEmpty && LocalThumbnailService.hasThumbnail(vPath)) {
      _resolvedThumb = LocalThumbnailService.getThumbnailPath(vPath);
      return;
    }

    // 3. Trigger fast on-demand background extraction via ffmpeg
    if (!_isExtracting && vPath.isNotEmpty && !vPath.startsWith('asset:')) {
      _isExtracting = true;
      LocalThumbnailService.extractThumbnail(vPath).then((path) {
        if (!mounted || widget.item.videoPath != vPath) return;
        if (path != null && path.isNotEmpty) {
          setState(() {
            _resolvedThumb = path;
            _isExtracting = false;
          });
        } else {
          setState(() => _isExtracting = false);
        }
      }).catchError((_) {
        if (mounted && widget.item.videoPath == vPath) {
          setState(() => _isExtracting = false);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final thumb = _resolvedThumb ?? widget.episode?.thumbnail;
    final hasThumb = thumb != null && thumb.isNotEmpty;
    final isLocal = hasThumb && LocalThumbnailService.fileExistsCached(thumb);
    final isNet = hasThumb && (thumb.startsWith('http://') || thumb.startsWith('https://'));

    if (isLocal) {
      return Image.file(
        File(thumb),
        fit: BoxFit.cover,
        cacheWidth: 260,
        errorBuilder: (_, _, _) => _buildFallback(),
      );
    } else if (isNet) {
      return Image.network(
        thumb,
        fit: BoxFit.cover,
        cacheWidth: 260,
        errorBuilder: (_, _, _) => _buildFallback(),
      );
    }
    return _buildFallback();
  }

  Widget _buildFallback() {
    final fb = widget.fallbackPoster ?? widget.item.customThumbnail ?? widget.item.backdropUrl;
    if (fb != null && fb.isNotEmpty) {
      final isLocal = LocalThumbnailService.fileExistsCached(fb);
      final isNet = fb.startsWith('http://') || fb.startsWith('https://');
      if (isLocal) {
        return Image.file(File(fb), fit: BoxFit.cover, cacheWidth: 260);
      } else if (isNet) {
        return Image.network(fb, fit: BoxFit.cover, cacheWidth: 260);
      }
    }
    return Container(
      color: const Color(0xFF222222),
      child: const Center(
        child: Icon(Icons.movie_creation_outlined, color: Colors.white24, size: 26),
      ),
    );
  }
}
