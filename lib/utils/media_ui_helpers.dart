import 'package:flutter/material.dart';
import '../models/media_item.dart';

/// Shared UI & media mapping helpers to eliminate duplicated logic across views and components.
class MediaUiHelpers {
  MediaUiHelpers._();

  static final RegExp _res4k = RegExp(r'(?:^|[\s._\-\[\(])(2160p|4k|uhd)(?:$|[\s._\-\]\)])', caseSensitive: false);
  static final RegExp _res1080 = RegExp(r'(?:^|[\s._\-\[\(])(1080p|1080|fhd)(?:$|[\s._\-\]\)])', caseSensitive: false);
  static final RegExp _res720 = RegExp(r'(?:^|[\s._\-\[\(])(720p|720)(?:$|[\s._\-\]\)])', caseSensitive: false);
  static final RegExp _res480 = RegExp(r'(?:^|[\s._\-\[\(])(480p|480)(?:$|[\s._\-\]\)])', caseSensitive: false);

  /// Accurately infer resolution label from video filename without false-positive substring matches.
  static String resolveVideoResolutionLabel(MediaItem item) {
    final path = item.videoPath.isNotEmpty
        ? item.videoPath
        : (item.episodes.isNotEmpty ? item.episodes.first.videoPath : '');
    if (path.isEmpty) return '1080p';
    if (_res4k.hasMatch(path)) return '4K';
    if (_res1080.hasMatch(path)) return '1080p';
    if (_res720.hasMatch(path)) return '720p';
    if (_res480.hasMatch(path)) return '480p';
    return '1080p';
  }

  /// Build a playable episode [MediaItem] preserving all parent metadata (including backdrop2Url & logoUrl).
  static MediaItem buildEpisodeMediaItem({
    required MediaItem parent,
    required Episode episode,
    String? seriesTitleOverride,
    String? seriesIdOverride,
  }) {
    final sTitle = seriesTitleOverride ?? parent.seriesTitle ?? parent.title;
    final sId = seriesIdOverride ?? parent.seriesId ?? parent.id;
    final epLabel = episode.title.isNotEmpty ? episode.title : 'Episode ${episode.episodeNumber}';
    return MediaItem(
      id: episode.id,
      title: '$sTitle - $epLabel',
      description: (episode.synopsis != null && episode.synopsis!.isNotEmpty)
          ? episode.synopsis!
          : parent.description,
      genre: parent.genre,
      maturity: parent.maturity,
      category: parent.category,
      videoPath: episode.videoPath,
      customThumbnail: episode.thumbnail ?? parent.customThumbnail,
      backdropUrl: parent.backdropUrl,
      backdrop2Url: parent.backdrop2Url,
      logoUrl: parent.logoUrl,
      cast: parent.cast,
      director: parent.director,
      year: parent.year,
      rating: parent.rating,
      isSeries: true,
      episodes: parent.episodes,
      seriesId: sId,
      seriesTitle: sTitle,
      seasonNumber: episode.season,
      episodeNumber: episode.episodeNumber,
      episodeTitle: episode.title,
    );
  }

  /// Unified floating SnackBar shown when a user clicks an offline/disconnected media item.
  static void showDisconnectedStorageSnackBar(BuildContext context, String title) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF222222),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        content: Row(
          children: [
            const Icon(Icons.cloud_off_rounded, color: Color(0xFFE50914), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Folder penyimpanan untuk "$title" sedang tidak terhubung. Sambungkan drive atau periksa folder di Pengaturan.',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
