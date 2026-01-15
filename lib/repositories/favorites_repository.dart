import 'package:cloud_firestore/cloud_firestore.dart';

class FavoritesRepository {
  FavoritesRepository(this._firestore);

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> albumFavRef({
    required String uid,
    required String albumId,
  }) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('favorites_albums')
        .doc(albumId);
  }

  DocumentReference<Map<String, dynamic>> artistFavRef({
    required String uid,
    required String artistId,
  }) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('favorites_artists')
        .doc(artistId);
  }

  Future<void> setAlbumFavorite({
    required bool isFav,
    required String uid,
    required String albumId,
    required String title,
    required String primaryArtistName,
    required String primaryArtistId,
    required String coverUrl,
  }) async {
    final ref = albumFavRef(uid: uid, albumId: albumId);

    if (isFav) {
      await ref.delete();
      return;
    }

    await ref.set(
      {
        'albumId': albumId,
        'title': title,
        'primaryArtistName': primaryArtistName,
        if (primaryArtistId.trim().isNotEmpty) 'primaryArtistId': primaryArtistId.trim(),
        'coverUrl': coverUrl.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> setArtistFavorite({
    required bool isFav,
    required String uid,
    required String artistId,
    required String artistName,
    required String imageUrl,
  }) async {
    final ref = artistFavRef(uid: uid, artistId: artistId);

    if (isFav) {
      await ref.delete();
      return;
    }

    await ref.set(
      {
        'artistId': artistId,
        'name': artistName,
        'imageUrl': imageUrl.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}
