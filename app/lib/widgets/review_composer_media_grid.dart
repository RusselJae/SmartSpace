import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../models/review.dart';

/// Tile-based photo/video attachment grid for the review composer.
class ReviewMediaAttachmentGrid extends StatelessWidget {
  const ReviewMediaAttachmentGrid({
    super.key,
    required this.media,
    required this.maxCount,
    required this.enabled,
    required this.uploading,
    required this.onRemove,
    required this.onMediaPicked,
    this.videoDurations = const {},
    this.resolveUrl,
  });

  final List<ReviewMediaItem> media;
  final int maxCount;
  final bool enabled;
  final bool uploading;
  final ValueChanged<int> onRemove;
  final Future<void> Function(String path, String name, bool isVideo) onMediaPicked;
  final Map<String, Duration> videoDurations;
  final String Function(String url)? resolveUrl;

  static const double _tileSize = 92;
  static final ImagePicker _picker = ImagePicker();

  String _url(ReviewMediaItem item) => resolveUrl?.call(item.url) ?? item.url;

  String _formatDuration(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  bool _isVideoFile(XFile file) {
    final mime = file.mimeType?.toLowerCase() ?? '';
    if (mime.startsWith('video/')) return true;
    final lower = file.path.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.avi');
  }

  Future<void> _openGallery() async {
    if (!enabled || uploading || media.length >= maxCount) return;
    final file = await _picker.pickMedia();
    if (file == null) return;
    await onMediaPicked(file.path, file.name, _isVideoFile(file));
  }

  @override
  Widget build(BuildContext context) {
    final canAdd = enabled && !uploading && media.length < maxCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Photos & videos (optional)',
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < media.length; i++)
              _AttachmentTile(
                item: media[i],
                imageUrl: _url(media[i]),
                duration: media[i].isVideo ? videoDurations[media[i].url] : null,
                enabled: enabled,
                onRemove: () => onRemove(i),
                formatDuration: _formatDuration,
              ),
            if (canAdd)
              GestureDetector(
                onTap: _openGallery,
                child: Container(
                  width: _tileSize,
                  height: _tileSize,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFBDBDBD),
                      width: 1.2,
                      strokeAlign: BorderSide.strokeAlignInside,
                    ),
                  ),
                  child: const Icon(
                    Icons.add,
                    size: 32,
                    color: Color(0xFF8D6E63),
                  ),
                ),
              ),
            if (uploading)
              SizedBox(
                width: _tileSize,
                height: _tileSize,
                child: const Center(child: CupertinoActivityIndicator()),
              ),
          ],
        ),
      ],
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.item,
    required this.imageUrl,
    required this.enabled,
    required this.onRemove,
    required this.formatDuration,
    this.duration,
  });

  final ReviewMediaItem item;
  final String imageUrl;
  final bool enabled;
  final VoidCallback onRemove;
  final String Function(Duration) formatDuration;
  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: ReviewMediaAttachmentGrid._tileSize,
      height: ReviewMediaAttachmentGrid._tileSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: item.isVideo
                ? Container(
                    width: double.infinity,
                    height: double.infinity,
                    color: const Color(0xFF3E4A3A),
                    child: const Center(
                      child: Icon(
                        CupertinoIcons.play_circle_fill,
                        color: Colors.white70,
                        size: 32,
                      ),
                    ),
                  )
                : Image.network(
                    imageUrl,
                    width: double.infinity,
                    height: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: const Color(0xFFE0E0E0),
                      child: const Icon(CupertinoIcons.photo, color: Colors.black45),
                    ),
                  ),
          ),
          if (item.isVideo && duration != null)
            Positioned(
              right: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  formatDuration(duration!),
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: enabled ? onRemove : null,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
