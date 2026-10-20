class MediaItem {
  final String id;
  final String title;
  final String description;
  final String genre;
  final String maturity;
  final String slug;
  final String category; // 'series' or 'films'
  final String videoPath;
  final String? customThumbnail;

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
  });

  String get thumbnailPath {
    if (customThumbnail != null) return customThumbnail!;
    return 'assets/images/$category/$genre/$slug/small.jpg';
  }

  String get largePosterPath {
    if (customThumbnail != null) return customThumbnail!;
    return 'assets/images/$category/$genre/$slug/large.jpg';
  }
}
