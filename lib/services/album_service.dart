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
  static Future<Album> upsertFromMusicBrainz(MbReleaseGroup rg) async {
    final albumRef = _db.collection('albums').doc(rg.id);

    try {
      await retry(
        () async {
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

      // Fetch & store tracklist
      await updateTracklistFromMusicBrainz(rg);

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
          .orderBy('disc')
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
  static Future<void> updateTracklistFromMusicBrainz(MbReleaseGroup rg) async {
    final albumRef = _db.collection('albums').doc(rg.id);
    final tracksRef = albumRef.collection('tracks');

    // Check if tracks already exist
    final existingTracks = await tracksRef.limit(1).get();
    if (existingTracks.docs.isNotEmpty) {
      if (kDebugMode) {
        debugPrint('Tracks already exist for ${rg.title}, skipping fetch');
      }
      return;
    }

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

      for (final Map<String, dynamic> t in tracks) {
        final disc = t['disc'] ?? 1;
        final position = t['position'] ?? 0;
        final String docId = '${disc}_$position';
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
    }
  }

  /// Fetches and stores tracks for an album by ID (for existing albums missing tracks)
  static Future<void> fetchAndStoreTracksById(String albumId) async {
    final albumRef = _db.collection('albums').doc(albumId);
    final tracksRef = albumRef.collection('tracks');

    final existingTracks = await tracksRef.limit(1).get();
    if (existingTracks.docs.isNotEmpty) return;

    try {
      final tracks = await _fetchTrackList(albumId);
      if (tracks.isEmpty) return;

      final batch = _db.batch();
      for (final t in tracks) {
        final disc = t['disc'] ?? 1;
        final position = t['position'] ?? 0;
        final docId = '${disc}_$position';
        batch.set(tracksRef.doc(docId), t);
      }
      await batch.commit();
      
      if (kDebugMode) {
        debugPrint('Fetched ${tracks.length} tracks for album $albumId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Failed to fetch tracks for $albumId: $e');
      }
    }
  }

  /// Fetches the tracklist for the *best* release in a release-group
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

      // Try to find the best release (prefer official, complete releases)
      String? bestReleaseId;
      for (final release in releases) {
        final status = release['status'] as String?;
        if (status == 'Official') {
          bestReleaseId = release['id'] as String?;
          break;
        }
      }
      bestReleaseId ??= releases.first['id'] as String?;

      if (bestReleaseId == null || bestReleaseId.isEmpty) {
        return <Map<String, dynamic>>[];
      }

      // Rate limiting delay
      await Future.delayed(const Duration(milliseconds: 500));

      // 2) Fetch that release with recordings (tracks)
      final Uri releaseUrl = Uri.parse(
        '$base/release/$bestReleaseId?inc=recordings&fmt=json',
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

      // 3) Normalize tracks from ALL discs
      final List<Map<String, dynamic>> tracks = <Map<String, dynamic>>[];

      for (final medium in media) {
        if (medium is! Map<String, dynamic>) continue;

        final int discNum = (medium['position'] as num?)?.toInt() ?? 1;
        final List<dynamic> tracksRaw =
            (medium['tracks'] as List?) ?? const [];

        for (final t in tracksRaw) {
          if (t is! Map<String, dynamic>) continue;

          final int position = (t['position'] as num?)?.toInt() ?? 0;
          final Map<String, dynamic>? recording =
              t['recording'] as Map<String, dynamic>?;

          final String title =
              (t['title'] ?? recording?['title'] ?? '') as String;

          final dynamic lengthVal = t['length'] ?? recording?['length'];
          double? durationSeconds;
          if (lengthVal is num) {
            durationSeconds = lengthVal / 1000.0;
          }

          tracks.add(<String, dynamic>{
            'disc': discNum,
            'position': position,
            'title': title,
            if (durationSeconds != null) 'durationSeconds': durationSeconds,
          });
        }
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
          .collection('albums')
          .doc(albumId)
          .collection('reviews')
          .get();

      if (snapshot.docs.isEmpty) return null;

      double total = 0;
      int count = 0;
      for (final doc in snapshot.docs) {
        final rating = (doc.data()['rating'] as num?)?.toDouble();
        if (rating != null) {
          total += rating;
          count++;
        }
      }

      return count > 0 ? total / count : null;
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
          .collection('albums')
          .doc(albumId)
          .collection('reviews')
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