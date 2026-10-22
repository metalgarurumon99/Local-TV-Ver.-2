import 'dart:io';
import 'package:flutter/material.dart';
import '../services/watch_history_service.dart';

class ContinueWatchingRow extends StatelessWidget {
  final List<WatchHistoryEntry> items;
  final ValueChanged<WatchHistoryEntry> onResume;
  final ValueChanged<WatchHistoryEntry> onRemove;

  const ContinueWatchingRow({
    super.key,
    required this.items,
    required this.onResume,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 50, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.history_rounded, color: Color(0xFFE50914), size: 22),
              SizedBox(width: 8),
              Text(
                'Lanjutkan Menonton',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 50),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final entry = items[index];
              return RepaintBoundary(
                child: _ContinueWatchingCard(
                  entry: entry,
                  onResume: () => onResume(entry),
                  onRemove: () => onRemove(entry),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ContinueWatchingCard extends StatefulWidget {
  final WatchHistoryEntry entry;
  final VoidCallback onResume;
  final VoidCallback onRemove;

  const _ContinueWatchingCard({
    required this.entry,
    required this.onResume,
    required this.onRemove,
  });

  @override
  State<_ContinueWatchingCard> createState() => _ContinueWatchingCardState();
}

class _ContinueWatchingCardState extends State<_ContinueWatchingCard> {
  bool _isHovered = false;

  Widget _buildThumbnail() {
    final path = widget.entry.thumbnailPath;
    if (path.isNotEmpty) {
      if (path.startsWith('http://') || path.startsWith('https://')) {
        return Image.network(
          path,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          cacheWidth: 320,
          errorBuilder: (_, _, _) => _fallbackThumbnail(),
        );
      }
      final file = File(path);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          cacheWidth: 320,
          errorBuilder: (_, _, _) => _fallbackThumbnail(),
        );
      }
    }
    return _fallbackThumbnail();
  }

  Widget _fallbackThumbnail() {
    return Container(
      color: const Color(0xFF222222),
      child: const Center(
        child: Icon(Icons.movie_filter_rounded, size: 36, color: Colors.white24),
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
        onTap: widget.onResume,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          width: 220,
          margin: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF181818),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isHovered ? const Color(0xFFE50914) : Colors.white12,
              width: _isHovered ? 1.5 : 1.0,
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: const Color(0xFFE50914).withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail 16:9 with Play Overlay and Progress Bar
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildThumbnail(),

                      // Dark subtle gradient overlay
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.7),
                            ],
                          ),
                        ),
                      ),

                      // Hover Play Button
                      Center(
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 180),
                          opacity: _isHovered ? 1.0 : 0.0,
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFE50914).withValues(alpha: 0.9),
                            ),
                            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                          ),
                        ),
                      ),

                      // Remove from history button
                      if (_isHovered)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Tooltip(
                            message: 'Hapus dari riwayat',
                            child: GestureDetector(
                              onTap: widget.onRemove,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.8),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close_rounded, color: Colors.white70, size: 14),
                              ),
                            ),
                          ),
                        ),

                      // Netflix-Style Red Progress Bar Line
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 4,
                          color: Colors.white24,
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: widget.entry.progress,
                            child: Container(
                              color: const Color(0xFFE50914),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Title and Remaining Info
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.entry.mediaTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              widget.entry.isSeries && widget.entry.episodeTitle != null
                                  ? widget.entry.episodeTitle!
                                  : (widget.entry.isSeries ? 'Episode ${widget.entry.episodeNumber ?? 1}' : 'Film'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white60, fontSize: 11),
                            ),
                          ),
                          Text(
                            widget.entry.formattedRemainingTime,
                            style: const TextStyle(
                              color: Color(0xFFE50914),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
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
