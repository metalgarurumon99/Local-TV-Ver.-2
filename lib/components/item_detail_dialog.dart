import 'dart:io';
import 'package:flutter/material.dart';
import '../models/media_item.dart';

class ItemDetailDialog extends StatelessWidget {
  final MediaItem item;
  final VoidCallback onPlay;
  final VoidCallback? onEdit;
  final ValueChanged<Episode>? onPlayEpisode;

  const ItemDetailDialog({
    super.key,
    required this.item,
    required this.onPlay,
    this.onEdit,
    this.onPlayEpisode,
  });

  Widget _buildBackdropImage() {
    if (item.isNetworkImage) {
      return Image.network(
        item.customThumbnail!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildPlaceholder(),
      );
    }
    if (item.customThumbnail != null && File(item.customThumbnail!).existsSync()) {
      return Image.file(
        File(item.customThumbnail!),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildPlaceholder(),
      );
    }
    return Image.asset(
      item.largePosterPath,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Image.asset(
        item.thumbnailPath,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildPlaceholder(),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFF222222),
      child: const Center(
        child: Icon(Icons.movie, size: 60, color: Colors.white24),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Dialog(
      backgroundColor: const Color(0xFF181818),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight: screenHeight * 0.9,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Backdrop Image with Gradient
              Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: _buildBackdropImage(),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            const Color(0xFF181818).withValues(alpha: 0.8),
                            const Color(0xFF181818),
                          ],
                          stops: const [0.4, 0.8, 1.0],
                        ),
                      ),
                    ),
                  ),
                  // Close Button
                  Positioned(
                    top: 16,
                    right: 16,
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                  // Title & Action on Backdrop
                  Positioned(
                    left: 32,
                    bottom: 24,
                    right: 32,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(context).pop();
                                onPlay();
                              },
                              icon: const Icon(Icons.play_arrow, color: Colors.black, size: 24),
                              label: Text(
                                item.isSeries ? 'Putar Episode 1' : 'Putar Video',
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                            if (onEdit != null) ...[
                              const SizedBox(width: 12),
                              OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  onEdit!();
                                },
                                icon: const Icon(Icons.edit_note, color: Colors.white70, size: 20),
                                label: const Text(
                                  'Edit Info & Poster',
                                  style: TextStyle(color: Colors.white70, fontSize: 13),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Colors.white30),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Metadata & Description Details
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 8, 32, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white54),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text(
                            '${item.maturity}+',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (item.year != null) ...[
                          const SizedBox(width: 10),
                          Text(
                            item.year!,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        if (item.rating != null) ...[
                          const SizedBox(width: 10),
                          Row(
                            children: [
                              const Icon(Icons.star, color: Colors.amber, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                item.rating!,
                                style: const TextStyle(
                                  color: Colors.amber,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white38),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text(
                            item.isSeries ? '${item.episodes.length} EPISODE' : 'FILM',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          item.genre,
                          style: const TextStyle(
                            color: Color(0xFF46D369),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      item.description,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),

                    // Episodes Section for Series
                    if (item.isSeries && item.episodes.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Daftar Episode',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${item.episodes.length} Episode Tersedia',
                            style: const TextStyle(color: Colors.white54, fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF222222),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: item.episodes.length,
                          separatorBuilder: (_, _) => const Divider(color: Colors.white12, height: 1),
                          itemBuilder: (ctx, index) {
                            final ep = item.episodes[index];
                            final sizeMb = ep.fileSize != null
                                ? '${(ep.fileSize! / (1024 * 1024)).toStringAsFixed(1)} MB'
                                : '';

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              leading: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Center(
                                  child: Text(
                                    '${index + 1}',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                              title: Text(
                                ep.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                'Season ${ep.season}${sizeMb.isNotEmpty ? ' • $sizeMb' : ''}',
                                style: const TextStyle(color: Colors.white38, fontSize: 12),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.play_circle_fill_rounded, color: Color(0xFFE50914), size: 30),
                                tooltip: 'Putar Episode Ini',
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  if (onPlayEpisode != null) {
                                    onPlayEpisode!(ep);
                                  } else {
                                    onPlay();
                                  }
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ],

                    if (item.videoPath.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text(
                        'File Utama: ${item.videoPath}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white30, fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
