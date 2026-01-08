import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // kDebugMode / debugPrint
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'musicbrainz_service.dart';

class AlbumService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Used in the User-Agent header for all MusicBrainz calls.
  /// 🔹 TIP: put a real contact email here (MusicBrainz prefers that).
  static const String _mbUserAgent =
      'music_all_app/1.0.0 (quentincoxmusic@gmail.com)';

  /// Create a HTTP client that plays nicely with MusicBrainz TLS on iOS.
  static IOClient _createMbClient() {
    final HttpClient io = HttpClient()
      ..idleTimeout = const Duration(seconds: 15)
      ..connectionTimeout = const Duration(seconds: 15);

    return IOClient(io);
  }

  /// Creates/updates an album doc using the MusicBrainz Release Group as source.
  ///
  /// - Writes to:  albums/{releaseGroupId}
  /// - Also ensures: artists/{primaryArtistId} exists (if available)
  /// - Then triggers a tracklist update under: albums/{id}/tracks
  static Future<void> upsertFromMusicBrainz(MbReleaseGroup rg) async {
    final albumRef = _db.collection('albums').doc(rg.id);

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
        'updatedAt': FieldValue.serverTimestamp(),
        // createdAt is preserved on merges if already present
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

    // 3) Fetch & store tracklist (soft-fails on network errors).
    await updateTracklistFromMusicBrainz(rg);
  }

  /// Fetches a tracklist from MusicBrainz and stores it in:
  ///   albums/{albumId}/tracks/{position}
  static Future<void> updateTracklistFromMusicBrainz(
    MbReleaseGroup rg,
  ) async {
    final albumRef = _db.collection('albums').doc(rg.id);

    try {
      final List<Map<String, dynamic>> tracks = await _fetchTrackList(rg.id);

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
    }
  }

  /// Fetches the tracklist for the *first* release in a release-group from
  /// MusicBrainz and normalizes it to a simple list of maps.
  ///
  /// Each returned map looks like:
  /// {
  ///   "position": 1,
  ///   "title": "Speed of Life",
  ///   "durationSeconds": 154.0, // optional
  /// }
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

      final http.Response releasesRes = await client.get(
        releasesUrl,
        headers: {
          'User-Agent': _mbUserAgent,
        },
      );

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
        if (kDebugMode) {
          debugPrint(
            'No releases found for release-group $releaseGroupId',
          );
        }
        return <Map<String, dynamic>>[];
      }

      // For now, just pick the first release; can be made smarter later
      final String? firstReleaseId = releases.first['id'] as String?;
      if (firstReleaseId == null || firstReleaseId.isEmpty) {
        return <Map<String, dynamic>>[];
      }

      // 2) Fetch that release with recordings (tracks)
      final Uri releaseUrl = Uri.parse(
        '$base/release/$firstReleaseId?inc=recordings&fmt=json',
      );

      final http.Response releaseRes = await client.get(
        releaseUrl,
        headers: {
          'User-Agent': _mbUserAgent,
        },
      );

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
      final List<Map<String, dynamic>> tracks =
          <Map<String, dynamic>>[];
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
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
          '⚠️ Tracklist fetch failed for $releaseGroupId: $e\n$st',
        );
      }
      // Fail-soft so the UI just shows "No tracklist available yet."
      return <Map<String, dynamic>>[];
    } finally {
      client.close();
    }
  }
}
