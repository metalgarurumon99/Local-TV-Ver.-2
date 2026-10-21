import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class OnlineMetadataResult {
  final String title;
  final String blurb; // Sinopsis / Overview
  final String? posterUrl;
  final String? bannerUrl;
  final String? year;
  final String? rating;
  final String? genre;
  final String source;

  const OnlineMetadataResult({
    required this.title,
    required this.blurb,
    this.posterUrl,
    this.bannerUrl,
    this.year,
    this.rating,
    this.genre,
    required this.source,
  });
}

class OnlineMetadataService {
  static const Duration _timeout = Duration(seconds: 5);

  /// Fetch metadata online from free open APIs (TVMaze & AniList)
  static Future<OnlineMetadataResult?> searchMetadata(String queryTitle) async {
    final clean = queryTitle.trim();
    if (clean.length < 2) return null;

    // 1. Try TVMaze (for Western Movies, TV Shows, Documentaries)
    try {
      final tvMazeResult = await _fetchTVMaze(clean);
      if (tvMazeResult != null) return tvMazeResult;
    } catch (e) {
      debugPrint('TVMaze fetch error: $e');
    }

    // 2. Try AniList (for Anime Series & Anime Movies)
    try {
      final aniListResult = await _fetchAniList(clean);
      if (aniListResult != null) return aniListResult;
    } catch (e) {
      debugPrint('AniList fetch error: $e');
    }

    return null;
  }

  /// TVMaze API - Free & No API Key Required
  static Future<OnlineMetadataResult?> _fetchTVMaze(String title) async {
    final uri = Uri.parse(
      'https://api.tvmaze.com/singlesearch/shows?q=${Uri.encodeComponent(title)}',
    );

    final res = await http.get(uri).timeout(_timeout);
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;

      final name = data['name'] as String? ?? title;
      final rawSummary = data['summary'] as String? ?? '';
      final cleanBlurb = _stripHtml(rawSummary);

      final imageObj = data['image'] as Map<String, dynamic>?;
      final posterUrl = (imageObj?['original'] ?? imageObj?['medium']) as String?;

      final ratingObj = data['rating'] as Map<String, dynamic>?;
      final rating = ratingObj?['average']?.toString();

      final premiered = data['premiered'] as String?;
      final year = premiered != null && premiered.length >= 4 ? premiered.substring(0, 4) : null;

      final genresList = (data['genres'] as List<dynamic>?)?.map((e) => e.toString()).toList();
      final genre = genresList != null && genresList.isNotEmpty ? genresList.join(', ') : 'Drama';

      return OnlineMetadataResult(
        title: name,
        blurb: cleanBlurb.isNotEmpty ? cleanBlurb : 'Tidak ada sinopsis tersedia.',
        posterUrl: posterUrl,
        year: year,
        rating: rating,
        genre: genre,
        source: 'TVMaze',
      );
    }
    return null;
  }

  /// AniList GraphQL API - Free & No API Key Required
  static Future<OnlineMetadataResult?> _fetchAniList(String title) async {
    final uri = Uri.parse('https://graphql.anilist.co');
    const query = r'''
      query ($search: String) {
        Media (search: $search, type: ANIME, sort: SEARCH_MATCH) {
          title {
            english
            romaji
            native
          }
          coverImage {
            extraLarge
            large
          }
          bannerImage
          description
          genres
          averageScore
          seasonYear
        }
      }
    ''';

    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'query': query,
        'variables': {'search': title},
      }),
    ).timeout(_timeout);

    if (res.statusCode == 200) {
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final m = json['data']?['Media'] as Map<String, dynamic>?;
      if (m == null) return null;

      final titleObj = m['title'] as Map<String, dynamic>?;
      final name = titleObj?['english'] ?? titleObj?['romaji'] ?? titleObj?['native'] ?? title;

      final rawDesc = m['description'] as String? ?? '';
      final cleanBlurb = _stripHtml(rawDesc);

      final coverObj = m['coverImage'] as Map<String, dynamic>?;
      final posterUrl = (coverObj?['extraLarge'] ?? coverObj?['large']) as String?;
      final bannerUrl = m['bannerImage'] as String?;

      final score = m['averageScore'] as num?;
      final rating = score != null ? (score / 10).toStringAsFixed(1) : null;

      final year = m['seasonYear']?.toString();
      final genresList = (m['genres'] as List<dynamic>?)?.map((e) => e.toString()).toList();
      final genre = genresList != null && genresList.isNotEmpty ? genresList.join(', ') : 'Anime';

      return OnlineMetadataResult(
        title: name,
        blurb: cleanBlurb.isNotEmpty ? cleanBlurb : 'Sinopsis anime tidak tersedia.',
        posterUrl: posterUrl,
        bannerUrl: bannerUrl,
        year: year,
        rating: rating,
        genre: genre,
        source: 'AniList',
      );
    }
    return null;
  }

  static String _stripHtml(String html) {
    if (html.isEmpty) return '';
    return html
        .replaceAll(RegExp(r'<br\s*[\/]?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&nbsp;', ' ')
        .trim();
  }
}
