import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/media_item.dart';

class ItemDetailDialog extends StatefulWidget {
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

  @override
  State<ItemDetailDialog> createState() => _ItemDetailDialogState();
}

class _ItemDetailDialogState extends State<ItemDetailDialog> {
  Player? _previewPlayer;
  VideoController? _previewController;
  Timer? _previewTimer;
  StreamSubscription? _posSub;
  bool _isVideoReady = false;
  bool _isMuted = true;

  @override
  void initState() {
    super.initState();
    _schedulePreview();
  }

  @override
  void dispose() {
    _stopPreview();
    super.dispose();
  }

  void _schedulePreview() {
    _previewTimer?.cancel();
    _previewTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) {
        _startDialogPreview();
      }
    });
  }

  String _resolveVideoPath() {
    if (widget.item.videoPath.isNotEmpty && !widget.item.videoPath.startsWith('asset:')) {
      return widget.item.videoPath;
    }
    if (widget.item.episodes.isNotEmpty) {
      return widget.item.episodes.first.videoPath;
    }
    return '';
  }

  Future<void> _startDialogPreview() async {
    final path = _resolveVideoPath();
    if (path.isEmpty || !File(path).existsSync()) return;

    try {
      final player = Player();
      final controller = VideoController(player);

      await player.setVolume(_isMuted ? 0 : 50);
      await player.open(Media(path), play: true);
      await player.seek(const Duration(seconds: 40));

      // Loop a 25-second snippet
      _posSub = player.stream.position.listen((pos) {
        if (pos.inSeconds > 65) {
          player.seek(const Duration(seconds: 40));
        }
      });

      if (mounted) {
        setState(() {
          _previewPlayer = player;
          _previewController = controller;
          _isVideoReady = true;
        });
      } else {
        player.dispose();
      }
    } catch (e) {
      debugPrint('Dialog preview failed: $e');
    }
  }

  void _stopPreview() {
    _previewTimer?.cancel();
    _posSub?.cancel();
    _isVideoReady = false;
    _previewPlayer?.stop();
    _previewPlayer?.dispose();
    _previewPlayer = null;
    _previewController = null;
  }

  void _toggleMute() {
    if (_previewPlayer == null) return;
    setState(() {
      _isMuted = !_isMuted;
    });
    _previewPlayer!.setVolume(_isMuted ? 0 : 50);
  }

  Widget _buildBackdropImage() {
    if (widget.item.isNetworkImage) {
      return Image.network(
        widget.item.customThumbnail!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildPlaceholder(),
      );
    }
    if (widget.item.customThumbnail != null && File(widget.item.customThumbnail!).existsSync()) {
      return Image.file(
        File(widget.item.customThumbnail!),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildPlaceholder(),
      );
    }
    return Image.asset(
      widget.item.largePosterPath,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Image.asset(
        widget.item.thumbnailPath,
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
              // Top Backdrop Image & Video Preview with Gradient
              Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      children: [
                        Positioned.fill(child: _buildBackdropImage()),
                        if (_previewController != null)
                          Positioned.fill(
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 600),
                              opacity: _isVideoReady ? 1.0 : 0.0,
                              child: Video(
                                controller: _previewController!,
                                fit: BoxFit.cover,
                                controls: NoVideoControls,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Gradient Vignette
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
                      onTap: () {
                        _stopPreview();
                        Navigator.of(context).pop();
                      },
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

                  // Mute / Unmute Button on Backdrop
                  if (_previewController != null && _isVideoReady)
                    Positioned(
                      top: 16,
                      right: 56,
                      child: InkWell(
                        onTap: _toggleMute,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
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
                          widget.item.title,
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
                                _stopPreview();
                                Navigator.of(context).pop();
                                widget.onPlay();
                              },
                              icon: const Icon(Icons.play_arrow, color: Colors.black, size: 24),
                              label: Text(
                                widget.item.isSeries ? 'Putar Episode 1' : 'Putar Video',
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
                            if (widget.onEdit != null) ...[
                              const SizedBox(width: 12),
                              OutlinedButton.icon(
                                onPressed: () {
                                  _stopPreview();
                                  Navigator.of(context).pop();
                                  widget.onEdit!();
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
                            '${widget.item.maturity}+',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (widget.item.year != null) ...[
                          const SizedBox(width: 10),
                          Text(
                            widget.item.year!,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        if (widget.item.rating != null) ...[
                          const SizedBox(width: 10),
                          Row(
                            children: [
                              const Icon(Icons.star, color: Colors.amber, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                widget.item.rating!,
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
                            widget.item.isSeries ? '${widget.item.episodes.length} EPISODE' : 'FILM',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          widget.item.genre,
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
                      widget.item.description,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),

                    // Episodes Section for Series
                    if (widget.item.isSeries && widget.item.episodes.isNotEmpty) ...[
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
                            '${widget.item.episodes.length} Episode Tersedia',
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
                          itemCount: widget.item.episodes.length,
                          separatorBuilder: (_, _) => const Divider(color: Colors.white12, height: 1),
                          itemBuilder: (ctx, index) {
                            final ep = widget.item.episodes[index];
                            final sizeMb = ep.fileSize != null
                                ? '${(ep.fileSize! / (1024 * 1024)).toStringAsFixed(1)} MB'
                                : '';
                            final hasThumb = ep.thumbnail != null && ep.thumbnail!.isNotEmpty;

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Container(
                                  width: 80,
                                  height: 48,
                                  color: Colors.white.withValues(alpha: 0.08),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      if (hasThumb)
                                        Image.network(
                                          ep.thumbnail!,
                                          width: 80,
                                          height: 48,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) => Center(
                                            child: Text(
                                              '${index + 1}',
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                        )
                                      else
                                        Center(
                                          child: Text(
                                            '${index + 1}',
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      Positioned(
                                        top: 2,
                                        left: 2,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(alpha: 0.7),
                                            borderRadius: BorderRadius.circular(2),
                                          ),
                                          child: Text(
                                            'E${ep.episodeNumber}',
                                            style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ),
                                    ],
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
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Season ${ep.season}${sizeMb.isNotEmpty ? ' • $sizeMb' : ''}',
                                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                                  ),
                                  if (ep.synopsis != null && ep.synopsis!.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      ep.synopsis!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white60, fontSize: 11, height: 1.3),
                                    ),
                                  ],
                                ],
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.play_circle_fill_rounded, color: Color(0xFFE50914), size: 30),
                                tooltip: 'Putar Episode Ini',
                                onPressed: () {
                                  _stopPreview();
                                  Navigator.of(context).pop();
                                  if (widget.onPlayEpisode != null) {
                                    widget.onPlayEpisode!(ep);
                                  } else {
                                    widget.onPlay();
                                  }
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ],

                    if (widget.item.videoPath.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text(
                        'File Utama: ${widget.item.videoPath}',
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
