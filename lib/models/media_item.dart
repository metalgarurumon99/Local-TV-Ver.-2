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
  });

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
    };
  }

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    return MediaItem(
      id: json['id'] as String? ?? 'id-${DateTime.now().millisecondsSinceEpoch}',
      title: json['title'] as String? ?? 'Untitled',
      description: json['description'] as String? ?? '',
      genre: json['genre'] as String? ?? 'Local',
      maturity: json['maturity'] as String? ?? '13',
      slug: json['slug'] as String? ?? 'local-video',
      category: json['category'] as String? ?? 'films',
      videoPath: json['videoPath'] as String? ?? '',
      customThumbnail: json['customThumbnail'] as String?,
      year: json['year'] as String?,
      rating: json['rating'] as String?,
      isManualEdit: json['isManualEdit'] as bool? ?? false,
      folderPath: json['folderPath'] as String?,
    );
  }
}
