import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Minimal album-ish result from MusicBrainz Release Group search.
class MbReleaseGroup {
  MbReleaseGroup({
    required this.id,
    required this.title,
    this.primaryArtistId,
    required this.primaryArtistName,
    this.firstReleaseDate,
    this.primaryType,
    this.score,
  });

  final String id;
  final String title;
  final String? primaryArtistId;
  final String primaryArtistName;
  final String? firstReleaseDate;
  final String? primaryType;
  final int? score; // MusicBrainz relevance score (0-100)
}

/// Artist search result from MusicBrainz
class MbArtistSearchResult {
  MbArtistSearchResult({
    required this.id,
    required this.name,
    this.type,
    this.country,
    this.score,
    this.disambiguation,
  });

  final String id;
  final String name;
  final String? type;
  final String? country;
  final int? score;
  final String? disambiguation;
}

/// Artist details from MusicBrainz
class MbArtist {
  MbArtist({
    required this.id,
    required this.name,
    this.type,
    this.country,
    this.disambiguation, // ✅ NEW (fixes your provider error)
    this.beginArea,
    this.beginDate,
    this.endDate,
  });

  final String id;
  final String name;
  final String? type;
  final String? country;
  final String? disambiguation; // ✅ NEW
  final String? beginArea;
  final String? beginDate;
  final String? endDate;

  String? get lifeSpan {
    if (beginDate == null && endDate == null) return null;
    final start = beginDate?.split('-').first ?? '?';
    final end = endDate?.split('-').first ?? 'present';
    return '$start – $end';
  }
}

class MusicBrainzService {
  MusicBrainzService({
    http.Client? client,
    this.appUserAgent = 'MusicAllApp/0.1 (contact: quentincoxmusic@gmail.com)',
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String appUserAgent;

  // ---------------------------
  // Search
  // ---------------------------

  Future<List<MbReleaseGroup>> searchReleaseGroups(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];

    final lucene = Uri.encodeQueryComponent(q);
    final url = Uri.parse(
      'https://musicbrainz.org/ws/2/release-group/?query=$lucene&fmt=json&limit=25',
    );

    final resp = await _client.get(
      url,
      headers: {
        'User-Agent': appUserAgent,
        'Accept': 'application/json',
      },
    );

    if (resp.statusCode == 503) {
      throw Exception('MusicBrainz rate limit (503). Try again in a moment.');
    }
    if (resp.statusCode != 200) {
      throw Exception('MusicBrainz error: ${resp.statusCode}');
    }

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = (decoded['release-groups'] as List<dynamic>? ?? const []);

    final results = list.map((raw) {
      final m = raw as Map<String, dynamic>;
      final title = (m['title'] as String?)?.trim() ?? '';
      final id = (m['id'] as String?)?.trim() ?? '';
      final score = m['score'] as int?;

      String artistName = '';
      String? artistId;

      final artistCredit = m['artist-credit'];
      if (artistCredit is List && artistCredit.isNotEmpty) {
        final first = artistCredit.first;
        if (first is Map) {
          if (first['name'] is String) {
            artistName = (first['name'] as String).trim();
          }
          final artistObj = first['artist'];
          if (artistObj is Map && artistObj['id'] is String) {
            artistId = (artistObj['id'] as String).trim();
          }
        }
      }

      return MbReleaseGroup(
        id: id,
        title: title,
        primaryArtistId: (artistId?.isEmpty == true) ? null : artistId,
        primaryArtistName: artistName,
        firstReleaseDate: m['first-release-date'] as String?,
        primaryType: m['primary-type'] as String?,
        score: score,
      );
    }).where((r) => r.id.isNotEmpty && r.title.isNotEmpty).toList();

    // Sort by score (highest first) - MusicBrainz relevance
    results.sort((a, b) => (b.score ?? 0).compareTo(a.score ?? 0));

    return results;
  }

  /// Search for artists
  Future<List<MbArtistSearchResult>> searchArtists(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];

    final lucene = Uri.encodeQueryComponent(q);
    final url = Uri.parse(
      'https://musicbrainz.org/ws/2/artist/?query=$lucene&fmt=json&limit=15',
    );

    final resp = await _client.get(
      url,
      headers: {
        'User-Agent': appUserAgent,
        'Accept': 'application/json',
      },
    );

    if (resp.statusCode == 503) {
      throw Exception('MusicBrainz rate limit (503). Try again in a moment.');
    }
    if (resp.statusCode != 200) {
      throw Exception('MusicBrainz error: ${resp.statusCode}');
    }

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = (decoded['artists'] as List<dynamic>? ?? const []);

    final results = list.map((raw) {
      final m = raw as Map<String, dynamic>;
      final id = (m['id'] as String?)?.trim() ?? '';
      final name = (m['name'] as String?)?.trim() ?? '';

      return MbArtistSearchResult(
        id: id,
        name: name,
        type: m['type'] as String?,
        country: m['country'] as String?,
        score: m['score'] as int?,
        disambiguation: (m['disambiguation'] as String?)?.trim(),
      );
    }).where((r) => r.id.isNotEmpty && r.name.isNotEmpty).toList();

    // Sort by score
    results.sort((a, b) => (b.score ?? 0).compareTo(a.score ?? 0));

    return results;
  }

