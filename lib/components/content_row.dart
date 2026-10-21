import 'package:flutter/material.dart';
import '../models/media_item.dart';
import 'video_card.dart';

class ContentRow extends StatefulWidget {
  final String title;
  final List<MediaItem> items;
  final ValueChanged<MediaItem> onPlay;
  final ValueChanged<MediaItem> onSelect;
  final ValueChanged<MediaItem>? onEdit;

  const ContentRow({
    super.key,
    required this.title,
    required this.items,
    required this.onPlay,
    required this.onSelect,
    this.onEdit,
  });

  @override
  State<ContentRow> createState() => _ContentRowState();
}

class _ContentRowState extends State<ContentRow> {
  final ScrollController _scrollController = ScrollController();
  bool _showLeftChevron = false;
  bool _showRightChevron = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    setState(() {
      _showLeftChevron = _scrollController.offset > 20;
      _showRightChevron = _scrollController.offset <
          (_scrollController.position.maxScrollExtent - 20);
    });
  }

  void _scrollLeft() {
    _scrollController.animateTo(
      _scrollController.offset - 600,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
    );
  }

  void _scrollRight() {
    _scrollController.animateTo(
      _scrollController.offset + 600,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Row Title
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 12),
          child: Text(
            widget.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),
        ),

        // Carousel with Scroll Indicators
        SizedBox(
          height: 265,
          child: Stack(
            children: [
              ListView.builder(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 50),
                itemCount: widget.items.length,
                itemBuilder: (context, index) {
                  final item = widget.items[index];
                  return VideoCard(
                    item: item,
                    onPlay: () => widget.onPlay(item),
                    onSelect: () => widget.onSelect(item),
                    onEdit: widget.onEdit != null ? () => widget.onEdit!(item) : null,
                  );
                },
              ),

              // Left Chevron Indicator
              if (_showLeftChevron)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 45,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withValues(alpha: 0.85),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Center(
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
                        onPressed: _scrollLeft,
                      ),
                    ),
                  ),
                ),

              // Right Chevron Indicator
              if (_showRightChevron)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 45,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.85),
                        ],
                      ),
                    ),
                    child: Center(
                      child: IconButton(
                        icon: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 20),
                        onPressed: _scrollRight,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
