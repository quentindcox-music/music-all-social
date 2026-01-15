import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class DeezerService {
  static const String _base = 'https://api.deezer.com';

  // Small in-memory caches
  static final Map<String, Future<int?>> _bestArtistIdCache = {};
  static final Map<String, Future<String?>> _bestArtistImageCache = {};

  /// Backwards compatible API (keeps your existing calls working).
  static Future<List<DeezerTrack>> getArtistTopTracks(String artistName) {
    return getTopTracksForMusicBrainzArtist(
      artistName: artistName,
      limit: 5,
    );
  }

  /// ✅ Safer than name-only:
  /// - If MB type is Person/Character => returns empty (prevents wrong “band” tracks)
  /// - Otherwise searches Deezer, picks best match, returns top tracks.
  static Future<List<DeezerTrack>> getTopTracksForMusicBrainzArtist({
    required String artistName,
    String? mbType,
    String? country,
    int limit = 5,
  }) async {
    final q = artistName.trim();
    if (q.isEmpty) return const <DeezerTrack>[];

    final type = (mbType ?? '').trim().toLowerCase();
    if (type == 'person' || type == 'character') {
      // Don’t attach popular band tracks to a person duplicate.
      return const <DeezerTrack>[];
    }

    try {
      final artistId = await _getBestArtistId(
        q,
        mbType: mbType,
        country: country,
        limit: 8,
      );
      if (artistId == null) return const <DeezerTrack>[];

      final tracksUrl = Uri.parse('$_base/artist/$artistId/top?limit=$limit');
      final tracksResp =
          await http.get(tracksUrl).timeout(const Duration(seconds: 10));
      if (tracksResp.statusCode != 200) return const <DeezerTrack>[];

      final tracksData = json.decode(tracksResp.body) as Map<String, dynamic>;
      final tracks = tracksData['data'] as List?;
      if (tracks == null) return const <DeezerTrack>[];

      return tracks
          .whereType<Map>()
          .map((t) => DeezerTrack.fromJson(Map<String, dynamic>.from(t)))
          .toList(growable: false);
    } catch (_) {
      return const <DeezerTrack>[];
    }
  }

  /// ✅ Get a best-effort artist image from Deezer (high coverage).
  /// Conservative for Person/Character via caller (you should pass mbType).
  static Future<String?> getBestArtistImageUrl(
    String artistName, {
    String? mbType,
    String? country,
    int limit = 8,
  }) {
    final q = artistName.trim();
    if (q.isEmpty) return Future.value(null);

    final type = (mbType ?? '').trim().toLowerCase();
    if (type == 'person' || type == 'character') return Future.value(null);

    final cacheKey = 'img:${q.toLowerCase()}|${(country ?? '').toLowerCase()}|$type|$limit';
    return _bestArtistImageCache.putIfAbsent(cacheKey, () async {
      try {
        final hits = await _searchArtists(q, limit: limit);
        if (hits.isEmpty) return null;

        final best = _pickBest(hits, queryName: q);
        if (best == null) return null;

        final pic = (best['picture_xl'] ??
                best['picture_big'] ??
                best['picture_medium'] ??
                best['picture']) ??
            '';
        final url = pic.toString().trim();
        return url.isEmpty ? null : url;
      } catch (_) {
        return null;
      }
    });
  }

  // -----------------------
  // Internals
  // -----------------------

  static Future<int?> _getBestArtistId(
    String artistName, {
    String? mbType,
    String? country,
    int limit = 8,
  }) {
    final q = artistName.trim();
    if (q.isEmpty) return Future.value(null);

    final type = (mbType ?? '').trim().toLowerCase();
    final cacheKey = 'id:${q.toLowerCase()}|${(country ?? '').toLowerCase()}|$type|$limit';

    return _bestArtistIdCache.putIfAbsent(cacheKey, () async {
      final hits = await _searchArtists(q, limit: limit);
      if (hits.isEmpty) return null;

      final best = _pickBest(hits, queryName: q);
      if (best == null) return null;

      final id = best['id'];
      if (id is num) return id.toInt();
      return int.tryParse(id?.toString() ?? '');
    });
  }

  static Future<List<Map<String, dynamic>>> _searchArtists(
    String q, {
    int limit = 8,
  }) async {
    final url = Uri.parse(
      '$_base/search/artist?q=${Uri.encodeQueryComponent(q)}&limit=$limit',
    );

    final resp = await http.get(url).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return const <Map<String, dynamic>>[];

    final data = json.decode(resp.body) as Map<String, dynamic>;
    final list = data['data'];
    if (list is! List || list.isEmpty) return const <Map<String, dynamic>>[];

    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  static Map<String, dynamic>? _pickBest(
    List<Map<String, dynamic>> hits, {
    required String queryName,
  }) {
    final qNorm = _norm(queryName);
    Map<String, dynamic>? best;
    int bestScore = -1;

    for (final item in hits) {
      final name = (item['name']?.toString() ?? '').trim();
      if (name.isEmpty) continue;

      final nNorm = _norm(name);

      int score = 0;

      // Strong match heuristics
      if (nNorm == qNorm) {
        score += 1000;
      } else if (nNorm.startsWith(qNorm)) {
        score += 600;
      } else if (qNorm.startsWith(nNorm)) {
        score += 450;
      } else if (nNorm.contains(qNorm) || qNorm.contains(nNorm)) {
        score += 200;
      }

      // Popularity helps among multiple valid matches
      final fans = item['nb_fan'];
      final int fanCount =
          fans is num ? fans.toInt() : int.tryParse(fans?.toString() ?? '') ?? 0;
      score += (fanCount ~/ 20000).clamp(0, 250);

      if (score > bestScore) {
        bestScore = score;
        best = item;
      }
    }

    // If we never got a “real” name similarity signal, bail out.
    if (bestScore < 200) return null;
    return best;
  }

  static String _norm(String s) {
    // lowercase, remove punctuation/extra spaces
    final lower = s.toLowerCase().trim();
    final noPunct = lower.replaceAll(RegExp(r"[^a-z0-9\s]"), "");
    return noPunct.replaceAll(RegExp(r"\s+"), " ").trim();
  }
}

class DeezerTrack {
  final String id;
  final String title;
  final int durationSeconds;
  final String? albumCoverUrl;
  final String? albumTitle;
  final String? previewUrl;

  DeezerTrack({
    required this.id,
    required this.title,
    required this.durationSeconds,
    this.albumCoverUrl,
    this.albumTitle,
    this.previewUrl,
  });

  factory DeezerTrack.fromJson(Map<String, dynamic> json) {
    final album = json['album'] as Map<String, dynamic>?;
    return DeezerTrack(
      id: json['id'].toString(),
      title: (json['title'] as String?) ?? '',
      durationSeconds: (json['duration'] as int?) ?? 0,
      albumCoverUrl: album?['cover_medium'] as String?,
      albumTitle: album?['title'] as String?,
      previewUrl: json['preview'] as String?,
    );
  }

  String get formattedDuration {
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
