import 'dart:async';
import 'package:flutter/material.dart';
import '../components/hover_animated_widget.dart';
import '../components/video_card.dart';
import '../models/media_item.dart';
import '../services/library_service.dart';
import '../services/preview_player_service.dart';

enum BrowseMediaTypeFilter { all, series, films }

enum BrowseSortOption {
  titleAsc('Judul (A–Z)'),
  titleDesc('Judul (Z–A)'),
  ratingDesc('Rating Tertinggi'),
  yearDesc('Tahun Terbaru'),
  episodesDesc('Episode Terbanyak');

  final String label;
  const BrowseSortOption(this.label);
}

/// Dedicated "Browse" view with multi-criteria filtering, sorting, animated controls, and virtualized grid.
class CatalogBrowseView extends StatefulWidget {
  final List<MediaItem> items;
  final List<String> connectedFolders;
  final ValueChanged<MediaItem> onPlay;
  final ValueChanged<MediaItem> onSelect;
  final ValueChanged<MediaItem> onEdit;

  const CatalogBrowseView({
    super.key,
    required this.items,
    required this.connectedFolders,
    required this.onPlay,
    required this.onSelect,
    required this.onEdit,
  });

  @override
  State<CatalogBrowseView> createState() => _CatalogBrowseViewState();
}

