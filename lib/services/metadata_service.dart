import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'app_settings_service.dart';

class EpisodeOnlineMetadata {
  final int season;
  final int episodeNumber;
  final String title;
  final String synopsis;
  final String? thumbnailUrl;
  final String? duration;

  const EpisodeOnlineMetadata({
    required this.season,
    required this.episodeNumber,
    required this.title,
    required this.synopsis,
    this.thumbnailUrl,
    this.duration,
  });
}

class OnlineMetadataResult {
  final String title;
  final String blurb; // Sinopsis / Overview
  final String? posterUrl;
  final String? bannerUrl;
  final String? banner2Url;
  final String? logoUrl;
  final String? year;
  final String? rating;
  final String? genre;
  final String source;
  final List<EpisodeOnlineMetadata> episodes;
  final List<String> cast;
  final String? director;

  const OnlineMetadataResult({
    required this.title,
    required this.blurb,
    this.posterUrl,
    this.bannerUrl,
    this.banner2Url,
    this.logoUrl,
    this.year,
    this.rating,
    this.genre,
    required this.source,
    this.episodes = const [],
    this.cast = const [],
    this.director,
  });
}

class OnlineMetadataService {
  static const Duration _timeout = Duration(seconds: 6);
  static final http.Client _httpClient = http.Client();

