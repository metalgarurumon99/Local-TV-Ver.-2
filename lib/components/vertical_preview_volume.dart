import 'package:flutter/material.dart';
import '../services/preview_player_service.dart';

enum VolumeSliderDirection { up, down }

/// Clean vertical volume slider for preview video player.
/// Shows the classic circular speaker button at its standard size.
/// On hover, displays a pure vertical track line and knob directly above/below the icon
/// with a completely transparent background (no capsule, no border box).
class VerticalPreviewVolumeControl extends StatefulWidget {
  final double iconSize;
  final double buttonPadding;
  final double sliderHeight;
  final VolumeSliderDirection direction;
  final Color? buttonBackgroundColor;
  final Border? buttonBorder;

  const VerticalPreviewVolumeControl({
    super.key,
    this.iconSize = 20,
    this.buttonPadding = 8,
    this.sliderHeight = 70,
    this.direction = VolumeSliderDirection.up,
    this.buttonBackgroundColor,
    this.buttonBorder,
  });

  @override
  State<VerticalPreviewVolumeControl> createState() => _VerticalPreviewVolumeControlState();
}

class _VerticalPreviewVolumeControlState extends State<VerticalPreviewVolumeControl> {
  bool _isHovered = false;

  void _updateVolumeFromDy(double localDy, double totalHeight) {
    final previewService = PreviewPlayerService.instance;
    final double pct;
    if (widget.direction == VolumeSliderDirection.up) {
      // Top is 100%, bottom is 0%
      pct = (1.0 - (localDy / totalHeight)).clamp(0.0, 1.0);
    } else {
      // Top is 0%, bottom is 100%
      pct = (localDy / totalHeight).clamp(0.0, 1.0);
    }
    previewService.setVolume(pct * 100.0);
  }

  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final previewService = PreviewPlayerService.instance;
    final bool showSlider = _isHovered || _isDragging;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: ValueListenableBuilder<({double volume, bool isMuted})>(
        valueListenable: previewService.volumeStateNotifier,
        builder: (context, volState, _) {
          final isMuted = volState.isMuted || volState.volume <= 0.0;
          final double currentVol = isMuted ? 0.0 : volState.volume.clamp(0.0, 100.0);
          final double effectivePct = (currentVol / 100.0).clamp(0.0, 1.0);

          // Speaker Button (classic circular style)
          final speakerButton = InkWell(
            onTap: previewService.toggleMute,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: EdgeInsets.all(widget.buttonPadding),
              decoration: BoxDecoration(
                color: widget.buttonBackgroundColor ?? Colors.black.withValues(alpha: 0.6),
                shape: BoxShape.circle,
                border: widget.buttonBorder ?? Border.all(color: Colors.white38, width: 1.0),
              ),
              child: Icon(
                isMuted
                    ? Icons.volume_off_rounded
                    : (currentVol < 50
                        ? Icons.volume_down_rounded
                        : Icons.volume_up_rounded),
                color: Colors.white,
                size: widget.iconSize,
              ),
            ),
          );

          // Pure Vertical Track Bar (no capsule, no borders, transparent background)
          final verticalTrack = AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: showSlider ? 1.0 : 0.0,
            child: IgnorePointer(
              ignoring: !showSlider,
              child: SizedBox(
                width: 28,
                height: widget.sliderHeight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: (details) {
                    setState(() => _isDragging = true);
                    _updateVolumeFromDy(details.localPosition.dy, widget.sliderHeight);
                  },
                  onVerticalDragUpdate: (details) =>
                      _updateVolumeFromDy(details.localPosition.dy, widget.sliderHeight),
                  onVerticalDragEnd: (_) => setState(() => _isDragging = false),
                  onVerticalDragCancel: () => setState(() => _isDragging = false),
                  onTapDown: (details) =>
                      _updateVolumeFromDy(details.localPosition.dy, widget.sliderHeight),
                  child: Center(
                    child: SizedBox(
                      width: 14,
                      height: widget.sliderHeight,
                      child: Stack(
                        alignment: widget.direction == VolumeSliderDirection.up
                            ? Alignment.bottomCenter
                            : Alignment.topCenter,
                        children: [
                          // Inactive Track Line
                          Container(
                            width: 3.0,
                            height: widget.sliderHeight,
                            decoration: BoxDecoration(
                              color: Colors.white30,
                              borderRadius: BorderRadius.circular(1.5),
                            ),
                          ),
                          // Active Progress Track Line
                          Container(
                            width: 3.0,
                            height: widget.sliderHeight * effectivePct,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(1.5),
                            ),
                          ),
                          // Circular Knob / Thumb
                          Positioned(
                            bottom: widget.direction == VolumeSliderDirection.up
                                ? (widget.sliderHeight * effectivePct - 5.0)
                                    .clamp(0.0, widget.sliderHeight - 10.0)
                                : null,
                            top: widget.direction == VolumeSliderDirection.down
                                ? (widget.sliderHeight * effectivePct - 5.0)
                                    .clamp(0.0, widget.sliderHeight - 10.0)
                                : null,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black54,
                                    blurRadius: 3,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );

          if (widget.direction == VolumeSliderDirection.up) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                verticalTrack,
                const SizedBox(height: 6),
                speakerButton,
              ],
            );
          } else {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                speakerButton,
                const SizedBox(height: 6),
                verticalTrack,
              ],
            );
          }
        },
      ),
    );
  }
}

