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
  bool _isPressed = false;

  @override
  void didUpdateWidget(covariant HoverAnimatedWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onTap == null && (_isHovered || _isPressed)) {
      _isHovered = false;
      _isPressed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isInteractive = widget.onTap != null;
    final bool effectiveHover = isInteractive && _isHovered;
    final double targetScale = !isInteractive
        ? 1.0
        : (_isPressed ? 0.96 : (effectiveHover ? widget.hoverScale : 1.0));

    Widget content = AnimatedScale(
      scale: targetScale,
      duration: _isPressed ? const Duration(milliseconds: 80) : widget.duration,
      curve: widget.curve,
      child: widget.builder(context, effectiveHover),
    );

    if (isInteractive) {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          if (!_isPressed) setState(() => _isPressed = true);
        },
        onTapUp: (_) {
          if (_isPressed) setState(() => _isPressed = false);
        },
        onTapCancel: () {
          if (_isPressed) setState(() => _isPressed = false);
        },
        onTap: widget.onTap,
        child: content,
      );
    }

    return MouseRegion(
      cursor: isInteractive ? widget.cursor : SystemMouseCursors.basic,
      onEnter: (_) {
        if (isInteractive && !_isHovered) setState(() => _isHovered = true);
      },
      onExit: (_) {
        if (_isHovered || _isPressed) {
          setState(() {
            _isHovered = false;
            _isPressed = false;
          });
        }
      },
      child: content,
    );
  }
}

