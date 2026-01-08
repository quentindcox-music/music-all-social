// lib/widgets/album_thumb.dart

import 'package:flutter/material.dart';

class AlbumThumb extends StatelessWidget {
  const AlbumThumb({
    super.key,
    required this.releaseId,
    this.size = 64,
  });

  /// MusicBrainz release-group MBID (same as your albumId from search).
  final String releaseId;

  /// Square size of the thumbnail.
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Cover Art Archive: release-group front image
    final coverUrl =
        'https://coverartarchive.org/release-group/$releaseId/front-250.jpg';

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: size,
        height: size,
        color: theme.colorScheme.surfaceContainerHighest,
        child: Image.network(
          coverUrl,
          fit: BoxFit.cover,
          // If the image fails (404 / network), fall back to a simple placeholder.
          errorBuilder: (context, error, stackTrace) {
            return _PlaceholderArt(size: size);
          },
          // Optional: show a subtle placeholder while loading
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return _ShimmerPlaceholder(size: size);
          },
        ),
      ),
    );
  }
}

class _PlaceholderArt extends StatelessWidget {
  const _PlaceholderArt({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: size,
      height: size,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.album,
        size: size * 0.5,
        color: theme.colorScheme.outline,
      ),
    );
  }
}

class _ShimmerPlaceholder extends StatelessWidget {
  const _ShimmerPlaceholder({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: size,
      height: size,
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
        size: size * 0.4,
        color: theme.colorScheme.outline,
      ),
    );
  }
}
