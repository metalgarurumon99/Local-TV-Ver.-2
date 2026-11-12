import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'hover_animated_widget.dart';

class CustomAppTitleBar extends StatefulWidget {
  final String title;
  final bool isTransparent;

  // Optional unified navbar controls (used on BrowseScreen)
  final String? activeCategory;
  final ValueChanged<String>? onCategoryChanged;
  final VoidCallback? onSyncLibrary;
  final bool isScanning;
  final VoidCallback? onBack;
  final String? playingTitle;
  final bool isPlayerMode;

  const CustomAppTitleBar({
    super.key,
    this.title = 'Local TV Ver. 2',
    this.isTransparent = false,
    this.activeCategory,
    this.onCategoryChanged,
    this.onSyncLibrary,
    this.isScanning = false,
    this.onBack,
    this.playingTitle,
    this.isPlayerMode = false,
  });

  @override
  State<CustomAppTitleBar> createState() => _CustomAppTitleBarState();
}

class _CustomAppTitleBarState extends State<CustomAppTitleBar> with WindowListener {
  bool _isMaximized = false;

  bool get _hasNavControls => widget.onCategoryChanged != null;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _checkMaximizedState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _checkMaximizedState() async {
    final max = await windowManager.isMaximized();
    if (mounted) setState(() => _isMaximized = max);
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  Future<void> _toggleMaximize() async {
    if (_isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasBack = widget.onBack != null;
    final bool isPlayerMode = widget.isPlayerMode;
    final double barHeight = (_hasNavControls || hasBack || isPlayerMode) ? 46.0 : 34.0;
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isCompact = screenWidth < 1050;

    return Container(
      height: barHeight,
      decoration: BoxDecoration(
        color: widget.isTransparent ? Colors.transparent : const Color(0xFF121212),
        border: widget.isTransparent
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFF242424), width: 0.8)),
      ),
      child: Row(
        children: [
          if (isPlayerMode) ...[
            // YouTube-style windowed topbar: Brand Logo ONLY (per request #8)
            DragToMoveArea(
              child: GestureDetector(
                onDoubleTap: _toggleMaximize,
                child: Padding(
                  padding: EdgeInsets.only(left: isCompact ? 14 : 20, right: isCompact ? 12 : 16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'LOCAL TV',
                        style: TextStyle(
                          color: Color(0xFFE50914),
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE50914),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text(
                          'v2',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Expanded(
              child: DragToMoveArea(
                child: SizedBox.expand(),
              ),
            ),
          ] else if (hasBack) ...[
            // Back to Home Button
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 6),
              child: HoverAnimatedWidget(
                hoverScale: 1.05,
                onTap: widget.onBack,
                builder: (context, isHovered) => AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: isHovered ? Colors.white.withValues(alpha: 0.16) : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: isHovered ? Colors.white38 : Colors.white12, width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back_rounded, color: isHovered ? Colors.white : Colors.white70, size: 14),
                      const SizedBox(width: 5),
                      Text(
                        'Beranda',
                        style: TextStyle(
                          color: isHovered ? Colors.white : Colors.white70,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Draggable Brand Logo
            DragToMoveArea(
              child: GestureDetector(
                onDoubleTap: _toggleMaximize,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'LOCAL TV',
                        style: TextStyle(
                          color: Color(0xFFE50914),
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE50914),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text(
                          'v2',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            if (widget.playingTitle != null && widget.playingTitle!.isNotEmpty) ...[
              Container(
                width: 1,
                height: 16,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: Colors.white12,
              ),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: screenWidth * 0.40),
                child: Text(
                  widget.playingTitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ] else if (_hasNavControls) ...[
            // 1. Draggable Brand Logo
            DragToMoveArea(
              child: GestureDetector(
                onDoubleTap: _toggleMaximize,
                child: Padding(
                  padding: EdgeInsets.only(left: isCompact ? 14 : 22, right: isCompact ? 12 : 20),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'LOCAL TV',
                        style: TextStyle(
                          color: Color(0xFFE50914),
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE50914),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text(
                          'v2',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 2. Category Tabs (Home & Settings)
            _buildNavTab('all', 'Home'),
            const SizedBox(width: 4),
            _buildNavTab('settings', 'Settings'),
            const SizedBox(width: 6),
            _buildSyncButton(),
          ],

          // Clean Draggable Window Area (Center spacer)
          Expanded(
            child: DragToMoveArea(
              child: GestureDetector(
                onDoubleTap: _toggleMaximize,
                child: Container(
                  color: Colors.transparent,
                ),
              ),
            ),
          ),

          // Right Side: Avatar (when in unified BrowseScreen mode or Player mode)
          if (_hasNavControls || hasBack) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.asset(
                'assets/images/users/1.png',
                width: 24,
                height: 24,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 24,
                  height: 24,
                  color: const Color(0xFFE50914),
                  child: const Icon(Icons.person, color: Colors.white, size: 15),
                ),
              ),
            ),
            Container(
              width: 1,
              height: 16,
              margin: const EdgeInsets.only(left: 12, right: 2),
              color: Colors.white12,
            ),
          ],

          // Window Control Buttons (Minimize, Maximize/Restore, Close)
          _WindowButton(
            height: barHeight,
            icon: Icons.horizontal_rule_rounded,
            iconSize: 14,
            tooltip: 'Minimize',
            onTap: () => windowManager.minimize(),
          ),
          _WindowButton(
            height: barHeight,
            icon: _isMaximized ? Icons.filter_none_rounded : Icons.crop_square_rounded,
            iconSize: 13,
            tooltip: _isMaximized ? 'Restore' : 'Maximize',
            onTap: _toggleMaximize,
          ),
          _WindowButton(
            height: barHeight,
            icon: Icons.close_rounded,
            iconSize: 15,
            isClose: true,
            tooltip: 'Close',
            onTap: () => windowManager.close(),
          ),
        ],
      ),
    );
  }

  Widget _buildNavTab(String id, String label) {
    final bool isActive = widget.activeCategory == id;
    return HoverAnimatedWidget(
      hoverScale: 1.07,
      onTap: () => widget.onCategoryChanged?.call(id),
      builder: (context, isHovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.white.withValues(alpha: 0.14)
              : isHovered
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive || isHovered ? Colors.white : Colors.white60,
            fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }

  Widget _buildSyncButton() {
    return HoverAnimatedWidget(
      hoverScale: 1.08,
      onTap: widget.isScanning ? null : widget.onSyncLibrary,
      builder: (context, isHovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isHovered
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isHovered ? Colors.white24 : Colors.transparent,
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            widget.isScanning
                ? const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: Color(0xFFE50914),
                    ),
                  )
                : Icon(
                    Icons.sync_rounded,
                    color: isHovered ? Colors.white : Colors.white70,
                    size: 15,
                  ),
            const SizedBox(width: 5),
            Text(
              widget.isScanning ? 'Syncing...' : 'Sync',
              style: TextStyle(
                color: isHovered ? Colors.white : Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  final double height;
  final IconData icon;
  final double iconSize;
  final bool isClose;
  final String tooltip;
  final VoidCallback onTap;

  const _WindowButton({
    required this.height,
    required this.icon,
    required this.iconSize,
    this.isClose = false,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    Color bgColor = Colors.transparent;
    Color iconColor = Colors.white70;

    if (_isHovered) {
      if (widget.isClose) {
        bgColor = const Color(0xFFE50914);
        iconColor = Colors.white;
      } else {
        bgColor = Colors.white.withValues(alpha: 0.12);
        iconColor = Colors.white;
      }
    }

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 44,
            height: widget.height,
            color: bgColor,
            child: Center(
              child: Icon(
                widget.icon,
                size: widget.iconSize,
                color: iconColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
