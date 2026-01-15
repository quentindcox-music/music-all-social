import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_providers.dart';

typedef AlbumUserKey = ({String albumId, String uid});

/// Current user's review for an album (or null if none).
final myReviewProvider =
    StreamProvider.family<Map<String, dynamic>?, AlbumUserKey>((ref, key) {
  if (key.uid.trim().isEmpty) {
    // No signed-in user; no review doc.
    return const Stream.empty();
  }

  final firestore = ref.watch(firestoreProvider);
  final docRef = firestore
      .collection('albums')
      .doc(key.albumId)
      .collection('reviews')
      .doc(key.uid);

  return docRef.snapshots().map((snap) => snap.data());
});

/// Community reviews for an album (up to 200, newest first).
final communityReviewsProvider = StreamProvider.family<
    List<QueryDocumentSnapshot<Map<String, dynamic>>>,
    String>((ref, albumId) {
  final firestore = ref.watch(firestoreProvider);

  final q = firestore
      .collection('albums')
      .doc(albumId)
      .collection('reviews')
      .orderBy('updatedAt', descending: true)
      .limit(200);

  return q.snapshots().map((snap) => snap.docs);
});

/// Derived stats (count + average rating).
final communityReviewStatsProvider =
    Provider.family<AsyncValue<({int count, double? avg})>, String>(
        (ref, albumId) {
  final asyncDocs = ref.watch(communityReviewsProvider(albumId));

  return asyncDocs.whenData((docs) {
    int count = 0;
    double sum = 0;

    for (final d in docs) {
      final ratingValue = d.data()['rating'];
      if (ratingValue is num) {
        count += 1;
        sum += ratingValue.toDouble();
      }
    }

    return (count: count, avg: count == 0 ? null : (sum / count));
  });
});
