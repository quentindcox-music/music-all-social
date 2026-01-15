import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_providers.dart';

// --------------------
// Favorite Albums
// --------------------
final favoriteAlbumRefProvider =
    Provider.family<DocumentReference<Map<String, dynamic>>?, String>((ref, albumId) {
  final uid = ref.watch(uidProvider);
  if (uid.isEmpty) return null;

  return ref
      .watch(firestoreProvider)
      .collection('users')
      .doc(uid)
      .collection('favorites_albums')
      .doc(albumId);
});

final favoriteAlbumDocProvider =
    StreamProvider.family<DocumentSnapshot<Map<String, dynamic>>?, String>((ref, albumId) {
  final favRef = ref.watch(favoriteAlbumRefProvider(albumId));
  if (favRef == null) return const Stream.empty();
  return favRef.snapshots();
});

final isFavoriteAlbumProvider = Provider.family<bool, String>((ref, albumId) {
  final snap = ref.watch(favoriteAlbumDocProvider(albumId)).valueOrNull;
  return snap?.exists == true;
});

// --------------------
// Favorite Artists
// --------------------
final favoriteArtistRefProvider =
    Provider.family<DocumentReference<Map<String, dynamic>>?, String>((ref, artistId) {
  final uid = ref.watch(uidProvider);
  if (uid.isEmpty) return null;

  return ref
      .watch(firestoreProvider)
      .collection('users')
      .doc(uid)
      .collection('favorites_artists')
      .doc(artistId);
});

final favoriteArtistDocProvider =
    StreamProvider.family<DocumentSnapshot<Map<String, dynamic>>?, String>((ref, artistId) {
  final favRef = ref.watch(favoriteArtistRefProvider(artistId));
  if (favRef == null) return const Stream.empty();
  return favRef.snapshots();
});

final isFavoriteArtistProvider = Provider.family<bool, String>((ref, artistId) {
  final snap = ref.watch(favoriteArtistDocProvider(artistId)).valueOrNull;
  return snap?.exists == true;
});
