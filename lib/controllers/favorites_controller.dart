import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/firebase_providers.dart';
import '../repositories/favorites_repository.dart';

final favoritesRepositoryProvider = Provider<FavoritesRepository>((ref) {
  return FavoritesRepository(ref.watch(firestoreProvider));
});

final favoritesControllerProvider =
    NotifierProvider<FavoritesController, Set<String>>(FavoritesController.new);

class FavoritesController extends Notifier<Set<String>> {
  @override
  Set<String> build() => <String>{};

  bool isBusy(String key) => state.contains(key);

  Future<void> setAlbumFavorite({
    required bool isFav,
    required String albumId,
    required String title,
    required String primaryArtistName,
    required String primaryArtistId,
    required String coverUrl,
  }) async {
    final uid = ref.read(uidProvider);
    if (uid.isEmpty) return;

    final key = 'album:$albumId';
    if (state.contains(key)) return;

    state = {...state, key};
    try {
      await ref.read(favoritesRepositoryProvider).setAlbumFavorite(
            isFav: isFav,
            uid: uid,
            albumId: albumId,
            title: title,
            primaryArtistName: primaryArtistName,
            primaryArtistId: primaryArtistId,
            coverUrl: coverUrl,
          );
    } finally {
      state = state.where((k) => k != key).toSet();
    }
  }

  Future<void> setArtistFavorite({
    required bool isFav,
    required String artistId,
    required String artistName,
    required String imageUrl,
  }) async {
    final uid = ref.read(uidProvider);
    if (uid.isEmpty) return;

    final key = 'artist:$artistId';
    if (state.contains(key)) return;

    state = {...state, key};
    try {
      await ref.read(favoritesRepositoryProvider).setArtistFavorite(
            isFav: isFav,
            uid: uid,
            artistId: artistId,
            artistName: artistName,
            imageUrl: imageUrl,
          );
    } finally {
      state = state.where((k) => k != key).toSet();
    }
  }
}