  // ---------------------------
  // Artist details + discography
  // ---------------------------

  /// Fetch artist details by MBID
  static Future<MbArtist?> fetchArtistDetails(String artistId) async {
    final id = artistId.trim();
    if (id.isEmpty) return null;

    final url = Uri.parse('https://musicbrainz.org/ws/2/artist/$id?fmt=json');

    final resp = await http.get(url, headers: {
      'User-Agent': 'MusicAllApp/0.1 (contact: quentincoxmusic@gmail.com)',
      'Accept': 'application/json',
    });

    if (resp.statusCode != 200) return null;

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final lifeSpan = data['life-span'] as Map<String, dynamic>?;
    final beginArea = data['begin-area'] as Map<String, dynamic>?;

    return MbArtist(
      id: (data['id'] as String?)?.trim() ?? id,
      name: (data['name'] as String?)?.trim() ?? '',
      type: (data['type'] as String?)?.trim(),
      country: (data['country'] as String?)?.trim(),
      disambiguation: (data['disambiguation'] as String?)?.trim(), // ✅ NEW
      beginArea: (beginArea?['name'] as String?)?.trim(),
      beginDate: (lifeSpan?['begin'] as String?)?.trim(),
      endDate: (lifeSpan?['end'] as String?)?.trim(),
    );
  }

  static Future<List<Map<String, dynamic>>> fetchArtistReleaseGroups(String artistId) async {
    final id = artistId.trim();
    if (id.isEmpty) return const [];

    final url = Uri.parse(
      'https://musicbrainz.org/ws/2/release-group?artist=$id&type=album|ep|single&fmt=json&limit=100',
    );

    final resp = await http.get(url, headers: {
      'User-Agent': 'MusicAllApp/0.1 (contact: quentincoxmusic@gmail.com)',
      'Accept': 'application/json',
    });

    if (resp.statusCode != 200) return const [];

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final groups = data['release-groups'] as List<dynamic>? ?? const [];

    return groups.map((g) {
      final m = g as Map<String, dynamic>;
      return <String, dynamic>{
        'id': (m['id'] as String?)?.trim() ?? '',
        'title': (m['title'] as String?)?.trim() ?? '',
        'primaryType': m['primary-type'] as String?,
        'secondaryTypes': m['secondary-types'] as List?,
        'firstReleaseDate': m['first-release-date'] as String?,
      };
    }).where((m) => (m['id'] as String).isNotEmpty).toList(growable: false);
  }

  // ---------------------------
  // Tracklist helpers
  // ---------------------------

  static const String _mbBase = 'https://musicbrainz.org/ws/2';

  static Map<String, String> _mbHeaders({String? userAgent}) => {
        'User-Agent': userAgent ?? 'MusicAllApp/0.1 (contact: quentincoxmusic@gmail.com)',
        'Accept': 'application/json',
      };

  static int _dateScore(String? date) {
    // Lower is better (earlier). Unknown dates are "worst".
    if (date == null || date.trim().isEmpty) return 99999999;
    final parts = date.trim().split('-');
    final y = int.tryParse(parts[0]) ?? 9999;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 12 : 12;
    final d = parts.length > 2 ? int.tryParse(parts[2]) ?? 28 : 28;
    return y * 10000 + m * 100 + d;
  }