  static Map<String, dynamic> _decodeJson(http.Response res) {
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  // TMDB API Key resolved from Settings UI or build-time `--dart-define=TMDB_API_KEY=...`
  // (Never hardcoded in public source code!)
  static const String _envApiKey = String.fromEnvironment('TMDB_API_KEY', defaultValue: '');

  static String get _apiKey {
    final userKey = AppSettingsService.instance.tmdbApiKey.trim();
    if (userKey.isNotEmpty) return userKey;
    return _envApiKey.trim();
  }

  static bool get hasApiKey => _apiKey.isNotEmpty;
  static bool get isUsingCustomKey => AppSettingsService.instance.tmdbApiKey.trim().isNotEmpty;
  static bool get hasBuiltInKey => _envApiKey.trim().isNotEmpty;

  static const String _apiBaseUrl = 'https://api.themoviedb.org/3';

  // Optimized TMDB Image CDN URLs (Preventing large original files)
  // w500 for Posters (~50-80 KB)
  // w780 for Backdrops/Banners (~80-120 KB)
  // w300 for Episode Stills (~20-30 KB)
  static const String _posterBaseUrl = 'https://image.tmdb.org/t/p/w500';
  static const String _backdropBaseUrl = 'https://image.tmdb.org/t/p/w780';
  static const String _stillBaseUrl = 'https://image.tmdb.org/t/p/w300';

  /// Primary metadata search via TMDB (The Movie Database).
  /// Pass [localSeasons] to fetch exact seasons present on disk (supporting Season 6+, 10+, etc.).
  static Future<OnlineMetadataResult?> searchMetadata(
    String queryTitle, {
    bool isSeries = false,
    Set<int>? localSeasons,
  }) async {
    if (!hasApiKey) return null;
    final clean = _cleanQueryTitle(queryTitle);
    if (clean.length < 2) return null;

    try {
      final tmdbResult = await _fetchTMDB(clean, preferTv: isSeries, localSeasons: localSeasons);
      if (tmdbResult != null) return tmdbResult;
    } catch (e) {
      debugPrint('TMDB fetch error for "$clean": $e');
    }

    return null;
  }

  /// Detects whether text contains East Asian characters (Japanese Kanji/Kana, Korean Hangul, Chinese Hanzi)
  static bool _containsAsianCharacters(String text) {
    if (text.isEmpty) return false;
    return RegExp(r'[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uac00-\ud7af]').hasMatch(text);
  }

  /// Selects the best human-readable title, prioritizing English over Japanese/Kanji original names.
  static String _resolveEffectiveTitle(String? idTitle, String? enTitle, String originalQuery) {
    final en = (enTitle ?? '').trim();
    final id = (idTitle ?? '').trim();

    // If English title is available and in Latin script, strongly prefer it for international readability
    if (en.isNotEmpty && !_containsAsianCharacters(en)) {
      return en;
    }

    // If Indonesian title is in Latin script (e.g. Indonesian local movies)
    if (id.isNotEmpty && !_containsAsianCharacters(id)) {
      return id;
    }

    // Fallbacks
    if (en.isNotEmpty) return en;
    if (id.isNotEmpty) return id;
    return originalQuery;
  }

  /// Clean query title from common scene tags, release groups, and resolutions
  static String _cleanQueryTitle(String raw) {
    var text = raw.trim();

    // Remove file extensions
    text = text.replaceAll(RegExp(r'\.(mkv|mp4|avi|mov|wmv|flv|webm)$', caseSensitive: false), '');

    // Remove bracketed release info like [HorribleSubs], [1080p], (2020), etc.
    text = text.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
    text = text.replaceAll(RegExp(r'\([^\)]*\)'), ' ');

    // Remove common video tags
    text = text.replaceAll(RegExp(r'\b(1080p|720p|480p|4k|2160p|bluray|bdrip|web-dl|webrip|x264|x265|hevc|aac|dts)\b', caseSensitive: false), ' ');

    // Remove episode or season suffixes if any
    text = text.replaceAll(RegExp(r'\b(season\s*\d+|s\d+\s*e\d+|s\d+|ep\s*\d+|episode\s*\d+)\b', caseSensitive: false), ' ');

    // Normalize separators
    text = text.replaceAll(RegExp(r'[._]+'), ' ');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    return text;
  }

  /// Query TMDB Multi-Search (Movies & TV Series)
  static Future<OnlineMetadataResult?> _fetchTMDB(
    String title, {
    bool preferTv = false,
    Set<int>? localSeasons,
  }) async {
    // 1. Search TMDB
    final searchUri = Uri.parse(
      '$_apiBaseUrl/search/multi?api_key=$_apiKey&query=${Uri.encodeComponent(title)}&language=en-US&include_adult=false',
    );

    final res = await _httpClient.get(searchUri).timeout(_timeout);
    if (res.statusCode != 200) return null;

    final data = _decodeJson(res);
    final results = data['results'] as List<dynamic>?;
    if (results == null || results.isEmpty) {
      // Try searching TV specifically if multi returned nothing
      return await _fetchTMDBTvDirect(title, localSeasons: localSeasons);
    }

    // Pick top movie or tv item, respecting preferTv for series
    Map<String, dynamic>? match;
    for (final item in results) {
      if (item is Map<String, dynamic>) {
        final mediaType = item['media_type'] as String?;
        if (preferTv && mediaType == 'tv') {
          match = item;
          break;
        } else if (!preferTv && (mediaType == 'movie' || mediaType == 'tv')) {
          match = item;
          break;
        }
      }
    }

    match ??= results.firstWhere(
      (item) => item is Map<String, dynamic> && (item['media_type'] == 'tv' || item['media_type'] == 'movie'),
      orElse: () => null,
    ) as Map<String, dynamic>?;

    if (match == null) return null;

    final id = match['id'] as int?;
    final mediaType = match['media_type'] as String? ?? (preferTv ? 'tv' : 'movie');
    if (id == null) return null;

    if (mediaType == 'tv') {
      return await _fetchTvDetails(id, title, localSeasons: localSeasons);
    } else {
      return await _fetchMovieDetails(id, title);
    }
  }

  /// Fallback direct TV search if multi-search yields nothing
  static Future<OnlineMetadataResult?> _fetchTMDBTvDirect(
    String title, {
    Set<int>? localSeasons,
  }) async {
    final searchUri = Uri.parse(
      '$_apiBaseUrl/search/tv?api_key=$_apiKey&query=${Uri.encodeComponent(title)}&language=en-US&include_adult=false',
    );
    final res = await _httpClient.get(searchUri).timeout(_timeout);
    if (res.statusCode != 200) return null;

    final data = _decodeJson(res);
    final results = data['results'] as List<dynamic>?;
    if (results == null || results.isEmpty) return null;

    final match = results.first as Map<String, dynamic>;
    final id = match['id'] as int?;
    if (id == null) return null;

    return await _fetchTvDetails(id, title, localSeasons: localSeasons);
  }

  /// Fetch TV Show Details, Credits (Cast & Director), Logos, and Season/Episode info in parallel
  static Future<OnlineMetadataResult?> _fetchTvDetails(
    int tvId,
    String originalQuery, {
    Set<int>? localSeasons,
  }) async {
    final idUri = Uri.parse('$_apiBaseUrl/tv/$tvId?api_key=$_apiKey&language=id-ID');
    final enUri = Uri.parse(
      '$_apiBaseUrl/tv/$tvId?api_key=$_apiKey&language=en-US&append_to_response=images,credits&include_image_language=en,null',
    );

    final responses = await Future.wait<http.Response?>([
      _httpClient.get(idUri).timeout(_timeout).then<http.Response?>((r) => r).catchError((_) => null),
      _httpClient.get(enUri).timeout(_timeout).then<http.Response?>((r) => r).catchError((_) => null),
    ]);

    final idRes = responses[0];
    final enRes = responses[1];
    if (enRes == null || enRes.statusCode != 200) return null;

    Map<String, dynamic>? idData;
    if (idRes != null && idRes.statusCode == 200) {
      try {
        idData = _decodeJson(idRes);
      } catch (_) {}
    }
    final enData = _decodeJson(enRes);

    // Prefer Indonesian title & overview if available and valid
    final idOverview = (idData?['overview'] as String? ?? '').trim();
    final enOverview = (enData['overview'] as String? ?? '').trim();
    final overview = idOverview.isNotEmpty ? idOverview : (enOverview.isNotEmpty ? enOverview : 'Sinopsis tidak tersedia.');

    final enName = (enData['name'] as String? ?? '').trim();
    final idName = (idData?['name'] as String? ?? '').trim();
    final effectiveTitle = _resolveEffectiveTitle(idName, enName, originalQuery);

    // Poster & Dual Backdrops (Optimized CDN URLs)
    final posterPath = (idData?['poster_path'] ?? enData['poster_path']) as String?;
    final backdropPath = (idData?['backdrop_path'] ?? enData['backdrop_path']) as String?;
    final posterUrl = posterPath != null ? '$_posterBaseUrl$posterPath' : null;
    String? bannerUrl = backdropPath != null ? '$_backdropBaseUrl$backdropPath' : null;
    String? banner2Url;

    final imagesObj = enData['images'] as Map<String, dynamic>?;
    final backdropsList = imagesObj?['backdrops'] as List<dynamic>? ?? [];
    for (final b in backdropsList) {
      if (b is Map<String, dynamic>) {
        final p = b['file_path'] as String?;
        if (p != null && p.isNotEmpty) {
          final full = '$_backdropBaseUrl$p';
          if (bannerUrl == null) {
            bannerUrl = full;
          } else if (full != bannerUrl) {
            banner2Url = full;
            break;
          }
        }
      }
    }

    // Rating & Year
    final voteAvg = (enData['vote_average'] as num?)?.toDouble();
    final rating = voteAvg != null && voteAvg > 0 ? voteAvg.toStringAsFixed(1) : null;
    final firstAir = enData['first_air_date'] as String?;
    final year = firstAir != null && firstAir.length >= 4 ? firstAir.substring(0, 4) : null;

    // Genres
    final genresList = (enData['genres'] as List<dynamic>?)
        ?.map((g) => (g as Map<String, dynamic>)['name']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
    final genre = genresList != null && genresList.isNotEmpty ? genresList.join(', ') : 'Series & Anime';

    // Credits (Cast & Director) extracted directly from append_to_response=credits
    List<String> cast = [];
    String? director;
    final creditsData = enData['credits'] as Map<String, dynamic>?;
    if (creditsData != null) {
      final rawCast = creditsData['cast'] as List<dynamic>? ?? [];
      cast = rawCast
          .take(6)
          .map((c) => (c as Map<String, dynamic>)['name']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .toList();

      final rawCrew = creditsData['crew'] as List<dynamic>? ?? [];
      for (final c in rawCrew) {
        if (c is Map<String, dynamic>) {
          final job = (c['job'] as String? ?? '').toLowerCase();
          if (job == 'director' || job == 'series director' || job == 'creator') {
            director = c['name'] as String?;
            break;
          }
        }
      }
    }

    // Fallback director from 'created_by' in TV details
    if (director == null || director.isEmpty) {
      final createdByList = enData['created_by'] as List<dynamic>?;
      if (createdByList != null && createdByList.isNotEmpty) {
        director = (createdByList.first as Map<String, dynamic>)['name'] as String?;
      }
    }

    // Fetch Episodes for seasons that actually exist on disk (no arbitrary 5-season cap!)
    final rawSeasons = enData['seasons'] as List<dynamic>? ?? [];
    final Set<int> availableTmdbSeasons = {};
    for (final s in rawSeasons) {
      if (s is Map<String, dynamic>) {
        final seasonNum = (s['season_number'] as num?)?.toInt() ?? 0;
        if (seasonNum > 0) availableTmdbSeasons.add(seasonNum);
      }
    }

    final List<int> seasonNumbers;
    if (localSeasons != null && localSeasons.isNotEmpty) {
      final matched = localSeasons.where((s) => s > 0 && availableTmdbSeasons.contains(s)).toList()..sort();
      if (matched.isNotEmpty) {
        seasonNumbers = matched;
      } else {
        // Fallback if local folder uses custom numbering not directly matching TMDB season index
        seasonNumbers = (availableTmdbSeasons.toList()..sort()).take(5).toList();
      }
    } else {
      seasonNumbers = (availableTmdbSeasons.toList()..sort()).take(5).toList();
    }

    final seasonResults = await Future.wait(
      seasonNumbers.map((seasonNum) async {
        final List<EpisodeOnlineMetadata> eps = [];
        try {
          final seasonUri = Uri.parse('$_apiBaseUrl/tv/$tvId/season/$seasonNum?api_key=$_apiKey&language=en-US');
          final seasonRes = await _httpClient.get(seasonUri).timeout(_timeout);
          if (seasonRes.statusCode == 200) {
            final seasonData = _decodeJson(seasonRes);
            final rawEps = seasonData['episodes'] as List<dynamic>? ?? [];
            for (final ep in rawEps) {
              if (ep is Map<String, dynamic>) {
                final epNum = (ep['episode_number'] as num?)?.toInt() ?? 1;
                final epName = ep['name'] as String? ?? 'Episode $epNum';
                final epOverview = (ep['overview'] as String? ?? '').trim();
                final stillPath = ep['still_path'] as String?;
                final stillUrl = stillPath != null ? '$_stillBaseUrl$stillPath' : null;
                final runtime = (ep['runtime'] as num?)?.toInt();
                final durationStr = runtime != null && runtime > 0 ? '${runtime}m' : null;

                eps.add(EpisodeOnlineMetadata(
                  season: seasonNum,
                  episodeNumber: epNum,
                  title: epName,
                  synopsis: epOverview,
                  thumbnailUrl: stillUrl,
                  duration: durationStr,
                ));
              }
            }
          }
        } catch (e) {
          debugPrint('Error fetching Season $seasonNum for TV $tvId: $e');
        }
        return eps;
      }),
    );

    final List<EpisodeOnlineMetadata> episodeList = [
      for (final s in seasonResults) ...s,
    ];

    final logoUrl = _pickBestLogoFromImages(imagesObj);

    return OnlineMetadataResult(
      title: effectiveTitle,
      blurb: overview,
      posterUrl: posterUrl,
      bannerUrl: bannerUrl,
      banner2Url: banner2Url,
      logoUrl: logoUrl,
      year: year,
      rating: rating,
      genre: genre,
      source: 'TMDB',
      episodes: episodeList,
      cast: cast,
      director: director,
    );
  }

  /// Fetch Movie Details, Credits, and Logos in parallel
  static Future<OnlineMetadataResult?> _fetchMovieDetails(int movieId, String originalQuery) async {
    final idUri = Uri.parse('$_apiBaseUrl/movie/$movieId?api_key=$_apiKey&language=id-ID');
    final enUri = Uri.parse(
      '$_apiBaseUrl/movie/$movieId?api_key=$_apiKey&language=en-US&append_to_response=images,credits&include_image_language=en,null',
    );

    final responses = await Future.wait<http.Response?>([
      _httpClient.get(idUri).timeout(_timeout).then<http.Response?>((r) => r).catchError((_) => null),
      _httpClient.get(enUri).timeout(_timeout).then<http.Response?>((r) => r).catchError((_) => null),
    ]);

    final idRes = responses[0];
    final enRes = responses[1];
    if (enRes == null || enRes.statusCode != 200) return null;

    Map<String, dynamic>? idData;
    if (idRes != null && idRes.statusCode == 200) {
      try {
        idData = _decodeJson(idRes);
      } catch (_) {}
    }
    final enData = _decodeJson(enRes);

    final idOverview = (idData?['overview'] as String? ?? '').trim();
    final enOverview = (enData['overview'] as String? ?? '').trim();
    final overview = idOverview.isNotEmpty ? idOverview : (enOverview.isNotEmpty ? enOverview : 'Sinopsis tidak tersedia.');

    final enTitle = (enData['title'] as String? ?? '').trim();
    final idTitle = (idData?['title'] as String? ?? '').trim();
    final effectiveTitle = _resolveEffectiveTitle(idTitle, enTitle, originalQuery);

    final posterPath = (idData?['poster_path'] ?? enData['poster_path']) as String?;
    final backdropPath = (idData?['backdrop_path'] ?? enData['backdrop_path']) as String?;
    final posterUrl = posterPath != null ? '$_posterBaseUrl$posterPath' : null;
    String? bannerUrl = backdropPath != null ? '$_backdropBaseUrl$backdropPath' : null;
    String? banner2Url;

    final imagesObj = enData['images'] as Map<String, dynamic>?;
    final backdropsList = imagesObj?['backdrops'] as List<dynamic>? ?? [];
    for (final b in backdropsList) {
      if (b is Map<String, dynamic>) {
        final p = b['file_path'] as String?;
        if (p != null && p.isNotEmpty) {
          final full = '$_backdropBaseUrl$p';
          if (bannerUrl == null) {
            bannerUrl = full;
          } else if (full != bannerUrl) {
            banner2Url = full;
            break;
          }
        }
      }
    }

    final voteAvg = (enData['vote_average'] as num?)?.toDouble();
    final rating = voteAvg != null && voteAvg > 0 ? voteAvg.toStringAsFixed(1) : null;
    final releaseDate = enData['release_date'] as String?;
    final year = releaseDate != null && releaseDate.length >= 4 ? releaseDate.substring(0, 4) : null;

    final genresList = (enData['genres'] as List<dynamic>?)
        ?.map((g) => (g as Map<String, dynamic>)['name']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
    final genre = genresList != null && genresList.isNotEmpty ? genresList.join(', ') : 'Film';

    // Credits extracted directly from append_to_response=credits
    List<String> cast = [];
    String? director;
    final creditsData = enData['credits'] as Map<String, dynamic>?;
    if (creditsData != null) {
      final rawCast = creditsData['cast'] as List<dynamic>? ?? [];
      cast = rawCast
          .take(6)
          .map((c) => (c as Map<String, dynamic>)['name']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .toList();

      final rawCrew = creditsData['crew'] as List<dynamic>? ?? [];
      for (final c in rawCrew) {
        if (c is Map<String, dynamic>) {
          final job = (c['job'] as String? ?? '').toLowerCase();
          if (job == 'director') {
            director = c['name'] as String?;
            break;
          }
        }
      }
    }

    final logoUrl = _pickBestLogoFromImages(imagesObj);

    return OnlineMetadataResult(
      title: effectiveTitle,
      blurb: overview,
      posterUrl: posterUrl,
      bannerUrl: bannerUrl,
      banner2Url: banner2Url,
      logoUrl: logoUrl,
      year: year,
      rating: rating,
      genre: genre,
      source: 'TMDB',
      cast: cast,
      director: director,
    );
  }

  /// Pick best official PNG logo from appended TMDB images object (0 extra HTTP calls)
  static String? _pickBestLogoFromImages(Map<String, dynamic>? imagesObj) {
    final logos = imagesObj?['logos'] as List<dynamic>? ?? [];
    if (logos.isEmpty) return null;

    bool isPng(dynamic path) => path is String && path.toLowerCase().endsWith('.png');

    for (final l in logos) {
      if (l is Map<String, dynamic> && l['iso_639_1'] == 'en' && isPng(l['file_path'])) {
        return '$_posterBaseUrl${l['file_path']}';
      }
    }
    for (final l in logos) {
      if (l is Map<String, dynamic> && (l['iso_639_1'] == null || l['iso_639_1'] == '') && isPng(l['file_path'])) {
        return '$_posterBaseUrl${l['file_path']}';
      }
    }
    for (final l in logos) {
      if (l is Map<String, dynamic> && isPng(l['file_path'])) {
        return '$_posterBaseUrl${l['file_path']}';
      }
    }
    for (final l in logos) {
      if (l is Map<String, dynamic> && l['file_path'] != null) {
        return '$_posterBaseUrl${l['file_path']}';
      }
    }
    return null;
  }
}
