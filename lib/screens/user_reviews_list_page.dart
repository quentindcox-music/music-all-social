import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'album_detail_page.dart';
import 'package:music_all_app/widgets/album_thumb.dart';

enum UserReviewsListMode {
  ratedAlbums,
  writtenReviews,
}

class UserReviewsListPage extends StatelessWidget {
  const UserReviewsListPage({
    super.key,
    required this.mode,
  });

  final UserReviewsListMode mode;

  String get _title {
    switch (mode) {
      case UserReviewsListMode.ratedAlbums:
        return 'Albums Rated';
      case UserReviewsListMode.writtenReviews:
        return 'Written Reviews';
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    // All reviews across all albums; we filter in Dart
    final reviewsStream =
        FirebaseFirestore.instance.collectionGroup('reviews').snapshots();

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: reviewsStream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Error loading reviews:\n${snap.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          // Only this user's docs
          final allDocs = snap.data!.docs;
          final userDocs = allDocs.where((d) => d.id == uid).toList();

          // Filter based on mode
          final filteredDocs = userDocs.where((d) {
            final data = d.data();
            final ratingValue = data['rating'];
            final text = (data['text'] as String?)?.trim() ?? '';

            switch (mode) {
              case UserReviewsListMode.ratedAlbums:
                // Any numeric rating counts, even if no text
                return ratingValue is num;
              case UserReviewsListMode.writtenReviews:
                // Must have non-empty text
                return text.isNotEmpty;
            }
          }).toList();

          if (filteredDocs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  mode == UserReviewsListMode.ratedAlbums
                      ? 'You haven\'t rated any albums yet.'
                      : 'You haven\'t written any reviews yet.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          // Sort by updatedAt desc if present
          filteredDocs.sort((a, b) {
            final aData = a.data();
            final bData = b.data();
            final aTs = aData['updatedAt'];
            final bTs = bData['updatedAt'];
            if (aTs is Timestamp && bTs is Timestamp) {
              return bTs.compareTo(aTs);
            }
            return 0;
          });

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: filteredDocs.length,
            separatorBuilder: (_, _) => const Divider(height: 0),
            itemBuilder: (context, index) {
              final doc = filteredDocs[index];
              final data = doc.data();

              final num? ratingNum = data['rating'] as num?;
              final double? rating = ratingNum?.toDouble();
              final text = (data['text'] as String?)?.trim() ?? '';

              // Parent album doc
              final albumRef = doc.reference.parent.parent;
              if (albumRef == null) {
                return const ListTile(
                  title: Text('Unknown album'),
                );
              }

              return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: albumRef.get(),
                builder: (context, albumSnap) {
                  if (!albumSnap.hasData) {
                    return const ListTile(
                      title: Text('Loading album...'),
                    );
                  }

                  final albumData = albumSnap.data!.data();
                  final title =
                      (albumData?['title'] as String?) ?? 'Unknown album';
                  final artist =
                      (albumData?['primaryArtistName'] as String?) ?? '';

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),

                    // 🔹 Cover art thumbnail using shared AlbumThumb
                    leading: SizedBox(
                      width: 50,
                      height: 50,
                      child: AlbumThumb(
                        releaseId: albumRef.id, // MBID used elsewhere
                        size: 50,
                      ),
                    ),

                    title: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),

                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (artist.isNotEmpty)
                          Text(
                            artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (rating != null) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text('${rating.toStringAsFixed(1)}/10'),
                              const SizedBox(width: 8),
                              buildStarRow(context, rating, size: 14),
                            ],
                          ),
                        ],
                        if (mode == UserReviewsListMode.writtenReviews &&
                            text.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),

                    trailing: const Icon(Icons.chevron_right),

                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              AlbumDetailPage(albumId: albumRef.id),
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// Displays stars 1–10 with half-filled look based on rating.
/// Example: rating 7.5 = ★★★★★★★½☆
Widget buildStarRow(
  BuildContext context,
  double rating, {
  double size = 16,
}) {
  final theme = Theme.of(context);

  // Use your theme purple
  final filledColor = theme.colorScheme.primary;
  final emptyColor = theme.colorScheme.primary.withValues(alpha: 0.28);

  // If rating is 0–10, we want 10 stars
  final fullStars = rating.floor().clamp(0, 10);
  final hasHalfStar = (rating - fullStars) >= 0.5 && fullStars < 10;

  return Row(
    mainAxisSize: MainAxisSize.min,
    children: List.generate(10, (i) {
      if (i < fullStars) {
        return Icon(Icons.star, color: filledColor, size: size);
      } else if (i == fullStars && hasHalfStar) {
        return Icon(Icons.star_half, color: filledColor, size: size);
      } else {
        return Icon(Icons.star_border, color: emptyColor, size: size);
      }
    }),
  );
}