  static Map<String, dynamic>? _pickBestRelease(List releases) {
    // Prefer Official; then earliest date; else first.
    Map<String, dynamic>? best;
    int bestRank = 1 << 30;

    for (final r in releases) {
      if (r is! Map) continue;
      final status = (r['status'] as String?)?.toLowerCase();
      final date = r['date'] as String?;
      final isOfficial = status == 'official';

      final rank = (isOfficial ? 0 : 1) * 100000000 + _dateScore(date);
      if (rank < bestRank) {
        bestRank = rank;
        best = Map<String, dynamic>.from(r);
      }
    }

    if (best != null) return best;
    if (releases.isNotEmpty && releases.first is Map) {
      return Map<String, dynamic>.from(releases.first as Map);
    }
    return null;
  }

  /// Fetch releases for a release-group (needed to pick a release for tracklist)
  static Future<List<Map<String, dynamic>>> fetchReleaseGroupReleases(
    String releaseGroupId, {
    String? userAgent,
  }) async {
    final id = releaseGroupId.trim();
    if (id.isEmpty) return const [];

    final url = Uri.parse('$_mbBase/release-group/$id?fmt=json&inc=releases');

    final resp = await http.get(url, headers: _mbHeaders(userAgent: userAgent));

    if (resp.statusCode == 503) {
      throw Exception('MusicBrainz rate limit (503). Try again in a moment.');
    }
    if (resp.statusCode != 200) {
      throw Exception('MusicBrainz error: ${resp.statusCode}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final releases = (data['releases'] as List?) ?? const [];

    return releases
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  /// Fetch a release with recordings and return normalized tracks
  /// Output maps match what your AlbumDetailPage already expects:
  /// { title, disc, position, durationSeconds, recordingId }
  static Future<List<Map<String, dynamic>>> fetchReleaseTracklist(
    String releaseId, {
    String? userAgent,
  }) async {
    final id = releaseId.trim();
    if (id.isEmpty) return const [];

    final url = Uri.parse('$_mbBase/release/$id?fmt=json&inc=recordings');

    final resp = await http.get(url, headers: _mbHeaders(userAgent: userAgent));

    if (resp.statusCode == 503) {
      throw Exception('MusicBrainz rate limit (503). Try again in a moment.');
    }
    if (resp.statusCode != 200) {
      throw Exception('MusicBrainz error: ${resp.statusCode}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final media = (data['media'] as List?) ?? const [];

    final tracksOut = <Map<String, dynamic>>[];

    for (final m in media) {
      if (m is! Map) continue;

      final discNum = (m['position'] as num?)?.toInt() ?? 1;
      final tracks = (m['tracks'] as List?) ?? const [];

      for (final t in tracks) {
        if (t is! Map) continue;

        final pos = (t['position'] as num?)?.toInt() ?? 0;
        final title = (t['title'] as String?)?.trim();
        final lengthMs = (t['length'] as num?)?.toInt();

        final rec = t['recording'];
        final recordingId = rec is Map ? (rec['id'] as String?)?.trim() : null;

        final durationSeconds = lengthMs == null ? null : (lengthMs / 1000.0).round();

        tracksOut.add({
          'title': (title != null && title.isNotEmpty) ? title : 'Untitled track',
          'disc': discNum,
          'position': pos,
          if (durationSeconds != null) 'durationSeconds': durationSeconds,
          if (recordingId != null && recordingId.isNotEmpty) 'recordingId': recordingId,
        });
      }
    }

    tracksOut.sort((a, b) {
      final da = (a['disc'] as int?) ?? 1;
      final db = (b['disc'] as int?) ?? 1;
      if (da != db) return da.compareTo(db);
      final pa = (a['position'] as int?) ?? 0;
      final pb = (b['position'] as int?) ?? 0;
      return pa.compareTo(pb);
    });

    return tracksOut;
  }

  /// Convenience: release-group -> choose release -> fetch tracklist
  static Future<({String releaseId, List<Map<String, dynamic>> tracks})> fetchTracklistForReleaseGroup(
    String releaseGroupId, {
    String? userAgent,
  }) async {
    final releases = await fetchReleaseGroupReleases(
      releaseGroupId,
      userAgent: userAgent,
    );

    // MusicBrainz is rate-limited; be polite between calls.
    await Future.delayed(const Duration(milliseconds: 1100));

    final best = _pickBestRelease(releases);
    if (best == null) {
      throw Exception('No releases found for release-group $releaseGroupId');
    }

    final releaseId = (best['id'] as String?)?.trim();
    if (releaseId == null || releaseId.isEmpty) {
      throw Exception('Could not determine release id for $releaseGroupId');
    }

    final tracks = await fetchReleaseTracklist(
      releaseId,
      userAgent: userAgent,
    );

    return (releaseId: releaseId, tracks: tracks);
  }
}
