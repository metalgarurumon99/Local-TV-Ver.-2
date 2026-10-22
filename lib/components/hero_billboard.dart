import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/media_item.dart';

class HeroBillboard extends StatefulWidget {
  final MediaItem featuredItem;
  final VoidCallback onPlay;
  final VoidCallback onMoreInfo;

  const HeroBillboard({
    super.key,
    required this.featuredItem,
    required this.onPlay,
    required this.onMoreInfo,
  });

  @override
  State<HeroBillboard> createState() => _HeroBillboardState();
}

class _HeroBillboardState extends State<HeroBillboard> {
  Player? _previewPlayer;
  VideoController? _videoController;
  Timer? _previewTimer;
  StreamSubscription? _posSub;
  bool _isVideoReady = false;
  bool _isMuted = true;

  @override
  void initState() {
    super.initState();
    _schedulePreview();
  }

  @override
  void didUpdateWidget(covariant HeroBillboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.featuredItem.id != widget.featuredItem.id ||
        oldWidget.featuredItem.videoPath != widget.featuredItem.videoPath) {
      _stopPreview();
      _schedulePreview();
    }
  }

  @override
  void dispose() {
    _stopPreview();
    super.dispose();
  }

  void _schedulePreview() {
    _previewTimer?.cancel();
    _previewTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) {
        _startHeroPreview();
      }
    });
  }

  String _resolveVideoPath() {
    if (widget.featuredItem.videoPath.isNotEmpty &&
        !widget.featuredItem.videoPath.startsWith('asset:')) {
      return widget.featuredItem.videoPath;
    }
    if (widget.featuredItem.episodes.isNotEmpty) {
      return widget.featuredItem.episodes.first.videoPath;
    }
    return '';
  }

  Future<void> _startHeroPreview() async {
    final path = _resolveVideoPath();
    if (path.isEmpty || !File(path).existsSync()) return;

    try {
      final player = Player();
      final controller = VideoController(player);

      await player.setVolume(_isMuted ? 0 : 50);

      // Start playing
      await player.open(Media(path), play: true);

      // Seek forward 40 seconds to skip black screens and logos
      await player.seek(const Duration(seconds: 40));

      // Loop a 25-second segment
      _posSub = player.stream.position.listen((pos) {
        if (pos.inSeconds > 65) {
          player.seek(const Duration(seconds: 40));
        }
      });

      if (mounted) {
        setState(() {
          _previewPlayer = player;
          _videoController = controller;
          _isVideoReady = true;
        });
      } else {
        player.dispose();
      }
    } catch (e) {
      debugPrint('Hero preview playback failed: $e');
    }
  }

  void _stopPreview() {
    _previewTimer?.cancel();
    _posSub?.cancel();
    _isVideoReady = false;
    _previewPlayer?.stop();
    _previewPlayer?.dispose();
    _previewPlayer = null;
    _videoController = null;
  }

  void _toggleMute() {
    if (_previewPlayer == null) return;
    setState(() {
      _isMuted = !_isMuted;
    });
    _previewPlayer!.setVolume(_isMuted ? 0 : 50);
  }

  Widget _buildBackgroundImage() {
    final custom = widget.featuredItem.customThumbnail;
    if (custom != null && custom.isNotEmpty) {
      if (custom.startsWith('http://') || custom.startsWith('https://')) {
        return Image.network(
          custom,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          cacheWidth: 800,
          errorBuilder: (_, _, _) => _buildFallbackImage(),
        );
      }
      final localFile = File(custom);
      if (localFile.existsSync()) {
        return Image.file(
          localFile,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          cacheWidth: 800,
          errorBuilder: (_, _, _) => _buildFallbackImage(),
        );
      }
    }
    return _buildFallbackImage();
  }

  Widget _buildFallbackImage() {
    return Container(
      color: const Color(0xFF141414),
      child: const Center(
        child: Icon(Icons.movie, size: 80, color: Colors.white24),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double billboardHeight = (screenHeight * 0.65).clamp(420.0, 620.0);

    return SizedBox(
      height: billboardHeight,
      width: double.infinity,
      child: Stack(
        children: [
          // 1. Static Poster Background
          Positioned.fill(
            child: _buildBackgroundImage(),
          ),

          // 2. High-Quality Video Preview Layer with Smooth Crossfade
          if (_videoController != null)
            Positioned.fill(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 700),
                opacity: _isVideoReady ? 1.0 : 0.0,
                child: Video(
                  controller: _videoController!,
                  fit: BoxFit.cover,
                  controls: NoVideoControls,
                ),
              ),
            ),

          // 3. Dark Vignette Gradients Overlay (Netflix style)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.black.withValues(alpha: 0.88),
                    Colors.black.withValues(alpha: 0.4),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.48, 1.0],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    const Color(0xFF111111).withValues(alpha: 0.6),
                    const Color(0xFF111111),
                  ],
                  stops: const [0.55, 0.85, 1.0],
                ),
              ),
            ),
          ),

          // 4. Content Callout (Title, Blurb, Buttons)
          Positioned(
            left: 50,
            bottom: 40,
            width: 580,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Badge
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE50914),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: const Text(
                        'FEATURED',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.featuredItem.genre.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Title Callout
                Text(
                  widget.featuredItem.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                    letterSpacing: -0.5,
                    shadows: [
                      Shadow(
                        color: Colors.black,
                        blurRadius: 16,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Synopsis Text (Blurb)
                Text(
                  widget.featuredItem.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 14,
                    height: 1.45,
                    shadows: const [
                      Shadow(color: Colors.black, blurRadius: 8),
                    ],
                  ),
                ),
                const SizedBox(height: 22),

                // Action Buttons (Play & More Info)
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        _stopPreview();
                        widget.onPlay();
                      },
                      icon: const Icon(Icons.play_arrow, color: Colors.black, size: 28),
                      label: Text(
                        widget.featuredItem.isSeries ? 'Play Episode 1' : 'Play',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        elevation: 4,
                      ),
                    ),
                    const SizedBox(width: 14),
                    ElevatedButton.icon(
                      onPressed: () {
                        _stopPreview();
                        widget.onMoreInfo();
                      },
                      icon: const Icon(Icons.info_outline, color: Colors.white, size: 22),
                      label: const Text(
                        'More Info',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.25),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 5. Netflix-Style Audio Toggle Button (Bottom Right)
          if (_videoController != null && _isVideoReady)
            Positioned(
              right: 50,
              bottom: 45,
              child: InkWell(
                onTap: _toggleMute,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white38, width: 1),
                  ),
                  child: Icon(
                    _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
