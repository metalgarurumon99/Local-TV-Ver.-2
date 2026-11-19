import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';
import '../models/media_item.dart';
import '../services/app_settings_service.dart';
import '../services/chapter_service.dart';
import '../services/thumbnail_service.dart';
import '../services/trickplay_service.dart';
import '../services/watch_history_service.dart';
import 'custom_app_title_bar.dart';
import 'hover_animated_widget.dart';


part 'player/player_youtube_layout.dart';
part 'player/player_popovers_overlay.dart';
part 'player/player_widgets.dart';
class InAppPlayer extends StatefulWidget {
  final MediaItem item;
  final VoidCallback onClose;
  final List<MediaItem> playlist;
  final List<MediaItem> allLibraryItems;
  final ValueChanged<MediaItem>? onMediaChanged;
  final bool isMiniplayer;
  final VoidCallback? onToggleMiniplayer;

  const InAppPlayer({
    super.key,
    required this.item,
    required this.onClose,
    this.playlist = const [],
    this.allLibraryItems = const [],
    this.onMediaChanged,
    this.isMiniplayer = false,
    this.onToggleMiniplayer,
  });

  static final RegExp _folderBadgeRegex = RegExp(r'^(.*?)\s*\[Folder:\s*([^\]]+)\]\s*$');

  /// Formats season names cleanly, stripping [Folder: ...] unless there is an identical base season name collision.
  static String formatSeasonDisplay(String rawName, List<String> allSeasonNames) {
    final match = _folderBadgeRegex.firstMatch(rawName.trim());
    if (match != null) {
      final base = match.group(1)!.trim();
      final badge = match.group(2)!.trim();
      int collisionCount = 0;
      for (final other in allSeasonNames) {
        final oMatch = _folderBadgeRegex.firstMatch(other.trim());
        final oBase = oMatch != null ? oMatch.group(1)!.trim() : other.trim();
        if (oBase.toLowerCase() == base.toLowerCase()) {
          collisionCount++;
        }
      }
      if (collisionCount > 1) {
        return '$base [Folder: $badge]';
      }
      return base;
    }
    return rawName.trim();
  }

  @override
  State<InAppPlayer> createState() => _InAppPlayerState();
}

class _InAppPlayerState extends State<InAppPlayer> with WindowListener {
  late final Player _player;
  late final VideoController _controller;
  late MediaItem _currentItem;
  late List<MediaItem> _currentPlaylist;

  bool _showControls = true;
  Timer? _hideTimer;
  Timer? _historyTimer;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<Duration> _durationNotifier = ValueNotifier<Duration>(Duration.zero);
  static double _persistedVolume = 100.0;
  double _volumeBeforeMute = 100.0;
  bool _isPlaying = true;
  double _volume = 100.0;
  bool _isFullScreen = true;
  bool _isClosingPlayer = false;
  bool _miniplayerHovered = false;
  final GlobalKey _playerSurfaceKey = GlobalKey();

  // Stream subscriptions & cancellable timers
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _autoPlayNextTimer;

  // Resume Watch History State
  int? _resumePositionMs;
  String? _resumeToastMessage;
  Timer? _resumeToastTimer;

  // Seamless First-Frame Poster Crossfade State
  bool _hasRenderedFirstFrame = false;
  Timer? _firstFrameFallbackTimer;

  // Track & Subtitle selection state
  Tracks _tracks = const Tracks();
  Track _currentTrack = const Track();
  bool _showAudioSubtitlePopover = false;
  bool _showEpisodesDrawer = false;
  bool _isHoveringEpisodeList = false;

  // Continuous Autoplay (Sleep Mode) State
  bool _continuousAutoplay = true;
  bool _isHandlingCompletion = false;

  // Season Selector State for YouTube-Style Right Sidebar & Netflix Fullscreen Drawer
  String _selectedSeason = 'Season 1';
  bool _isSeasonSelectorOpen = false;

  // Track state (audio & subtitle IDs)
  String? _activeAudioTrackId;
  String? _activeSubtitleTrackId;

  // On-Screen Volume HUD
  double? _hudVolume;
  double _lastHudVolume = 100.0;
  Timer? _hudVolumeTimer;

  // Memoized catalog & recommendation lookups (avoid O(N*M) scans on every build)
  String? _memoizedCatalogKey;
  MediaItem? _cachedSeriesCatalogItem;
  String? _memoizedRecsKey;
  List<MediaItem> _cachedRecommendations = const [];

  // Hover grace period timers for Audio/Subtitle and Episodes drawer
  Timer? _audioSubtitleHoverTimer;
  Timer? _episodesHoverTimer;

  // Chapters & Skip Intro State
  List<VideoChapter> _chapters = [];
  VideoChapter? _activeIntroChapter;

  // Trickplay seekbar scrubbing state
  TrickplayData? _trickplayData;

  // TV Broadcast "Now Watching" Corner Overlay State
  Timer? _tvOverlayTimer;
  Timer? _tvOverlayDismissTimer;
  bool _showTvOverlay = false;
  String _tvOverlayLine1 = 'Saat ini anda sedang menyaksikan';
  String _tvOverlayLine2 = '';

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _currentItem = widget.item;
    _currentPlaylist = List<MediaItem>.from(widget.playlist);
    _syncSelectedSeasonForCurrentItem();

    // Enable native libass rendering so subtitle styling is identical to original MPV
    _player = Player(
      configuration: const PlayerConfiguration(
        libass: true,
      ),
    );
    _volume = _persistedVolume.clamp(0.0, AppSettingsService.instance.maxVolume);
    if (_volume > 0) _volumeBeforeMute = _volume;
    _continuousAutoplay = AppSettingsService.instance.continuousAutoplay;
    _isFullScreen = !widget.isMiniplayer;
    _player.setVolume(_volume);
    _player.setRate(AppSettingsService.instance.defaultPlaybackSpeed);
    _controller = VideoController(_player);
    _controller.waitUntilFirstFrameRendered.then((_) {
      if (mounted && !_hasRenderedFirstFrame) {
        setState(() => _hasRenderedFirstFrame = true);
      }
    });

    _applyMpvSubtitleStyling();

    _loadResumePosition();

    _subscriptions.add(
      _player.stream.position.listen((pos) {
        if (!mounted) return;
        final firstFrameFlip = !_hasRenderedFirstFrame && pos > Duration.zero;
        final shouldNotifyPosition = (pos.inMilliseconds - _positionNotifier.value.inMilliseconds).abs() >= 200 || pos == Duration.zero;
        _position = pos;
        if (shouldNotifyPosition) {
          _positionNotifier.value = pos;
        }

        // Detect if playback is currently inside an intro chapter
        VideoChapter? intro;
        if (_chapters.isNotEmpty) {
          for (final ch in _chapters) {
            if (ch.isIntro && pos >= ch.start && pos < ch.end) {
              intro = ch;
              break;
            }
          }
        }
        final introChanged = intro != _activeIntroChapter;
        _activeIntroChapter = intro;

        // Only rebuild the full player tree on rare state transitions (first frame / intro boundary),
        // never on high-frequency 200ms position ticks!
        if (firstFrameFlip || introChanged) {
          setState(() {
            if (firstFrameFlip) _hasRenderedFirstFrame = true;
          });
        }
      }),
    );

