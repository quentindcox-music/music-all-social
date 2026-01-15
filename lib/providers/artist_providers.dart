import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/musicbrainz_service.dart';
import '../services/fanart_service.dart';
import '../services/deezer_service.dart';
import 'firebase_providers.dart';

typedef ArtistKey = ({String artistId, String artistName});

class ArtistHeader {
  const ArtistHeader({
    required this.artist,
    required this.images,
    required this.topTracks,
  });

  final MbArtist? artist;
  final ArtistImages? images;
  final List<DeezerTrack> topTracks;
}

/// Small logger provider so we can debug without importing `foundation` everywhere.
final loggerProvider = Provider<void Function(String)>((ref) {
  return (msg) {
    if (kDebugMode) debugPrint(msg);
  };
});

/// Loads header data (artist meta + images + top tracks).
/// This provider is resilient: partial failures won't crash the page.
final artistHeaderProvider = FutureProvider.family<ArtistHeader, ArtistKey>((ref, key) async {
  MbArtist? artist;
  ArtistImages? images;
  List<DeezerTrack> topTracks = const [];

  final log = ref.read(loggerProvider);

  try {
    artist = await MusicBrainzService.fetchArtistDetails(key.artistId);
  } catch (e, st) {
    log('fetchArtistDetails failed for ${key.artistId}: $e\n$st');
  }

  try {
    images = await FanartService.getArtistImages(key.artistId);
  } catch (e, st) {
    log('getArtistImages failed for ${key.artistId}: $e\n$st');
  }

  try {
    topTracks = await DeezerService.getArtistTopTracks(key.artistName);
  } catch (e, st) {
    log('getArtistTopTracks failed for ${key.artistName}: $e\n$st');
  }

  return ArtistHeader(artist: artist, images: images, topTracks: topTracks);
});

final artistAlbumsQueryProvider =
    Provider.family<Query<Map<String, dynamic>>, String>((ref, artistId) {
  return ref
      .watch(firestoreProvider)
      .collection('albums')
      .where('primaryArtistId', isEqualTo: artistId)
      .orderBy('firstReleaseDate', descending: true);
});

/// Firestore album list for artist (normalized maps).
final artistAlbumsProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>((ref, artistId) {
  final query = ref.watch(artistAlbumsQueryProvider(artistId));
  return query.snapshots().map((snap) {
    return snap.docs.map((d) {
      final data = d.data();
      data['id'] ??= d.id;

      final sec = data['secondaryTypes'];
      if (sec is! List) data['secondaryTypes'] = <String>[];

      // Optional: normalize coverUrl string
      final cover = data['coverUrl'];
      if (cover is String) data['coverUrl'] = cover.trim();

      return Map<String, dynamic>.from(data);
    }).toList();
  });
});
