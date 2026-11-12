import 'package:flutter/material.dart';

/// Reusable interactive hover wrapper that brings menus, options, and buttons to life
/// with smooth scale and state-aware builder animations when the cursor enters/exits.
class HoverAnimatedWidget extends StatefulWidget {
  final Widget Function(BuildContext context, bool isHovered) builder;
  final double hoverScale;
  final Duration duration;
  final Curve curve;
  final VoidCallback? onTap;
  final MouseCursor cursor;

  const HoverAnimatedWidget({
    super.key,
    required this.builder,
    this.hoverScale = 1.04,
    this.duration = const Duration(milliseconds: 160),
    this.curve = Curves.easeOutCubic,
    this.onTap,
    this.cursor = SystemMouseCursors.click,
  });

  @override
  State<HoverAnimatedWidget> createState() => _HoverAnimatedWidgetState();
}

class _HoverAnimatedWidgetState extends State<HoverAnimatedWidget> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    Widget content = AnimatedScale(
      scale: _isHovered ? widget.hoverScale : 1.0,
      duration: widget.duration,
      curve: widget.curve,
      child: widget.builder(context, _isHovered),
    );

    if (widget.onTap != null) {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: content,
      );
    }

    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) {
        if (!_isHovered) setState(() => _isHovered = true);
      },
      onExit: (_) {
        if (_isHovered) setState(() => _isHovered = false);
      },
      child: content,
    );
  }
}

