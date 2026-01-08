import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../widgets/album_thumb.dart';
import '../screens/album_detail_page.dart';

class RecentlyViewedSection extends StatelessWidget {
  const RecentlyViewedSection({
    super.key,
    required this.uid,
  });

  final String uid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final query = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('recentAlbums')
        .orderBy('lastViewedAt', descending: true)
        .limit(12);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap) {
        // Only show loading on initial load, not reconnects
        if (!snap.hasData && !snap.hasError) {
          return const SizedBox.shrink();
        }

        if (snap.hasError) {
          debugPrint('RecentlyViewed error: ${snap.error}');
          return const SizedBox.shrink();
        }

        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Recently Viewed:',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            SizedBox(
              height: 150,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: docs.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final data = docs[index].data();
                  final albumId = data['albumId'] as String? ?? '';
                  final title = (data['title'] as String? ?? '').trim();
                  final artist = (data['primaryArtistName'] as String? ?? '').trim();

                  if (albumId.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  return GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AlbumDetailPage(albumId: albumId),
                        ),
                      );
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: AlbumThumb(releaseId: albumId),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: 80,
                          child: Text(
                            title.isEmpty ? 'Unknown' : title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        if (artist.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          SizedBox(
                            width: 80,
                            child: Text(
                              artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: theme.colorScheme.outline),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
class RecentlyViewedService {
  static Future<void> markAlbumViewed({
    required String uid,
    required String albumId,
    required String title,
    required String primaryArtistName,
    required String primaryArtistId,
    required String coverUrl,
  }) async {
    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('recentAlbums')
        .doc(albumId);

    await docRef.set({
      'albumId': albumId,
      'title': title,
      'primaryArtistName': primaryArtistName,
      'primaryArtistId': primaryArtistId,
      'coverUrl': coverUrl,
      'lastViewedAt': FieldValue.serverTimestamp(),
    });
  }
}