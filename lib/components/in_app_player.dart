import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';
import '../models/media_item.dart';
import '../services/thumbnail_service.dart';
import '../services/watch_history_service.dart';
import 'custom_app_title_bar.dart';

class InAppPlayer extends StatefulWidget {
  final MediaItem item;
  final VoidCallback onClose;
  final List<MediaItem> playlist;
  final ValueChanged<MediaItem>? onMediaChanged;

  const InAppPlayer({
    super.key,
    required this.item,
    required this.onClose,
    this.playlist = const [],
    this.onMediaChanged,
  });

  @override
  State<InAppPlayer> createState() => _InAppPlayerState();
}

class _InAppPlayerState extends State<InAppPlayer> with WindowListener {
  late final Player _player;
  late final VideoController _controller;
  late MediaItem _currentItem;

  bool _showControls = true;
  Timer? _hideTimer;
  Timer? _historyTimer;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = true;
  double _volume = 100.0;
  bool _isFullScreen = false;

  // Resume Watch History State
  int? _resumePositionMs;
  String? _resumeToastMessage;
  Timer? _resumeToastTimer;

  // Track & Subtitle selection state
  Tracks _tracks = const Tracks();
  Track _currentTrack = const Track();
  bool _showAudioSubtitlePopover = false;
  bool _showEpisodesDrawer = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _currentItem = widget.item;

    // Enable native libass rendering so subtitle styling is identical to original MPV
    _player = Player(
      configuration: const PlayerConfiguration(
        libass: true,
      ),
    );
    _controller = VideoController(_player);

    _applyMpvSubtitleStyling();

    _loadResumePosition();

