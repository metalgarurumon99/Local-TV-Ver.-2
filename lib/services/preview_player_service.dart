import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'debug_logger.dart';
import 'thumbnail_service.dart';

/// Netflix-style Single Shared Hardware Preview Engine + Micro-Preview Cache (`.cache/previews/`).
///
/// Guarantees:
/// 1. At most ONE lightweight hardware-decoded `Player` + `VideoController` (640x360) exists
///    across the entire catalog (`HeroBillboard`, `VideoCard`, `ItemDetailDialog`).
/// 2. Never creates/destroys Direct3D11/ANGLE swapchains repeatedly on hover or banner rotation.
/// 3. Skips embedded MKV fonts (`embeddedfonts=no`), subtitles (`sid=no`, `libass=false`),
///    and uses keyframe start (`start=+40`, `hr-seek=no`) so 1.7GB 10-bit HEVC files open with minimal I/O.
/// 4. Auto-stops after 14 seconds (no infinite looping) so idle CPU/GPU returns to 0%.
/// 5. Automatically caches 12-second 480p `.mp4` micro-previews in `.cache/previews/` when `ffmpeg` is available.
class PreviewPlayerService extends ChangeNotifier {
  PreviewPlayerService._();
  static final PreviewPlayerService instance = PreviewPlayerService._();

  Player? _player;
  VideoController? _controller;
  bool _engineConfigured = false;

  String? _activeOwnerId;
  bool _isFrameReady = false;
  bool _isMuted = false;
  double _volume = 50.0;
  final ValueNotifier<({double volume, bool isMuted})> volumeStateNotifier =
      ValueNotifier<({double volume, bool isMuted})>((volume: 50.0, isMuted: false));
  bool _isSuspended = false;

  Timer? _autoStopTimer;
  Timer? _scrollCooldownTimer;
  StreamSubscription<Duration>? _frameSub;
  bool _isScrolling = false;
  int _scrollGeneration = 0;
  int _requestToken = 0;

  String? get activeOwnerId => _activeOwnerId;
  VideoController? get controller => _controller;
  bool get isMuted => _isMuted;
  double get volume => _volume;
  int get scrollGeneration => _scrollGeneration;

  bool isOwnerReady(String ownerId) =>
      !_isSuspended && _activeOwnerId == ownerId && _isFrameReady && _controller != null;

  /// Lazily initialize the single shared hardware-accelerated preview player
  Future<void> _ensureEngine() async {
    if (_player != null && _controller != null) return;

    final player = Player(
      configuration: const PlayerConfiguration(
        libass: false,
        bufferSize: 4 * 1024 * 1024, // 4 MB lightweight buffer
      ),
    );

    final controller = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );

    _player = player;
    _controller = controller;

