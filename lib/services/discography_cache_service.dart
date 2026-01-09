import 'package:cloud_firestore/cloud_firestore.dart';

class DiscographyCacheService {
  DiscographyCacheService(this._db);

  final FirebaseFirestore _db;

  /// Skip resync if we’ve synced recently.
  Future<bool> shouldSyncArtist(String artistId, {Duration ttl = const Duration(hours: 24)}) async {
    final ref = _db.collection('artists').doc(artistId);
    final snap = await ref.get();
    final ts = snap.data()?['lastDiscographySyncAt'] as Timestamp?;
    if (ts == null) return true;

    final last = ts.toDate();
    return DateTime.now().difference(last) > ttl;
  }

  Future<void> upsertArtistAndAlbums({
    required String artistId,
    required String artistName,
    required List<Map<String, dynamic>> releaseGroups,
  }) async {
    // Update artist doc first
    final artistRef = _db.collection('artists').doc(artistId);
    await artistRef.set({
      'id': artistId,
      'name': artistName,
      'source': 'musicbrainz',
      'lastDiscographySyncAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Firestore batches are max 500 operations each.
    WriteBatch batch = _db.batch();
    int opCount = 0;

    Future<void> commitIfNeeded() async {
      if (opCount == 0) return;
      await batch.commit();
      batch = _db.batch();
      opCount = 0;
    }

    for (final rg in releaseGroups) {
      final id = rg['id'] as String?;
      if (id == null || id.isEmpty) continue;

      final albumRef = _db.collection('albums').doc(id);

      // Normalize fields you rely on for querying/sorting/filtering
      final data = <String, dynamic>{
        'id': id,
        'title': rg['title'] ?? 'Unknown',
        'firstReleaseDate': rg['firstReleaseDate'], // keep as string if that’s what you use
        'primaryArtistId': artistId,
        'primaryArtistName': artistName,
        'primaryType': rg['primaryType'],
        'secondaryTypes': rg['secondaryTypes'] ?? <String>[],
        'source': 'musicbrainz',
        'updatedAt': FieldValue.serverTimestamp(),
        // Optionally: coverUrl if you want to store it
        'coverUrl': 'https://coverartarchive.org/release-group/$id/front-250',
      };

      batch.set(albumRef, data, SetOptions(merge: true));
      opCount++;

      if (opCount >= 450) {
        // keep a little headroom
        await commitIfNeeded();
      }
    }

    await commitIfNeeded();
  }
}
