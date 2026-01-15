// lib/providers/favorites_controller.dart

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_providers.dart';

class FavoriteAlbumPayload {
  const FavoriteAlbumPayload({
    required this.albumId,
    required this.title,
    required this.primaryArtistName,
    required this.primaryArtistId,
    required this.coverUrl,
  });

  final String albumId;
  final String title;
  final String primaryArtistName;
  final String primaryArtistId;
  final String coverUrl;
}

class FavoriteArtistPayload {
  const FavoriteArtistPayload({
    required this.artistId,
    required this.artistName,
    required this.imageUrl,
  });

  final String artistId;
  final String artistName;
  final String imageUrl;
}

// --------------------
// Favorite Album Controller (FAMILY)
// --------------------
final favoriteAlbumControllerProvider =
    AutoDisposeAsyncNotifierProviderFamily<FavoriteAlbumController, void, String>(
  FavoriteAlbumController.new,
);

final favoriteAlbumBusyProvider = Provider.family<bool, String>((ref, albumId) {
  return ref.watch(favoriteAlbumControllerProvider(albumId)).isLoading;
});

class FavoriteAlbumController extends AutoDisposeFamilyAsyncNotifier<void, String> {
  @override
  FutureOr<void> build(String albumId) {
    // no-op; we just use this controller for actions
  }

  Future<void> toggle({
    required bool isCurrentlyFav,
    required FavoriteAlbumPayload payload,
  }) async {
    final uid = ref.read(uidProvider).trim();
    if (uid.isEmpty) return;

    final firestore = ref.read(firestoreProvider);
    final favRef = firestore
        .collection('users')
        .doc(uid)
        .collection('favorites_albums')
        .doc(payload.albumId);

    state = const AsyncLoading();

    state = await AsyncValue.guard(() async {
      if (isCurrentlyFav) {
        await favRef.delete();
        return;
      }

      await favRef.set({
        'albumId': payload.albumId,
        'title': payload.title,
        'primaryArtistName': payload.primaryArtistName,
        if (payload.primaryArtistId.trim().isNotEmpty)
          'primaryArtistId': payload.primaryArtistId.trim(),
        'coverUrl': payload.coverUrl.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }
}

// --------------------
// Favorite Artist Controller (FAMILY)
// --------------------
final favoriteArtistControllerProvider =
    AutoDisposeAsyncNotifierProviderFamily<FavoriteArtistController, void, String>(
  FavoriteArtistController.new,
);

final favoriteArtistBusyProvider = Provider.family<bool, String>((ref, artistId) {
  return ref.watch(favoriteArtistControllerProvider(artistId)).isLoading;
});

class FavoriteArtistController extends AutoDisposeFamilyAsyncNotifier<void, String> {
  @override
  FutureOr<void> build(String artistId) {
    // no-op; we just use this controller for actions
  }

  Future<void> toggle({
    required bool isCurrentlyFav,
    required FavoriteArtistPayload payload,
  }) async {
    final uid = ref.read(uidProvider).trim();
    if (uid.isEmpty) return;

    final firestore = ref.read(firestoreProvider);
    final favRef = firestore
        .collection('users')
        .doc(uid)
        .collection('favorites_artists')
        .doc(payload.artistId);

    state = const AsyncLoading();

    state = await AsyncValue.guard(() async {
      if (isCurrentlyFav) {
        await favRef.delete();
        return;
      }

      final img = payload.imageUrl.trim();

      // Write BOTH legacy + new keys so older UI code never breaks.
      await favRef.set({
        'artistId': payload.artistId,

        // keep both so any existing code works
        'name': payload.artistName,
        'artistName': payload.artistName,

        // keep both so any existing code works
        if (img.isNotEmpty) ...{
          'imageUrl': img,
          'thumbUrl': img,
        },

        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }
}