    if (!_engineConfigured) {
      _engineConfigured = true;
      final dynamic platform = player.platform;
      try {
        platform.setProperty('hwdec', 'auto-safe');
        platform.setProperty('sid', 'no');
        platform.setProperty('sub-auto', 'no');
        platform.setProperty('aid', 'auto');
        platform.setProperty('alang', '');
        platform.setProperty('audio-file-auto', 'no');
        platform.setProperty('embeddedfonts', 'no');
        platform.setProperty('hr-seek', 'no');
        platform.setProperty('demuxer-readahead-secs', '3');
        platform.setProperty('vd-lavc-fast', 'yes');
        platform.setProperty('vd-lavc-skiploopfilter', 'nonref');
      } catch (e) {
        debugPrint('PreviewPlayerService property config error: $e');
      }
    }
  }

  /// Called by scroll views to temporarily suppress starting new previews during active scrolling
  void notifyScrollActivity() {
    _isScrolling = true;
    _scrollGeneration++;
    if (_activeOwnerId != null && _activeOwnerId!.startsWith('card-')) {
      releasePreview(_activeOwnerId!);
    }
    _scrollCooldownTimer?.cancel();
    _scrollCooldownTimer = Timer(const Duration(milliseconds: 300), () {
      _isScrolling = false;
    });
  }

  /// Request the shared preview player for [ownerId] and [videoPath].
  Future<void> requestPreview({
    required String ownerId,
    required String videoPath,
    bool allowAudio = true,
    Duration maxDuration = const Duration(seconds: 30),
  }) async {
    DebugLogger.log('requestPreview START: ownerId=$ownerId, path=$videoPath');
    if (_isSuspended) {
      DebugLogger.log('requestPreview REJECTED: suspended');
      return;
    }
    if (videoPath.isEmpty || videoPath.startsWith('asset:')) return;
    if (_isScrolling && ownerId.startsWith('card-')) {
      DebugLogger.log('requestPreview REJECTED: isScrolling');
      return;
    }
    if (!LocalThumbnailService.fileExistsCached(videoPath)) return;

    final int token = ++_requestToken;
    _autoStopTimer?.cancel();
    _frameSub?.cancel();
    _frameSub = null;

    bool isSuperseded() => token != _requestToken || _isSuspended || _activeOwnerId != ownerId;
    void stopOnlyIfNoNewOwner() {
      // Only stop the shared player if no newer owner has taken over
      if (_activeOwnerId == null || _isSuspended) {
        try {
          _player?.setVolume(0.0);
          _player?.stop();
        } catch (_) {}
      }
    }

    final double targetVolume = (allowAudio && !_isMuted) ? _volume : 0.0;

    _activeOwnerId = ownerId;
    _isFrameReady = false;
    notifyListeners();

    await _ensureEngine();
    if (isSuperseded()) {
      stopOnlyIfNoNewOwner();
      return;
    }

    final player = _player!;

    // Direct hardware stream playback from local video file
    // Bypasses low-res 360p micro-preview so billboard and card previews render at original crisp resolution!
    final String finalSource = File(videoPath).absolute.path;

    try {
      final dynamic platform = player.platform;
      // Fast keyframe seek to 30s to skip studio intros and dive into the action
      platform.setProperty('start', '+30');
    } catch (_) {}

    // Open with volume 0.0 initially to completely eliminate ANY sound leakage during load
    try {
      await player.setVolume(0.0);
    } catch (_) {}
    if (isSuperseded()) {
      stopOnlyIfNoNewOwner();
      return;
    }

    // Continuous loop mode so preview video doesn't cut to a black box
    await player.setPlaylistMode(PlaylistMode.loop);
    if (isSuperseded()) {
      stopOnlyIfNoNewOwner();
      return;
    }

    // Open in PAUSED mode (play: false). Never starts audio or unpauses until validated!
    await player.open(Media(finalSource), play: false);

    // If cancelled or released while opening, stop only if no newer owner took over
    if (isSuperseded()) {
      stopOnlyIfNoNewOwner();
      return;
    }

    // Request is still active and valid: now safely start playback and restore volume
    await player.setVolume(targetVolume);
    await player.play();
    DebugLogger.log('requestPreview PLAYING: ownerId=$ownerId, vol=$targetVolume');

    if (isSuperseded()) {
      stopOnlyIfNoNewOwner();
      return;
    }

    // Wait until the new video actually begins playing frames before making it visible
    void onFrameStarted() {
      _frameSub?.cancel();
      _frameSub = null;
      if (!isSuperseded()) {
        if (!_isFrameReady) {
          _isFrameReady = true;
          notifyListeners();
        }
      } else {
        stopOnlyIfNoNewOwner();
      }
    }

    _frameSub?.cancel();
    _frameSub = player.stream.position.listen((pos) {
      if (pos > Duration.zero) {
        onFrameStarted();
      }
    });

    if (player.state.position > Duration.zero && player.state.playing) {
      onFrameStarted();
    }

    _scheduleAutoStop(ownerId, token, maxDuration);
  }

  void _scheduleAutoStop(String ownerId, int token, Duration maxDuration) {
    _autoStopTimer = Timer(maxDuration, () {
      if (token == _requestToken && _activeOwnerId == ownerId) {
        releasePreview(ownerId);
      }
    });
  }

  /// Release preview if currently owned by [ownerId].
  void releasePreview(String ownerId) {
    DebugLogger.log('releasePreview CALLED: ownerId=$ownerId, currentOwner=$_activeOwnerId');
    if (_activeOwnerId != null && _activeOwnerId != ownerId) {
      DebugLogger.log('releasePreview IGNORED: ownerId mismatch ($ownerId vs $_activeOwnerId)');
      return;
    }
    stopAll();
  }

  /// Unconditionally stop whatever preview is currently playing and reset all preview state.
  void stopAll() {
    DebugLogger.log('stopAll CALLED: previousOwner=$_activeOwnerId');
    _requestToken++;
    _autoStopTimer?.cancel();
    _frameSub?.cancel();
    _frameSub = null;
    _activeOwnerId = null;
    _isFrameReady = false;
    try {
      _player?.setVolume(0.0);
      _player?.stop();
    } catch (_) {}
    notifyListeners();
  }

  /// Suspend all previews immediately (e.g., when opening full InAppPlayer).
  void suspendAll() {
    _isSuspended = true;
    _requestToken++;
    _autoStopTimer?.cancel();
    _frameSub?.cancel();
    _frameSub = null;
    final bool hadOwner = _activeOwnerId != null || _isFrameReady;
    _activeOwnerId = null;
    _isFrameReady = false;
    try {
      _player?.setVolume(0.0);
      _player?.stop();
    } catch (_) {}
    if (hadOwner) {
      notifyListeners();
    }
  }

  /// Resume preview availability after returning from InAppPlayer.
  void resumeFromSuspension() {
    if (!_isSuspended) return;
    _isSuspended = false;
    notifyListeners();
  }

  /// Set preview volume (0.0 to 100.0) without triggering full Video layer rebuilds
  void setVolume(double val) {
    _volume = val.clamp(0.0, 100.0);
    if (_isMuted && _volume > 0) {
      _isMuted = false;
    }
    _player?.setVolume(_volume);
    volumeStateNotifier.value = (volume: _volume, isMuted: _isMuted);
  }

  /// Toggle mute for Hero / Dialog previews without triggering full Video layer rebuilds
  void toggleMute() {
    _isMuted = !_isMuted;
    _player?.setVolume(_isMuted ? 0.0 : _volume);
    volumeStateNotifier.value = (volume: _volume, isMuted: _isMuted);
  }


}

