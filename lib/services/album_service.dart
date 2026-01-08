// lib/services/album_service.dart

import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:retry/retry.dart';

import '../models/album.dart';
import 'musicbrainz_service.dart';

class AlbumService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String _mbUserAgent =
      'music_all_app/1.0.0 (quentincoxmusic@gmail.com)';

  static IOClient _createMbClient() {
    final HttpClient io = HttpClient()
      ..idleTimeout = const Duration(seconds: 15)
      ..connectionTimeout = const Duration(seconds: 15);

    return IOClient(io);
  }

  /// Creates/updates an album doc using the MusicBrainz Release Group as source.
  /// Now with retry logic and better error handling.
  static Future<Album> upsertFromMusicBrainz(MbReleaseGroup rg) async {
    final albumRef = _db.collection('albums').doc(rg.id);

    try {
      // Use retry for network resilience
      await retry(
        () async {
          // 1) Upsert album document
          await albumRef.set(
            {
              'id': rg.id,
              'title': rg.title,
              'primaryArtistName': rg.primaryArtistName,
              'primaryArtistId': rg.primaryArtistId ?? '',
              'firstReleaseDate': rg.firstReleaseDate ?? '',
              'primaryType': rg.primaryType ?? '',
              'source': 'musicbrainz',
              'coverUrl': 'https://coverartarchive.org/release-group/${rg.id}/front-250',
              'updatedAt': FieldValue.serverTimestamp(),
              'createdAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );

          // 2) Upsert basic artist doc (if we have an artist MBID)
          if (rg.primaryArtistId != null && rg.primaryArtistId!.isNotEmpty) {
            final artistRef = _db.collection('artists').doc(rg.primaryArtistId!);

            await artistRef.set(
              {
                'id': rg.primaryArtistId,
                'name': rg.primaryArtistName,
                'updatedAt': FieldValue.serverTimestamp(),
                'createdAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
          }
        },
        retryIf: (e) => e is SocketException || e is TimeoutException,
        maxAttempts: 3,
      );

      // 3) Fetch & store tracklist (soft-fails on network errors)
      await updateTracklistFromMusicBrainz(rg);

      // 4) Fetch the created album and return it
      final doc = await albumRef.get();
      return Album.fromFirestore(doc);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('⚠️ Failed to upsert album ${rg.id}: $e\n$st');
      }
      rethrow;
    }
  }

  /// Fetches an album by ID from Firestore
  static Future<Album?> getAlbum(String albumId) async {
    try {
      final doc = await _db.collection('albums').doc(albumId).get();
      if (!doc.exists) return null;
      return Album.fromFirestore(doc);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('⚠️ Failed to fetch album $albumId: $e\n$st');
      }
      rethrow;
    }
  }

  /// Fetches tracks for an album
  static Future<List<Track>> getTracks(String albumId) async {
    try {
      final snapshot = await _db
          .collection('albums')
          .doc(albumId)
          .collection('tracks')
          .orderBy('position')
          .get();

      return snapshot.docs.map((doc) => Track.fromFirestore(doc)).toList();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('⚠️ Failed to fetch tracks for $albumId: $e\n$st');
      }
      return [];
    }
  }

  /// Fetches a tracklist from MusicBrainz and stores it
  static Future<void> updateTracklistFromMusicBrainz(
    MbReleaseGroup rg,
  ) async {
    final albumRef = _db.collection('albums').doc(rg.id);

    try {
      final List<Map<String, dynamic>> tracks = await retry(
        () => _fetchTrackList(rg.id),
        retryIf: (e) => e is SocketException || e is TimeoutException,
        maxAttempts: 3,
      );

      if (tracks.isEmpty) {
        if (kDebugMode) {
          debugPrint('No tracks found for ${rg.title}');
        }
        return;
      }

      final WriteBatch batch = _db.batch();
      final CollectionReference<Map<String, dynamic>> tracksRef =
          albumRef.collection('tracks');

      for (final Map<String, dynamic> t in tracks) {
        final String docId = '${t['position']}';
        batch.set(
          tracksRef.doc(docId),
          t,
          SetOptions(merge: true),
        );
      }

      await batch.commit();

      if (kDebugMode) {
        debugPrint(
          'Tracklist updated for ${rg.title} (${tracks.length} tracks)',
        );
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
          '⚠️ Failed to fetch tracklist for ${rg.id}: $e\n$st',
        );
      }
      // Soft fail - don't throw
    }
  }

  /// Fetches the tracklist for the *first* release in a release-group
  static Future<List<Map<String, dynamic>>> _fetchTrackList(
    String releaseGroupId,
  ) async {
    const String base = 'https://musicbrainz.org/ws/2';
    final IOClient client = _createMbClient();

    try {
      // 1) Get releases for this release-group
      final Uri releasesUrl = Uri.parse(
        '$base/release-group/$releaseGroupId?inc=releases&fmt=json',
      );

      final http.Response releasesRes = await client
          .get(
            releasesUrl,
            headers: {'User-Agent': _mbUserAgent},
          )
          .timeout(const Duration(seconds: 15));

      if (releasesRes.statusCode != 200) {
        throw HttpException(
          'Release-group fetch failed (${releasesRes.statusCode})',
          uri: releasesUrl,
        );
      }

      final Map<String, dynamic> releasesJson =
          json.decode(releasesRes.body) as Map<String, dynamic>;
      final List<dynamic> releases =
          (releasesJson['releases'] as List?) ?? const [];

      if (releases.isEmpty) {
        return <Map<String, dynamic>>[];
      }

      final String? firstReleaseId = releases.first['id'] as String?;
      if (firstReleaseId == null || firstReleaseId.isEmpty) {
        return <Map<String, dynamic>>[];
      }

      // 2) Fetch that release with recordings (tracks)
      final Uri releaseUrl = Uri.parse(
        '$base/release/$firstReleaseId?inc=recordings&fmt=json',
      );

      final http.Response releaseRes = await client
          .get(
            releaseUrl,
            headers: {'User-Agent': _mbUserAgent},
          )
          .timeout(const Duration(seconds: 15));

      if (releaseRes.statusCode != 200) {
        throw HttpException(
          'Release fetch failed (${releaseRes.statusCode})',
          uri: releaseUrl,
        );
      }

      final Map<String, dynamic> releaseJson =
          json.decode(releaseRes.body) as Map<String, dynamic>;
      final List<dynamic> media =
          (releaseJson['media'] as List?) ?? const [];

      if (media.isEmpty) {
        return <Map<String, dynamic>>[];
      }

      final Map<String, dynamic> firstMedium =
          media.first as Map<String, dynamic>;
      final List<dynamic> tracksRaw =
          (firstMedium['tracks'] as List?) ?? const [];

      // 3) Normalize tracks
      final List<Map<String, dynamic>> tracks = <Map<String, dynamic>>[];
      int position = 1;

      for (final dynamic t in tracksRaw) {
        if (t is! Map<String, dynamic>) continue;

        final Map<String, dynamic>? recording =
            t['recording'] as Map<String, dynamic>?;

        final String title =
            (recording?['title'] ?? t['title'] ?? '') as String? ?? '';

        final dynamic lengthVal = t['length'];
        double? durationSeconds;
        if (lengthVal is int) {
          durationSeconds = lengthVal / 1000.0;
        } else if (lengthVal is String) {
          final int? parsed = int.tryParse(lengthVal);
          if (parsed != null) {
            durationSeconds = parsed / 1000.0;
          }
        }

        tracks.add(<String, dynamic>{
          'position': position,
          'title': title,
          if (durationSeconds != null) 'durationSeconds': durationSeconds,
        });

        position++;
      }

      return tracks;
    } finally {
      client.close();
    }
  }

  /// Get average rating for an album
  static Future<double?> getAverageRating(String albumId) async {
    try {
      final snapshot = await _db
          .collectionGroup('reviews')
          .where('albumId', isEqualTo: albumId)
          .get();

      if (snapshot.docs.isEmpty) return null;

      double total = 0;
      for (final doc in snapshot.docs) {
        final rating = (doc.data()['rating'] as num?)?.toDouble() ?? 0;
        total += rating;
      }

      return total / snapshot.docs.length;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('⚠️ Failed to get average rating for $albumId: $e\n$st');
      }
      return null;
    }
  }

  /// Get review count for an album
  static Future<int> getReviewCount(String albumId) async {
    try {
      final snapshot = await _db
          .collectionGroup('reviews')
          .where('albumId', isEqualTo: albumId)
          .get();

      return snapshot.docs.length;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('⚠️ Failed to get review count for $albumId: $e\n$st');
      }
      return 0;
    }
  }
}