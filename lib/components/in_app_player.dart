import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/media_item.dart';

class InAppPlayer extends StatefulWidget {
  final MediaItem item;
  final VoidCallback onClose;

  const InAppPlayer({
    super.key,
    required this.item,
    required this.onClose,
  });

  @override
  State<InAppPlayer> createState() => _InAppPlayerState();
}

class _InAppPlayerState extends State<InAppPlayer> {
  late final Player _player;
  late final VideoController _controller;
  bool _showControls = true;
  Timer? _hideTimer;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = true;
  double _volume = 100.0;

  @override
  void initState() {
    super.initState();
    // Enable native libass rendering so subtitle styling is identical to original MPV
    _player = Player(
      configuration: const PlayerConfiguration(
        libass: true,
      ),
    );
    _controller = VideoController(_player);

    _applyMpvSubtitleStyling();

    _player.stream.position.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });

    _player.stream.duration.listen((dur) {
      if (mounted) setState(() => _duration = dur);
    });

    _player.stream.playing.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    });

    _player.stream.volume.listen((vol) {
      if (mounted) setState(() => _volume = vol);
    });

    // Start playback
    final mediaSource = widget.item.videoPath;
    _player.open(Media(mediaSource));

    _startHideTimer();
  }

  void _applyMpvSubtitleStyling() {
    final dynamic platform = _player.platform;
    try {
      // Subtitle SSA/ASS Asli (Typesetting, Karaoke & Custom Fonts)
      platform.setProperty('sub-ass-override', 'no');
      platform.setProperty('embeddedfonts', 'yes');
      platform.setProperty('sub-auto', 'all');
      platform.setProperty('sub-visibility', 'yes');
      platform.setProperty('sid', 'auto');
      platform.setProperty('slang', 'ind,id,indonesian,bahasa,eng,en,english,jpn,ja,und');
      platform.setProperty('alang', 'jpn,ja,kor,ko,ind,id,eng,en');

      // Subtitle styling non-ASS (Trebuchet MS, pure white, shadow, border)
      platform.setProperty('sub-font', 'Trebuchet MS');
      platform.setProperty('sub-font-size', '46');
      platform.setProperty('sub-color', '#FFFFFFFF');
      platform.setProperty('sub-border-color', '#FF111111');
      platform.setProperty('sub-border-size', '3.0');
      platform.setProperty('sub-shadow-offset', '1.2');
      platform.setProperty('sub-margin-y', '42');
      platform.setProperty('hwdec', 'auto-safe');
    } catch (e) {
      debugPrint('Error applying MPV subtitle styling: $e');
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _onUserActivity() {
    setState(() => _showControls = true);
    _startHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return '${twoDigits(duration.inHours)}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (_) => _onUserActivity(),
      child: GestureDetector(
        onTap: () {
          setState(() => _showControls = !_showControls);
          if (_showControls) _startHideTimer();
        },
        child: Container(
          color: Colors.black,
          child: Stack(
            children: [
              // Core Video Rendering Surface (media_kit LibMPV texture)
              Center(
                child: Video(
                  controller: _controller,
                  controls: NoVideoControls,
                  subtitleViewConfiguration: const SubtitleViewConfiguration(
                    visible: false,
                  ),
                ),
              ),

              // Controls Overlay
              AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: _showControls ? 1.0 : 0.0,
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: Stack(
                    children: [
                      // Top Bar
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.85),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
                                onPressed: widget.onClose,
                                tooltip: 'Kembali ke Katalog',
                              ),
                              const SizedBox(width: 16),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.item.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '${widget.item.category.toUpperCase()} • ${widget.item.genre}',
                                    style: const TextStyle(
                                      color: Colors.white60,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE50914),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.tv, color: Colors.white, size: 14),
                                    SizedBox(width: 4),
                                    Text(
                                      'IN-APP MPV',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Bottom Control Bar
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.9),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Scrubber Slider
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  activeTrackColor: const Color(0xFFE50914),
                                  inactiveTrackColor: Colors.white24,
                                  thumbColor: const Color(0xFFE50914),
                                  trackHeight: 4,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                ),
                                child: Slider(
                                  value: _position.inMilliseconds.clamp(0, _duration.inMilliseconds).toDouble(),
                                  min: 0.0,
                                  max: _duration.inMilliseconds.toDouble() > 0
                                      ? _duration.inMilliseconds.toDouble()
                                      : 1.0,
                                  onChanged: (val) {
                                    _player.seek(Duration(milliseconds: val.toInt()));
                                    _onUserActivity();
                                  },
                                ),
                              ),

                              Row(
                                children: [
                                  // Play/Pause Button
                                  IconButton(
                                    icon: Icon(
                                      _isPlaying ? Icons.pause : Icons.play_arrow,
                                      color: Colors.white,
                                      size: 32,
                                    ),
                                    onPressed: () {
                                      _player.playOrPause();
                                      _onUserActivity();
                                    },
                                  ),
                                  const SizedBox(width: 8),

                                  // Fast Backward 10s
                                  IconButton(
                                    icon: const Icon(Icons.replay_10, color: Colors.white70, size: 24),
                                    onPressed: () {
                                      final target = _position - const Duration(seconds: 10);
                                      _player.seek(target < Duration.zero ? Duration.zero : target);
                                      _onUserActivity();
                                    },
                                  ),

                                  // Fast Forward 10s
                                  IconButton(
                                    icon: const Icon(Icons.forward_10, color: Colors.white70, size: 24),
                                    onPressed: () {
                                      final target = _position + const Duration(seconds: 10);
                                      _player.seek(target > _duration ? _duration : target);
                                      _onUserActivity();
                                    },
                                  ),
                                  const SizedBox(width: 12),

                                  // Time Label
                                  Text(
                                    '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                                  ),

                                  const Spacer(),

                                  // Volume Slider
                                  IconButton(
                                    icon: Icon(
                                      _volume == 0
                                          ? Icons.volume_off
                                          : (_volume < 50 ? Icons.volume_down : Icons.volume_up),
                                      color: Colors.white,
                                    ),
                                    onPressed: () {
                                      _player.setVolume(_volume > 0 ? 0.0 : 100.0);
                                    },
                                  ),
                                  SizedBox(
                                    width: 80,
                                    child: SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        activeTrackColor: Colors.white,
                                        inactiveTrackColor: Colors.white24,
                                        thumbColor: Colors.white,
                                        trackHeight: 3,
                                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                                      ),
                                      child: Slider(
                                        value: _volume.clamp(0.0, 100.0),
                                        min: 0.0,
                                        max: 100.0,
                                        onChanged: (val) {
                                          _player.setVolume(val);
                                          _onUserActivity();
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
