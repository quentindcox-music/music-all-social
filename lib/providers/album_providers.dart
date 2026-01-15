import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'firebase_providers.dart';

final albumRefProvider =
    Provider.family<DocumentReference<Map<String, dynamic>>, String>((ref, albumId) {
  return ref.watch(firestoreProvider).collection('albums').doc(albumId);
});

final albumDocProvider =
    StreamProvider.family<DocumentSnapshot<Map<String, dynamic>>, String>((ref, albumId) {
  return ref.watch(albumRefProvider(albumId)).snapshots();
});

final albumDataProvider =
    Provider.family<Map<String, dynamic>?, String>((ref, albumId) {
  final snap = ref.watch(albumDocProvider(albumId)).valueOrNull;
  return snap?.data();
});

final tracksQueryProvider =
    Provider.family<Query<Map<String, dynamic>>, String>((ref, albumId) {
  final album = ref.watch(albumDataProvider(albumId));
  final refDoc = ref.watch(albumRefProvider(albumId));

  final syncVersion = (album?['tracksSyncVersion'] as num?)?.toInt() ?? 0;

  // Works with your Suggestion 5 approach.
  if (syncVersion > 0) {
    return refDoc
        .collection('tracks')
        .where('syncVersion', isEqualTo: syncVersion)
        .orderBy('disc')
        .orderBy('position');
  }
  return refDoc.collection('tracks').orderBy('disc').orderBy('position');
});

final tracksProvider =
    StreamProvider.family<QuerySnapshot<Map<String, dynamic>>, String>((ref, albumId) {
  final q = ref.watch(tracksQueryProvider(albumId));
  return q.snapshots();
});