    _subscriptions.add(
      _player.stream.duration.listen((dur) {
        if (!mounted) return;
        _duration = dur;
        _durationNotifier.value = dur;
        setState(() {});
        final activePath = _currentItem.videoPath;
        if (_trickplayData == null && dur > Duration.zero) {
          TrickplayService.instance.getOrGenerateTrickplay(activePath, dur).then((tp) {
            if (mounted && tp != null && _isSamePath(_currentItem.videoPath, activePath)) {
              setState(() => _trickplayData = tp);
            }
          });
        }
        if (dur > Duration.zero && _resumePositionMs != null) {
          final target = _resumePositionMs!;
          _resumePositionMs = null;
          _player.seek(Duration(milliseconds: target));
          _showResumeToast('Melanjutkan dari ${_formatDuration(Duration(milliseconds: target))}');
        }
      }),
    );

    _subscriptions.add(
      _player.stream.playing.listen((playing) {
        if (mounted) {
          setState(() {
            _isPlaying = playing;
            if (!_hasRenderedFirstFrame && playing && _position > Duration.zero) {
              _hasRenderedFirstFrame = true;
            }
          });
        }
      }),
    );

    _subscriptions.add(
      _player.stream.volume.listen((vol) {
        if (mounted) setState(() => _volume = vol);
        if (vol > 0) {
          _volumeBeforeMute = vol;
          _persistedVolume = vol;
        }
      }),
    );

    _subscriptions.add(
      _player.stream.tracks.listen((tracks) {
        if (mounted) {
          setState(() => _tracks = tracks);
          _syncActiveTracksFromMpv();
        }
      }),
    );

    _subscriptions.add(
      _player.stream.track.listen((track) {
        if (mounted) {
          setState(() => _currentTrack = track);
          _syncActiveTracksFromMpv();
        }
      }),
    );

    // Handle end-of-video event for continuous sleep playback across episodes & series
    _subscriptions.add(
      _player.stream.completed.listen((completed) {
        if (mounted) {
          if (!completed) {
            _isHandlingCompletion = false;
          } else if (!_isHandlingCompletion && !_isClosingPlayer && _continuousAutoplay) {
            _handlePlaybackCompleted();
          }
        }
      }),
    );

