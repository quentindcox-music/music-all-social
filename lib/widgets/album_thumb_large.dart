// lib/widgets/album_thumb_large.dart

import 'package:flutter/material.dart';

class AlbumThumbLarge extends StatelessWidget {
  const AlbumThumbLarge({
    super.key,
    required this.releaseId,
    this.size = 200,
  });

  /// MusicBrainz release-group MBID (your albumId).
  final String releaseId;

  /// Square size of the large thumbnail.
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final coverUrl =
        'https://coverartarchive.org/release-group/$releaseId/front-500.jpg';

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          width: size,
          height: size,
          color: theme.colorScheme.surfaceContainerHighest,
          child: Image.network(
            coverUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return _LargePlaceholderArt();
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return _LargeShimmerPlaceholder();
            },
          ),
        ),
      ),
    );
  }
}

class _LargePlaceholderArt extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.surfaceContainerHighest,
            theme.colorScheme.surfaceContainerHighest,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(
        Icons.album,
        size: 64,
        color: theme.colorScheme.outline,
      ),
    );
  }
}

class _LargeShimmerPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.surfaceContainerHighest,
            theme.colorScheme.surfaceContainerHighest,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(
        Icons.music_note,
        size: 48,
        color: theme.colorScheme.outline,
      ),
    );
  }
}
