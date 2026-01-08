import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

import 'package:music_all_app/services/recently_viewed_service.dart';
import 'artist_detail_page.dart';
import 'review_editor_page.dart';

class AlbumDetailPage extends StatefulWidget {
  const AlbumDetailPage({super.key, required this.albumId});

  final String albumId;

  @override
  State<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends State<AlbumDetailPage> {
  Color? _topColor;
  Color? _bottomColor;
  String? _paletteForCoverUrl; // to avoid recomputing for same art

  Future<void> _generatePalette(String coverUrl, ThemeData theme) async {
    if (coverUrl.isEmpty) return;
    if (_paletteForCoverUrl == coverUrl && _topColor != null) return;

    try {
      final palette = await PaletteGenerator.fromImageProvider(
        NetworkImage(coverUrl),
        maximumColorCount: 16,
      );

      final dominant = palette.dominantColor?.color;
      final vibrant = palette.vibrantColor?.color;
      final darkVibrant = palette.darkVibrantColor?.color;

      // nice fallbacks
      final top = dominant ?? vibrant ?? theme.colorScheme.primary;
      final bottom =
          darkVibrant ?? palette.darkMutedColor?.color ?? theme.colorScheme.surface;

      if (!mounted) return;
      setState(() {
        _paletteForCoverUrl = coverUrl;
        _topColor = top;
        _bottomColor = bottom;
      });
    } catch (_) {
      // quietly fall back to theme colors
    }
  }

  @override
  Widget build(BuildContext context) {
    final albumRef =
        FirebaseFirestore.instance.collection('albums').doc(widget.albumId);
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Album')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: albumRef.snapshots(),
        builder: (context, albumSnap) {
          if (albumSnap.hasError) {
            return Center(
              child: Text('Something went wrong: ${albumSnap.error}'),
            );
          }

          if (albumSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final album = albumSnap.data?.data();
          if (album == null) {
            return Center(child: Text('Album "${widget.albumId}" not found.'));
          }

          final title = (album['title'] ?? '') as String;
          final artist = (album['primaryArtistName'] ?? '') as String;
          final primaryArtistId = (album['primaryArtistId'] as String?) ?? '';
          final firstReleaseDate = (album['firstReleaseDate'] ?? '') as String?;
          final primaryType = (album['primaryType'] ?? '') as String?;
          final coverUrl = (album['coverUrl'] as String?)?.trim() ?? '';

          // mark as recently viewed (idempotent)
          RecentlyViewedService.markAlbumViewed(
            uid: uid,
            albumId: widget.albumId,
            title: title,
            primaryArtistName: artist,
            primaryArtistId: primaryArtistId,
            coverUrl: coverUrl,
          );

          // kick off palette generation
          _generatePalette(coverUrl, theme);

          final releaseLabel = formatReleaseDate(firstReleaseDate);

          final gradientTop = _topColor ?? theme.colorScheme.surface;
          final gradientBottom =
              _bottomColor ?? theme.colorScheme.surfaceContainerHighest;

          return ListView(
            padding: EdgeInsets.zero,
            children: [
              // ---------- TOP GRADIENT + ART + TEXT ----------
              Container(
                padding:
                    const EdgeInsets.fromLTRB(16, 16, 16, 20), // bottom tighter
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      gradientTop,
                      gradientTop.withValues(),
                      gradientBottom,
                    ],
                  ),
                ),
                child: Column(
                  children: [
                    // art
                    SizedBox(
                      height: 220,
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: coverUrl.isNotEmpty
                            ? Image.network(
                                coverUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    _AlbumArtPlaceholder(title: title),
                              )
                            : _AlbumArtPlaceholder(title: title),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // title
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // artist (tappable if we know artist id)
                    if (primaryArtistId.isNotEmpty)
                      InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ArtistDetailPage(
                                artistId: primaryArtistId,
                                artistName: artist,
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          child: Text(
                            artist,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      )
                    else
                      Text(
                        artist,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium,
                      ),
                    const SizedBox(height: 12),

                    // meta chips
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      alignment: WrapAlignment.center,
                      children: [
                        if (releaseLabel != null)
                          _InfoChip(
                            icon: Icons.calendar_today_outlined,
                            label: releaseLabel,
                          ),
                        if (primaryType != null &&
                            primaryType.trim().isNotEmpty)
                          _InfoChip(
                            icon: Icons.album_outlined,
                            label: primaryType,
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // ---------- TRACKLIST HEADER ----------
              const Divider(height: 1),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Text(
                  'Tracklist',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

              // ---------- TRACKLIST ----------
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: albumRef
                    .collection('tracks')
                    .orderBy('position')
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Text(
                        'Could not load tracklist.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    );
                  }

                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }

                  final docs = snap.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Text(
                        'No tracklist available yet.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    );
                  }

                  final hasMultipleDiscs = docs.any((d) {
                    final disc = d.data()['disc'];
                    return disc is num && disc > 1;
                  });

                  return Column(
                    children: docs.map((d) {
                      final data = d.data();
                      final trackNum =
                          (data['position'] as num?)?.toInt() ?? 0;
                      final disc = (data['disc'] as num?)?.toInt() ?? 1;

                      final tTitle =
                          (data['title'] as String?)?.trim().isNotEmpty == true
                              ? (data['title'] as String).trim()
                              : 'Untitled track';

                      final durNum = data['durationSeconds'] as num?;
                      String durationLabel = '';
                      if (durNum != null) {
                        final totalSeconds = durNum.round();
                        final minutes = totalSeconds ~/ 60;
                        final seconds = totalSeconds % 60;
                        durationLabel =
                            '$minutes:${seconds.toString().padLeft(2, '0')}';
                      }

                      final discPrefix =
                          hasMultipleDiscs ? 'Disc $disc · ' : '';

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 24,
                              child: Text(
                                trackNum.toString(), // "1" not "01"
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    tTitle,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontSize: 16),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (discPrefix.isNotEmpty)
                                    Text(
                                      discPrefix,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                              color:
                                                  theme.colorScheme.outline),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            if (durationLabel.isNotEmpty)
                              Text(
                                durationLabel,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),

              const SizedBox(height: 24),

              // ---------- YOUR REVIEW ----------
              _YourReviewSection(
                albumRef: albumRef,
                uid: uid,
                albumId: widget.albumId,
              ),

              const SizedBox(height: 24),

              // ---------- COMMUNITY REVIEWS ----------
              _CommunityReviewsSection(
                albumRef: albumRef,
                uid: uid,
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

class _AlbumArtPlaceholder extends StatelessWidget {
  const _AlbumArtPlaceholder({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial =
        title.trim().isEmpty ? '?' : title.trim().characters.first.toUpperCase();

    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: theme.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Small pill chip used for year / type
class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

/// YOUR REVIEW card
class _YourReviewSection extends StatelessWidget {
  const _YourReviewSection({
    required this.albumRef,
    required this.uid,
    required this.albumId,
  });

  final DocumentReference<Map<String, dynamic>> albumRef;
  final String uid;
  final String albumId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final myReviewRef = albumRef.collection('reviews').doc(uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: myReviewRef.snapshots(),
      builder: (context, reviewSnap) {
        if (reviewSnap.hasError) {
          return Center(
            child: Text('Couldn’t load your review: ${reviewSnap.error}'),
          );
        }

        if (reviewSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final review = reviewSnap.data?.data();
        final hasReview = review != null;

        final rating =
            hasReview ? (review['rating'] as num? ?? 0).toDouble() : 0.0;
        final text = hasReview ? (review['text'] as String? ?? '') : '';

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your review',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  if (hasReview) ...[
                    Row(
                      children: [
                        RatingStars(rating: rating),
                        const SizedBox(width: 8),
                        Text(
                          '${rating.toStringAsFixed(1)}/10',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (text.trim().isNotEmpty) Text(text),
                    if (text.trim().isEmpty)
                      Text(
                        '(No written review)',
                        style: theme.textTheme.bodySmall,
                      ),
                  ] else
                    Text(
                      'You haven’t rated this album yet.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ReviewEditorPage(
                                albumId: albumId,
                                existingRating: hasReview ? rating : null,
                                existingText: hasReview ? text : null,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.rate_review),
                        label: Text(
                          hasReview
                              ? 'Edit rating / review'
                              : 'Rate this album',
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (hasReview)
                        TextButton(
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete review?'),
                                content:
                                    const Text('This can’t be undone.'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(ctx, true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );

                            if (ok == true) {
                              await myReviewRef.delete();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Review deleted'),
                                  ),
                                );
                              }
                            }
                          },
                          child: const Text('Delete'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// COMMUNITY REVIEWS & STATS
class _CommunityReviewsSection extends StatelessWidget {
  const _CommunityReviewsSection({
    required this.albumRef,
    required this.uid,
  });

  final DocumentReference<Map<String, dynamic>> albumRef;
  final String uid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: albumRef
          .collection('reviews')
          .orderBy('updatedAt', descending: true)
          .limit(200)
          .snapshots(),
      builder: (context, listSnap) {
        if (listSnap.hasError) {
          return Center(
            child: Text('Couldn’t load reviews: ${listSnap.error}'),
          );
        }

        if (listSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = listSnap.data?.docs ?? const [];

        int count = 0;
        double sum = 0;
        for (final d in docs) {
          final data = d.data();
          final ratingValue = data['rating'];
          if (ratingValue is num) {
            sum += ratingValue.toDouble();
            count += 1;
          }
        }
        final double? avg = count == 0 ? null : (sum / count);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Community reviews: $count'),
                      Text(
                        avg == null
                            ? 'Avg: —'
                            : 'Avg: ${avg.toStringAsFixed(1)}/10',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Recent reviews',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              if (docs.isEmpty)
                const Text('No reviews yet.')
              else
                Column(
                  children: docs.take(20).map((d) {
                    final data = d.data();
                    final ratingNum = data['rating'];
                    final rating =
                        ratingNum is num ? ratingNum.toDouble() : 0.0;
                    final text =
                        (data['text'] as String? ?? '').trim();
                    final who = d.id;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: _DisplayNameChip(uid: who),
                        title: Row(
                          children: [
                            RatingStars(rating: rating, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              '${rating.toStringAsFixed(1)}/10',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        subtitle: text.isEmpty
                            ? Text(
                                '(No written review)',
                                style: theme.textTheme.bodySmall,
                              )
                            : Text(
                                text,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                        trailing: who == uid
                            ? Text(
                                'You',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            : null,
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Read-only 0–10 → 0–5 stars renderer.
class RatingStars extends StatelessWidget {
  const RatingStars({super.key, required this.rating, this.size = 18});

  final double rating; // 0–10
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final fiveScale = rating / 2.0;
    int full = fiveScale.floor().clamp(0, 5);
    final double frac = fiveScale - full;
    bool hasHalf = frac >= 0.25 && frac < 0.75;
    if (full == 5) hasHalf = false;

    final icons = <Widget>[];
    for (int i = 0; i < full; i++) {
      icons.add(
        Icon(Icons.star, size: size, color: theme.colorScheme.primary),
      );
    }
    if (hasHalf) {
      icons.add(
        Icon(Icons.star_half,
            size: size, color: theme.colorScheme.primary),
      );
    }
    while (icons.length < 5) {
      icons.add(
        Icon(Icons.star_border,
            size: size, color: theme.colorScheme.primary),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: icons);
  }
}

class _DisplayNameChip extends StatelessWidget {
  const _DisplayNameChip({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    final userRef =
        FirebaseFirestore.instance.collection('users').doc(uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userRef.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final name = (data?['displayName'] as String?)?.trim();

        final display = (name != null && name.isNotEmpty)
            ? name
            : uid.substring(0, uid.length >= 6 ? 6 : uid.length);

        return Chip(
          label: Text(display),
        );
      },
    );
  }
}

/// Converts an ISO-like date string (YYYY, YYYY-MM, YYYY-MM-DD)
/// into something like "Nov 4, 1969".
String? formatReleaseDate(String? iso) {
  if (iso == null || iso.trim().isEmpty) return null;

  final trimmed = iso.trim();

  // Try full DateTime parse first (YYYY-MM-DD or full ISO)
  try {
    final dt = DateTime.parse(trimmed);
    const monthNames = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final m = monthNames[dt.month - 1];
    return '$m ${dt.day}, ${dt.year}';
  } catch (_) {
    // If parse fails, fall back to manual handling below.
  }

  // Fallback: split on "-"
  final parts = trimmed.split('-');
  if (parts.length == 1) {
    return parts[0];
  } else if (parts.length == 2) {
    const monthNames = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final year = parts[0];
    final monthIndex = int.tryParse(parts[1]) ?? 1;
    final m = monthNames[(monthIndex - 1).clamp(0, 11)];
    return '$m $year';
  } else {
    return trimmed;
  }
}