    _player.stream.position.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });

    _player.stream.duration.listen((dur) {
      if (mounted) {
        setState(() => _duration = dur);
        if (dur > Duration.zero && _resumePositionMs != null) {
          final target = _resumePositionMs!;
          _resumePositionMs = null;
          _player.seek(Duration(milliseconds: target));
          _showResumeToast('Melanjutkan dari ${_formatDuration(Duration(milliseconds: target))}');
        }
      }
    });

    _player.stream.playing.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    });

    _player.stream.volume.listen((vol) {
      if (mounted) setState(() => _volume = vol);
    });

    _player.stream.tracks.listen((tracks) {
      if (mounted) setState(() => _tracks = tracks);
    });

    _player.stream.track.listen((track) {
      if (mounted) setState(() => _currentTrack = track);
    });

    windowManager.isFullScreen().then((val) {
      if (mounted) setState(() => _isFullScreen = val);
    });

    // Periodic watch history saving every 4 seconds
    _historyTimer = Timer.periodic(const Duration(seconds: 4), (_) => _saveWatchProgress());

    // Start playback
    _startPlayback(_currentItem.videoPath);
    _startHideTimer();
  }

  Future<void> _loadResumePosition() async {
    final entry = await WatchHistoryService.getProgress(_currentItem.id);
    if (entry != null && entry.positionMs > 5000 && !entry.isCompleted) {
      _resumePositionMs = entry.positionMs;
    }
  }

  void _showResumeToast(String msg) {
    _resumeToastTimer?.cancel();
    if (mounted) {
      setState(() => _resumeToastMessage = msg);
      _resumeToastTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _resumeToastMessage = null);
      });
    }
  }

  void _saveWatchProgress() {
    if (_duration.inMilliseconds <= 0 || _position.inMilliseconds < 2000) return;
    WatchHistoryService.saveProgress(
      mediaId: _currentItem.id,
      mediaTitle: _currentItem.title,
      videoPath: _currentItem.videoPath,
      thumbnailPath: _currentItem.customThumbnail ?? _currentItem.thumbnailPath,
      category: _currentItem.category,
      isSeries: _currentItem.isSeries,
      positionMs: _position.inMilliseconds,
      durationMs: _duration.inMilliseconds,
    );
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted && !_isFullScreen) setState(() => _isFullScreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted && _isFullScreen) setState(() => _isFullScreen = false);
  }

  Future<void> _exitFullScreen() async {
    try {
      await windowManager.setFullScreen(false);
      if (mounted) setState(() => _isFullScreen = false);
    } catch (e) {
      debugPrint('Exit fullscreen error: $e');
    }
  }

  Future<void> _enterFullScreen() async {
    try {
      await windowManager.setFullScreen(true);
      if (mounted) setState(() => _isFullScreen = true);
    } catch (e) {
      debugPrint('Enter fullscreen error: $e');
    }
  }

  Future<void> _toggleFullScreen() async {
    final isFull = await windowManager.isFullScreen();
    if (isFull) {
      await _exitFullScreen();
    } else {
      await _enterFullScreen();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _historyTimer?.cancel();
    _resumeToastTimer?.cancel();
    windowManager.removeListener(this);
    _saveWatchProgress();
    _player.dispose();
    if (_isFullScreen) {
      windowManager.setFullScreen(false);
    }
    super.dispose();
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      _player.pause();
    } else {
      _player.play();
    }
    _onUserActivity();
  }

  void _seekRelative(Duration delta) {
    final target = _position + delta;
    if (target < Duration.zero) {
      _player.seek(Duration.zero);
    } else if (target > _duration) {
      _player.seek(_duration);
    } else {
      _player.seek(target);
    }
    _onUserActivity();
  }

  void _startPlayback(String path) {
    _player.open(Media(path));
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

  void _switchMedia(MediaItem newItem) {
    _saveWatchProgress();
    setState(() {
      _currentItem = newItem;
      _showEpisodesDrawer = false;
      _showAudioSubtitlePopover = false;
    });
    widget.onMediaChanged?.call(newItem);
    _loadResumePosition();
    _startPlayback(newItem.videoPath);
    _onUserActivity();
  }

  void _playNextInPlaylist() {
    if (widget.playlist.isEmpty) return;
    final currentIndex = widget.playlist.indexWhere((it) => it.videoPath == _currentItem.videoPath);
    if (currentIndex != -1 && currentIndex + 1 < widget.playlist.length) {
      _switchMedia(widget.playlist[currentIndex + 1]);
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (_showAudioSubtitlePopover || _showEpisodesDrawer) {
      // Keep controls visible while menu/drawer is open
      return;
    }
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isPlaying && !_showAudioSubtitlePopover && !_showEpisodesDrawer) {
        setState(() => _showControls = false);
      }
    });
  }

  void _onUserActivity() {
    if (!_showControls) {
      setState(() => _showControls = true);
    }
    _startHideTimer();
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

  String _getTrackName(dynamic track, String fallback) {
    if (track == null) return fallback;
    final title = track.title as String?;
    final lang = track.language as String?;
    if (title != null && title.isNotEmpty) return title;
    if (lang != null && lang.isNotEmpty) return lang.toUpperCase();
    return fallback;
  }

  Widget _buildPosterThumbnail(MediaItem item) {
    // 1. Check local extracted video thumbnail first!
    if (LocalThumbnailService.hasThumbnail(item.videoPath)) {
      final path = LocalThumbnailService.getThumbnailPath(item.videoPath);
      return Image.file(
        File(path),
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        cacheWidth: 320,
        errorBuilder: (_, _, _) => _buildThumbnailPlaceholder(),
      );
    }

    if (item.customThumbnail != null && item.customThumbnail!.isNotEmpty) {
      if (item.isNetworkImage) {
        return Image.network(
          item.customThumbnail!,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          cacheWidth: 320,
          errorBuilder: (_, _, _) => _buildThumbnailPlaceholder(),
        );
      }
      final file = File(item.customThumbnail!);
      if (file.existsSync()) {
        return Image.file(
          file,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          cacheWidth: 320,
          errorBuilder: (_, _, _) => _buildThumbnailPlaceholder(),
        );
      }
    }
    return _buildThumbnailPlaceholder();
  }

  Widget _buildThumbnailPlaceholder() {
    return Container(
      color: const Color(0xFF222222),
      child: const Center(
        child: Icon(Icons.movie_filter_rounded, size: 24, color: Colors.white24),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF): _toggleFullScreen,
        const SingleActivator(LogicalKeyboardKey.space): _togglePlayPause,
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _seekRelative(const Duration(seconds: 10)),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _seekRelative(const Duration(seconds: -10)),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () {
          final newVol = (_volume + 5.0).clamp(0.0, 100.0);
          _player.setVolume(newVol);
          _onUserActivity();
        },
        const SingleActivator(LogicalKeyboardKey.arrowDown): () {
          final newVol = (_volume - 5.0).clamp(0.0, 100.0);
          _player.setVolume(newVol);
          _onUserActivity();
        },
        const SingleActivator(LogicalKeyboardKey.keyM): () {
          _player.setVolume(_volume > 0 ? 0.0 : 100.0);
          _onUserActivity();
        },
        const SingleActivator(LogicalKeyboardKey.escape): () async {
          if (_isFullScreen) {
            await _exitFullScreen();
          } else {
            _saveWatchProgress();
            widget.onClose();
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: MouseRegion(
          onHover: (_) => _onUserActivity(),
          child: GestureDetector(
            onDoubleTap: _toggleFullScreen,
            onTap: () {
              if (_showAudioSubtitlePopover || _showEpisodesDrawer) {
                setState(() {
                  _showAudioSubtitlePopover = false;
                  _showEpisodesDrawer = false;
                });
                return;
              }
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

                  // Resume Position Toast
                  if (_resumeToastMessage != null)
                    Positioned(
                      bottom: 95,
                      left: 32,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E1E).withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE50914), width: 1.2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.8),
                              blurRadius: 14,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.history_rounded, color: Color(0xFFE50914), size: 18),
                            const SizedBox(width: 8),
                            Text(
                              _resumeToastMessage!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
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
                          // Top Bar with Custom Window Controls when not in fullscreen
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!_isFullScreen)
                                  const CustomAppTitleBar(isTransparent: true),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
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
                                        onPressed: () async {
                                          if (_isFullScreen) {
                                            await _exitFullScreen();
                                          }
                                          _saveWatchProgress();
                                          widget.onClose();
                                        },
                                      ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _currentItem.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (_currentItem.year != null || _currentItem.genre.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        '${_currentItem.genre} ${_currentItem.year != null ? "• ${_currentItem.year}" : ""}',
                                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                      // Netflix-Style Audio & Subtitles Popover
                      if (_showAudioSubtitlePopover)
                        Positioned(
                          bottom: 90,
                          right: 60,
                          child: _buildNetflixAudioSubtitleMenu(),
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
                                Colors.black.withValues(alpha: 0.5),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.6, 1.0],
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Timeline Scrubber
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
                                  value: _position.inMilliseconds
                                      .clamp(0, _duration.inMilliseconds)
                                      .toDouble(),
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
                                  // Play/Pause
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
                                  const SizedBox(width: 6),

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
                                  const SizedBox(width: 8),

                                  // Next Video / Episode button
                                  if (widget.playlist.isNotEmpty)
                                    IconButton(
                                      icon: const Icon(Icons.skip_next_rounded, color: Colors.white70, size: 26),
                                      tooltip: 'Video Berikutnya',
                                      onPressed: _playNextInPlaylist,
                                    ),

                                  const SizedBox(width: 8),

                                  // Time Label
                                  Text(
                                    '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                                  ),

                                  const Spacer(),

                                  // Volume
                                  IconButton(
                                    icon: Icon(
                                      _volume == 0
                                          ? Icons.volume_off
                                          : (_volume < 50 ? Icons.volume_down : Icons.volume_up),
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                    onPressed: () {
                                      _player.setVolume(_volume > 0 ? 0.0 : 100.0);
                                    },
                                  ),
                                  SizedBox(
                                    width: 75,
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
                                  const SizedBox(width: 14),

                                  // Netflix-Style: Episodes Button
                                  if (widget.playlist.isNotEmpty)
                                    IconButton(
                                      icon: Icon(
                                        Icons.video_library_rounded,
                                        color: _showEpisodesDrawer ? const Color(0xFFE50914) : Colors.white,
                                        size: 24,
                                      ),
                                      tooltip: 'Daftar Video / Episode',
                                      onPressed: () {
                                        setState(() {
                                          _showEpisodesDrawer = !_showEpisodesDrawer;
                                          _showAudioSubtitlePopover = false;
                                        });
                                        _onUserActivity();
                                      },
                                    ),

                                  // Netflix-Style: Audio & Subtitles Button
                                  IconButton(
                                    icon: Icon(
                                      Icons.chat_bubble_outline_rounded,
                                      color: _showAudioSubtitlePopover ? const Color(0xFFE50914) : Colors.white,
                                      size: 24,
                                    ),
                                    tooltip: 'Audio & Subtitle',
                                    onPressed: () {
                                      setState(() {
                                        _showAudioSubtitlePopover = !_showAudioSubtitlePopover;
                                        _showEpisodesDrawer = false;
                                      });
                                      _onUserActivity();
                                    },
                                  ),
                                  const SizedBox(width: 4),

                                  // Netflix-Style: Fullscreen Button
                                  IconButton(
                                    icon: Icon(
                                      _isFullScreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                                      color: Colors.white,
                                      size: 26,
                                    ),
                                    tooltip: _isFullScreen ? 'Keluar Layar Penuh (F / Esc)' : 'Layar Penuh (F)',
                                    onPressed: () {
                                      _toggleFullScreen();
                                      _onUserActivity();
                                    },
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

              // Netflix-Style Episodes Card / Pop-up (Max Half Screen Height)
              if (_showEpisodesDrawer && widget.playlist.isNotEmpty)
                Positioned(
                  bottom: 85,
                  right: 24,
                  child: _buildNetflixEpisodesPopup(),
                ),
            ],
          ),
        ),
      ),
    ),
  ),
);
}

  /// Netflix-Style 2-Column Audio & Subtitles Menu
  Widget _buildNetflixAudioSubtitleMenu() {
    final audioTracks = _tracks.audio;
    final subtitleTracks = _tracks.subtitle;

    return Container(
      width: 440,
      constraints: const BoxConstraints(maxHeight: 380),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xF2181818),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.8),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Audio Column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Row(
                  children: [
                    Icon(Icons.audiotrack, color: Color(0xFFE50914), size: 16),
                    SizedBox(width: 6),
                    Text(
                      'AUDIO',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (audioTracks.isEmpty)
                  const Text('Tidak ada audio track', style: TextStyle(color: Colors.white38, fontSize: 12))
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: audioTracks.length,
                      itemBuilder: (ctx, idx) {
                        final track = audioTracks[idx];
                        final isSelected = _currentTrack.audio == track;
                        final label = _getTrackName(track, 'Audio ${idx + 1}');

                        return InkWell(
                          onTap: () {
                            _player.setAudioTrack(track);
                            setState(() {});
                            _onUserActivity();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.check_rounded,
                                  color: isSelected ? const Color(0xFFE50914) : Colors.transparent,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : Colors.white70,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          Container(width: 1, height: 260, color: Colors.white12, margin: const EdgeInsets.symmetric(horizontal: 16)),

          // Subtitles Column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Row(
                  children: [
                    Icon(Icons.subtitles, color: Color(0xFFE50914), size: 16),
                    SizedBox(width: 6),
                    Text(
                      'SUBTITLES',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Off Option
                InkWell(
                  onTap: () {
                    _player.setSubtitleTrack(SubtitleTrack.no());
                    setState(() {});
                    _onUserActivity();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_rounded,
                          color: (_currentTrack.subtitle == SubtitleTrack.no())
                              ? const Color(0xFFE50914)
                              : Colors.transparent,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Nonaktif (Off)',
                          style: TextStyle(
                            color: (_currentTrack.subtitle == SubtitleTrack.no())
                                ? Colors.white
                                : Colors.white70,
                            fontWeight: (_currentTrack.subtitle == SubtitleTrack.no())
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Subtitle Tracks
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: subtitleTracks.length,
                    itemBuilder: (ctx, idx) {
                      final track = subtitleTracks[idx];
                      if (track.id == 'no' || track.id == 'auto') return const SizedBox.shrink();

                      final isSelected = _currentTrack.subtitle == track;
                      final label = _getTrackName(track, 'Subtitle ${idx + 1}');

                      return InkWell(
                        onTap: () {
                          _player.setSubtitleTrack(track);
                          setState(() {});
                          _onUserActivity();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_rounded,
                                color: isSelected ? const Color(0xFFE50914) : Colors.transparent,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : Colors.white70,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Netflix-Style Episodes Card / Pop-up (Max Half Screen Height, Compact Vertical with Thumbnail Left, Synopsis Right)
  Widget _buildNetflixEpisodesPopup() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final popupWidth = screenWidth < 700 ? screenWidth * 0.92 : 540.0;
    final maxHeight = screenHeight * 0.50; // Tepat maksimal setengah layar!

    return Container(
      width: popupWidth,
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: const Color(0xF7161616),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.85),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
            child: Row(
              children: [
                const Icon(Icons.video_library_rounded, color: Color(0xFFE50914), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Episodes (${widget.playlist.length})',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Tutup',
                  onPressed: () => setState(() => _showEpisodesDrawer = false),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),

          // Scrollable Episodes List
          Flexible(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 6),
              shrinkWrap: true,
              itemCount: widget.playlist.length,
              separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 1),
              itemBuilder: (ctx, index) {
                final item = widget.playlist[index];
                final isCurrent = item.videoPath == _currentItem.videoPath;
                final badgeText = isCurrent ? 'S1E${index + 1} • NOW PLAYING' : 'S1E${index + 1}';

                return InkWell(
                  onTap: () {
                    _switchMedia(item);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    color: isCurrent ? const Color(0xFFE50914).withValues(alpha: 0.12) : Colors.transparent,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left Column: Compact 16:9 Thumbnail with Badges
                        SizedBox(
                          width: 140,
                          height: 78,
                          child: Stack(
                            children: [
                              Container(
                                width: 140,
                                height: 78,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: isCurrent ? const Color(0xFFE50914) : Colors.white12,
                                    width: isCurrent ? 1.5 : 0.8,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: _buildPosterThumbnail(item),
                                ),
                              ),
                              // Top-Left Badge (S1E... / S1E... Now Playing)
                              Positioned(
                                top: 3,
                                left: 3,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isCurrent ? const Color(0xFFE50914) : Colors.black.withValues(alpha: 0.8),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    badgeText,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                              ),
                              // Center Equalizer if Current
                              if (isCurrent)
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black38,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Center(
                                      child: Icon(Icons.equalizer_rounded, color: Colors.white, size: 22),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Right Column: Baris 1 (Nama Movie/series) & Baris 2 (Episode "xx")
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Baris Pertama: Nama Movie/series
                              Text(
                                _getSeriesTitle(item),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isCurrent ? const Color(0xFFE50914) : Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 5),
                              // Baris kedua: Episode "xx"
                              Text(
                                'Episode "${(index + 1).toString().padLeft(2, '0')}"',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _getSeriesTitle(MediaItem item) {
    final title = _currentItem.title;
    final dash = title.indexOf(' - ');
    if (dash != -1) return title.substring(0, dash).trim();
    return title;
  }
}
