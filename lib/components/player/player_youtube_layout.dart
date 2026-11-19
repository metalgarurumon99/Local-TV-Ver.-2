part of '../in_app_player.dart';

extension _InAppPlayerYoutubeLayout on _InAppPlayerState {
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
    final key = '${_currentItem.id}|${_currentItem.videoPath}|${widget.allLibraryItems.length}';
    if (_memoizedCatalogKey == key) return _cachedSeriesCatalogItem;
    _memoizedCatalogKey = key;

    final targetId = _currentItem.seriesId ?? _currentItem.id;
    MediaItem? found;
    for (final it in widget.allLibraryItems) {
      if (it.id == targetId) {
        found = it;
        break;
      }
      if (it.episodes.any((ep) => _isSamePath(ep.videoPath, _currentItem.videoPath) || ep.id == _currentItem.id)) {
        found = it;
        break;
      }
    }
    if (found == null) {
      final cleanCurrentTitle = _currentItem.title.split(' - ').first.toLowerCase().trim();
      final cleanSeriesTitle = _currentItem.seriesTitle?.split(' - ').first.toLowerCase().trim();
      for (final it in widget.allLibraryItems) {
        final itLower = it.title.toLowerCase().trim();
        if (itLower == cleanCurrentTitle || (cleanSeriesTitle != null && itLower == cleanSeriesTitle)) {
          found = it;
          break;
        }
      }
    }
    _cachedSeriesCatalogItem = found;
    return found;
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
                      _updateState(() => _selectedSeason = val);
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
                                        AnimatedNowPlayingBadge(text: 'Sedang Diputar', isPlaying: _isPlaying)
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
                                            isSeries ? 'Episode ${epNumDisplay.toString().padLeft(2, '0')}' : (hasCustomTitle ? rawEpTitle : 'Video $epNumDisplay'),
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
    final recsKey = '${_currentItem.id}|${_currentItem.videoPath}|${widget.allLibraryItems.length}';
    if (_memoizedRecsKey != recsKey) {
      _memoizedRecsKey = recsKey;
      final currentSeriesOrMediaId = _currentItem.seriesId ?? _currentItem.id;
      final currentSeriesTitle = (_currentItem.seriesTitle ?? _getSeriesTitle(_currentItem)).toLowerCase();
      _cachedRecommendations = widget.allLibraryItems.where((it) {
        final itId = it.seriesId ?? it.id;
        if (itId == currentSeriesOrMediaId || it.id == _currentItem.id || _isSamePath(it.videoPath, _currentItem.videoPath)) {
          return false;
        }
        if (it.title.toLowerCase() == currentSeriesTitle) return false;
        return true;
      }).toList();
    }
    final recommendations = _cachedRecommendations;

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
}
