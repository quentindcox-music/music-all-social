// lib/services/recently_viewed_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class RecentlyViewedService {
  static final _db = FirebaseFirestore.instance;

  /// Record that a user viewed this album.
  /// Safe to call multiple times – it just overwrites the doc.
  static Future<void> markAlbumViewed({
    required String uid,
    required String albumId,
    required String title,
    required String primaryArtistName,
    String? primaryArtistId,
    String? coverUrl, // <-- NEW
  }) async {
    final docRef = _db
        .collection('users')
        .doc(uid)
        .collection('recentlyViewedAlbums')
        .doc(albumId);

    await docRef.set(
      {
        'albumId': albumId,
        'title': title,
        'primaryArtistName': primaryArtistName,
        if (primaryArtistId != null && primaryArtistId.isNotEmpty)
          'primaryArtistId': primaryArtistId,
        if (coverUrl != null && coverUrl.isNotEmpty)
          'coverUrl': coverUrl, // <-- store cover art URL
        'viewedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}
