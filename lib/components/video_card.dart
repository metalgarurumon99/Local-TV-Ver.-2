import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/media_item.dart';

class VideoCard extends StatefulWidget {
  final MediaItem item;
  final VoidCallback onPlay;
  final VoidCallback onSelect;
  final VoidCallback? onEdit;

  const VideoCard({
    super.key,
    required this.item,
    required this.onPlay,
    required this.onSelect,
    this.onEdit,
  });

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  bool _isHovered = false;
  Player? _previewPlayer;
  VideoController? _previewController;
  Timer? _hoverTimer;
  StreamSubscription? _posSub;
  bool _isPreviewReady = false;

  @override
  void dispose() {
    _stopPreview();
    super.dispose();
  }

  void _onHoverEnter() {
    setState(() => _isHovered = true);
    // Delay 850ms before launching video preview to avoid lag during fast scrolling
    _hoverTimer?.cancel();
    _hoverTimer = Timer(const Duration(milliseconds: 850), () {
      if (mounted && _isHovered) {
        _startHoverPreview();
      }
    });
  }

  void _onHoverExit() {
    setState(() => _isHovered = false);
    _stopPreview();
  }

  String _resolveVideoPath() {
    if (widget.item.videoPath.isNotEmpty && !widget.item.videoPath.startsWith('asset:')) {
      return widget.item.videoPath;
    }
    if (widget.item.episodes.isNotEmpty) {
      return widget.item.episodes.first.videoPath;
    }
    return '';
  }

  Future<void> _startHoverPreview() async {
    final path = _resolveVideoPath();
    if (path.isEmpty || !File(path).existsSync()) return;

    try {
      final player = Player();
      final controller = VideoController(player);

      await player.setVolume(0); // Muted preview
      await player.open(Media(path), play: true);
      await player.seek(const Duration(seconds: 35)); // Skip opening black frames

      // Loop a 15-second snippet
      _posSub = player.stream.position.listen((pos) {
        if (pos.inSeconds > 50) {
          player.seek(const Duration(seconds: 35));
        }
      });

      if (mounted && _isHovered) {
        setState(() {
          _previewPlayer = player;
          _previewController = controller;
          _isPreviewReady = true;
        });
      } else {
        player.dispose();
      }
    } catch (e) {
      debugPrint('Card preview failed: $e');
    }
  }

  void _stopPreview() {
    _hoverTimer?.cancel();
    _posSub?.cancel();
    _isPreviewReady = false;
    _previewPlayer?.stop();
    _previewPlayer?.dispose();
    _previewPlayer = null;
    _previewController = null;
  }

  Widget _buildFallbackCard() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2A1114),
            Color(0xFF1E1E1E),
            Color(0xFF141414),
          ],
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.movie_filter_rounded, color: Color(0xFFE50914), size: 36),
          const SizedBox(height: 10),
          Text(
            widget.item.title,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          if (widget.item.year != null) ...[
            const SizedBox(height: 6),
            Text(
              widget.item.year!,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildThumbnail() {
    if (widget.item.isNetworkImage) {
      return Image.network(
        widget.item.customThumbnail!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildFallbackCard(),
      );
    }

    if (widget.item.customThumbnail != null &&
        File(widget.item.customThumbnail!).existsSync()) {
      return Image.file(
        File(widget.item.customThumbnail!),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildFallbackCard(),
      );
    }

    return Image.asset(
      widget.item.thumbnailPath,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => _buildFallbackCard(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _onHoverEnter(),
      onExit: (_) => _onHoverExit(),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          _stopPreview();
          widget.onSelect();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: 155, // Clean 2:3 vertical poster width
          margin: const EdgeInsets.only(right: 14),
          transform: Matrix4.diagonal3Values(
            _isHovered ? 1.05 : 1.0,
            _isHovered ? 1.05 : 1.0,
            1.0,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.9),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: const Color(0xFFE50914).withValues(alpha: 0.4),
                      blurRadius: 10,
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              children: [
                // 1. Full Portrait 2:3 Poster
                AspectRatio(
                  aspectRatio: 2 / 3,
                  child: _buildThumbnail(),
                ),

                // 2. Video Preview when Hovered for >850ms
                if (_previewController != null)
                  Positioned.fill(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 300),
                      opacity: _isPreviewReady ? 1.0 : 0.0,
                      child: Video(
                        controller: _previewController!,
                        fit: BoxFit.cover,
                        controls: NoVideoControls,
                      ),
                    ),
                  ),

                // 3. Permanent Title Overlay at Bottom (when not hovered)
                if (!_isHovered)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.9),
                          ],
                        ),
                      ),
                      child: Text(
                        widget.item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                        ),
                      ),
                    ),
                  ),

                // 4. Series Episode Count Badge (Top-Right)
                if (widget.item.isSeries && widget.item.episodes.isNotEmpty)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE50914),
                        borderRadius: BorderRadius.circular(3),
                        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4)],
                      ),
                      child: Text(
                        '${widget.item.episodes.length} EPS',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                // 5. Rich Hover Controls Overlay
                Positioned.fill(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    opacity: _isHovered ? 1.0 : 0.0,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.75),
                            Colors.black.withValues(alpha: 0.95),
                          ],
                          stops: const [0.3, 0.65, 1.0],
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              // Quick Play Button
                              InkWell(
                                onTap: () {
                                  _stopPreview();
                                  widget.onPlay();
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.play_arrow,
                                    color: Colors.black,
                                    size: 18,
                                  ),
                                ),
                              ),
                              const Spacer(),

                              // Edit Button
                              if (widget.onEdit != null) ...[
                                Tooltip(
                                  message: 'Edit Info & Poster',
                                  child: InkWell(
                                    onTap: () {
                                      _stopPreview();
                                      widget.onEdit!();
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(5),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white38, width: 0.8),
                                      ),
                                      child: const Icon(Icons.edit_outlined, color: Colors.white, size: 14),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],

                              // Info Chevron
                              const Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 20),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Title
                          Text(
                            widget.item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),

                          // Genre & Maturity
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.white54, width: 0.8),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                child: Text(
                                  '${widget.item.maturity}+',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  widget.item.genre.split(',').first,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF46D369),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
