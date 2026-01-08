// lib/widgets/album_thumb.dart

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class AlbumThumb extends StatelessWidget {
  final String releaseId;
  final double size;

  const AlbumThumb({
    required this.releaseId,
    this.size = 48,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final coverUrl =
        'https://coverartarchive.org/release-group/$releaseId/front-250';

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: CachedNetworkImage(
        imageUrl: coverUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          width: size,
          height: size,
          color: Colors.grey[800],
          child: const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        errorWidget: (context, url, error) => Container(
          width: size,
          height: size,
          color: Colors.grey[800],
          child: const Icon(Icons.album, color: Colors.grey),
        ),
      ),
    );
  }
}