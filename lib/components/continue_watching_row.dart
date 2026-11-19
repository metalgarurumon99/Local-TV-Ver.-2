import 'dart:io';
import 'package:flutter/material.dart';
import '../services/library_service.dart';
import '../services/preview_player_service.dart';
import '../services/thumbnail_service.dart';
import '../services/watch_history_service.dart';
import '../utils/media_ui_helpers.dart';
import 'video_card.dart';

class ContinueWatchingRow extends StatefulWidget {
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
  State<ContinueWatchingRow> createState() => _ContinueWatchingRowState();
}

class _ContinueWatchingRowState extends State<ContinueWatchingRow> {
  static double _savedOffset = 0.0;

  late final ScrollController _scrollController;
  late final ValueNotifier<bool> _showLeftNotifier;
  late final ValueNotifier<bool> _showRightNotifier;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(initialScrollOffset: _savedOffset);
    _showLeftNotifier = ValueNotifier<bool>(_savedOffset > 10.0);
    _showRightNotifier = ValueNotifier<bool>(false);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollButtons());
  }

  @override
  void didUpdateWidget(covariant ContinueWatchingRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollButtons());
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _showLeftNotifier.dispose();
    _showRightNotifier.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    _savedOffset = _scrollController.offset;
    VideoCard.closeActivePopover();
    PreviewPlayerService.instance.notifyScrollActivity();
    _updateScrollButtons();
  }

  void _updateScrollButtons() {
    if (!mounted || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (!position.haveDimensions) return;
    final offset = position.pixels;
    final maxExt = position.maxScrollExtent;
    final showLeft = offset > 10.0;
    final showRight = maxExt > 10.0 && offset < (maxExt - 10.0);
    if (_showLeftNotifier.value != showLeft) _showLeftNotifier.value = showLeft;
    if (_showRightNotifier.value != showRight) _showRightNotifier.value = showRight;
  }

  void _scrollLeft() {
    if (!_scrollController.hasClients) return;
    final target = (_scrollController.offset - 762.0).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollRight() {
    if (!_scrollController.hasClients) return;
    final target = (_scrollController.offset + 762.0).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    return RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(50, 10, 50, 8),
            child: Text(
              'Lanjutkan Menonton',
              style: TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
          SizedBox(
            height: 195,
            child: Stack(
              children: [
                NotificationListener<ScrollMetricsNotification>(
                  onNotification: (notification) {
                    _updateScrollButtons();
                    return false;
                  },
                  child: ListView.builder(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 50),
                    itemExtent: 254.0, // 240px card + 14px right padding
                    addAutomaticKeepAlives: false,
                    itemCount: widget.items.length,
                    itemBuilder: (context, index) {
                      final entry = widget.items[index];
                      return RepaintBoundary(
                        child: _ContinueWatchingCard(
                          key: ValueKey<String>('cw-${entry.mediaId}-${entry.videoPath}'),
                          entry: entry,
                          onResume: () => widget.onResume(entry),
                          onRemove: () => widget.onRemove(entry),
                        ),
                      );
                    },
                  ),
                ),

                // Left Arrow Button (only when scrollable and scrolled right)
                ValueListenableBuilder<bool>(
                  valueListenable: _showLeftNotifier,
                  builder: (context, showLeft, _) {
                    if (!showLeft) return const SizedBox.shrink();
                    return Positioned(
                      left: 0,
                      top: 4,
                      bottom: 13,
                      width: 46,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color(0xE6000000),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: Center(
                          child: IconButton(
                            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                            onPressed: _scrollLeft,
                          ),
                        ),
                      ),
                    );
                  },
                ),

                // Right Arrow Button (only when items exceed 1 screen width and more items to the right)
                ValueListenableBuilder<bool>(
                  valueListenable: _showRightNotifier,
                  builder: (context, showRight, _) {
                    if (!showRight) return const SizedBox.shrink();
                    return Positioned(
                      right: 0,
                      top: 4,
                      bottom: 13,
                      width: 46,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              Color(0xE6000000),
                            ],
                          ),
                        ),
                        child: Center(
                          child: IconButton(
                            icon: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 20),
                            onPressed: _scrollRight,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContinueWatchingCard extends StatefulWidget {
  final WatchHistoryEntry entry;
  final VoidCallback onResume;
  final VoidCallback onRemove;

  const _ContinueWatchingCard({
    super.key,
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
    if (LocalThumbnailService.hasThumbnail(widget.entry.videoPath)) {
      final thumbPath = LocalThumbnailService.getThumbnailPath(widget.entry.videoPath);
      return Image.file(
        File(thumbPath),
        fit: BoxFit.cover,
        alignment: Alignment.center,
        cacheWidth: 360,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
        errorBuilder: (_, _, _) => _buildPosterOrFallback(),
      );
    }
    return _buildPosterOrFallback();
  }

  Widget _buildPosterOrFallback() {
    final path = widget.entry.thumbnailPath;
    if (path.isNotEmpty) {
      if (path.startsWith('http://') || path.startsWith('https://')) {
        return Image.network(
          path,
          fit: BoxFit.cover,
          alignment: const Alignment(0.0, -0.3),
          width: double.infinity,
          height: double.infinity,
          cacheWidth: 360,
          gaplessPlayback: true,
          filterQuality: FilterQuality.low,
          errorBuilder: (_, _, _) => _fallbackThumbnail(),
        );
      }
      if (LocalThumbnailService.fileExistsCached(path)) {
        return Image.file(
          File(path),
          fit: BoxFit.cover,
          alignment: const Alignment(0.0, -0.3),
          width: double.infinity,
          height: double.infinity,
          cacheWidth: 360,
          gaplessPlayback: true,
          filterQuality: FilterQuality.low,
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

  String _buildContinueWatchingSubtitle() {
    final rem = widget.entry.formattedRemainingTime;
    final remainingText = rem.isEmpty ? 'Selesai' : rem;

    if (widget.entry.isSeries && widget.entry.episodeNumber != null) {
      return 'Episode ${widget.entry.episodeNumber} • $remainingText';
    } else if (widget.entry.isSeries && widget.entry.episodeTitle != null && widget.entry.episodeTitle!.isNotEmpty) {
      return '${widget.entry.episodeTitle} • $remainingText';
    } else {
      return remainingText;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = LocalLibraryService.isItemFileAccessible(widget.entry.videoPath);
    return Padding(
      padding: const EdgeInsets.only(right: 14, top: 4),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            if (!isConnected) {
              MediaUiHelpers.showDisconnectedStorageSnackBar(context, widget.entry.mediaTitle);
              return;
            }
            widget.onResume();
          },
          child: SizedBox(
            width: 240,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. 16:9 Landscape Card (240 x 135)
                Container(
                  width: 240,
                  height: 135,
                  decoration: BoxDecoration(
                    color: const Color(0xFF181818),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black45,
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildThumbnail(),

                        if (!isConnected)
                          Container(color: Colors.black45),

                        if (!isConnected)
                          Positioned(
                            top: 6,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xDD000000),
                                borderRadius: BorderRadius.circular(3),
                                border: Border.all(color: const Color(0xFFE50914), width: 0.8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.cloud_off_rounded, color: Color(0xFFE50914), size: 10),
                                  SizedBox(width: 3),
                                  Text(
                                    'Terputus',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // Hover Play Button
                        if (_isHovered)
                          Center(
                            child: DecoratedBox(
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xCC181818),
                              ),
                              child: SizedBox(
                                width: 46,
                                height: 46,
                                child: Icon(
                                  isConnected ? Icons.play_arrow_rounded : Icons.cloud_off_rounded,
                                  color: isConnected ? Colors.white : const Color(0xFFE50914),
                                  size: 30,
                                ),
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
                                  decoration: const BoxDecoration(
                                    color: Color(0xCC000000),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close_rounded, color: Colors.white70, size: 14),
                                ),
                              ),
                            ),
                          ),

                        // Red progress bar at the very bottom of the card image
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 3.5,
                          child: ColoredBox(
                            color: Colors.white24,
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: widget.entry.progress.clamp(0.02, 1.0),
                              child: const ColoredBox(
                                color: Color(0xFFE50914),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // 2. Title Below Card
                Text(
                  widget.entry.mediaTitle,
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

                // 3. Episode & Remaining Time Below Title
                Text(
                  _buildContinueWatchingSubtitle(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
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
