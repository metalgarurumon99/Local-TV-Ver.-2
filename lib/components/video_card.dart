import 'dart:io';
import 'package:flutter/material.dart';
import '../models/media_item.dart';

class VideoCard extends StatefulWidget {
  final MediaItem item;
  final VoidCallback onPlay;
  final VoidCallback onSelect;

  const VideoCard({
    super.key,
    required this.item,
    required this.onPlay,
    required this.onSelect,
  });

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  bool _isHovered = false;

  Widget _buildThumbnail() {
    if (widget.item.customThumbnail != null &&
        File(widget.item.customThumbnail!).existsSync()) {
      return Image.file(
        File(widget.item.customThumbnail!),
        fit: BoxFit.cover,
      );
    }

    return Image.asset(
      widget.item.thumbnailPath,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(
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
            const Icon(Icons.movie_filter_rounded, color: Color(0xFFE50914), size: 30),
            const SizedBox(height: 8),
            Text(
              widget.item.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onSelect,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          width: 220,
          margin: const EdgeInsets.only(right: 12),
          transform: Matrix4.diagonal3Values(
            _isHovered ? 1.05 : 1.0,
            _isHovered ? 1.05 : 1.0,
            1.0,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.8),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: const Color(0xFFE50914).withValues(alpha: 0.3),
                      blurRadius: 10,
                    ),
                  ]
                : [],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              children: [
                // Thumbnail Image
                AspectRatio(
                  aspectRatio: 16 / 9.5,
                  child: _buildThumbnail(),
                ),

                // Hover Info Overlay
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
                            Colors.black.withValues(alpha: 0.8),
                            Colors.black.withValues(alpha: 0.95),
                          ],
                          stops: const [0.2, 0.6, 1.0],
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
                                onTap: widget.onPlay,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.play_arrow,
                                    color: Colors.black,
                                    size: 16,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),

                              // Maturity Badge
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
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const Spacer(),

                              // Info Chevron
                              const Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 20),
                            ],
                          ),
                          const SizedBox(height: 6),

                          // Title
                          Text(
                            widget.item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),

                          // Short snippet
                          Text(
                            widget.item.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 10,
                              height: 1.2,
                            ),
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
