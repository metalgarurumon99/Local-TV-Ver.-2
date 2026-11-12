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
import '../services/chapter_service.dart';
import '../services/thumbnail_service.dart';
import '../services/trickplay_service.dart';
import '../services/watch_history_service.dart';
import 'custom_app_title_bar.dart';
import 'hover_animated_widget.dart';

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
  static double _persistedVolume = 100.0;
  bool _isPlaying = true;
  double _volume = 100.0;
  bool _isFullScreen = true;
  bool _isClosingPlayer = false;
  bool _miniplayerHovered = false;
  final GlobalKey _playerSurfaceKey = GlobalKey();

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
  Timer? _hudVolumeTimer;

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
    _volume = _persistedVolume;
    _player.setVolume(_persistedVolume);
    _controller = VideoController(_player);
    _controller.waitUntilFirstFrameRendered.then((_) {
      if (mounted && !_hasRenderedFirstFrame) {
        setState(() => _hasRenderedFirstFrame = true);
      }
    });

    _applyMpvSubtitleStyling();

    _loadResumePosition();

    _player.stream.position.listen((pos) {
      if (mounted) {
        final firstFrameFlip = !_hasRenderedFirstFrame && pos > Duration.zero;
        final shouldRebuildControls = _showControls && (pos.inMilliseconds - _position.inMilliseconds).abs() >= 200;
        _position = pos;

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

        if (firstFrameFlip || shouldRebuildControls || introChanged) {
          setState(() {
            if (firstFrameFlip) _hasRenderedFirstFrame = true;
          });
        }
      }
    });

    _player.stream.duration.listen((dur) {
      if (mounted) {
        setState(() => _duration = dur);
        if (_trickplayData == null && dur > Duration.zero) {
          TrickplayService.instance.getOrGenerateTrickplay(_currentItem.videoPath, dur).then((tp) {
            if (mounted && tp != null) {
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
      }
    });

    _player.stream.playing.listen((playing) {
      if (mounted) {
        setState(() {
          _isPlaying = playing;
          if (!_hasRenderedFirstFrame && playing && _position > Duration.zero) {
            _hasRenderedFirstFrame = true;
          }
        });
      }
    });

    _player.stream.volume.listen((vol) {
      if (mounted) setState(() => _volume = vol);
      _persistedVolume = vol;
    });

    _player.stream.tracks.listen((tracks) {
      if (mounted) {
        setState(() => _tracks = tracks);
        _syncActiveTracksFromMpv();
      }
    });

    _player.stream.track.listen((track) {
      if (mounted) {
        setState(() => _currentTrack = track);
        _syncActiveTracksFromMpv();
      }
    });

    // Handle end-of-video event for continuous sleep playback across episodes & series
    _player.stream.completed.listen((completed) {
      if (mounted) {
        if (!completed) {
          _isHandlingCompletion = false;
        } else if (!_isHandlingCompletion && !_isClosingPlayer && _continuousAutoplay) {
          _handlePlaybackCompleted();
        }
      }
    });

    // Enter OS fullscreen first while UI thread is idle, then start playback seamlessly
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _enterFullScreen();
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
    final entry = await WatchHistoryService.getProgress(
      mediaId,
      videoPath: _currentItem.videoPath,
    );
    if (entry != null && entry.positionMs >= 2000 && !entry.isCompleted) {
      _resumePositionMs = entry.positionMs;
      if (mounted && _duration > Duration.zero && _resumePositionMs != null) {
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

    WatchHistoryService.saveProgress(
      mediaId: _currentItem.seriesId ?? _currentItem.id,
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
    _hideTimer?.cancel();
    _historyTimer?.cancel();
    _resumeToastTimer?.cancel();
    _firstFrameFallbackTimer?.cancel();
    _hudVolumeTimer?.cancel();
    _audioSubtitleHoverTimer?.cancel();
    _episodesHoverTimer?.cancel();
    _tvOverlayTimer?.cancel();
    _tvOverlayDismissTimer?.cancel();
    windowManager.removeListener(this);
    _saveWatchProgress();
    _player.dispose();
    if (_isFullScreen && !_isClosingPlayer) {
      windowManager.setFullScreen(false);
    }
    super.dispose();
  }

  void _changeVolume(double val) {
    final v = val.clamp(0.0, 130.0);
    _persistedVolume = v;
    _volume = v;
    _player.setVolume(v);
    _hudVolumeTimer?.cancel();
    setState(() {
      _hudVolume = v;
    });
    _hudVolumeTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _hudVolume = null);
    });
    _onUserActivity();
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
    if (_isSamePath(ep.videoPath, _currentItem.videoPath)) return true;
    if (ep.id == _currentItem.id) return true;
    if (_currentItem.episodeNumber != null && ep.episodeNumber == _currentItem.episodeNumber) {
      if (_currentItem.seasonNumber != null && ep.season == _currentItem.seasonNumber) {
        return true;
      }
    }
    return false;
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
      if (mounted) {
        setState(() => _chapters = ch);
      }
    });

    if (_duration > Duration.zero) {
      TrickplayService.instance.getOrGenerateTrickplay(path, _duration).then((tp) {
        if (mounted && tp != null) {
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

    _tvOverlayLine1 = 'Saat ini anda sedang menyaksikan';
    if (isSeries) {
      if (epTitle.isNotEmpty &&
          epTitle.toLowerCase() != 'episode $epNum' &&
          epTitle.toLowerCase() != 'ep $epNum' &&
          epTitle.toLowerCase() != 'episode $epNumStr') {
        _tvOverlayLine2 = 'Episode "$epNumStr" - $epTitle';
      } else {
        _tvOverlayLine2 = 'Episode "$epNumStr"';
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
    try {
      // Subtitle SSA/ASS Asli (Typesetting, Karaoke & Custom Fonts)
      platform.setProperty('sub-ass-override', 'no');
      platform.setProperty('embeddedfonts', 'yes');
      platform.setProperty('sub-auto', 'fuzzy');
      platform.setProperty('sub-visibility', 'yes');
      platform.setProperty('sid', 'auto');
      platform.setProperty('aid', 'auto');
      platform.setProperty('alang', '');
      platform.setProperty('slang', '');

      // Subtitle styling non-ASS (Trebuchet MS, pure white, shadow, border)
      platform.setProperty('sub-font', 'Trebuchet MS');
      platform.setProperty('sub-font-size', '46');
      platform.setProperty('sub-color', '#FFFFFFFF');
      platform.setProperty('sub-border-color', '#FF111111');
      platform.setProperty('sub-border-size', '3.0');
      platform.setProperty('sub-shadow-offset', '1.2');
      platform.setProperty('sub-margin-y', '42');
      platform.setProperty('hwdec', 'auto-safe');
      // Set volume-max to 130 matching native MPV audio amplification behavior
      platform.setProperty('volume-max', '130');
    } catch (e) {
      debugPrint('Error applying MPV subtitle styling: $e');
    }
  }

  void _switchMedia(MediaItem newItem) {
    _saveWatchProgress();
    _firstFrameFallbackTimer?.cancel();
    setState(() {
      _currentItem = newItem;
      _syncSelectedSeasonForCurrentItem();
      _hasRenderedFirstFrame = false;
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
    _saveWatchProgress(forceCompleted: true);

    final currentIndex = _currentPlaylist.indexWhere((it) => it.videoPath == _currentItem.videoPath);
    if (currentIndex != -1 && currentIndex + 1 < _currentPlaylist.length) {
      final nextEp = _currentPlaylist[currentIndex + 1];
      final title = nextEp.episodeTitle?.isNotEmpty == true
          ? nextEp.episodeTitle!
          : (nextEp.episodeNumber != null ? 'Episode ${nextEp.episodeNumber}' : nextEp.title);
      _showResumeToast('Memutar episode berikutnya: $title');

      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted || _isClosingPlayer) return;
        _switchMedia(nextEp);
      });
    } else {
      // Reached the end of current series or movie!
      // Pick next random series or film for continuous sleep playback.
      _showResumeToast('Memutar serial/film selanjutnya...');
      Future.delayed(const Duration(milliseconds: 800), () {
        if (!mounted || _isClosingPlayer) return;
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
        final f = LocalThumbnailService.resolveFile(c);
        if (LocalThumbnailService.fileExistsCached(f.path) || f.existsSync()) {
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
        final file = LocalThumbnailService.resolveFile(path);
        if (file.existsSync() || LocalThumbnailService.fileExistsCached(path)) {
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
      final file = LocalThumbnailService.resolveFile(item.customThumbnail!);
      if (LocalThumbnailService.fileExistsCached(file.path) || file.existsSync()) {
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
    if (widget.item.id != _currentItem.id || widget.item.videoPath != _currentItem.videoPath) {
      _saveWatchProgress();
      _currentItem = widget.item;
      _currentPlaylist = List<MediaItem>.from(widget.playlist);
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
                // 1. Live Video Surface with Subtitles
                Video(
                  controller: _controller,
                  fit: BoxFit.cover,
                  controls: NoVideoControls,
                  subtitleViewConfiguration: const SubtitleViewConfiguration(
                    visible: true,
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

                            // Bottom Progress Indicator (Thin Red Line)
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: LinearProgressIndicator(
                                value: _duration.inMilliseconds > 0
                                    ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
                                    : 0.0,
                                backgroundColor: Colors.white24,
                                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE50914)),
                                minHeight: 3,
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

                  // MPV-Style Vertical Volume Overlay on Right Corner (per request #4)
                  if (_hudVolume != null)
                    Positioned(
                      right: 64,
                      top: 0,
                      bottom: 0,
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
                                    '${_hudVolume!.round()}',
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
                                            height: 240 * (_hudVolume! / 130.0).clamp(0.0, 1.0),
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
                                  _hudVolume == 0
                                      ? Icons.volume_off_rounded
                                      : (_hudVolume! < 65 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
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
                                        await windowManager.setFullScreen(false);
                                      }
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
                                        await windowManager.setFullScreen(false);
                                        _isFullScreen = false;
                                      }
                                      widget.onToggleMiniplayer?.call();
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
                                // Timeline Scrubber with Trickplay Preview & Chapter Notches
                                _PlayerSeekBar(
                                  position: _position,
                                  duration: _duration,
                                  chapters: _chapters,
                                  trickplayData: _trickplayData,
                                  onSeek: (target) => _player.seek(target),
                                  onActivity: _onUserActivity,
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
                                    if (widget.playlist.isNotEmpty)
                                      MouseRegion(
                                        onEnter: (_) => _closeAllPopoversInstantly(),
                                        child: IconButton(
                                          icon: const Icon(Icons.skip_next_rounded, color: Colors.white70, size: 26),
                                          onPressed: _playNextInPlaylist,
                                        ),
                                      ),

                                    const SizedBox(width: 8),

                                    // Time Label
                                    Text(
                                      '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                                      style: const TextStyle(color: Colors.white70, fontSize: 13),
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
                                      onPressed: () {
                                        final target = _volume > 0 ? 0.0 : (_persistedVolume > 0 ? _persistedVolume : 100.0);
                                        _changeVolume(target);
                                      },
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

              // TV Broadcast "Now Watching" Overlay (Top Left)
              if (_showTvOverlay)
                Positioned(
                  top: 28,
                  left: 32,
                  child: _buildTvBroadcastOverlay(),
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
        const SingleActivator(LogicalKeyboardKey.keyM): () {
          final target = _volume > 0 ? 0.0 : (_persistedVolume > 0 ? _persistedVolume : 100.0);
          _changeVolume(target);
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
      child: content,
    );
  }

  /// YouTube-Style Non-Fullscreen Layout:
  /// Left: 16:9 Player + Title + Meta + Synopsis + "Rekomendasi Lainnya"
  /// Right: YouTube-style playlist sidebar (Daftar Episode / Playlist)
  Widget _buildYoutubeStyleWindowed(Widget playerBody) {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      body: Column(
        children: [
          RepaintBoundary(
            child: const CustomAppTitleBar(
              isTransparent: false,
              isPlayerMode: true,
            ),
          ),

          // Main YouTube Split View
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Area: 16:9 Video Box + Metadata + Recommendations
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 16, 20, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 16:9 Video Box
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: playerBody,
                          ),
                        ),
                        const SizedBox(height: 18),

                        // Baris 1: Judul series/film
                        // Baris 2: Episode "XX" - Judul episode (jika ada) [untuk series]
                        Builder(
                          builder: (context) {
                            final isSeries = _currentItem.isSeries ||
                                widget.item.isSeries ||
                                _currentItem.seriesTitle != null ||
                                widget.item.seriesTitle != null ||
                                _currentItem.episodes.isNotEmpty ||
                                widget.item.episodes.isNotEmpty;

                            Episode? matchedEp;
                            final epList = widget.item.episodes.isNotEmpty ? widget.item.episodes : _currentItem.episodes;
                            if (isSeries && epList.isNotEmpty) {
                              for (final ep in epList) {
                                if (_isSamePath(ep.videoPath, _currentItem.videoPath) || ep.id == _currentItem.id) {
                                  matchedEp = ep;
                                  break;
                                }
                              }
                            }

                            final catalogItem = _resolveSeriesCatalogItem();
                            final String mainTitle = isSeries
                                ? (catalogItem?.title.trim().isNotEmpty == true
                                    ? catalogItem!.title.trim()
                                    : _getSeriesTitle(_currentItem))
                                : _currentItem.title;

                            String? epSubtitle;
                            if (isSeries && matchedEp != null) {
                              final epNum = matchedEp.episodeNumber > 0
                                  ? matchedEp.episodeNumber.toString().padLeft(2, '0')
                                  : '01';
                              String rawTitle = matchedEp.title.trim();
                              final prefix = '$mainTitle - ';
                              if (rawTitle.startsWith(prefix)) {
                                rawTitle = rawTitle.substring(prefix.length).trim();
                              }
                              final hasCustomTitle = rawTitle.isNotEmpty &&
                                  rawTitle.toLowerCase() != 'episode ${matchedEp.episodeNumber}' &&
                                  rawTitle.toLowerCase() != 'episode $epNum' &&
                                  rawTitle.toLowerCase() != 'ep ${matchedEp.episodeNumber}';
                              epSubtitle = hasCustomTitle ? 'Episode $epNum - $rawTitle' : 'Episode $epNum';
                            } else if (isSeries) {
                              final epNum = _currentItem.episodeNumber != null && _currentItem.episodeNumber! > 0
                                  ? _currentItem.episodeNumber!.toString().padLeft(2, '0')
                                  : null;
                              String rawTitle = _currentItem.episodeTitle?.trim() ?? '';
                              if (rawTitle.isEmpty) {
                                final prefix = '$mainTitle - ';
                                if (_currentItem.title.startsWith(prefix)) {
                                  rawTitle = _currentItem.title.substring(prefix.length).trim();
                                }
                              }
                              final hasCustomTitle = rawTitle.isNotEmpty &&
                                  rawTitle.toLowerCase() != 'episode ${_currentItem.episodeNumber}' &&
                                  rawTitle.toLowerCase() != 'episode $epNum' &&
                                  rawTitle.toLowerCase() != 'ep ${_currentItem.episodeNumber}';
                              if (epNum != null) {
                                epSubtitle = hasCustomTitle ? 'Episode $epNum - $rawTitle' : 'Episode $epNum';
                              } else if (rawTitle.isNotEmpty) {
                                epSubtitle = rawTitle;
                              }
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  mainTitle,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: -0.4,
                                  ),
                                ),
                                if (epSubtitle != null && epSubtitle.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    epSubtitle,
                                    style: const TextStyle(
                                      color: Color(0xFFE50914),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 12),

                        // Chips: Category, Genre, Rating, Year
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _buildChip(
                              _currentItem.isSeries ? 'Serial TV & Anime' : 'Film Layar Lebar',
                              isAccent: true,
                            ),
                            if (_currentItem.year != null && _currentItem.year!.isNotEmpty)
                              _buildChip(_currentItem.year!),
                            if (_currentItem.rating != null && _currentItem.rating!.isNotEmpty)
                              _buildChip('★ ${_currentItem.rating!}'),
                            if (_currentItem.maturity.isNotEmpty)
                              _buildChip('${_currentItem.maturity}+'),
                            if (_currentItem.genre.isNotEmpty)
                              _buildChip(_currentItem.genre),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Description Box (YouTube style)
                        if (_currentItem.description.isNotEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1B1B1B),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Sinopsis',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _currentItem.description,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.88),
                                    fontSize: 14,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 32),

                        // Recommendations Section
                        _buildRecommendationsSection(),
                      ],
                    ),
                  ),
                ),

                // Right Sidebar: YouTube Playlist
                Container(
                  width: 390,
                  decoration: const BoxDecoration(
                    color: Color(0xFF141414),
                    border: Border(left: BorderSide(color: Color(0xFF222222), width: 1)),
                  ),
                  child: _buildRightPlaylistSidebar(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  MediaItem? _resolveSeriesCatalogItem() {
    final targetId = _currentItem.seriesId ?? _currentItem.id;
    for (final it in widget.allLibraryItems) {
      if (it.id == targetId) return it;
      if (it.episodes.any((ep) => _isSamePath(ep.videoPath, _currentItem.videoPath) || ep.id == _currentItem.id)) {
        return it;
      }
    }
    final cleanCurrentTitle = _currentItem.title.split(' - ').first.toLowerCase().trim();
    final cleanSeriesTitle = _currentItem.seriesTitle?.split(' - ').first.toLowerCase().trim();
    for (final it in widget.allLibraryItems) {
      final itLower = it.title.toLowerCase().trim();
      if (itLower == cleanCurrentTitle || (cleanSeriesTitle != null && itLower == cleanSeriesTitle)) {
        return it;
      }
    }
    return null;
  }

  String? _resolveSidebarBackdropPath(MediaItem? catalogItem) {
    final candidates = <String?>[
      catalogItem?.backdrop2Url,
      _currentItem.backdrop2Url,
      _currentItem.backdropUrl,
      catalogItem?.backdropUrl,
      catalogItem?.customThumbnail,
      _currentItem.customThumbnail,
    ];
    for (final p in candidates) {
      if (p != null && p.isNotEmpty) {
        if (p.startsWith('http://') || p.startsWith('https://')) {
          return p;
        }
        if (LocalThumbnailService.fileExistsCached(p)) {
          return p;
        }
      }
    }
    return null;
  }

  String? _resolveSidebarLogoPath(MediaItem? catalogItem, String seriesTitle) {
    final candidates = <String?>[
      _currentItem.logoUrl,
      catalogItem?.logoUrl,
    ];
    for (final p in candidates) {
      if (p != null && p.isNotEmpty) {
        if (p.startsWith('http://') || p.startsWith('https://')) {
          return p;
        }
        if (LocalThumbnailService.fileExistsCached(p)) {
          return p;
        }
      }
    }
    final clean = seriesTitle.toLowerCase();
    if (clean.contains('onimai') || clean.contains('onii-chan') || clean.contains('oshimai')) {
      const localCandidates = [
        '.cache/logos/logo_onimai_en.png',
        '.cache/logos\\logo_onimai_en.png',
      ];
      for (final p in localCandidates) {
        if (LocalThumbnailService.fileExistsCached(p)) return p;
      }
    }
    return null;
  }

  Widget _buildSidebarBackdropHeader(MediaItem? catalogItem, String seriesTitle) {
    final backdropPath = _resolveSidebarBackdropPath(catalogItem);
    final logoPath = _resolveSidebarLogoPath(catalogItem, seriesTitle);
    final rating = _currentItem.rating ?? catalogItem?.rating;

    Widget backdropWidget;
    if (backdropPath != null && backdropPath.isNotEmpty) {
      if (backdropPath.startsWith('http://') || backdropPath.startsWith('https://')) {
        backdropWidget = Image.network(
          backdropPath,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          cacheWidth: 640,
          errorBuilder: (_, _, _) => _buildPosterThumbnail(_currentItem),
        );
      } else {
        backdropWidget = Image.file(
          File(backdropPath),
          fit: BoxFit.cover,
          alignment: Alignment.center,
          cacheWidth: 640,
          errorBuilder: (_, _, _) => _buildPosterThumbnail(_currentItem),
        );
      }
    } else {
      backdropWidget = _buildPosterThumbnail(_currentItem);
    }

    Widget? logoWidget;
    if (logoPath != null && logoPath.isNotEmpty) {
      if (logoPath.startsWith('http://') || logoPath.startsWith('https://')) {
        logoWidget = ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 50, maxWidth: 210),
          child: Image.network(
            logoPath,
            fit: BoxFit.contain,
            alignment: Alignment.bottomLeft,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        );
      } else {
        logoWidget = ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 50, maxWidth: 210),
          child: Image.file(
            File(logoPath),
            fit: BoxFit.contain,
            alignment: Alignment.bottomLeft,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. 16:9 Rounded Rectangle Backdrop Card (segi 4 dengan sudut tumpul, tidak terpotong)
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF181818),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12, width: 0.8),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black45,
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9.2),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    backdropWidget,
                    const Positioned(
                      left: -2,
                      right: -2,
                      bottom: -2,
                      height: 85,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Color(0x59000000),
                              Color(0xCC000000),
                              Color(0xFF000000),
                            ],
                            stops: [0.0, 0.40, 0.75, 1.0],
                          ),
                        ),
                      ),
                    ),
                    if (rating != null && rating.isNotEmpty && rating != '0' && rating != '0.0')
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: Colors.white24, width: 0.6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                '★',
                                style: TextStyle(
                                  color: Color(0xFFFFB800),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  height: 1.0,
                                ),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                rating,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  height: 1.0,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (logoWidget != null)
                      Positioned(
                        left: 12,
                        bottom: 10,
                        right: 48,
                        child: logoWidget,
                      ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 10),

          // 2. Judul di bawah backdrop (di luar segi 4)
          Text(
            seriesTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightPlaylistSidebar() {
    final playlist = _currentPlaylist;
    final catalogItem = _resolveSeriesCatalogItem();
    final isSeries = _currentItem.isSeries || (catalogItem?.isSeries ?? false) || playlist.any((it) => it.isSeries);
    final seriesTitle = _currentItem.seriesTitle ?? catalogItem?.title ?? _getSeriesTitle(_currentItem);

    final episodes = _currentItem.episodes.isNotEmpty
        ? _currentItem.episodes
        : (catalogItem?.episodes ?? const <Episode>[]);

    final List<String> seasonNames = [];
    for (final ep in episodes) {
      final sName = ep.seasonName.isNotEmpty ? ep.seasonName : 'Season 1';
      if (!seasonNames.contains(sName)) {
        seasonNames.add(sName);
      }
    }
    if (seasonNames.isEmpty) {
      seasonNames.add('Season 1');
    }

    final activeSeason = seasonNames.contains(_selectedSeason)
        ? _selectedSeason
        : seasonNames.first;

    final List<MediaItem> filteredPlaylist = (isSeries && episodes.isNotEmpty && seasonNames.length > 1)
        ? playlist.where((item) {
            for (final ep in episodes) {
              if (_isSamePath(ep.videoPath, item.videoPath) || ep.id == item.id ||
                  (item.episodeNumber != null && ep.episodeNumber == item.episodeNumber && ep.season == (item.seasonNumber ?? 1))) {
                final sName = ep.seasonName.isNotEmpty ? ep.seasonName : 'Season 1';
                return sName == activeSeason;
              }
            }
            return false;
          }).toList()
        : playlist;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Top Rounded Rectangle Backdrop + Logo + Title below backdrop
        _buildSidebarBackdropHeader(catalogItem, seriesTitle),

        // 2. Two-Column Header: Left ("Daftar Episode") | Right (Season Dropdown like "Info Selengkapnya")
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            color: Color(0xFF181818),
            border: Border(
              top: BorderSide(color: Color(0xFF262626)),
              bottom: BorderSide(color: Color(0xFF262626)),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Left Column: Daftar Episode
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isSeries ? Icons.view_list_rounded : Icons.playlist_play_rounded,
                    color: const Color(0xFFE50914),
                    size: 19,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    isSeries ? 'Daftar Episode' : 'Daftar Putar',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),

              const SizedBox(width: 10),

              // Right Column: Season Selector Dropdown (ONLY when > 1 season) with Ellipsis Protection
              if (isSeries && seasonNames.length > 1)
                Flexible(
                  child: PopupMenuButton<String>(
                    color: const Color(0xFF242424),
                    constraints: const BoxConstraints(maxWidth: 260),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                      side: const BorderSide(color: Colors.white24, width: 0.8),
                    ),
                    offset: const Offset(0, 38),
                    onSelected: (val) {
                      setState(() => _selectedSeason = val);
                    },
                    itemBuilder: (ctx) {
                      return seasonNames.map((s) {
                        final epCount = episodes.isNotEmpty
                            ? episodes.where((e) => (e.seasonName.isNotEmpty ? e.seasonName : 'Season 1') == s).length
                            : playlist.length;
                        final isCurrent = s == activeSeason;
                        return PopupMenuItem<String>(
                          value: s,
                          child: Text(
                            '${InAppPlayer.formatSeasonDisplay(s, seasonNames)} ($epCount Episode)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isCurrent ? const Color(0xFFE50914) : Colors.white,
                              fontSize: 13,
                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                        );
                      }).toList();
                    },
                    child: HoverAnimatedWidget(
                      hoverScale: 1.03,
                      builder: (context, isHovered) {
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          constraints: const BoxConstraints(maxWidth: 195),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isHovered ? const Color(0xFF2E2E2E) : const Color(0xFF242424),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isHovered ? Colors.white54 : Colors.white24,
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  '${InAppPlayer.formatSeasonDisplay(activeSeason, seasonNames)} (${filteredPlaylist.length} Episode)',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.arrow_drop_down, color: Colors.white, size: 18),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                )
              else
                Flexible(
                  child: Text(
                    isSeries ? '${filteredPlaylist.length} Episode' : '${filteredPlaylist.length} Video',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),

        // 3. Episode / Video List (Same content as "Info Selengkapnya": Direct Episode Title + Synopsis without Series Title)
        Expanded(
          child: filteredPlaylist.isEmpty
              ? const Center(
                  child: Text('Tidak ada video lain dalam daftar putar.', style: TextStyle(color: Colors.white38, fontSize: 13)),
                )
              : ListView.builder(
                  key: ValueKey<String>('ep-list-${_currentItem.seriesId ?? _currentItem.id}-$activeSeason'),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: filteredPlaylist.length,
                  itemBuilder: (context, index) {
                    final item = filteredPlaylist[index];
                    final isSelected = item.videoPath == _currentItem.videoPath;

                    Episode? matchedEp;
                    for (final ep in episodes) {
                      if (ep.videoPath == item.videoPath || ep.id == item.id) {
                        matchedEp = ep;
                        break;
                      }
                    }

                    final epNumDisplay = matchedEp?.episodeNumber ?? item.episodeNumber ?? (index + 1);
                    final durationLabel = matchedEp?.duration ?? '';

                    // Resolve pure episode title (without series title prefix)
                    String rawEpTitle = '';
                    if (matchedEp != null && matchedEp.title.trim().isNotEmpty) {
                      rawEpTitle = matchedEp.title.trim();
                    } else if (item.episodeTitle != null && item.episodeTitle!.trim().isNotEmpty) {
                      rawEpTitle = item.episodeTitle!.trim();
                    } else {
                      final prefix = '$seriesTitle - ';
                      if (item.title.startsWith(prefix)) {
                        rawEpTitle = item.title.substring(prefix.length).trim();
                      } else {
                        rawEpTitle = item.title.trim();
                      }
                    }

                    final hasCustomTitle = rawEpTitle.isNotEmpty &&
                        rawEpTitle.toLowerCase() != 'episode $epNumDisplay' &&
                        rawEpTitle.toLowerCase() != 'ep $epNumDisplay';

                    // Match ItemDetailDialog: only show episode synopsis if present
                    final String synopsisText = isSeries
                        ? (matchedEp?.synopsis?.trim() ?? '')
                        : item.description.trim();

                    return HoverAnimatedWidget(
                      key: ValueKey<String>('ep-item-${item.id}-${item.videoPath}'),
                      hoverScale: 1.015,
                      onTap: () {
                        if (!isSelected) {
                          _switchMedia(item);
                        }
                      },
                      builder: (context, isHovered) {
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF262626)
                                : (isHovered ? const Color(0xFF202020) : Colors.transparent),
                            borderRadius: BorderRadius.circular(6),
                            border: isSelected
                                ? Border.all(color: const Color(0xFFE50914), width: 1.2)
                                : (isHovered
                                    ? Border.all(color: Colors.white24, width: 0.8)
                                    : Border.all(color: Colors.transparent, width: 0.8)),
                          ),
                          child: Row(
                            crossAxisAlignment: synopsisText.isNotEmpty
                                ? CrossAxisAlignment.start
                                : CrossAxisAlignment.center,
                            children: [
                              // Thumbnail Preview with Netflix animated equalizer overlay
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: SizedBox(
                                  width: 115,
                                  height: 65,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      _PlayerEpisodeThumbnail(
                                        episode: matchedEp,
                                        item: item,
                                        fallbackPoster: item.backdropUrl ?? item.customThumbnail ?? _currentItem.backdropUrl,
                                      ),
                                      if (isSelected)
                                        const AnimatedNowPlayingBadge(text: 'Sedang Diputar')
                                      else
                                        Positioned(
                                          bottom: 4,
                                          right: 4,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withValues(alpha: 0.8),
                                              borderRadius: BorderRadius.circular(2),
                                            ),
                                            child: Text(
                                              '#$epNumDisplay',
                                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              // Info Column (Baris 1: Episode "XX" & Durasi, Baris 2: Judul Episode, Baris 3: Sinopsis)
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Baris 1: Episode "XX" (untuk series) & Durasi di kanan
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            isSeries ? 'Episode "${epNumDisplay.toString().padLeft(2, '0')}"' : (hasCustomTitle ? rawEpTitle : 'Video $epNumDisplay'),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: isSelected ? const Color(0xFFE50914) : Colors.white,
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        if (durationLabel.isNotEmpty) ...[
                                          const SizedBox(width: 6),
                                          Text(
                                            durationLabel,
                                            style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    // Baris 2: Judul Episode (jika ada)
                                    if (hasCustomTitle) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        rawEpTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.9),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                    // Baris 3: Sinopsis episode (jika ada)
                                    if (synopsisText.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        synopsisText,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Colors.white54, fontSize: 11, height: 1.25),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildRecommendationsSection() {
    final currentSeriesOrMediaId = _currentItem.seriesId ?? _currentItem.id;
    final currentSeriesTitle = (_currentItem.seriesTitle ?? _getSeriesTitle(_currentItem)).toLowerCase();
    final recommendations = widget.allLibraryItems.where((it) {
      final itId = it.seriesId ?? it.id;
      if (itId == currentSeriesOrMediaId || it.id == _currentItem.id || it.videoPath == _currentItem.videoPath) return false;
      if (it.title.toLowerCase() == currentSeriesTitle) return false;
      return true;
    }).toList();

    if (recommendations.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.recommend_rounded, color: Color(0xFFE50914), size: 22),
            SizedBox(width: 8),
            Text(
              'Rekomendasi Lainnya',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            childAspectRatio: 16 / 12,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
          ),
          itemCount: recommendations.length.clamp(0, 8),
          itemBuilder: (context, index) {
            final recItem = recommendations[index];
            return HoverAnimatedWidget(
              hoverScale: 1.03,
              onTap: () => _playRecommendation(recItem),
              builder: (context, isHovered) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  decoration: BoxDecoration(
                    color: isHovered ? const Color(0xFF262626) : const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isHovered ? Colors.white38 : Colors.white10,
                      width: isHovered ? 1.0 : 0.8,
                    ),
                    boxShadow: isHovered
                        ? const [
                            BoxShadow(
                              color: Colors.black54,
                              blurRadius: 12,
                              offset: Offset(0, 6),
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _buildPosterThumbnail(recItem),
                              Positioned(
                                top: 6,
                                left: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: recItem.isSeries ? const Color(0xFF0071EB) : const Color(0xFFE50914),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    recItem.isSeries ? 'SERIAL' : 'FILM',
                                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              recItem.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              recItem.genre.isNotEmpty ? recItem.genre : 'Lokal',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white38, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildChip(String text, {bool isAccent = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isAccent ? const Color(0xFFE50914).withValues(alpha: 0.2) : Colors.white10,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isAccent ? const Color(0xFFE50914).withValues(alpha: 0.5) : Colors.white12,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isAccent ? const Color(0xFFE50914) : Colors.white70,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// Netflix-Style 2-Column Audio & Subtitles Menu
  Widget _buildNetflixAudioSubtitleMenu() {
    // Strictly filter out virtual media_kit internal tracks ('auto' & 'no')
    final audioTracks = _tracks.audio.where((t) => t.id != 'no' && t.id != 'auto').toList();
    final subtitleTracks = _tracks.subtitle.where((t) => t.id != 'no' && t.id != 'auto').toList();

    final Map<String, int> audioLangCounts = {};
    for (final t in audioTracks) {
      final l = (t.language ?? '').toLowerCase();
      audioLangCounts[l] = (audioLangCounts[l] ?? 0) + 1;
    }
    final Map<String, int> audioLangIndices = {};

    final Map<String, int> subLangCounts = {};
    for (final t in subtitleTracks) {
      final l = (t.language ?? '').toLowerCase();
      subLangCounts[l] = (subLangCounts[l] ?? 0) + 1;
    }
    final Map<String, int> subLangIndices = {};

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
                        final isSelected = (_activeAudioTrackId != null && _activeAudioTrackId == track.id) ||
                            ((_activeAudioTrackId == null || _activeAudioTrackId == 'auto') &&
                                (_currentTrack.audio.id == track.id || track.isDefault == true || track == audioTracks.first));
                        final l = (track.language ?? '').toLowerCase();
                        audioLangIndices[l] = (audioLangIndices[l] ?? 0) + 1;
                        final total = audioLangCounts[l] ?? 1;
                        final label = _getTrackName(
                          track,
                          'Audio ${idx + 1}',
                          index: audioLangIndices[l],
                          totalWithSameLang: total,
                        );

                        return InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () {
                            _player.setAudioTrack(track);
                            setState(() => _activeAudioTrackId = track.id);
                            _onUserActivity();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFFE50914).withValues(alpha: 0.18) : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
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
                Builder(
                  builder: (context) {
                    final isOff = _activeSubtitleTrackId == 'no' ||
                        (_activeSubtitleTrackId == null && (_currentTrack.subtitle.id == 'no' || subtitleTracks.isEmpty));
                    return InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () {
                        _player.setSubtitleTrack(SubtitleTrack.no());
                        setState(() => _activeSubtitleTrackId = 'no');
                        _onUserActivity();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        decoration: BoxDecoration(
                          color: isOff ? const Color(0xFFE50914).withValues(alpha: 0.18) : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_rounded,
                              color: isOff ? const Color(0xFFE50914) : Colors.transparent,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Nonaktif (Off)',
                              style: TextStyle(
                                color: isOff ? Colors.white : Colors.white70,
                                fontWeight: isOff ? FontWeight.bold : FontWeight.normal,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                // Subtitle Tracks
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: subtitleTracks.length,
                    itemBuilder: (ctx, idx) {
                      final track = subtitleTracks[idx];
                      final isSelected = (_activeSubtitleTrackId != null && _activeSubtitleTrackId == track.id) ||
                          ((_activeSubtitleTrackId == null || _activeSubtitleTrackId == 'auto') &&
                              (_currentTrack.subtitle.id == track.id || track.isDefault == true));
                      final l = (track.language ?? '').toLowerCase();
                      subLangIndices[l] = (subLangIndices[l] ?? 0) + 1;
                      final total = subLangCounts[l] ?? 1;
                      final label = _getTrackName(
                        track,
                        'Subtitle ${idx + 1}',
                        index: subLangIndices[l],
                        totalWithSameLang: total,
                      );

                      return InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () {
                          _player.setSubtitleTrack(track);
                          setState(() => _activeSubtitleTrackId = track.id);
                          _onUserActivity();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFFE50914).withValues(alpha: 0.18) : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                          ),
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

  /// Netflix-Style Episodes & Season Selection Drawer (Matching Screenshot 1 & 2)
  Widget _buildNetflixEpisodesPopup() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    // Fixed dimensions to prevent jumping or size flickering
    final popupWidth = screenWidth < 640 ? (screenWidth - 32) : 560.0;
    final popupHeight = (screenHeight * 0.52).clamp(420.0, 500.0);

    final playlist = _currentPlaylist;
    final catalogItem = _resolveSeriesCatalogItem();
    final isSeries = _currentItem.isSeries || (catalogItem?.isSeries ?? false) || playlist.any((it) => it.isSeries);
    final seriesTitle = _currentItem.seriesTitle ?? catalogItem?.title ?? _getSeriesTitle(_currentItem);

    final episodes = _currentItem.episodes.isNotEmpty
        ? _currentItem.episodes
        : (catalogItem?.episodes ?? const <Episode>[]);

    final List<String> seasonNames = [];
    for (final ep in episodes) {
      final sName = ep.seasonName.isNotEmpty ? ep.seasonName : 'Season 1';
      if (!seasonNames.contains(sName)) {
        seasonNames.add(sName);
      }
    }
    if (seasonNames.isEmpty) {
      seasonNames.add('Season 1');
    }

    final activeSeason = seasonNames.contains(_selectedSeason)
        ? _selectedSeason
        : seasonNames.first;

    // Filter episodes strictly for the active season
    final List<Episode> seasonEpisodes = episodes.where((ep) {
      final sName = ep.seasonName.isNotEmpty ? ep.seasonName : 'Season 1';
      return sName == activeSeason;
    }).toList();

    // Fallback if episodes metadata is absent (e.g. loose folder)
    final List<MediaItem> fallbackPlaylist = (isSeries && episodes.isNotEmpty && seasonNames.length > 1)
        ? playlist.where((item) {
            for (final ep in episodes) {
              if (_isSamePath(ep.videoPath, item.videoPath) || ep.id == item.id ||
                  (item.episodeNumber != null && ep.episodeNumber == item.episodeNumber && ep.season == (item.seasonNumber ?? 1))) {
                final sName = ep.seasonName.isNotEmpty ? ep.seasonName : 'Season 1';
                return sName == activeSeason;
              }
            }
            return false;
          }).toList()
        : playlist;

    return MouseRegion(
      onEnter: (_) => _isHoveringEpisodeList = true,
      onExit: (_) => _isHoveringEpisodeList = false,
      child: Container(
        width: popupWidth,
        height: popupHeight,
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
      child: _isSeasonSelectorOpen && seasonNames.length > 1
          ? Column(
              // VIEW 1: Netflix Season Selection List (Screenshot 1)
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Text(
                    seriesTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                const Divider(color: Colors.white12, height: 1),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    itemCount: seasonNames.length,
                    itemBuilder: (ctx, idx) {
                      final s = seasonNames[idx];
                      final isCurrent = s == activeSeason;
                      final count = episodes.where((e) => (e.seasonName.isNotEmpty ? e.seasonName : 'Season 1') == s).length;
                      final epCountLabel = count > 0 ? ' ($count Episode)' : '';

                      return HoverAnimatedWidget(
                        key: ValueKey('season-select-$s'),
                        hoverScale: 1.01,
                        onTap: () {
                          setState(() {
                            _selectedSeason = s;
                            _isSeasonSelectorOpen = false;
                          });
                          _onUserActivity();
                        },
                        builder: (context, isHovered) {
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 140),
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : (isHovered ? Colors.white.withValues(alpha: 0.04) : Colors.transparent),
                              borderRadius: BorderRadius.circular(5),
                              border: isCurrent
                                  ? Border.all(color: Colors.white, width: 1.2)
                                  : (isHovered
                                      ? Border.all(color: Colors.white24, width: 0.8)
                                      : Border.all(color: Colors.transparent, width: 0.8)),
                            ),
                            child: Row(
                              children: [
                                if (isCurrent) ...[
                                  const Icon(Icons.check_rounded, color: Colors.white, size: 18),
                                  const SizedBox(width: 10),
                                ],
                                Expanded(
                                  child: Text(
                                    '${InAppPlayer.formatSeasonDisplay(s, seasonNames)}$epCountLabel',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: isCurrent ? Colors.white : Colors.white70,
                                      fontSize: 14.5,
                                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                                    ),
                                  ),
                                ),
                                if (isCurrent)
                                  const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            )
          : Column(
              // VIEW 2: Netflix Episodes List for Selected Season (Screenshot 2)
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: Back button + Season name (clicking switches to season selector view)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                  child: seasonNames.length > 1
                      ? HoverAnimatedWidget(
                          hoverScale: 1.02,
                          onTap: () {
                            setState(() => _isSeasonSelectorOpen = true);
                            _onUserActivity();
                          },
                          builder: (context, isHovered) {
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.arrow_back_rounded,
                                  color: isHovered ? Colors.white : Colors.white70,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  InAppPlayer.formatSeasonDisplay(activeSeason, seasonNames),
                                  style: TextStyle(
                                    color: isHovered ? Colors.white : Colors.white.withValues(alpha: 0.9),
                                    fontSize: 16.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.arrow_drop_down_rounded,
                                  color: isHovered ? Colors.white : Colors.white54,
                                  size: 20,
                                ),
                              ],
                            );
                          },
                        )
                      : Row(
                          children: [
                            const Icon(Icons.video_library_rounded, color: Color(0xFFE50914), size: 18),
                            const SizedBox(width: 8),
                            Text(
                              seriesTitle,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                ),
                const Divider(color: Colors.white12, height: 1),

                // Scrollable Episodes List
                Expanded(
                  child: seasonEpisodes.isNotEmpty
                      ? ListView.builder(
                          key: ValueKey('net-ep-list-$activeSeason'),
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: seasonEpisodes.length,
                          itemBuilder: (ctx, index) {
                            final ep = seasonEpisodes[index];
                            final isSelected = _isEpisodePlaying(ep);
                            final epNumDisplay = ep.episodeNumber > 0 ? ep.episodeNumber : (index + 1);
                            final durationLabel = ep.duration ?? '';
                            final synopsisText = ep.synopsis?.trim() ?? '';
                            String rawEpTitle = ep.title.trim();
                            for (final prefix in [
                              'Episode $epNumDisplay - ',
                              'Episode $epNumDisplay: ',
                              'Episode ${epNumDisplay.toString().padLeft(2, '0')} - ',
                              'Episode ${epNumDisplay.toString().padLeft(2, '0')}: ',
                              'Ep $epNumDisplay - ',
                              'Ep $epNumDisplay: ',
                              'Ep ${epNumDisplay.toString().padLeft(2, '0')} - ',
                              'Ep ${epNumDisplay.toString().padLeft(2, '0')}: ',
                            ]) {
                              if (rawEpTitle.startsWith(prefix)) {
                                rawEpTitle = rawEpTitle.substring(prefix.length).trim();
                                break;
                              }
                            }
                            final hasCustomTitle = rawEpTitle.isNotEmpty &&
                                rawEpTitle.toLowerCase() != 'episode $epNumDisplay' &&
                                rawEpTitle.toLowerCase() != 'episode ${epNumDisplay.toString().padLeft(2, '0')}' &&
                                rawEpTitle.toLowerCase() != 'ep $epNumDisplay' &&
                                rawEpTitle.toLowerCase() != 'ep ${epNumDisplay.toString().padLeft(2, '0')}';

                            return HoverAnimatedWidget(
                              key: ValueKey('net-ep-${ep.id}-${ep.videoPath}'),
                              hoverScale: 1.012,
                              onTap: () {
                                _playEpisodeFromDrawer(ep, seriesTitle, episodes);
                              },
                              builder: (context, isHovered) {
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFF262626)
                                        : (isHovered ? const Color(0xFF202020) : Colors.transparent),
                                    borderRadius: BorderRadius.circular(6),
                                    border: isSelected
                                        ? Border.all(color: const Color(0xFFE50914), width: 1.2)
                                        : (isHovered
                                            ? Border.all(color: Colors.white24, width: 0.8)
                                            : Border.all(color: Colors.transparent, width: 0.8)),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: synopsisText.isNotEmpty
                                        ? CrossAxisAlignment.start
                                        : CrossAxisAlignment.center,
                                    children: [
                                      // Number on the left (matching Screenshot 2: "343", "344")
                                      SizedBox(
                                        width: 32,
                                        child: Center(
                                          child: Text(
                                            '$epNumDisplay',
                                            style: TextStyle(
                                              color: isSelected ? const Color(0xFFE50914) : Colors.white70,
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),

                                      // Thumbnail with "Sedang Diputar" animated equalizer overlay
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: SizedBox(
                                          width: 115,
                                          height: 65,
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              _PlayerEpisodeThumbnail(
                                                episode: ep,
                                                item: MediaItem(
                                                  id: ep.id,
                                                  title: ep.title,
                                                  description: '',
                                                  genre: '',
                                                  maturity: '',
                                                  category: '',
                                                  videoPath: ep.videoPath,
                                                  customThumbnail: ep.thumbnail,
                                                ),
                                                fallbackPoster: _currentItem.backdropUrl ?? _currentItem.customThumbnail,
                                              ),
                                              if (isSelected)
                                                const AnimatedNowPlayingBadge(text: 'Sedang Diputar'),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),

                                      // Right Column: Baris 1: Episode "XX" & Durasi, Baris 2: Judul Episode, Baris 3: Sinopsis
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // Baris 1: Episode "XX" & Durasi
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              crossAxisAlignment: CrossAxisAlignment.center,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    'Episode "${epNumDisplay.toString().padLeft(2, '0')}"',
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: isSelected ? const Color(0xFFE50914) : Colors.white,
                                                      fontSize: 13.5,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                if (durationLabel.isNotEmpty) ...[
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    durationLabel,
                                                    style: const TextStyle(
                                                      color: Colors.white54,
                                                      fontSize: 11.5,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            // Baris 2: Judul Episode (jika ada)
                                            if (hasCustomTitle) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                rawEpTitle,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.9),
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                            // Baris 3: Sinopsis episode (jika ada)
                                            if (synopsisText.isNotEmpty) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                synopsisText,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white60,
                                                  fontSize: 11,
                                                  height: 1.25,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: fallbackPlaylist.length,
                          itemBuilder: (ctx, index) {
                            final item = fallbackPlaylist[index];
                            final isSelected = _isSamePath(item.videoPath, _currentItem.videoPath);
                            final epNumDisplay = item.episodeNumber ?? (index + 1);

                            return HoverAnimatedWidget(
                              key: ValueKey('fallback-ep-${item.id}-${item.videoPath}'),
                              hoverScale: 1.012,
                              onTap: () {
                                if (!isSelected) _switchMedia(item);
                              },
                              builder: (context, isHovered) {
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFF262626)
                                        : (isHovered ? const Color(0xFF202020) : Colors.transparent),
                                    borderRadius: BorderRadius.circular(6),
                                    border: isSelected
                                        ? Border.all(color: const Color(0xFFE50914), width: 1.2)
                                        : (isHovered
                                            ? Border.all(color: Colors.white24, width: 0.8)
                                            : Border.all(color: Colors.transparent, width: 0.8)),
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 28,
                                        child: Center(
                                          child: Text(
                                            '$epNumDisplay',
                                            style: TextStyle(
                                              color: isSelected ? const Color(0xFFE50914) : Colors.white70,
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: SizedBox(
                                          width: 115,
                                          height: 65,
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              _PlayerEpisodeThumbnail(
                                                episode: null,
                                                item: item,
                                                fallbackPoster: item.backdropUrl ?? item.customThumbnail ?? _currentItem.backdropUrl,
                                              ),
                                              if (isSelected)
                                                const AnimatedNowPlayingBadge(text: 'Sedang Diputar'),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              isSeries ? 'Episode "${epNumDisplay.toString().padLeft(2, '0')}"' : item.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: isSelected ? const Color(0xFFE50914) : Colors.white,
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            if (isSeries && item.title != 'Episode $epNumDisplay') ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                item.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.9),
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                            if (item.description.trim().isNotEmpty) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                item.description.trim(),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white60,
                                                  fontSize: 11,
                                                  height: 1.25,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
        ),
    );
  }

  Widget _buildSkipIntroButton(VideoChapter chapter) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            _player.seek(chapter.end);
            setState(() => _activeIntroChapter = null);
          },
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white.withValues(alpha: 0.75), width: 1.4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.skip_next_rounded, color: Colors.white, size: 22),
                SizedBox(width: 8),
                Text(
                  'Lewati Intro',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTvBroadcastOverlay() {
    return AnimatedSlide(
      offset: _showTvOverlay ? Offset.zero : const Offset(-1.2, 0),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: _showTvOverlay ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 500),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xEB141414),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE50914), Color(0xFFB81D24)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      'LOCAL TV',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _tvOverlayLine1.toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFFE50914),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _tvOverlayLine2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getSeriesTitle(MediaItem item) {
    final catalog = _resolveSeriesCatalogItem();
    if (catalog != null && catalog.title.trim().isNotEmpty) {
      return catalog.title.trim();
    }
    String raw = (item.seriesTitle != null && item.seriesTitle!.trim().isNotEmpty)
        ? item.seriesTitle!.trim()
        : item.title.trim();

    if (item.episodeTitle != null &&
        item.episodeTitle!.isNotEmpty &&
        raw.toLowerCase().endsWith(' - ${item.episodeTitle!.toLowerCase().trim()}')) {
      raw = raw.substring(0, raw.length - (item.episodeTitle!.trim().length + 3)).trim();
    } else if (raw.contains(' - ')) {
      raw = raw.split(' - ').first.trim();
    }
    return raw;
  }
}

/// Animated "Sedang Diputar" badge with bouncing Netflix-style equalizer bars
class AnimatedNowPlayingBadge extends StatefulWidget {
  final String text;
  const AnimatedNowPlayingBadge({super.key, this.text = 'Sedang Diputar'});

  @override
  State<AnimatedNowPlayingBadge> createState() => _AnimatedNowPlayingBadgeState();
}

class _AnimatedNowPlayingBadgeState extends State<AnimatedNowPlayingBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.68),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Bouncing equalizer bars (Netflix style)
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final t = _controller.value;
                  final h1 = 4.0 + 8.0 * ((math.sin(t * 2 * math.pi) + 1) / 2);
                  final h2 = 4.0 + 9.5 * ((math.sin((t + 0.33) * 2 * math.pi) + 1) / 2);
                  final h3 = 4.0 + 7.5 * ((math.sin((t + 0.66) * 2 * math.pi) + 1) / 2);
                  return SizedBox(
                    height: 14,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _buildBar(h1),
                        const SizedBox(width: 2),
                        _buildBar(h2),
                        const SizedBox(width: 2),
                        _buildBar(h3),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(width: 5),
              Text(
                widget.text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBar(double height) {
    return Container(
      width: 2.5,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFE50914),
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}

/// Timeline Scrubber with Trickplay Preview Bubble & Chapter Marker Notches
class _PlayerSeekBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final List<VideoChapter> chapters;
  final TrickplayData? trickplayData;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onActivity;

  const _PlayerSeekBar({
    required this.position,
    required this.duration,
    required this.chapters,
    required this.trickplayData,
    required this.onSeek,
    required this.onActivity,
  });

  @override
  State<_PlayerSeekBar> createState() => _PlayerSeekBarState();
}

class _PlayerSeekBarState extends State<_PlayerSeekBar> {
  bool _isHovering = false;
  double _hoverX = 0.0;
  Duration _hoverDuration = Duration.zero;

  @override
  Widget build(BuildContext context) {
    final durMs = widget.duration.inMilliseconds;
    final posMs = widget.position.inMilliseconds.clamp(0, durMs > 0 ? durMs : 0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        const double horizontalPadding = 24.0;
        final trackWidth = math.max(1.0, totalWidth - (horizontalPadding * 2));

        VideoChapter? hoverChapter;
        if (widget.chapters.isNotEmpty && _hoverDuration > Duration.zero) {
          for (final ch in widget.chapters) {
            if (_hoverDuration >= ch.start && _hoverDuration < ch.end) {
              hoverChapter = ch;
              break;
            }
          }
        }

        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // Chapter Notches along track
            if (widget.chapters.isNotEmpty && durMs > 0)
              Positioned(
                left: horizontalPadding,
                right: horizontalPadding,
                height: 4,
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _ChapterNotchesPainter(
                      chapters: widget.chapters,
                      duration: widget.duration,
                    ),
                  ),
                ),
              ),

            // Slider
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
                value: posMs.toDouble(),
                min: 0.0,
                max: durMs > 0 ? durMs.toDouble() : 1.0,
                onChanged: (val) {
                  widget.onSeek(Duration(milliseconds: val.toInt()));
                  widget.onActivity();
                },
              ),
            ),

            // Mouse hover region
            Positioned.fill(
              child: MouseRegion(
                opaque: false,
                onHover: (event) {
                  final localX = event.localPosition.dx;
                  final clampedTrackX = (localX - horizontalPadding).clamp(0.0, trackWidth);
                  final fraction = (clampedTrackX / trackWidth).clamp(0.0, 1.0);
                  setState(() {
                    _isHovering = true;
                    _hoverX = localX;
                    _hoverDuration = Duration(milliseconds: (fraction * durMs).toInt());
                  });
                },
                onExit: (_) {
                  setState(() => _isHovering = false);
                },
              ),
            ),

            // Floating Trickplay Preview Card
            if (_isHovering && durMs > 0)
              Positioned(
                bottom: 34,
                left: (_hoverX - 85).clamp(8.0, totalWidth - 178.0),
                child: IgnorePointer(
                  child: Container(
                    width: 170,
                    decoration: BoxDecoration(
                      color: const Color(0xFA181818),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white24, width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.75),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.trickplayData?.decodedImage != null)
                          SizedBox(
                            width: 170,
                            height: 96,
                            child: CustomPaint(
                              painter: TrickplayTilePainter(
                                spriteImage: widget.trickplayData!.decodedImage!,
                                srcRect: widget.trickplayData!.getTileRect(_hoverDuration),
                              ),
                            ),
                          )
                        else
                          Container(
                            width: 170,
                            height: 96,
                            color: Colors.black45,
                            child: const Center(
                              child: Icon(Icons.movie_creation_outlined, color: Colors.white30, size: 30),
                            ),
                          ),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          color: const Color(0xFF1F1F1F),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _formatDurationTopLevel(widget.duration, _hoverDuration),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              if (hoverChapter != null && hoverChapter.title.trim().isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  hoverChapter.title.trim(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFFE50914),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

String _formatDurationTopLevel(Duration totalDuration, Duration duration) {
  String twoDigits(int n) => n.toString().padLeft(2, '0');
  final minutes = twoDigits(duration.inMinutes.remainder(60));
  final seconds = twoDigits(duration.inSeconds.remainder(60));
  if (totalDuration.inHours > 0 || duration.inHours > 0) {
    return '${twoDigits(duration.inHours)}:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}

class _ChapterNotchesPainter extends CustomPainter {
  final List<VideoChapter> chapters;
  final Duration duration;

  _ChapterNotchesPainter({required this.chapters, required this.duration});

  @override
  void paint(Canvas canvas, Size size) {
    if (duration.inMilliseconds <= 0 || chapters.isEmpty) return;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;

    final durMs = duration.inMilliseconds.toDouble();
    for (final ch in chapters) {
      if (ch.start <= Duration.zero) continue;
      final startFraction = ch.start.inMilliseconds.toDouble() / durMs;
      if (startFraction > 0.0 && startFraction < 1.0) {
        final x = startFraction * size.width;
        canvas.drawRect(Rect.fromLTWH(x - 1, -2, 2, size.height + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChapterNotchesPainter oldDelegate) {
    return oldDelegate.chapters != chapters || oldDelegate.duration != duration;
  }
}

/// Episode 16:9 Thumbnail Widget with On-Demand Extraction & Fallback
class _PlayerEpisodeThumbnail extends StatefulWidget {
  final Episode? episode;
  final MediaItem item;
  final String? fallbackPoster;

  const _PlayerEpisodeThumbnail({
    required this.episode,
    required this.item,
    this.fallbackPoster,
  });

  @override
  State<_PlayerEpisodeThumbnail> createState() => _PlayerEpisodeThumbnailState();
}

class _PlayerEpisodeThumbnailState extends State<_PlayerEpisodeThumbnail> {
  String? _resolvedThumb;
  bool _isExtracting = false;

  @override
  void initState() {
    super.initState();
    _checkAndExtractThumb();
  }

  @override
  void didUpdateWidget(covariant _PlayerEpisodeThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.videoPath != widget.item.videoPath ||
        oldWidget.episode?.thumbnail != widget.episode?.thumbnail) {
      _checkAndExtractThumb();
    }
  }

  void _checkAndExtractThumb() {
    final vPath = widget.item.videoPath;
    final epThumb = widget.episode?.thumbnail;

    // 1. Direct episode thumbnail file/URL
    if (epThumb != null && epThumb.isNotEmpty && LocalThumbnailService.fileExistsCached(epThumb)) {
      _resolvedThumb = epThumb;
      return;
    }

    // 2. Check if local thumbnail already exists on disk
    if (vPath.isNotEmpty && LocalThumbnailService.hasThumbnail(vPath)) {
      _resolvedThumb = LocalThumbnailService.getThumbnailPath(vPath);
      return;
    }

    // 3. Trigger fast on-demand background extraction via ffmpeg
    if (!_isExtracting && vPath.isNotEmpty && !vPath.startsWith('asset:')) {
      _isExtracting = true;
      LocalThumbnailService.extractThumbnail(vPath).then((path) {
        if (mounted && path != null && path.isNotEmpty) {
          setState(() {
            _resolvedThumb = path;
            _isExtracting = false;
          });
        } else if (mounted) {
          setState(() => _isExtracting = false);
        }
      }).catchError((_) {
        if (mounted) setState(() => _isExtracting = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final thumb = _resolvedThumb ?? widget.episode?.thumbnail;
    final hasThumb = thumb != null && thumb.isNotEmpty;
    final isLocal = hasThumb && LocalThumbnailService.fileExistsCached(thumb);
    final isNet = hasThumb && (thumb.startsWith('http://') || thumb.startsWith('https://'));

    if (isLocal) {
      return Image.file(
        File(thumb),
        fit: BoxFit.cover,
        cacheWidth: 260,
        errorBuilder: (_, _, _) => _buildFallback(),
      );
    } else if (isNet) {
      return Image.network(
        thumb,
        fit: BoxFit.cover,
        cacheWidth: 260,
        errorBuilder: (_, _, _) => _buildFallback(),
      );
    }
    return _buildFallback();
  }

  Widget _buildFallback() {
    final fb = widget.fallbackPoster ?? widget.item.customThumbnail ?? widget.item.backdropUrl;
    if (fb != null && fb.isNotEmpty) {
      final isLocal = LocalThumbnailService.fileExistsCached(fb);
      final isNet = fb.startsWith('http://') || fb.startsWith('https://');
      if (isLocal) {
        return Image.file(File(fb), fit: BoxFit.cover, cacheWidth: 260);
      } else if (isNet) {
        return Image.network(fb, fit: BoxFit.cover, cacheWidth: 260);
      }
    }
    return Container(
      color: const Color(0xFF222222),
      child: const Center(
        child: Icon(Icons.movie_creation_outlined, color: Colors.white24, size: 26),
      ),
    );
  }
}
