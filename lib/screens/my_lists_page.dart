import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class LatestReviewsPage extends StatefulWidget {
  const LatestReviewsPage({super.key, required this.uid});
  final String uid;

  @override
  State<LatestReviewsPage> createState() => _LatestReviewsPageState();
}

class _LatestReviewsPageState extends State<LatestReviewsPage> {
  final Map<String, Future<DocumentSnapshot<Map<String, dynamic>>>> _albumFutureCache = {};

  Future<DocumentSnapshot<Map<String, dynamic>>> _albumDoc(String albumId) {
    return _albumFutureCache.putIfAbsent(
      albumId,
      () => FirebaseFirestore.instance.collection('albums').doc(albumId).get(),
    );
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.month}/${dt.day}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final query = FirebaseFirestore.instance
        .collectionGroup('reviews')
        .where('authorUid', isEqualTo: widget.uid)
        .orderBy('updatedAt', descending: true)
        .limit(50);

    return Scaffold(
      appBar: AppBar(title: const Text('Latest reviews')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }

          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data?.docs ?? const [];
          if (docs.isEmpty) {
            return Center(
              child: Text(
                'No reviews yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            );
          }

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final reviewDoc = docs[i];
              final data = reviewDoc.data();

              // Prefer stored albumId, fallback to parsing the parent path
              final albumId =
                  (data['albumId'] as String?)?.trim().isNotEmpty == true
                      ? (data['albumId'] as String).trim()
                      : (reviewDoc.reference.parent.parent?.id ?? '');

              final ratingNum = data['rating'];
              final rating = ratingNum is num ? ratingNum.toDouble() : 0.0;

              final text = (data['text'] as String? ?? '').trim();
              final updatedAt = data['updatedAt'] as Timestamp?;
              final timeLabel = _formatDate(updatedAt);

              if (albumId.isEmpty) {
                // Defensive fallback: show the review even if albumId can't be determined
                return ListTile(
                  title: const Text('Album'),
                  subtitle: Text('${rating.toStringAsFixed(1)}/10 ${timeLabel.isNotEmpty ? "• $timeLabel" : ""}'),
                );
              }

              return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: _albumDoc(albumId),
                builder: (context, albumSnap) {
                  final album = albumSnap.data?.data();
                  final title = (album?['title'] as String?)?.trim();
                  final artist = (album?['primaryArtistName'] as String?)?.trim();
                  final coverUrl = (album?['coverUrl'] as String?)?.trim() ?? '';

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 52,
                        height: 52,
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: coverUrl.isNotEmpty
                            ? Image.network(
                                coverUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const Icon(Icons.album),
                              )
                            : const Icon(Icons.album),
                      ),
                    ),
                    title: Text(
                      title?.isNotEmpty == true ? title! : 'Album',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (artist?.isNotEmpty == true)
                          Text(
                            artist!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              '${rating.toStringAsFixed(1)}/10',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            if (timeLabel.isNotEmpty) ...[
                              Text(
                                ' • ',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                              Text(
                                timeLabel,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (text.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
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
