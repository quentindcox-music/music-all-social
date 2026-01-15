import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/musicbrainz_service.dart';
import '../services/fanart_service.dart';
import '../services/deezer_service.dart';
import '../services/lastfm_service.dart';
import 'firebase_providers.dart';

typedef ArtistKey = ({String artistId, String artistName});

class ArtistHeader {
  const ArtistHeader({
    required this.artist,
    required this.images,
    required this.topTracks,
    required this.bestImageUrl,
    required this.lastFmListeners,
  });

  final MbArtist? artist;
  final ArtistImages? images;
  final List<DeezerTrack> topTracks;

  /// A single “best effort” image URL:
  /// Fanart -> Last.fm -> Deezer (only when safe).
  final String? bestImageUrl;

  /// Optional: useful if you want to display listeners in the UI.
  final int? lastFmListeners;
}

/// Small logger provider so we can debug without importing `foundation` everywhere.
final loggerProvider = Provider<void Function(String)>((ref) {
  return (msg) {
    if (kDebugMode) debugPrint(msg);
  };
});

final lastFmServiceProvider = Provider<LastFmService>((ref) {
  final key = dotenv.env['LASTFM_API_KEY'] ?? '';
  return LastFmService(apiKey: key);
});

bool _isProbablyPersonType(String? mbType) {
  final t = (mbType ?? '').trim().toLowerCase();
  return t == 'person' || t == 'character';
}

/// Loads header data (artist meta + images + top tracks).
/// Optimized:
/// - Fetch MB artist first (so we can avoid mismatching duplicates)
/// - Then fetch Fanart + Last.fm image + Deezer image + Top Tracks
/// - Conservative fallbacks for "Person" artists to avoid showing band assets.
final artistHeaderProvider =
    FutureProvider.family<ArtistHeader, ArtistKey>((ref, key) async {
  final log = ref.read(loggerProvider);

  // 1) Fetch MusicBrainz artist FIRST (context for safe fallbacks).
  MbArtist? artist;
  try {
    artist = await MusicBrainzService.fetchArtistDetails(key.artistId);
  } catch (e, st) {
    log('fetchArtistDetails failed for ${key.artistId}: $e\n$st');
    artist = null;
  }

  final mbType = artist?.type;
  final mbCountry = artist?.country;
  final isPerson = _isProbablyPersonType(mbType);

  // If MB says it's a Person/Character, we do NOT want to fall back by name
  // (that’s how you accidentally show Pink Floyd band data for a person named Pink Floyd).
  final allowNameFallback = !isPerson;

  // 2) Fetch images + top tracks + fallback image urls in parallel (resilient).
  Future<ArtistImages?> safeFanartImages() async {
    try {
      return await FanartService.getArtistImages(key.artistId);
    } catch (e, st) {
      log('getArtistImages failed for ${key.artistId}: $e\n$st');
      return null;
    }
  }

  Future<String?> safeLastFmImageUrl() async {
    try {
      final lastfm = ref.read(lastFmServiceProvider);
      return await lastfm.getArtistImageUrl(
        key.artistName,
        mbid: key.artistId,
        allowNameFallback: allowNameFallback,
      );
    } catch (e, st) {
      log('Last.fm getArtistImageUrl failed for ${key.artistName}: $e\n$st');
      return null;
    }
  }

  Future<int?> safeLastFmListeners() async {
    try {
      final lastfm = ref.read(lastFmServiceProvider);
      final info = await lastfm.getArtistInfo(
        key.artistName,
        mbid: key.artistId,
        allowNameFallback: allowNameFallback,
      );
      return info?.listeners;
    } catch (e, st) {
      log('Last.fm getArtistInfo failed for ${key.artistName}: $e\n$st');
      return null;
    }
  }

  Future<String?> safeDeezerImageUrl() async {
    // Also conservative: don’t use Deezer fallback for Person-like artists.
    if (isPerson) return null;

    try {
      return await DeezerService.getBestArtistImageUrl(
        key.artistName,
        mbType: mbType,
        country: mbCountry,
        limit: 8,
      );
    } catch (e, st) {
      log('Deezer getBestArtistImageUrl failed for ${key.artistName}: $e\n$st');
      return null;
    }
  }

  Future<List<DeezerTrack>> safeTopTracks() async {
    try {
      return await DeezerService.getTopTracksForMusicBrainzArtist(
        artistName: key.artistName,
        mbType: mbType,
        country: mbCountry,
        limit: 5,
      );
    } catch (e, st) {
      log('getTopTracksForMusicBrainzArtist failed for ${key.artistName}: $e\n$st');
      return const <DeezerTrack>[];
    }
  }

  final results = await Future.wait<Object?>([
    safeFanartImages(),
    safeLastFmImageUrl(),
    safeDeezerImageUrl(),
    safeTopTracks(),
    safeLastFmListeners(),
  ]);

  final fanartImages = results[0] as ArtistImages?;
  final lastfmUrl = (results[1] as String?)?.trim();
  final deezerUrl = (results[2] as String?)?.trim();
  final topTracks = results[3] as List<DeezerTrack>;
  final listeners = results[4] as int?;

  // Prefer Fanart if it exists
  String? bestImageUrl;
  final fanartBg = (fanartImages?.artistBackground ?? '').trim();
  final fanartThumb = (fanartImages?.artistThumb ?? '').trim();
  if (fanartBg.isNotEmpty) {
    bestImageUrl = fanartBg;
  } else if (fanartThumb.isNotEmpty) {
    bestImageUrl = fanartThumb;
  } else if ((lastfmUrl ?? '').isNotEmpty) {
    bestImageUrl = lastfmUrl;
  } else if ((deezerUrl ?? '').isNotEmpty) {
    bestImageUrl = deezerUrl;
  }

  return ArtistHeader(
    artist: artist,
    images: fanartImages,
    topTracks: topTracks,
    bestImageUrl: bestImageUrl,
    lastFmListeners: listeners,
  );
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
  final query =
      ref.watch(artistAlbumsQueryProvider(artistId).select((q) => q));

  return query.snapshots().map((snap) {
    return snap.docs.map((d) {
      final data = d.data();

      final sec = data['secondaryTypes'];
      final List<String> secondaryTypes = sec is List
          ? sec.map((e) => e.toString()).toList(growable: false)
          : const <String>[];

      final cover = data['coverUrl'];
      final String? coverUrl = cover is String ? cover.trim() : null;

      return <String, dynamic>{
        ...data,
        'id': (data['id'] as String?) ?? d.id,
        'secondaryTypes': secondaryTypes,
        if (coverUrl != null) 'coverUrl': coverUrl,
      };
    }).toList(growable: false);
  });
});
