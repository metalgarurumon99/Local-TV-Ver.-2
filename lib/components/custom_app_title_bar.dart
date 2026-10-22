import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class CustomAppTitleBar extends StatefulWidget {
  final String title;
  final bool isTransparent;

  const CustomAppTitleBar({
    super.key,
    this.title = 'Local TV Ver. 2',
    this.isTransparent = false,
  });

  @override
  State<CustomAppTitleBar> createState() => _CustomAppTitleBarState();
}

class _CustomAppTitleBarState extends State<CustomAppTitleBar> with WindowListener {
  bool _isMaximized = false;

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
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: widget.isTransparent ? Colors.transparent : const Color(0xFF121212),
        border: widget.isTransparent
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFF222222), width: 0.8)),
      ),
      child: Row(
        children: [
          // App Icon / Logo Badge
          Padding(
            padding: const EdgeInsets.only(left: 14, right: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE50914),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text(
                    'LOCAL TV',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // Center Draggable Window Area
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

          // Window Control Buttons (Minimize, Maximize/Restore, Close)
          _WindowButton(
            icon: Icons.horizontal_rule_rounded,
            iconSize: 14,
            tooltip: 'Minimize',
            onTap: () => windowManager.minimize(),
          ),
          _WindowButton(
            icon: _isMaximized ? Icons.filter_none_rounded : Icons.crop_square_rounded,
            iconSize: 13,
            tooltip: _isMaximized ? 'Restore' : 'Maximize',
            onTap: _toggleMaximize,
          ),
          _WindowButton(
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
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final double iconSize;
  final bool isClose;
  final String tooltip;
  final VoidCallback onTap;

  const _WindowButton({
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
            height: 34,
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
