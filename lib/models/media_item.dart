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
  );
}

class MediaItem {
  final String id;
  final String title;
  final String description; // Blurb / Sinopsis
  final String genre;
  final String maturity;
  final String slug;
  final String category; // 'series' or 'films'
  final String videoPath;
  final String? customThumbnail; // URL http/https or local disk path
  final String? year;
  final String? rating;
  final bool isManualEdit;
  final String? folderPath;
  final bool isSeries;
  final List<Episode> episodes;

  const MediaItem({
    required this.id,
    required this.title,
    required this.description,
    required this.genre,
    required this.maturity,
    required this.slug,
    required this.category,
    this.videoPath = 'asset://assets/videos/bunny.mp4',
    this.customThumbnail,
    this.year,
    this.rating,
    this.isManualEdit = false,
    this.folderPath,
    this.isSeries = false,
    this.episodes = const [],
  });

  int get episodeCount => episodes.length;

  bool get isNetworkImage {
    if (customThumbnail == null) return false;
    return customThumbnail!.startsWith('http://') || customThumbnail!.startsWith('https://');
  }

  bool get isLocalImage {
    if (customThumbnail == null) return false;
    return !isNetworkImage && !customThumbnail!.startsWith('asset://') && !customThumbnail!.startsWith('assets/');
  }

  String get thumbnailPath {
    if (customThumbnail != null) return customThumbnail!;
    return 'assets/images/$category/$genre/$slug/small.jpg';
  }

  String get largePosterPath {
    if (customThumbnail != null) return customThumbnail!;
    return 'assets/images/$category/$genre/$slug/large.jpg';
  }

  MediaItem copyWith({
    String? id,
    String? title,
    String? description,
    String? genre,
    String? maturity,
    String? slug,
    String? category,
    String? videoPath,
    String? customThumbnail,
    String? year,
    String? rating,
    bool? isManualEdit,
    String? folderPath,
    bool? isSeries,
    List<Episode>? episodes,
  }) {
    return MediaItem(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      genre: genre ?? this.genre,
      maturity: maturity ?? this.maturity,
      slug: slug ?? this.slug,
      category: category ?? this.category,
      videoPath: videoPath ?? this.videoPath,
      customThumbnail: customThumbnail ?? this.customThumbnail,
      year: year ?? this.year,
      rating: rating ?? this.rating,
      isManualEdit: isManualEdit ?? this.isManualEdit,
      folderPath: folderPath ?? this.folderPath,
      isSeries: isSeries ?? this.isSeries,
      episodes: episodes ?? this.episodes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'genre': genre,
      'maturity': maturity,
      'slug': slug,
      'category': category,
      'videoPath': videoPath,
      'customThumbnail': customThumbnail,
      'year': year,
      'rating': rating,
      'isManualEdit': isManualEdit,
      'folderPath': folderPath,
      'isSeries': isSeries,
      'episodes': episodes.map((e) => e.toJson()).toList(),
    };
  }

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    var rawEpisodes = json['episodes'] as List<dynamic>? ?? [];
    var episodeList = rawEpisodes
        .map((e) => Episode.fromJson(e as Map<String, dynamic>))
        .toList();

    return MediaItem(
      id: json['id'] as String? ?? 'id-${DateTime.now().millisecondsSinceEpoch}',
      title: json['title'] as String? ?? 'Tanpa Judul',
      description: json['description'] as String? ?? '',
      genre: json['genre'] as String? ?? 'Koleksi Lokal',
      maturity: json['maturity'] as String? ?? '13',
      slug: json['slug'] as String? ?? 'local-video',
      category: json['category'] as String? ?? 'films',
      videoPath: json['videoPath'] as String? ?? '',
      customThumbnail: json['customThumbnail'] as String?,
      year: json['year'] as String?,
      rating: json['rating'] as String?,
      isManualEdit: json['isManualEdit'] as bool? ?? false,
      folderPath: json['folderPath'] as String?,
      isSeries: json['isSeries'] as bool? ?? false,
      episodes: episodeList,
    );
  }
}