    // Enter OS fullscreen first while UI thread is idle (unless opened as miniplayer), then start playback seamlessly
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (!widget.isMiniplayer) {
        await _enterFullScreen();
      }
      if (mounted) {
        _startPlayback(_currentItem.videoPath);
      }
    });

    // Safety fallback timer so poster crossfades even on blank/instant start
    _firstFrameFallbackTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted && !_hasRenderedFirstFrame) {
        setState(() => _hasRenderedFirstFrame = true);
      }
    });

    // Periodic watch history saving every 4 seconds
    // Periodic watch history saving every 15 seconds to minimize disk I/O
    _historyTimer = Timer.periodic(const Duration(seconds: 15), (_) => _saveWatchProgress());

    _startHideTimer();
  }

  void _syncSelectedSeasonForCurrentItem() {
    if (_currentItem.episodes.isNotEmpty) {
      for (final ep in _currentItem.episodes) {
        if (ep.videoPath == _currentItem.videoPath || ep.id == _currentItem.id) {
          if (ep.seasonName.isNotEmpty) {
            _selectedSeason = ep.seasonName;
            return;
          }
        }
      }
      final seasons = _currentItem.availableSeasonNames;
      if (seasons.isNotEmpty) {
        _selectedSeason = seasons.first;
        return;
      }
    }
    _selectedSeason = 'Season 1';
  }

  Future<void> _loadResumePosition() async {
    final mediaId = _currentItem.seriesId ?? _currentItem.id;
    WatchHistoryEntry? syncEntry = WatchHistoryService.getProgressSync(
      mediaId,
      videoPath: _currentItem.videoPath,
    );
    syncEntry ??= WatchHistoryService.getProgressSync(
      mediaId,
      episodeId: _currentItem.id,
    );
    if (syncEntry != null && syncEntry.positionMs >= 2000 && !syncEntry.isCompleted) {
      _resumePositionMs = syncEntry.positionMs;
      return;
    }

    _resumePositionMs = null;
    final targetPath = _currentItem.videoPath;
    final entry = await WatchHistoryService.getProgress(
      mediaId,
      videoPath: targetPath,
    );
    if (!mounted || !_isSamePath(_currentItem.videoPath, targetPath)) return;
    if (entry != null && entry.positionMs >= 2000 && !entry.isCompleted) {
      _resumePositionMs = entry.positionMs;
      if (_duration > Duration.zero && _resumePositionMs != null) {
        final target = _resumePositionMs!;
        _resumePositionMs = null;
        _player.seek(Duration(milliseconds: target));
        _showResumeToast('Melanjutkan dari ${_formatDuration(Duration(milliseconds: target))}');
      }
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

  void _saveWatchProgress({bool forceCompleted = false}) {
    if (_duration.inMilliseconds <= 0 && !forceCompleted) return;
    if (_position.inMilliseconds < 2000 && !forceCompleted) return;

    final int posMs = forceCompleted ? _duration.inMilliseconds : _position.inMilliseconds;
    final int durMs = _duration.inMilliseconds > 0 ? _duration.inMilliseconds : (posMs > 0 ? posMs : 10000);
    final String mediaId = _currentItem.seriesId ?? _currentItem.id;
    final bool isCompleted = forceCompleted || (durMs > 0 && (posMs / durMs) >= 0.95);

    if (isCompleted) {
      final bool isSeries = _currentItem.isSeries || _currentItem.episodes.isNotEmpty || _currentItem.seriesId != null;
      final int currentIdx = _currentPlaylist.indexWhere((it) => _isSamePath(it.videoPath, _currentItem.videoPath));
      final bool isLastInPlaylist = _currentPlaylist.isEmpty || currentIdx == -1 || currentIdx >= _currentPlaylist.length - 1;
      if (!isSeries || isLastInPlaylist) {
        // Movie or final episode of series finished: remove from watch history
        WatchHistoryService.removeEntry(mediaId, videoPath: _currentItem.videoPath);
        return;
      }
    }

    WatchHistoryService.saveProgress(
      mediaId: mediaId,
      mediaTitle: _currentItem.seriesTitle ?? _currentItem.title,
      videoPath: _currentItem.videoPath,
      thumbnailPath: _currentItem.customThumbnail ?? _currentItem.thumbnailPath,
      category: _currentItem.category,
      isSeries: _currentItem.isSeries,
      episodeId: _currentItem.id,
      seasonNumber: _currentItem.seasonNumber,
      episodeNumber: _currentItem.episodeNumber,
      episodeTitle: _currentItem.episodeTitle,
      positionMs: posMs,
      durationMs: durMs,
    );
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted && !_isClosingPlayer && !_isFullScreen) {
      setState(() => _isFullScreen = true);
    }
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted && !_isClosingPlayer && _isFullScreen) {
      setState(() => _isFullScreen = false);
    }
  }

  Future<void> _exitFullScreen() async {
    try {
      final isAlreadyFull = await windowManager.isFullScreen();
      if (isAlreadyFull) {
        await windowManager.setFullScreen(false);
      }
      if (mounted && _isFullScreen) {
        setState(() => _isFullScreen = false);
      }
    } catch (e) {
      debugPrint('Exit fullscreen error: $e');
    }
  }

  Future<void> _enterFullScreen() async {
    try {
      final isAlreadyFull = await windowManager.isFullScreen();
      if (!isAlreadyFull) {
        await windowManager.setFullScreen(true);
      }
      if (mounted && !_isFullScreen) {
        setState(() => _isFullScreen = true);
      }
    } catch (e) {
      debugPrint('Enter fullscreen error: $e');
    }
  }

  Future<void> _toggleFullScreen() async {
    final isFull = _isFullScreen;
    if (isFull) {
      await _exitFullScreen();
    } else {
      await _enterFullScreen();
    }
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _hideTimer?.cancel();
    _historyTimer?.cancel();
    _resumeToastTimer?.cancel();
    _firstFrameFallbackTimer?.cancel();
    _hudVolumeTimer?.cancel();
    _audioSubtitleHoverTimer?.cancel();
    _episodesHoverTimer?.cancel();
    _tvOverlayTimer?.cancel();
    _tvOverlayDismissTimer?.cancel();
    _autoPlayNextTimer?.cancel();
    _positionNotifier.dispose();
    _durationNotifier.dispose();
    windowManager.removeListener(this);
    _saveWatchProgress();
    _player.dispose();
    if (_isFullScreen && !_isClosingPlayer) {
      windowManager.setFullScreen(false);
    }
    super.dispose();
  }

  void _changeVolume(double val) {
    final v = val.clamp(0.0, AppSettingsService.instance.maxVolume);
    if (v > 0) {
      _volumeBeforeMute = v;
      _persistedVolume = v;
    }
    _volume = v;
    _player.setVolume(v);
    _hudVolumeTimer?.cancel();
    setState(() {
      _hudVolume = v;
      _lastHudVolume = v;
    });
    _hudVolumeTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _hudVolume = null);
    });
    _onUserActivity();
  }

  void _toggleMute() {
    final target = _volume > 0 ? 0.0 : (_volumeBeforeMute > 0 ? _volumeBeforeMute : 100.0);
    _changeVolume(target);
  }

  void _closeAllPopoversInstantly() {
    _audioSubtitleHoverTimer?.cancel();
    _episodesHoverTimer?.cancel();
    if (_showAudioSubtitlePopover || _showEpisodesDrawer) {
      setState(() {
        _showAudioSubtitlePopover = false;
        _showEpisodesDrawer = false;
        _isSeasonSelectorOpen = false;
      });
    }
  }

  Future<void> _syncActiveTracksFromMpv() async {
    final dynamic platform = _player.platform;
    try {
      final aid = await platform.getProperty('aid');
      final sid = await platform.getProperty('sid');
      if (mounted) {
        setState(() {
          if (aid != null && aid.isNotEmpty && aid != 'auto' && aid != 'no') {
            _activeAudioTrackId = aid;
          } else {
            final realAudioTracks = _tracks.audio.where((t) => t.id != 'no' && t.id != 'auto').toList();
            AudioTrack? defaultTrack;
            for (final t in realAudioTracks) {
              if (t.isDefault == true) {
                defaultTrack = t;
                break;
              }
            }
            defaultTrack ??= realAudioTracks.isNotEmpty ? realAudioTracks.first : null;
            _activeAudioTrackId = defaultTrack?.id ?? _currentTrack.audio.id;
          }

          if (sid != null && sid.isNotEmpty && sid != 'auto') {
            _activeSubtitleTrackId = sid;
          } else {
            final realSubTracks = _tracks.subtitle.where((t) => t.id != 'no' && t.id != 'auto').toList();
            SubtitleTrack? defaultSub;
            for (final t in realSubTracks) {
              if (t.isDefault == true) {
                defaultSub = t;
                break;
              }
            }
            _activeSubtitleTrackId = defaultSub?.id ?? (sid == 'no' ? 'no' : _currentTrack.subtitle.id);
          }
        });
      }
    } catch (_) {}
  }

  bool _isSamePath(String a, String b) {
    if (a == b) return true;
    if (a.isEmpty || b.isEmpty) return false;
    return a.replaceAll('\\', '/').toLowerCase().trim() == b.replaceAll('\\', '/').toLowerCase().trim();
  }

  bool _isEpisodePlaying(Episode ep) {
    if (ep.videoPath.isNotEmpty && _currentItem.videoPath.isNotEmpty) {
      return _isSamePath(ep.videoPath, _currentItem.videoPath);
    }
    return ep.id == _currentItem.id;
  }

  void _playEpisodeFromDrawer(Episode ep, String seriesTitle, List<Episode> allEpisodes) {
    // Check if an item with matching path exists in _currentPlaylist
    for (final it in _currentPlaylist) {
      if (_isSamePath(it.videoPath, ep.videoPath) || it.id == ep.id) {
        _switchMedia(it);
        return;
      }
    }
    // Otherwise construct MediaItem from Episode
    final playItem = MediaItem(
      id: ep.id,
      title: '$seriesTitle - ${ep.title.isNotEmpty ? ep.title : "Episode ${ep.episodeNumber}"}',
      description: (ep.synopsis != null && ep.synopsis!.isNotEmpty) ? ep.synopsis! : _currentItem.description,
      genre: _currentItem.genre,
      maturity: _currentItem.maturity,
      category: _currentItem.category,
      videoPath: ep.videoPath,
      customThumbnail: ep.thumbnail ?? _currentItem.customThumbnail,
      year: _currentItem.year,
      rating: _currentItem.rating,
      isSeries: true,
      episodes: allEpisodes,
      seriesId: _currentItem.seriesId ?? _currentItem.id,
      seriesTitle: seriesTitle,
      seasonNumber: ep.season,
      episodeNumber: ep.episodeNumber,
      episodeTitle: ep.title,
      backdropUrl: _currentItem.backdropUrl,
      backdrop2Url: _currentItem.backdrop2Url,
      logoUrl: _currentItem.logoUrl,
    );
    _switchMedia(playItem);
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      _player.pause();
      setState(() => _showControls = true);
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
    final startMs = _resumePositionMs;
    if (startMs != null && startMs >= 2000) {
      _resumePositionMs = null; // Clear so stream.duration doesn't double-seek & double-toast
      _player.open(Media(path, start: Duration(milliseconds: startMs)));
      _showResumeToast('Melanjutkan dari ${_formatDuration(Duration(milliseconds: startMs))}');
    } else {
      _player.open(Media(path));
    }
    _loadChaptersAndTrickplay(path);
    _scheduleTvOverlay();
  }

  void _loadChaptersAndTrickplay(String path) {
    setState(() {
      _chapters = [];
      _activeIntroChapter = null;
      _trickplayData = null;
    });

    ChapterService.instance.getChapters(path).then((ch) {
      if (mounted && _isSamePath(_currentItem.videoPath, path)) {
        setState(() => _chapters = ch);
      }
    });

    if (_duration > Duration.zero) {
      TrickplayService.instance.getOrGenerateTrickplay(path, _duration).then((tp) {
        if (mounted && tp != null && _isSamePath(_currentItem.videoPath, path)) {
          setState(() => _trickplayData = tp);
        }
      });
    }
  }

  void _scheduleTvOverlay() {
    _tvOverlayTimer?.cancel();
    _tvOverlayDismissTimer?.cancel();
    _showTvOverlay = false;

    final isSeries = _currentItem.isSeries || _currentItem.episodes.isNotEmpty || _currentItem.seriesId != null;
    final epNum = _currentItem.episodeNumber ?? 1;
    final epNumStr = epNum.toString().padLeft(2, '0');
    final epTitle = _currentItem.episodeTitle?.trim() ?? '';

    _tvOverlayLine1 = 'Sedang Tayang';
    if (isSeries) {
      if (epTitle.isNotEmpty &&
          epTitle.toLowerCase() != 'episode $epNum' &&
          epTitle.toLowerCase() != 'ep $epNum' &&
          epTitle.toLowerCase() != 'episode $epNumStr') {
        _tvOverlayLine2 = 'Episode $epNumStr • $epTitle';
      } else {
        _tvOverlayLine2 = 'Episode $epNumStr';
      }
    } else {
      _tvOverlayLine2 = _currentItem.title.trim();
    }

    _tvOverlayTimer = Timer(const Duration(milliseconds: 3500), () {
      if (!mounted || !_isPlaying) return;
      setState(() => _showTvOverlay = true);

      _tvOverlayDismissTimer = Timer(const Duration(seconds: 6), () {
        if (mounted) setState(() => _showTvOverlay = false);
      });
    });
  }

  void _applyMpvSubtitleStyling() {
    final dynamic platform = _player.platform;
    final settings = AppSettingsService.instance;
    try {
      // Subtitle SSA/ASS Asli (Typesetting, Karaoke & Custom Fonts)
      platform.setProperty('sub-ass-override', 'no');
      platform.setProperty('embeddedfonts', 'yes');
      platform.setProperty('sub-auto', 'fuzzy');
      platform.setProperty('sub-visibility', 'yes');
      platform.setProperty('sid', 'auto');
      platform.setProperty('aid', 'auto');
      platform.setProperty('alang', '');
      final prefLang = settings.preferredSubtitleLanguage;
      platform.setProperty(
        'slang',
        prefLang == 'id' ? 'ind,id,ms' : (prefLang == 'en' ? 'eng,en' : ''),
      );

      // Subtitle styling non-ASS (Trebuchet MS, pure white, shadow, border)
      platform.setProperty('sub-font', 'Trebuchet MS');
      platform.setProperty('sub-font-size', '${settings.subtitleSize}');
      platform.setProperty('sub-color', '#FFFFFFFF');
      platform.setProperty('sub-border-color', '#FF111111');
      platform.setProperty('sub-border-size', '3.0');
      platform.setProperty('sub-shadow-offset', '1.2');
      platform.setProperty('sub-margin-y', '42');
      platform.setProperty('hwdec', 'auto-safe');
      // Respect Audio Boost setting (130% vs 100%)
      platform.setProperty('volume-max', settings.volumeBoostEnabled ? '130' : '100');
    } catch (e) {
      debugPrint('Error applying MPV subtitle styling: $e');
    }
  }

  void _resetPlaybackStateForNewMedia() {
    _autoPlayNextTimer?.cancel();
    _autoPlayNextTimer = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    _positionNotifier.value = Duration.zero;
    _durationNotifier.value = Duration.zero;
    _tracks = const Tracks();
    _currentTrack = const Track();
    _activeAudioTrackId = null;
    _activeSubtitleTrackId = null;
    _isHandlingCompletion = false;
    _hasRenderedFirstFrame = false;
    _chapters = [];
    _activeIntroChapter = null;
    _trickplayData = null;
  }

  void _switchMedia(MediaItem newItem) {
    _saveWatchProgress();
    _firstFrameFallbackTimer?.cancel();
    setState(() {
      _currentItem = newItem;
      _resetPlaybackStateForNewMedia();
      _syncSelectedSeasonForCurrentItem();
      _showEpisodesDrawer = false;
      _showAudioSubtitlePopover = false;
      _isSeasonSelectorOpen = false;
    });
    _firstFrameFallbackTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted && !_hasRenderedFirstFrame) {
        setState(() => _hasRenderedFirstFrame = true);
      }
    });
    widget.onMediaChanged?.call(newItem);
    _loadResumePosition();
    _startPlayback(newItem.videoPath);
    _onUserActivity();
  }

  void _handlePlaybackCompleted() {
    _isHandlingCompletion = true;
    _autoPlayNextTimer?.cancel();
    _saveWatchProgress(forceCompleted: true);

    final currentIndex = _currentPlaylist.indexWhere((it) => _isSamePath(it.videoPath, _currentItem.videoPath));
    if (currentIndex != -1 && currentIndex + 1 < _currentPlaylist.length) {
      final nextEp = _currentPlaylist[currentIndex + 1];
      final title = nextEp.episodeTitle?.isNotEmpty == true
          ? nextEp.episodeTitle!
          : (nextEp.episodeNumber != null ? 'Episode ${nextEp.episodeNumber}' : nextEp.title);
      _showResumeToast('Memutar episode berikutnya: $title');

      _autoPlayNextTimer = Timer(const Duration(milliseconds: 600), () {
        if (!mounted || _isClosingPlayer || !_continuousAutoplay) return;
        _switchMedia(nextEp);
      });
    } else {
      // Reached the end of current series or movie!
      // Pick next random series or film for continuous sleep playback.
      _showResumeToast('Memutar serial/film selanjutnya...');
      _autoPlayNextTimer = Timer(const Duration(milliseconds: 800), () {
        if (!mounted || _isClosingPlayer || !_continuousAutoplay) return;
        _playNextRandomSeriesOrFilm();
      });
    }
  }

  void _playNextRandomSeriesOrFilm() {
    if (widget.allLibraryItems.isEmpty) return;

    final currentSeriesOrMediaId = _currentItem.seriesId ?? _currentItem.id;

    // Filter playable items (series with episodes, or films with valid videoPath)
    final eligible = widget.allLibraryItems.where((it) {
      if (it.isSeries) {
        return it.episodes.isNotEmpty;
      } else {
        return it.videoPath.isNotEmpty && !it.videoPath.startsWith('asset:');
      }
    }).toList();

    if (eligible.isEmpty) return;

    // Exclude the current series or movie so it doesn't immediately repeat
    final others = eligible.where((it) {
      final itId = it.seriesId ?? it.id;
      return itId != currentSeriesOrMediaId;
    }).toList();

    final pool = others.isNotEmpty ? others : eligible;
    final randomChoice = pool[math.Random().nextInt(pool.length)];

    _showResumeToast('Memutar selanjutnya: ${randomChoice.title}');
    _playRecommendation(randomChoice);
  }

  void _playNextInPlaylist() {
    if (_currentPlaylist.isEmpty) return;
    final currentIndex = _currentPlaylist.indexWhere((it) => it.videoPath == _currentItem.videoPath);
    if (currentIndex != -1 && currentIndex + 1 < _currentPlaylist.length) {
      _switchMedia(_currentPlaylist[currentIndex + 1]);
    } else {
      _playNextRandomSeriesOrFilm();
    }
  }

  void _playRecommendation(MediaItem recItem) {
    if (recItem.isSeries && recItem.episodes.isNotEmpty) {
      final epPlaylist = recItem.episodes.map((ep) {
        final epDesc = (ep.synopsis != null && ep.synopsis!.isNotEmpty)
            ? ep.synopsis!
            : recItem.description;
        final epThumb = ep.thumbnail ?? recItem.customThumbnail;

        return MediaItem(
          id: ep.id,
          title: '${recItem.title} - ${ep.title.isNotEmpty ? ep.title : "Episode ${ep.episodeNumber}"}',
          description: epDesc,
          genre: recItem.genre,
          maturity: recItem.maturity,
          category: recItem.category,
          videoPath: ep.videoPath,
          customThumbnail: epThumb,
          year: recItem.year,
          rating: recItem.rating,
          isSeries: true,
          episodes: recItem.episodes,
          seriesId: recItem.id,
          seriesTitle: recItem.title,
          seasonNumber: ep.season,
          episodeNumber: ep.episodeNumber,
          episodeTitle: ep.title,
          backdropUrl: recItem.backdropUrl,
          logoUrl: recItem.logoUrl,
        );
      }).toList();

      final firstEp = epPlaylist.first;
      setState(() {
        _currentPlaylist = epPlaylist;
      });
      _switchMedia(firstEp);
    } else {
      setState(() {
        _currentPlaylist = [recItem];
      });
      _switchMedia(recItem);
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

  int _lastUserActivityTimestamp = 0;
  void _onUserActivity() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!_showControls) {
      setState(() => _showControls = true);
      _lastUserActivityTimestamp = now;
      _startHideTimer();
      return;
    }
    if (now - _lastUserActivityTimestamp > 300) {
      _lastUserActivityTimestamp = now;
      _startHideTimer();
    }
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

  static const Map<String, String> _languageFullNames = {
    // Asia
    'ja': 'Jepang',
    'jpn': 'Jepang',
    'id': 'Indonesia',
    'ind': 'Indonesia',
    'in': 'Indonesia',
    'en': 'Inggris',
    'eng': 'Inggris',
    'ko': 'Korea',
    'kor': 'Korea',
    'zh': 'Mandarin',
    'zho': 'Mandarin',
    'chi': 'Mandarin',
    'cmn': 'Mandarin',
    'yue': 'Kanton',
    'th': 'Thailand',
    'tha': 'Thailand',
    'vi': 'Vietnam',
    'vie': 'Vietnam',
    'tl': 'Filipina',
    'tgl': 'Filipina',
    'fil': 'Filipina',
    'ms': 'Melayu',
    'msa': 'Melayu',
    'may': 'Melayu',
    'hi': 'Hindi',
    'hin': 'Hindi',
    'bn': 'Bengali',
    'ben': 'Bengali',
    'ta': 'Tamil',
    'tam': 'Tamil',

    // Eropa & Barat
    'es': 'Spanyol',
    'spa': 'Spanyol',
    'fr': 'Prancis',
    'fra': 'Prancis',
    'fre': 'Prancis',
    'de': 'Jerman',
    'deu': 'Jerman',
    'ger': 'Jerman',
    'it': 'Italia',
    'ita': 'Italia',
    'pt': 'Portugis',
    'por': 'Portugis',
    'ru': 'Rusia',
    'rus': 'Rusia',
    'nl': 'Belanda',
    'nld': 'Belanda',
    'dut': 'Belanda',
    'tr': 'Turki',
    'tur': 'Turki',
    'pl': 'Polandia',
    'pol': 'Polandia',
    'uk': 'Ukraina',
    'ukr': 'Ukraina',
    'sv': 'Swedia',
    'swe': 'Swedia',
    'no': 'Norwegia',
    'nor': 'Norwegia',
    'da': 'Denmark',
    'dan': 'Denmark',
    'fi': 'Finlandia',
    'fin': 'Finlandia',
    'el': 'Yunani',
    'ell': 'Yunani',
    'gre': 'Yunani',
    'cs': 'Ceko',
    'ces': 'Ceko',
    'cze': 'Ceko',
    'hu': 'Hungaria',
    'hun': 'Hungaria',
    'ro': 'Rumania',
    'ron': 'Rumania',
    'rum': 'Rumania',

    // Timur Tengah & Lainnya
    'ar': 'Arab',
    'ara': 'Arab',
    'fa': 'Persia',
    'fas': 'Persia',
    'per': 'Persia',
    'he': 'Ibrani',
    'heb': 'Ibrani',
    'la': 'Latin',
    'lat': 'Latin',
  };

  String _getTrackName(dynamic track, String fallback, {int? index, int? totalWithSameLang}) {
    if (track == null) return fallback;
    final title = track.title as String?;
    final lang = track.language as String?;
    if (title != null && title.trim().isNotEmpty) {
      return title.trim();
    }
    if (lang != null && lang.trim().isNotEmpty) {
      final code = lang.trim().toLowerCase();
      final fullName = _languageFullNames[code] ?? code.toUpperCase();
      if (totalWithSameLang != null && totalWithSameLang > 1 && index != null) {
        return '$fullName (Trek $index)';
      }
      return fullName;
    }
    return fallback;
  }

  Widget _buildPosterThumbnail(MediaItem item) {
    // 1. Check backdropUrl / backdrop2Url / poster / episode stills from TMDB or local cache
    final candidates = <String?>[
      item.backdropUrl,
      item.backdrop2Url,
      item.customThumbnail,
    ];
    if (item.episodes.isNotEmpty) {
      for (final ep in item.episodes) {
        if (ep.thumbnail != null && ep.thumbnail!.isNotEmpty) {
          candidates.add(ep.thumbnail);
        }
      }
    }

    for (final c in candidates) {
      if (c != null && c.isNotEmpty) {
        if (c.startsWith('http://') || c.startsWith('https://')) {
          return Image.network(
            c,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
            cacheWidth: 480,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, _, _) => _buildLocalFallbackOrPlaceholder(item),
          );
        }
        if (LocalThumbnailService.fileExistsCached(c)) {
          final f = LocalThumbnailService.resolveFile(c);
          return Image.file(
            f,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
            cacheWidth: 480,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, _, _) => _buildLocalFallbackOrPlaceholder(item),
          );
        }
      }
    }

    return _buildLocalFallbackOrPlaceholder(item);
  }

  Widget _buildLocalFallbackOrPlaceholder(MediaItem item) {
    // 2. Check local extracted video thumbnail for primary video path or episode paths
    final videoCandidates = <String>[
      if (item.videoPath.isNotEmpty) item.videoPath,
      ...item.episodes.map((e) => e.videoPath).where((p) => p.isNotEmpty),
    ];

    for (final vp in videoCandidates) {
      if (LocalThumbnailService.hasThumbnail(vp)) {
        final path = LocalThumbnailService.getThumbnailPath(vp);
        if (LocalThumbnailService.fileExistsCached(path)) {
          final file = LocalThumbnailService.resolveFile(path);
          return Image.file(
            file,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
            cacheWidth: 360,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, _, _) => _buildThumbnailPlaceholder(),
          );
        }
      }
    }

    // 3. Custom thumbnail fallback
    if (item.customThumbnail != null && item.customThumbnail!.isNotEmpty) {
      if (item.isNetworkImage) {
        return Image.network(
          item.customThumbnail!,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          cacheWidth: 320,
          gaplessPlayback: true,
          filterQuality: FilterQuality.low,
          errorBuilder: (_, _, _) => _buildThumbnailPlaceholder(),
        );
      }
      if (LocalThumbnailService.fileExistsCached(item.customThumbnail!)) {
        final file = LocalThumbnailService.resolveFile(item.customThumbnail!);
        return Image.file(
          file,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          cacheWidth: 320,
          gaplessPlayback: true,
          filterQuality: FilterQuality.low,
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
  void didUpdateWidget(covariant InAppPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only re-initialize if the external parent actually changed widget.item to something different from _currentItem.
    // (When _switchMedia or _playRecommendation updates _currentItem internally and notifies onMediaChanged,
    // widget.item simply catches up to _currentItem — we must NOT overwrite _currentPlaylist with a stale widget.playlist.)
    if (widget.item.id != _currentItem.id || !_isSamePath(widget.item.videoPath, _currentItem.videoPath)) {
      _saveWatchProgress();
      _currentItem = widget.item;
      _currentPlaylist = List<MediaItem>.from(widget.playlist);
      _resetPlaybackStateForNewMedia();
      _syncSelectedSeasonForCurrentItem();
      _loadResumePosition();
      _startPlayback(_currentItem.videoPath);
    }
    if (oldWidget.isMiniplayer != widget.isMiniplayer) {
      if (widget.isMiniplayer) {
        _exitFullScreen();
        _miniplayerHovered = false;
      } else {
        // Expand back from miniplayer: Always return to YouTube-style windowed / theater layout!
        _isFullScreen = false;
        _onUserActivity();
      }
    }
  }

  Widget _buildMiniplayerView() {
    return Material(
      type: MaterialType.transparency,
      textStyle: const TextStyle(
        fontFamily: 'Roboto',
        decoration: TextDecoration.none,
      ),
      child: Container(
        width: 340,
        height: 192,
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white24, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.85),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: MouseRegion(
            onEnter: (_) => setState(() => _miniplayerHovered = true),
            onExit: (_) => setState(() => _miniplayerHovered = false),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1. Live Video Surface (subtitles already rendered natively by libass)
                Video(
                  controller: _controller,
                  fit: BoxFit.cover,
                  controls: NoVideoControls,
                  subtitleViewConfiguration: const SubtitleViewConfiguration(
                    visible: false,
                  ),
                ),

                // 2. Click whole surface: 1 click = pause/play, 2 clicks = expand back to YouTube view!
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      _togglePlayPause();
                    },
                    onDoubleTap: () {
                      _isFullScreen = false; // Always enter YouTube / Theater view!
                      widget.onToggleMiniplayer?.call();
                    },
                    child: const SizedBox.expand(),
                  ),
                ),

                // 3. Hover Overlay Controls with Smooth Fade & Interactive Buttons
                IgnorePointer(
                  ignoring: !_miniplayerHovered,
                  child: AnimatedOpacity(
                    opacity: _miniplayerHovered ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 180),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        // 1 click anywhere on miniplayer overlay = pause/play
                        _togglePlayPause();
                      },
                      onDoubleTap: () {
                        // 2 clicks anywhere on miniplayer overlay = expand back to YouTube view!
                        _isFullScreen = false;
                        widget.onToggleMiniplayer?.call();
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.88),
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.90),
                            ],
                            stops: const [0.0, 0.45, 1.0],
                          ),
                        ),
                        child: Stack(
                          children: [
                            // Top Row: Title left, Expand & Close buttons right
                            Positioned(
                              top: 4,
                              left: 10,
                              right: 4,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _currentItem.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        decoration: TextDecoration.none,
                                        shadows: [
                                          Shadow(color: Colors.black, blurRadius: 6),
                                        ],
                                      ),
                                    ),
                                  ),
                                  // Expand to Theater View
                                  IconButton(
                                    icon: const Icon(Icons.fullscreen, color: Colors.white, size: 22),
                                    splashRadius: 16,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                    onPressed: () {
                                      _isFullScreen = false; // Enter YouTube / Theater view!
                                      widget.onToggleMiniplayer?.call();
                                    },
                                  ),
                                  // Close Player completely
                                  IconButton(
                                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                                    splashRadius: 16,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                    onPressed: () {
                                      _isClosingPlayer = true;
                                      _saveWatchProgress();
                                      widget.onClose();
                                    },
                                  ),
                                ],
                              ),
                            ),

                            // Center Play/Pause button
                            Center(
                              child: InkWell(
                                onTap: () {
                                  _player.playOrPause();
                                },
                                borderRadius: BorderRadius.circular(28),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white30, width: 1),
                                  ),
                                  child: Icon(
                                    _isPlaying ? Icons.pause : Icons.play_arrow,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                              ),
                            ),

                            // Bottom Progress Indicator (Thin Red Line) - isolated rebuild via ValueListenableBuilder
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: ValueListenableBuilder<Duration>(
                                valueListenable: _positionNotifier,
                                builder: (context, pos, _) {
                                  final durMs = _durationNotifier.value.inMilliseconds;
                                  return LinearProgressIndicator(
                                    value: durMs > 0
                                        ? (pos.inMilliseconds / durMs).clamp(0.0, 1.0)
                                        : 0.0,
                                    backgroundColor: Colors.white24,
                                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE50914)),
                                    minHeight: 3,
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isMiniplayer) {
      return _buildMiniplayerView();
    }
    final playerBody = Focus(
      key: _playerSurfaceKey,
      autofocus: true,
      child: Listener(
        onPointerSignal: (pointerSignal) {
          if (_isFullScreen && pointerSignal is PointerScrollEvent && !_isHoveringEpisodeList && !_showEpisodesDrawer) {
            if (pointerSignal.scrollDelta.dy < 0) {
              _changeVolume(_volume + 5.0);
            } else if (pointerSignal.scrollDelta.dy > 0) {
              _changeVolume(_volume - 5.0);
            }
          }
        },
        child: MouseRegion(
          onHover: (_) => _onUserActivity(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: _toggleFullScreen,
            onTap: () {
              if (_showAudioSubtitlePopover || _showEpisodesDrawer) {
                setState(() {
                  _showAudioSubtitlePopover = false;
                  _showEpisodesDrawer = false;
                });
                return;
              }
              _togglePlayPause();
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

                  // First-Frame Poster Crossfade & Cinema Dimming Layer
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: _hasRenderedFirstFrame,
                      child: AnimatedOpacity(
                        opacity: _hasRenderedFirstFrame ? 0.0 : 1.0,
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOutCubic,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _buildPosterThumbnail(_currentItem),
                            // Cinematic ambient vignette & dimming
                            Container(
                              decoration: BoxDecoration(
                                gradient: RadialGradient(
                                  center: Alignment.center,
                                  radius: 1.1,
                                  colors: [
                                    Colors.black.withValues(alpha: 0.35),
                                    Colors.black.withValues(alpha: 0.90),
                                  ],
                                ),
                              ),
                            ),
                            // Subtle luxury spinner while waiting for first video frame
                            if (!_hasRenderedFirstFrame)
                              const Center(
                                child: SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3.0,
                                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE50914)),
                                  ),
                                ),
                              ),
                          ],
                        ),
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

                  // MPV-Style Vertical Volume Overlay on Right Corner (kept mounted so AnimatedOpacity fades smoothly)
                  Positioned(
                    right: 64,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      ignoring: _hudVolume == null,
                      child: Center(
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 180),
                          opacity: _hudVolume != null ? 1.0 : 0.0,
                          child: SizedBox(
                            width: 60, // Fixed width ensures 1, 2, or 3 digits never shift the horizontal center
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Pure integer only, centered in fixed width container
                                SizedBox(
                                  width: 60,
                                  child: Text(
                                    '${(_hudVolume ?? _lastHudVolume).round()}',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.85),
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.5,
                                      shadows: const [
                                        Shadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 1)),
                                        Shadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 2)),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),

                                // Vertical MPV bar with 100% notch line - Larger and semi-transparent
                                Container(
                                  width: 24,
                                  height: 240,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.35),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.65),
                                      width: 2.2,
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black45,
                                        blurRadius: 12,
                                        offset: Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(2),
                                    child: Stack(
                                      children: [
                                        // Fill from bottom - semi-transparent white
                                        Align(
                                          alignment: Alignment.bottomCenter,
                                          child: Container(
                                            width: double.infinity,
                                            height: 240 * ((_hudVolume ?? _lastHudVolume) / 130.0).clamp(0.0, 1.0),
                                            color: Colors.white.withValues(alpha: 0.65),
                                          ),
                                        ),
                                        // MPV Notch at nominal 100% mark (100 / 130 = ~76.9%)
                                        Positioned(
                                          bottom: 240 * (100.0 / 130.0) - 1,
                                          left: 0,
                                          right: 0,
                                          child: Container(
                                            height: 2,
                                            color: Colors.black.withValues(alpha: 0.6),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),

                                // Speaker icon at bottom
                                Icon(
                                  (_hudVolume ?? _lastHudVolume) == 0
                                      ? Icons.volume_off_rounded
                                      : ((_hudVolume ?? _lastHudVolume) < 65
                                          ? Icons.volume_down_rounded
                                          : Icons.volume_up_rounded),
                                  color: Colors.white.withValues(alpha: 0.85),
                                  size: 26,
                                  shadows: const [
                                    Shadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 1)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
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
                          // Background Gesture Detector: 1 click = pause/play, 2 clicks = fullscreen
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTap: () {
                                if (_showAudioSubtitlePopover || _showEpisodesDrawer) {
                                  setState(() {
                                    _showAudioSubtitlePopover = false;
                                    _showEpisodesDrawer = false;
                                    _isSeasonSelectorOpen = false;
                                  });
                                  return;
                                }
                                _togglePlayPause();
                              },
                              onDoubleTap: _toggleFullScreen,
                              child: const SizedBox.expand(),
                            ),
                          ),

                          // Top Bar Back button & Title
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: Container(
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
                                      _isClosingPlayer = true;
                                      _saveWatchProgress();
                                      if (_isFullScreen) {
                                        try {
                                          await windowManager.setFullScreen(false);
                                        } catch (_) {}
                                      }
                                      if (mounted) widget.onClose();
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
                                            '${_currentItem.genre}${_currentItem.year != null ? "   •   ${_currentItem.year}" : ""}',
                                            style: const TextStyle(color: Colors.white60, fontSize: 12),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  // Top-Right: Miniplayer Toggle Button (No tooltip)
                                  IconButton(
                                    icon: const Icon(Icons.picture_in_picture_alt, color: Colors.white, size: 26),
                                    onPressed: () async {
                                      if (_isFullScreen) {
                                        try {
                                          await windowManager.setFullScreen(false);
                                        } catch (_) {}
                                        _isFullScreen = false;
                                      }
                                      if (mounted) widget.onToggleMiniplayer?.call();
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),

                      // Netflix-Style Audio & Subtitles Popover (with hover grace period)
                      if (_showAudioSubtitlePopover)
                        Positioned(
                          bottom: 90,
                          right: 60,
                          child: MouseRegion(
                            onEnter: (_) => _audioSubtitleHoverTimer?.cancel(),
                            onExit: (_) {
                              _audioSubtitleHoverTimer?.cancel();
                              _audioSubtitleHoverTimer = Timer(const Duration(milliseconds: 260), () {
                                if (mounted) setState(() => _showAudioSubtitlePopover = false);
                              });
                            },
                            child: _buildNetflixAudioSubtitleMenu(),
                          ),
                        ),

                      // Bottom Control Bar (Completely sterilized from passing taps to video background)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {},
                          onDoubleTap: () {},
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
                                // Timeline Scrubber with Trickplay Preview & Chapter Notches (isolated position rebuild)
                                ValueListenableBuilder<Duration>(
                                  valueListenable: _positionNotifier,
                                  builder: (context, pos, _) => _PlayerSeekBar(
                                    position: pos,
                                    duration: _durationNotifier.value,
                                    chapters: _chapters,
                                    trickplayData: _trickplayData,
                                    onSeek: (target) {
                                      _position = target;
                                      _positionNotifier.value = target;
                                      _player.seek(target);
                                    },
                                    onActivity: _onUserActivity,
                                  ),
                                ),

                                Row(
                                  children: [
                                    // Play/Pause
                                    MouseRegion(
                                      onEnter: (_) => _closeAllPopoversInstantly(),
                                      child: IconButton(
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
                                    ),
                                    const SizedBox(width: 6),

                                    // Fast Backward 10s
                                    MouseRegion(
                                      onEnter: (_) => _closeAllPopoversInstantly(),
                                      child: IconButton(
                                        icon: const Icon(Icons.replay_10, color: Colors.white70, size: 24),
                                        onPressed: () {
                                          final target = _position - const Duration(seconds: 10);
                                          _player.seek(target < Duration.zero ? Duration.zero : target);
                                          _onUserActivity();
                                        },
                                      ),
                                    ),

                                    // Fast Forward 10s
                                    MouseRegion(
                                      onEnter: (_) => _closeAllPopoversInstantly(),
                                      child: IconButton(
                                        icon: const Icon(Icons.forward_10, color: Colors.white70, size: 24),
                                        onPressed: () {
                                          final target = _position + const Duration(seconds: 10);
                                          _player.seek(target > _duration ? _duration : target);
                                          _onUserActivity();
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),

                                    // Next Video / Episode button
                                    if (_currentPlaylist.isNotEmpty)
                                      MouseRegion(
                                        onEnter: (_) => _closeAllPopoversInstantly(),
                                        child: IconButton(
                                          icon: const Icon(Icons.skip_next_rounded, color: Colors.white70, size: 26),
                                          onPressed: _playNextInPlaylist,
                                        ),
                                      ),

                                    const SizedBox(width: 8),

                                    // Time Label (isolated position rebuild)
                                    ValueListenableBuilder<Duration>(
                                      valueListenable: _positionNotifier,
                                      builder: (context, pos, _) => Text(
                                        '${_formatDuration(pos)} / ${_formatDuration(_durationNotifier.value)}',
                                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                                      ),
                                    ),

                                    const Spacer(),

                                    // Volume Icon
                                    IconButton(
                                      icon: Icon(
                                        _volume == 0
                                            ? Icons.volume_off
                                            : (_volume < 65 ? Icons.volume_down : Icons.volume_up),
                                        color: Colors.white,
                                        size: 22,
                                      ),
                                      onPressed: _toggleMute,
                                    ),
                                    // Volume Slider - Extended Width (130px) & Max 130 matching MPV
                                    SizedBox(
                                      width: 130,
                                      child: SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          activeTrackColor: Colors.white,
                                          inactiveTrackColor: Colors.white24,
                                          thumbColor: Colors.white,
                                          trackHeight: 3,
                                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                                        ),
                                        child: Slider(
                                          value: _volume.clamp(0.0, 130.0),
                                          min: 0.0,
                                          max: 130.0,
                                          onChanged: (val) {
                                            _changeVolume(val);
                                          },
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),

                                    // Sleep / Continuous Autoplay Mode Toggle Button (No tooltip per request #7)
                                    MouseRegion(
                                      onEnter: (_) => _closeAllPopoversInstantly(),
                                      child: IconButton(
                                        icon: Icon(
                                          _continuousAutoplay ? Icons.bedtime_rounded : Icons.bedtime_outlined,
                                          color: _continuousAutoplay ? const Color(0xFFE50914) : Colors.white70,
                                          size: 22,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _continuousAutoplay = !_continuousAutoplay;
                                          });
                                          _showResumeToast(
                                            _continuousAutoplay
                                                ? 'Mode Tidur diaktifkan'
                                                : 'Mode Tidur dinonaktifkan',
                                          );
                                          _onUserActivity();
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),

                                    // Netflix-Style: Episodes Button (Hover flyout + click toggle in fullscreen mode)
                                    if (_isFullScreen && _currentPlaylist.isNotEmpty)
                                      MouseRegion(
                                        onEnter: (_) {
                                          _episodesHoverTimer?.cancel();
                                          _audioSubtitleHoverTimer?.cancel();
                                          setState(() {
                                            _showEpisodesDrawer = true;
                                            _showAudioSubtitlePopover = false;
                                          });
                                        },
                                        onExit: (_) {
                                          _episodesHoverTimer?.cancel();
                                          _episodesHoverTimer = Timer(const Duration(milliseconds: 260), () {
                                            if (mounted) setState(() => _showEpisodesDrawer = false);
                                          });
                                        },
                                        child: IconButton(
                                          icon: Icon(
                                            Icons.video_library_rounded,
                                            color: _showEpisodesDrawer ? const Color(0xFFE50914) : Colors.white,
                                            size: 24,
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              _showEpisodesDrawer = !_showEpisodesDrawer;
                                              _showAudioSubtitlePopover = false;
                                            });
                                            _onUserActivity();
                                          },
                                        ),
                                      ),

                                    // Netflix-Style: Audio & Subtitles Button (Hover flyout + click toggle)
                                    MouseRegion(
                                      onEnter: (_) {
                                        _audioSubtitleHoverTimer?.cancel();
                                        _episodesHoverTimer?.cancel();
                                        _syncActiveTracksFromMpv();
                                        setState(() {
                                          _showAudioSubtitlePopover = true;
                                          _showEpisodesDrawer = false;
                                        });
                                      },
                                      onExit: (_) {
                                        _audioSubtitleHoverTimer?.cancel();
                                        _audioSubtitleHoverTimer = Timer(const Duration(milliseconds: 260), () {
                                          if (mounted) setState(() => _showAudioSubtitlePopover = false);
                                        });
                                      },
                                      child: IconButton(
                                        icon: Icon(
                                          Icons.chat_bubble_outline_rounded,
                                          color: _showAudioSubtitlePopover ? const Color(0xFFE50914) : Colors.white,
                                          size: 24,
                                        ),
                                        onPressed: () {
                                          _syncActiveTracksFromMpv();
                                          setState(() {
                                            _showAudioSubtitlePopover = !_showAudioSubtitlePopover;
                                            _showEpisodesDrawer = false;
                                          });
                                          _onUserActivity();
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 4),

                                    // Netflix-Style: Fullscreen Button (No tooltip)
                                    MouseRegion(
                                      onEnter: (_) => _closeAllPopoversInstantly(),
                                      child: IconButton(
                                        icon: Icon(
                                          _isFullScreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                                          color: Colors.white,
                                          size: 26,
                                        ),
                                        onPressed: () {
                                          _toggleFullScreen();
                                          _onUserActivity();
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Netflix-Style Episodes Card / Pop-up (Max Half Screen Height in fullscreen mode)
              if (_isFullScreen && _showEpisodesDrawer && _currentPlaylist.isNotEmpty)
                Positioned(
                  bottom: 85,
                  right: 24,
                  child: MouseRegion(
                    onEnter: (_) {
                      _isHoveringEpisodeList = true;
                      _episodesHoverTimer?.cancel();
                    },
                    onExit: (_) {
                      _isHoveringEpisodeList = false;
                      _episodesHoverTimer?.cancel();
                      _episodesHoverTimer = Timer(const Duration(milliseconds: 260), () {
                        if (mounted) {
                          setState(() {
                            _showEpisodesDrawer = false;
                            _isHoveringEpisodeList = false;
                          });
                        }
                      });
                    },
                    child: _buildNetflixEpisodesPopup(),
                  ),
                ),

              // Skip Intro Button (Bottom Right)
              if (_activeIntroChapter != null)
                Positioned(
                  bottom: _showControls ? 95 : 35,
                  right: 32,
                  child: _buildSkipIntroButton(_activeIntroChapter!),
                ),

              // TV Broadcast "Now Watching" Overlay (Top Right - kept mounted so AnimatedSlide/Opacity animate smoothly)
              Positioned(
                top: 28,
                right: 32,
                child: IgnorePointer(
                  ignoring: !_showTvOverlay,
                  child: _buildTvBroadcastOverlay(),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    ),
  );

    final Widget content = Material(color: Colors.black, child: _isFullScreen ? playerBody : _buildYoutubeStyleWindowed(playerBody));

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF): _toggleFullScreen,
        const SingleActivator(LogicalKeyboardKey.space): _togglePlayPause,
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _seekRelative(const Duration(seconds: 10)),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _seekRelative(const Duration(seconds: -10)),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _changeVolume(_volume + 5.0),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _changeVolume(_volume - 5.0),
        const SingleActivator(LogicalKeyboardKey.keyM): _toggleMute,
        const SingleActivator(LogicalKeyboardKey.escape): () async {
          if (_isFullScreen) {
            await _exitFullScreen();
          } else {
            _isClosingPlayer = true;
            _saveWatchProgress();
            widget.onClose();
          }
        },
      },
      child: content,
    );
  }

  void _updateState(VoidCallback fn) {
    if (mounted) setState(fn);
  }
}
