part of '../in_app_player.dart';

extension _InAppPlayerPopoversOverlay on _InAppPlayerState {
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
    final List<String> audioLabels = List<String>.generate(audioTracks.length, (idx) {
      final track = audioTracks[idx];
      final l = (track.language ?? '').toLowerCase();
      audioLangIndices[l] = (audioLangIndices[l] ?? 0) + 1;
      return _getTrackName(
        track,
        'Audio ${idx + 1}',
        index: audioLangIndices[l],
        totalWithSameLang: audioLangCounts[l] ?? 1,
      );
    });
    String? resolvedAudioId;
    if (_activeAudioTrackId != null && _activeAudioTrackId != 'auto') {
      resolvedAudioId = _activeAudioTrackId;
    } else if (audioTracks.any((t) => t.id == _currentTrack.audio.id)) {
      resolvedAudioId = _currentTrack.audio.id;
    } else if (audioTracks.any((t) => t.isDefault == true)) {
      resolvedAudioId = audioTracks.firstWhere((t) => t.isDefault == true).id;
    } else if (audioTracks.isNotEmpty) {
      resolvedAudioId = audioTracks.first.id;
    }

    final Map<String, int> subLangCounts = {};
    for (final t in subtitleTracks) {
      final l = (t.language ?? '').toLowerCase();
      subLangCounts[l] = (subLangCounts[l] ?? 0) + 1;
    }
    final Map<String, int> subLangIndices = {};
    final List<String> subtitleLabels = List<String>.generate(subtitleTracks.length, (idx) {
      final track = subtitleTracks[idx];
      final l = (track.language ?? '').toLowerCase();
      subLangIndices[l] = (subLangIndices[l] ?? 0) + 1;
      return _getTrackName(
        track,
        'Subtitle ${idx + 1}',
        index: subLangIndices[l],
        totalWithSameLang: subLangCounts[l] ?? 1,
      );
    });
    String? resolvedSubtitleId;
    if (_activeSubtitleTrackId != null && _activeSubtitleTrackId != 'auto') {
      resolvedSubtitleId = _activeSubtitleTrackId;
    } else if (_currentTrack.subtitle.id == 'no') {
      resolvedSubtitleId = 'no';
    } else if (subtitleTracks.any((t) => t.id == _currentTrack.subtitle.id)) {
      resolvedSubtitleId = _currentTrack.subtitle.id;
    } else if (subtitleTracks.any((t) => t.isDefault == true)) {
      resolvedSubtitleId = subtitleTracks.firstWhere((t) => t.isDefault == true).id;
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final popupWidth = screenWidth < 640 ? (screenWidth - 32) : 560.0;
    final popupHeight = (screenHeight * 0.52).clamp(420.0, 500.0);

    return Container(
      width: popupWidth,
      height: popupHeight,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xF5141414),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.85),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        final isSelected = resolvedAudioId == track.id;
                        final label = audioLabels[idx];

                        return InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () {
                            _player.setAudioTrack(track);
                            _updateState(() => _activeAudioTrackId = track.id);
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

          Container(width: 1, color: Colors.white12, margin: const EdgeInsets.symmetric(horizontal: 18)),

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
                        _updateState(() => _activeSubtitleTrackId = 'no');
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
                      final isSelected = resolvedSubtitleId == track.id;
                      final label = subtitleLabels[idx];

                      return InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () {
                          _player.setSubtitleTrack(track);
                          _updateState(() => _activeSubtitleTrackId = track.id);
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
              final sameVideo = (ep.videoPath.isNotEmpty && item.videoPath.isNotEmpty)
                  ? _isSamePath(ep.videoPath, item.videoPath)
                  : ep.id == item.id;
              if (sameVideo) {
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
                          _updateState(() {
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
                            _updateState(() => _isSeasonSelectorOpen = true);
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
                                                AnimatedNowPlayingBadge(text: 'Sedang Diputar', isPlaying: _isPlaying),
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
                                                    'Episode ${epNumDisplay.toString().padLeft(2, '0')}',
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
                                                AnimatedNowPlayingBadge(text: 'Sedang Diputar', isPlaying: _isPlaying),
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
                                              isSeries ? 'Episode ${epNumDisplay.toString().padLeft(2, '0')}' : item.title,
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
            _updateState(() => _activeIntroChapter = null);
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
    final bool isSeries = _currentItem.isSeries || _currentItem.episodes.isNotEmpty || _currentItem.seriesId != null;
    final String showTitle = isSeries ? _getSeriesTitle(_currentItem) : _currentItem.title.trim();

    return AnimatedSlide(
      offset: _showTvOverlay ? Offset.zero : const Offset(1.15, 0),
      duration: const Duration(milliseconds: 580),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: _showTvOverlay ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 420),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          decoration: BoxDecoration(
            color: const Color(0xD90E0E0E),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFFE50914),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(color: Color(0xAAE50914), blurRadius: 6),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${_tvOverlayLine1.toUpperCase()}  •  LOCAL TV',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.65),
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.4,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          showTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.15,
                          ),
                        ),
                        if (isSeries && _tvOverlayLine2.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            _tvOverlayLine2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // Clean TV Broadcast red accent bar anchored to the right edge
                Container(
                  width: 3.5,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFE50914), Color(0xFF99060D)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
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
