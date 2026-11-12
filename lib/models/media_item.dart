class Episode {
  final String id;
  final String title;
  final String videoPath;
  final int season;
  final int episodeNumber;
  final int? fileSize;
  final String? duration;
  final String? synopsis;
  final String? thumbnail;
  final String seasonName; // e.g. "Season 1", "Elbaph Arc", "Extras / Spesial", "OVA"

  const Episode({
    required this.id,
    required this.title,
    required this.videoPath,
    this.season = 1,
    this.episodeNumber = 1,
    this.fileSize,
    this.duration,
    this.synopsis,
    this.thumbnail,
    this.seasonName = 'Season 1',
  });

  Episode copyWith({
    String? id,
    String? title,
    String? videoPath,
    int? season,
    int? episodeNumber,
    int? fileSize,
    String? duration,
    String? synopsis,
    String? thumbnail,
    String? seasonName,
  }) {
    return Episode(
      id: id ?? this.id,
      title: title ?? this.title,
      videoPath: videoPath ?? this.videoPath,
      season: season ?? this.season,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      fileSize: fileSize ?? this.fileSize,
      duration: duration ?? this.duration,
      synopsis: synopsis ?? this.synopsis,
      thumbnail: thumbnail ?? this.thumbnail,
      seasonName: seasonName ?? this.seasonName,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'videoPath': videoPath,
    'season': season,
    'episodeNumber': episodeNumber,
    'fileSize': fileSize,
    'duration': duration,
    'synopsis': synopsis,
    'thumbnail': thumbnail,
    'seasonName': seasonName,
  };

  factory Episode.fromJson(Map<String, dynamic> json) => Episode(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    videoPath: json['videoPath'] as String? ?? '',
    season: (json['season'] as num?)?.toInt() ?? 1,
    episodeNumber: (json['episodeNumber'] as num?)?.toInt() ?? 1,
    fileSize: (json['fileSize'] as num?)?.toInt(),
    duration: json['duration'] as String?,
    synopsis: json['synopsis'] as String?,
    thumbnail: json['thumbnail'] as String?,
    seasonName: json['seasonName'] as String? ??
        ((json['season'] as num?)?.toInt() == 0 ? 'Extras / Spesial' : 'Season ${(json['season'] as num?)?.toInt() ?? 1}'),
  );
}

class MediaItem {
  final String id;
  final String title;
  final String description; // Blurb / Sinopsis
  final String genre;
  final String maturity;
  final String category; // 'series' or 'films'
  final String videoPath;
  final String? customThumbnail; // URL http/https or local disk path
  final String? year;
  final String? rating;
  final bool isManualEdit;
  final bool isOnlineChecked;
  final String? folderPath;
  final bool isSeries;
  final List<Episode> episodes;
  final String? seriesId;
  final String? seriesTitle;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? episodeTitle;
  final List<String> cast;
  final String? director;
  final String? backdropUrl;
  final String? backdrop2Url;
  final String? logoUrl;

  const MediaItem({
    required this.id,
    required this.title,
    required this.description,
    required this.genre,
    required this.maturity,
    required this.category,
    this.videoPath = '',
    this.customThumbnail,
    this.year,
    this.rating,
    this.isManualEdit = false,
    this.isOnlineChecked = false,
    this.folderPath,
    this.isSeries = false,
    this.episodes = const [],
    this.seriesId,
    this.seriesTitle,
    this.seasonNumber,
    this.episodeNumber,
    this.episodeTitle,
    this.cast = const [],
    this.director,
    this.backdropUrl,
    this.backdrop2Url,
    this.logoUrl,
  });

  int get episodeCount => episodes.length;

  static final Expando<String> _searchIndexCache = Expando<String>();

  /// Precomputed lowercase search index to enable ultra-fast sub-millisecond filtering on keystrokes
  String get searchIndex {
    final cached = _searchIndexCache[this];
    if (cached != null) return cached;
    final sb = StringBuffer();
    sb.write(title.toLowerCase());
    sb.write(' ');
    sb.write(genre.toLowerCase());
    sb.write(' ');
    sb.write(description.toLowerCase());
    if (year != null) {
      sb.write(' ');
      sb.write(year!.toLowerCase());
    }
    for (final ep in episodes) {
      if (ep.title.isNotEmpty) {
        sb.write(' ');
        sb.write(ep.title.toLowerCase());
      }
    }
    final result = sb.toString();
    _searchIndexCache[this] = result;
    return result;
  }

  bool matchesSearchQuery(String query) {
    if (query.isEmpty) return true;
    return searchIndex.contains(query);
  }

  /// Returns unique list of season / arc names preserving order
  List<String> get availableSeasonNames {
    final Set<String> names = {};
    for (final ep in episodes) {
      if (ep.seasonName.isNotEmpty) {
        names.add(ep.seasonName);
      }
    }
    if (names.isEmpty) {
      return ['Season 1'];
    }
    return names.toList();
  }

  bool get isNetworkImage {
    if (customThumbnail == null) return false;
    return customThumbnail!.startsWith('http://') || customThumbnail!.startsWith('https://');
  }

  bool get isLocalImage {
    if (customThumbnail == null) return false;
    return !isNetworkImage && !customThumbnail!.startsWith('asset://') && !customThumbnail!.startsWith('assets/');
  }

  String get thumbnailPath {
    return customThumbnail ?? '';
  }

  String get largePosterPath {
    return customThumbnail ?? '';
  }

  MediaItem copyWith({
    String? id,
    String? title,
    String? description,
    String? genre,
    String? maturity,
    String? category,
    String? videoPath,
    String? customThumbnail,
    String? year,
    String? rating,
    bool? isManualEdit,
    bool? isOnlineChecked,
    String? folderPath,
    bool? isSeries,
    List<Episode>? episodes,
    String? seriesId,
    String? seriesTitle,
    int? seasonNumber,
    int? episodeNumber,
    String? episodeTitle,
    List<String>? cast,
    String? director,
    String? backdropUrl,
    String? backdrop2Url,
    String? logoUrl,
  }) {
    return MediaItem(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      genre: genre ?? this.genre,
      maturity: maturity ?? this.maturity,
      category: category ?? this.category,
      videoPath: videoPath ?? this.videoPath,
      customThumbnail: customThumbnail ?? this.customThumbnail,
      year: year ?? this.year,
      rating: rating ?? this.rating,
      isManualEdit: isManualEdit ?? this.isManualEdit,
      isOnlineChecked: isOnlineChecked ?? this.isOnlineChecked,
      folderPath: folderPath ?? this.folderPath,
      isSeries: isSeries ?? this.isSeries,
      episodes: episodes ?? this.episodes,
      seriesId: seriesId ?? this.seriesId,
      seriesTitle: seriesTitle ?? this.seriesTitle,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      episodeTitle: episodeTitle ?? this.episodeTitle,
      cast: cast ?? this.cast,
      director: director ?? this.director,
      backdropUrl: backdropUrl ?? this.backdropUrl,
      backdrop2Url: backdrop2Url ?? this.backdrop2Url,
      logoUrl: logoUrl ?? this.logoUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'genre': genre,
      'maturity': maturity,
      'category': category,
      'videoPath': videoPath,
      'customThumbnail': customThumbnail,
      'year': year,
      'rating': rating,
      'isManualEdit': isManualEdit,
      'isOnlineChecked': isOnlineChecked,
      'folderPath': folderPath,
      'isSeries': isSeries,
      'episodes': episodes.map((e) => e.toJson()).toList(),
      'seriesId': seriesId,
      'seriesTitle': seriesTitle,
      'seasonNumber': seasonNumber,
      'episodeNumber': episodeNumber,
      'episodeTitle': episodeTitle,
      'cast': cast,
      'director': director,
      'backdropUrl': backdropUrl,
      'backdrop2Url': backdrop2Url,
      'logoUrl': logoUrl,
    };
  }

  static String _cleanString(String? text, String fallback) {
    if (text == null || text.isEmpty) return fallback;
    return text
        .replaceAll('â˜†', ' ')
        .replaceAll('â˜…', ' ')
        .replaceAll('☆', ' ')
        .replaceAll('★', ' ')
        .replaceAll('â€¢', ' • ')
        .replaceAll('â€™', "'")
        .replaceAll('â€œ', '"')
        .replaceAll('â€', '"')
        .replaceAll('Ã—', 'x')
        .replaceAll('Â', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    var rawEpisodes = json['episodes'] as List<dynamic>? ?? [];
    var episodeList = rawEpisodes
        .map((e) => Episode.fromJson(e as Map<String, dynamic>))
        .toList();

    return MediaItem(
      id: json['id'] as String? ?? 'id-${DateTime.now().millisecondsSinceEpoch}',
      title: _cleanString(json['title'] as String?, 'Tanpa Judul'),
      description: _cleanString(json['description'] as String?, ''),
      genre: _cleanString(json['genre'] as String?, 'Koleksi Lokal'),
      maturity: json['maturity'] as String? ?? '13',
      category: json['category'] as String? ?? 'films',
      videoPath: json['videoPath'] as String? ?? '',
      customThumbnail: json['customThumbnail'] as String?,
      year: json['year'] as String?,
      rating: json['rating'] as String?,
      isManualEdit: json['isManualEdit'] as bool? ?? false,
      isOnlineChecked: json['isOnlineChecked'] as bool? ?? (json['customThumbnail'] != null),
      folderPath: json['folderPath'] as String?,
      isSeries: json['isSeries'] as bool? ?? false,
      episodes: episodeList,
      seriesId: json['seriesId'] as String?,
      seriesTitle: json['seriesTitle'] as String?,
      seasonNumber: (json['seasonNumber'] as num?)?.toInt(),
      episodeNumber: (json['episodeNumber'] as num?)?.toInt(),
      episodeTitle: json['episodeTitle'] as String?,
      cast: (json['cast'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      director: json['director'] as String?,
      backdropUrl: json['backdropUrl'] as String?,
      backdrop2Url: json['backdrop2Url'] as String?,
      logoUrl: json['logoUrl'] as String?,
    );
  }
}
