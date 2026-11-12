import 'package:flutter/material.dart';
import '../models/media_item.dart';
import '../services/library_service.dart';
import '../services/preview_player_service.dart';
import 'video_card.dart';

class ContentRow extends StatefulWidget {
  final String title;
  final List<MediaItem> items;
  final ValueChanged<MediaItem> onPlay;
  final ValueChanged<MediaItem> onSelect;
  final ValueChanged<MediaItem>? onEdit;
  final List<String> connectedFolders;

  const ContentRow({
    super.key,
    required this.title,
    required this.items,
    required this.onPlay,
    required this.onSelect,
    this.onEdit,
    this.connectedFolders = const [],
  });

  @override
  State<ContentRow> createState() => _ContentRowState();
}

class _ContentRowState extends State<ContentRow> {
  static final Map<String, double> _savedRowOffsets = {};

  late final ScrollController _scrollController;
  late final ValueNotifier<bool> _showLeftNotifier;
  late final ValueNotifier<bool> _showRightNotifier;

  @override
  void initState() {
    super.initState();
    final savedOffset = _savedRowOffsets[widget.title] ?? 0.0;
    _scrollController = ScrollController(initialScrollOffset: savedOffset);
    _showLeftNotifier = ValueNotifier<bool>(savedOffset > 10.0);
    _showRightNotifier = ValueNotifier<bool>(false);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollButtons());
  }

  @override
  void didUpdateWidget(covariant ContentRow oldWidget) {
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
    _savedRowOffsets[widget.title] = _scrollController.offset;
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
    final target = (_scrollController.offset - 882.0).clamp(
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
    final target = (_scrollController.offset + 882.0).clamp(
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
          // Row Title (Netflix style)
          Padding(
            padding: const EdgeInsets.fromLTRB(50, 10, 50, 8),
            child: Text(
              widget.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),

          // 16:9 Landscape Backdrop Carousel (280x158 cards + 14px spacing = 294.0 itemExtent, with logo in bottom-left and title & year below)
          SizedBox(
            height: 214,
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
                    itemExtent: 294.0, // 280px card + 14px right padding
                    addAutomaticKeepAlives: false,
                    itemCount: widget.items.length,
                    itemBuilder: (context, index) {
                      final item = widget.items[index];
                      final isConnected = LocalLibraryService.isMediaItemConnected(
                        item,
                        connectedFolders: widget.connectedFolders,
                      );
                      return RepaintBoundary(
                        child: VideoCard(
                          key: ValueKey<String>(item.id),
                          item: item,
                          isConnected: isConnected,
                          onPlay: () => widget.onPlay(item),
                          onSelect: () => widget.onSelect(item),
                          onEdit: widget.onEdit != null ? () => widget.onEdit!(item) : null,
                        ),
                      );
                    },
                  ),
                ),

                // Left Arrow Button (centered vertically over the 158px backdrop card)
                ValueListenableBuilder<bool>(
                  valueListenable: _showLeftNotifier,
                  builder: (context, showLeft, _) {
                    if (!showLeft) return const SizedBox.shrink();
                    return Positioned(
                      left: 0,
                      top: 4,
                      height: 158,
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

                // Right Arrow Button (centered vertically over the 158px backdrop card)
                ValueListenableBuilder<bool>(
                  valueListenable: _showRightNotifier,
                  builder: (context, showRight, _) {
                    if (!showRight) return const SizedBox.shrink();
                    return Positioned(
                      right: 0,
                      top: 4,
                      height: 158,
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
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