class _CatalogBrowseViewState extends State<CatalogBrowseView> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  BrowseMediaTypeFilter _typeFilter = BrowseMediaTypeFilter.all;
  String _selectedGenre = 'Semua Genre';
  String _selectedYear = 'Semua Tahun';
  bool _onlyOnline = false;
  BrowseSortOption _sortOption = BrowseSortOption.titleAsc;
  String _searchQuery = '';

  List<String> _availableGenres = const ['Semua Genre'];
  List<String> _availableYears = const ['Semua Tahun'];
  List<MediaItem> _filteredItems = const [];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _recomputeMetadataOptions();
    _recomputeFiltered();
  }

  @override
  void didUpdateWidget(covariant CatalogBrowseView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items || oldWidget.connectedFolders != widget.connectedFolders) {
      _recomputeMetadataOptions();
      _recomputeFiltered();
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    VideoCard.closeActivePopover();
    PreviewPlayerService.instance.notifyScrollActivity();
  }

  void _recomputeMetadataOptions() {
    final Set<String> genres = {};
    final Set<String> years = {};

    for (final item in widget.items) {
      if (item.genre.isNotEmpty) {
        for (final g in item.genre.split(',')) {
          final clean = g.trim();
          if (clean.isNotEmpty && clean.toLowerCase() != 'koleksi lokal') {
            genres.add(clean);
          }
        }
      }
      final y = item.year?.trim();
      if (y != null && y.length == 4 && int.tryParse(y) != null) {
        years.add(y);
      }
    }

    final sortedGenres = genres.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final sortedYears = years.toList()..sort((a, b) => b.compareTo(a));

    _availableGenres = ['Semua Genre', ...sortedGenres];
    _availableYears = ['Semua Tahun', ...sortedYears];

    if (!_availableGenres.contains(_selectedGenre)) _selectedGenre = 'Semua Genre';
    if (!_availableYears.contains(_selectedYear)) _selectedYear = 'Semua Tahun';
  }

  void _recomputeFiltered() {
    final q = _searchQuery.trim().toLowerCase();
    final List<MediaItem> list = [];

    for (final item in widget.items) {
      if (_typeFilter == BrowseMediaTypeFilter.series && !item.isSeries) continue;
      if (_typeFilter == BrowseMediaTypeFilter.films && item.isSeries) continue;

      if (_selectedGenre != 'Semua Genre') {
        final itemGenres = item.genre.split(',').map((g) => g.trim().toLowerCase());
        if (!itemGenres.contains(_selectedGenre.toLowerCase())) continue;
      }

      if (_selectedYear != 'Semua Tahun' && item.year?.trim() != _selectedYear) {
        continue;
      }

      if (_onlyOnline &&
          !LocalLibraryService.isMediaItemConnected(item, connectedFolders: widget.connectedFolders)) {
        continue;
      }

      if (q.isNotEmpty && !item.matchesSearchQuery(q)) {
        continue;
      }

      list.add(item);
    }

    double parseRating(MediaItem it) => double.tryParse(it.rating ?? '') ?? -1.0;
    int parseYear(MediaItem it) => int.tryParse(it.year ?? '') ?? 0;

    list.sort((a, b) {
      switch (_sortOption) {
        case BrowseSortOption.titleAsc:
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case BrowseSortOption.titleDesc:
          return b.title.toLowerCase().compareTo(a.title.toLowerCase());
        case BrowseSortOption.ratingDesc:
          final cmp = parseRating(b).compareTo(parseRating(a));
          return cmp != 0 ? cmp : a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case BrowseSortOption.yearDesc:
          final cmp = parseYear(b).compareTo(parseYear(a));
          return cmp != 0 ? cmp : a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case BrowseSortOption.episodesDesc:
          final cmp = b.episodes.length.compareTo(a.episodes.length);
          return cmp != 0 ? cmp : a.title.toLowerCase().compareTo(b.title.toLowerCase());
      }
    });

    _filteredItems = list;
  }

  bool get _hasActiveFilters =>
      _typeFilter != BrowseMediaTypeFilter.all ||
      _selectedGenre != 'Semua Genre' ||
      _selectedYear != 'Semua Tahun' ||
      _onlyOnline ||
      _sortOption != BrowseSortOption.titleAsc ||
      _searchQuery.trim().isNotEmpty;

  void _resetFilters() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _typeFilter = BrowseMediaTypeFilter.all;
      _selectedGenre = 'Semua Genre';
      _selectedYear = 'Semua Tahun';
      _onlyOnline = false;
      _sortOption = BrowseSortOption.titleAsc;
      _searchQuery = '';
      _recomputeFiltered();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF111111),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sleek, Compact Top Header & Filter Toolbar
          Container(
            padding: const EdgeInsets.fromLTRB(40, 18, 40, 16),
            decoration: const BoxDecoration(
              color: Color(0xFF141414),
              border: Border(bottom: BorderSide(color: Color(0xFF222222), width: 1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Row 1: Title + Count + Inline Search
                Row(
                  children: [
                    const Text(
                      'Jelajahi Pustaka',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Text(
                        '${_filteredItems.length} / ${widget.items.length} judul',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 280,
                      height: 36,
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        cursorColor: const Color(0xFFE50914),
                        decoration: InputDecoration(
                          hintText: 'Filter judul, genre, tahun...',
                          hintStyle: const TextStyle(color: Colors.white38, fontSize: 12.5),
                          prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54, size: 18),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? HoverAnimatedWidget(
                                  hoverScale: 1.12,
                                  onTap: () {
                                    _searchDebounce?.cancel();
                                    _searchController.clear();
                                    setState(() {
                                      _searchQuery = '';
                                      _recomputeFiltered();
                                    });
                                  },
                                  builder: (_, hovered) => Icon(
                                    Icons.close_rounded,
                                    color: hovered ? Colors.white : Colors.white54,
                                    size: 16,
                                  ),
                                )
                              : null,
                          filled: true,
                          fillColor: Colors.black38,
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.white12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.white12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFFE50914)),
                          ),
                        ),
                        onChanged: (val) {
                          _searchDebounce?.cancel();
                          _searchDebounce = Timer(const Duration(milliseconds: 150), () {
                            if (!mounted) return;
                            setState(() {
                              _searchQuery = val;
                              _recomputeFiltered();
                            });
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Row 2: Compact Segmented Type Control + Styled Dropdowns + Online Toggle + Reset
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Compact Segmented Pill Group (Semua | Serial TV | Film)
                    Container(
                      height: 36,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildSegmentedItem('Semua', BrowseMediaTypeFilter.all),
                          const SizedBox(width: 2),
                          _buildSegmentedItem('Serial TV', BrowseMediaTypeFilter.series),
                          const SizedBox(width: 2),
                          _buildSegmentedItem('Film', BrowseMediaTypeFilter.films),
                        ],
                      ),
                    ),

                    // Subtle vertical separator
                    Container(width: 1, height: 20, color: Colors.white12),

                    // Styled Animated Genre Dropdown
                    _AnimatedFilterDropdown<String>(
                      icon: Icons.category_rounded,
                      value: _selectedGenre,
                      isHighlighted: _selectedGenre != 'Semua Genre',
                      options: _availableGenres,
                      labelBuilder: (g) => g,
                      onSelected: (val) {
                        setState(() {
                          _selectedGenre = val;
                          _recomputeFiltered();
                        });
                      },
                    ),

                    // Styled Animated Year Dropdown
                    _AnimatedFilterDropdown<String>(
                      icon: Icons.calendar_today_rounded,
                      value: _selectedYear,
                      isHighlighted: _selectedYear != 'Semua Tahun',
                      options: _availableYears,
                      labelBuilder: (y) => y,
                      onSelected: (val) {
                        setState(() {
                          _selectedYear = val;
                          _recomputeFiltered();
                        });
                      },
                    ),

                    // Styled Animated Sort Dropdown
                    _AnimatedFilterDropdown<BrowseSortOption>(
                      icon: Icons.sort_rounded,
                      value: _sortOption,
                      isHighlighted: _sortOption != BrowseSortOption.titleAsc,
                      options: BrowseSortOption.values,
                      labelBuilder: (opt) => opt.label,
                      onSelected: (val) {
                        setState(() {
                          _sortOption = val;
                          _recomputeFiltered();
                        });
                      },
                    ),

                    // Animated Online-Only Toggle Pill
                    HoverAnimatedWidget(
                      hoverScale: 1.03,
                      onTap: () {
                        setState(() {
                          _onlyOnline = !_onlyOnline;
                          _recomputeFiltered();
                        });
                      },
                      builder: (_, isHovered) => AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 13),
                        decoration: BoxDecoration(
                          color: _onlyOnline
                              ? Colors.greenAccent.withValues(alpha: isHovered ? 0.22 : 0.14)
                              : Colors.white.withValues(alpha: isHovered ? 0.12 : 0.06),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _onlyOnline
                                ? Colors.greenAccent.withValues(alpha: 0.6)
                                : (isHovered ? Colors.white30 : Colors.white12),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _onlyOnline ? Icons.check_circle_rounded : Icons.cloud_done_outlined,
                              size: 15,
                              color: _onlyOnline
                                  ? Colors.greenAccent
                                  : (isHovered ? Colors.white : Colors.white60),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              'Hanya Online',
                              style: TextStyle(
                                color: _onlyOnline
                                    ? Colors.greenAccent
                                    : (isHovered ? Colors.white : Colors.white70),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Animated Reset Pill
                    if (_hasActiveFilters)
                      HoverAnimatedWidget(
                        hoverScale: 1.04,
                        onTap: _resetFilters,
                        builder: (_, isHovered) => AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE50914).withValues(alpha: isHovered ? 0.22 : 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFFE50914).withValues(alpha: isHovered ? 0.8 : 0.4),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.restart_alt_rounded, size: 16, color: Color(0xFFFF4D55)),
                              SizedBox(width: 5),
                              Text(
                                'Reset',
                                style: TextStyle(
                                  color: Color(0xFFFF4D55),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Virtualized Responsive Grid (fixed mainAxisExtent so titles/metadata never clip)
          Expanded(
            child: _filteredItems.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.filter_list_off_rounded, color: Colors.white24, size: 54),
                        const SizedBox(height: 12),
                        const Text(
                          'Tidak ada tontonan yang cocok dengan filter ini.',
                          style: TextStyle(color: Colors.white60, fontSize: 14),
                        ),
                        if (_hasActiveFilters) ...[
                          const SizedBox(height: 14),
                          HoverAnimatedWidget(
                            hoverScale: 1.04,
                            onTap: _resetFilters,
                            builder: (_, isHovered) => AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: isHovered ? const Color(0xFFE50914) : Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isHovered ? const Color(0xFFE50914) : Colors.white24,
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.restart_alt_rounded, size: 16, color: Colors.white),
                                  SizedBox(width: 6),
                                  Text(
                                    'Reset Filter',
                                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  )
                : GridView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(40, 24, 40, 60),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 268,
                      mainAxisExtent: 198,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 18,
                    ),
                    itemCount: _filteredItems.length,
                    itemBuilder: (context, index) {
                      final item = _filteredItems[index];
                      final isConnected = LocalLibraryService.isMediaItemConnected(
                        item,
                        connectedFolders: widget.connectedFolders,
                      );
                      return RepaintBoundary(
                        child: VideoCard(
                          key: ValueKey<String>('browse-grid-${item.id}'),
                          item: item,
                          isConnected: isConnected,
                          onPlay: () => widget.onPlay(item),
                          onSelect: () => widget.onSelect(item),
                          onEdit: () => widget.onEdit(item),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentedItem(String label, BrowseMediaTypeFilter filter) {
    final bool selected = _typeFilter == filter;
    return HoverAnimatedWidget(
      hoverScale: 1.03,
      onTap: () {
        if (_typeFilter == filter) return;
        setState(() {
          _typeFilter = filter;
          _recomputeFiltered();
        });
      },
      builder: (_, isHovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFE50914)
              : (isHovered ? Colors.white.withValues(alpha: 0.10) : Colors.transparent),
          borderRadius: BorderRadius.circular(6),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: const Color(0xFFE50914).withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : (isHovered ? Colors.white : Colors.white70),
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// Ultra-lightweight, 120fps animated dropdown using OverlayPortal (no heavy Navigator ModalRoute).
class _AnimatedFilterDropdown<T> extends StatefulWidget {
  final IconData icon;
  final T value;
  final bool isHighlighted;
  final List<T> options;
  final String Function(T) labelBuilder;
  final ValueChanged<T> onSelected;

  const _AnimatedFilterDropdown({
    required this.icon,
    required this.value,
    required this.isHighlighted,
    required this.options,
    required this.labelBuilder,
    required this.onSelected,
  });

  @override
  State<_AnimatedFilterDropdown<T>> createState() => _AnimatedFilterDropdownState<T>();
}

class _AnimatedFilterDropdownState<T> extends State<_AnimatedFilterDropdown<T>>
    with SingleTickerProviderStateMixin {
  final OverlayPortalController _overlayController = OverlayPortalController();
  final LayerLink _layerLink = LayerLink();
  final Object _tapRegionGroupId = Object();
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;

  bool _isHovered = false;
  bool _isPressed = false;
  bool _isOpen = false;
  int _hoveredOptionIndex = -1;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 110),
      reverseDuration: const Duration(milliseconds: 85),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic);
    _scaleAnim = Tween<double>(begin: 0.96, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _openMenu() {
    if (_isOpen) return;
    setState(() {
      _isOpen = true;
      _hoveredOptionIndex = -1;
    });
    _overlayController.show();
    _animController.forward(from: 0.0);
  }

  Future<void> _closeMenu() async {
    if (!_isOpen) return;
    setState(() => _isOpen = false);
    await _animController.reverse();
    if (mounted && !_isOpen && _overlayController.isShowing) {
      _overlayController.hide();
    }
  }

  void _toggleMenu() {
    if (_isOpen) {
      _closeMenu();
    } else {
      _openMenu();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool active = widget.isHighlighted || _isOpen;
    final double scale = _isPressed ? 0.96 : (_isHovered ? 1.03 : 1.0);

    return TapRegion(
      groupId: _tapRegionGroupId,
      onTapOutside: (_) {
        if (_isOpen) _closeMenu();
      },
      child: CompositedTransformTarget(
        link: _layerLink,
        child: OverlayPortal(
          controller: _overlayController,
          overlayChildBuilder: (ctx) {
            return CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: const Offset(0, 42),
              child: Align(
                alignment: Alignment.topLeft,
                child: TapRegion(
                  groupId: _tapRegionGroupId,
                  child: RepaintBoundary(
                    child: FadeTransition(
                      opacity: _fadeAnim,
                      child: ScaleTransition(
                        scale: _scaleAnim,
                        alignment: Alignment.topLeft,
                        child: Material(
                          color: Colors.transparent,
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 195, maxWidth: 255, maxHeight: 330),
                            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFA191919),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.14), width: 1),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.65),
                                  blurRadius: 16,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ListView.builder(
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              itemCount: widget.options.length,
                              itemBuilder: (_, idx) {
                                final opt = widget.options[idx];
                                final bool isSelected = opt == widget.value;
                                final bool isItemHovered = _hoveredOptionIndex == idx;

                                return MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  onEnter: (_) {
                                    if (_hoveredOptionIndex != idx) {
                                      setState(() => _hoveredOptionIndex = idx);
                                    }
                                  },
                                  onExit: (_) {
                                    if (_hoveredOptionIndex == idx) {
                                      setState(() => _hoveredOptionIndex = -1);
                                    }
                                  },
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      widget.onSelected(opt);
                                      _closeMenu();
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      margin: const EdgeInsets.symmetric(vertical: 1),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? const Color(0xFFE50914).withValues(alpha: 0.20)
                                            : (isItemHovered ? Colors.white.withValues(alpha: 0.08) : Colors.transparent),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.check_rounded,
                                            size: 15,
                                            color: isSelected ? const Color(0xFFE50914) : Colors.transparent,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              widget.labelBuilder(opt),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: isSelected || isItemHovered ? Colors.white : Colors.white70,
                                                fontSize: 12.5,
                                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() {
              _isHovered = false;
              _isPressed = false;
            }),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => setState(() => _isPressed = true),
              onTapUp: (_) => setState(() => _isPressed = false),
              onTapCancel: () => setState(() => _isPressed = false),
              onTap: _toggleMenu,
              child: AnimatedScale(
                scale: scale,
                duration: _isPressed ? const Duration(milliseconds: 70) : const Duration(milliseconds: 120),
                curve: Curves.easeOutCubic,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFFE50914).withValues(alpha: _isHovered ? 0.22 : 0.14)
                        : Colors.white.withValues(alpha: _isHovered ? 0.12 : 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: active
                          ? const Color(0xFFE50914).withValues(alpha: 0.7)
                          : (_isHovered ? Colors.white30 : Colors.white12),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.icon,
                        size: 15,
                        color: active
                            ? const Color(0xFFFF4D55)
                            : (_isHovered ? Colors.white : Colors.white60),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        widget.labelBuilder(widget.value),
                        style: TextStyle(
                          color: active || _isHovered ? Colors.white : Colors.white70,
                          fontSize: 12.5,
                          fontWeight: active ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 6),
                      AnimatedRotation(
                        turns: _isOpen ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 130),
                        curve: Curves.easeOutCubic,
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: active || _isHovered ? Colors.white : Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
