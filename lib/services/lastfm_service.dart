import 'dart:convert';
import 'package:http/http.dart' as http;

class LastFmService {
  LastFmService({
    required this.apiKey,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  static const _baseUrl = 'https://ws.audioscrobbler.com/2.0/';

  // Simple in-memory caches to avoid repeating requests during a session.
  final Map<String, Future<LastFmArtistInfo?>> _artistInfoCache = {};
  final Map<String, Future<String?>> _artistImageCache = {};
  final Map<String, Future<LastFmAlbumInfo?>> _albumInfoCache = {};

  // -----------------------
  // Album
  // -----------------------

  /// Get album info with listener count (name-based).
  Future<LastFmAlbumInfo?> getAlbumInfo(String artist, String album) {
    if (apiKey.trim().isEmpty) return Future.value(null);

    final a = artist.trim();
    final b = album.trim();
    if (a.isEmpty || b.isEmpty) return Future.value(null);

    final cacheKey = 'album:${a.toLowerCase()}::${b.toLowerCase()}';
    return _albumInfoCache.putIfAbsent(cacheKey, () async {
      try {
        final url = Uri.parse(
          '$_baseUrl?method=album.getinfo&api_key=$apiKey'
          '&artist=${Uri.encodeComponent(a)}'
          '&album=${Uri.encodeComponent(b)}'
          '&autocorrect=1'
          '&format=json',
        );

        final resp = await _client.get(url).timeout(const Duration(seconds: 6));
        if (resp.statusCode != 200) return null;

        final decoded = jsonDecode(resp.body);
        if (decoded is! Map<String, dynamic>) return null;
        if (decoded.containsKey('error')) return null;

        final albumData = decoded['album'];
        if (albumData is! Map) return null;

        // Album "artist" sometimes is a string, sometimes an object.
        String artistName = '';
        final rawArtist = albumData['artist'];
        if (rawArtist is String) {
          artistName = rawArtist;
        } else if (rawArtist is Map) {
          artistName = (rawArtist['name'] as String?) ?? '';
        }

        return LastFmAlbumInfo(
          name: (albumData['name'] as String?) ?? '',
          artist: artistName,
          listeners: int.tryParse(albumData['listeners']?.toString() ?? '') ?? 0,
          playcount: int.tryParse(albumData['playcount']?.toString() ?? '') ?? 0,
        );
      } catch (_) {
        return null;
      }
    });
  }

  // -----------------------
  // Artist
  // -----------------------

  /// Get artist info with listener count.
  /// ✅ Tries MBID first when provided, then optionally falls back to name.
  Future<LastFmArtistInfo?> getArtistInfo(
    String artist, {
    String? mbid,
    bool allowNameFallback = true,
  }) {
    if (apiKey.trim().isEmpty) return Future.value(null);

    final name = artist.trim();
    final id = (mbid ?? '').trim();

    final cacheKey =
        id.isNotEmpty ? 'artist_mbid:$id' : 'artist_name:${name.toLowerCase()}';

    return _artistInfoCache.putIfAbsent(cacheKey, () async {
      // 1) Try MBID
      if (id.isNotEmpty) {
        final byMbid = await _fetchArtistInfoByMbid(id);
        if (byMbid != null) return byMbid;
        if (!allowNameFallback) return null;
      }

      // 2) Fallback by name
      if (name.isEmpty) return null;
      return _fetchArtistInfoByName(name);
    });
  }

  Future<LastFmArtistInfo?> _fetchArtistInfoByMbid(String mbid) async {
    try {
      final url = Uri.parse(
        '$_baseUrl?method=artist.getinfo&api_key=$apiKey'
        '&mbid=${Uri.encodeComponent(mbid)}'
        '&format=json',
      );

      final resp = await _client.get(url).timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body);
      if (data is! Map<String, dynamic>) return null;
      if (data.containsKey('error')) return null;

      final artistData = data['artist'];
      if (artistData is! Map) return null;

      final stats = artistData['stats'];
      final statsMap = stats is Map ? Map<String, dynamic>.from(stats) : null;

      return LastFmArtistInfo(
        name: (artistData['name'] as String?) ?? '',
        listeners: int.tryParse(statsMap?['listeners']?.toString() ?? '') ?? 0,
        playcount: int.tryParse(statsMap?['playcount']?.toString() ?? '') ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  Future<LastFmArtistInfo?> _fetchArtistInfoByName(String artist) async {
    try {
      final url = Uri.parse(
        '$_baseUrl?method=artist.getinfo&api_key=$apiKey'
        '&artist=${Uri.encodeComponent(artist)}'
        '&autocorrect=1'
        '&format=json',
      );

      final resp = await _client.get(url).timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body);
      if (data is! Map<String, dynamic>) return null;
      if (data.containsKey('error')) return null;

      final artistData = data['artist'];
      if (artistData is! Map) return null;

      final stats = artistData['stats'];
      final statsMap = stats is Map ? Map<String, dynamic>.from(stats) : null;

      return LastFmArtistInfo(
        name: (artistData['name'] as String?) ?? '',
        listeners: int.tryParse(statsMap?['listeners']?.toString() ?? '') ?? 0,
        playcount: int.tryParse(statsMap?['playcount']?.toString() ?? '') ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// Get best available artist image URL (Last.fm).
  ///
  /// ✅ MBID first (best disambiguation)
  /// ✅ name + autocorrect=1 fallback
  /// ✅ NEW: if getinfo has no images, fallback to artist.search and pick best match
  Future<String?> getArtistImageUrl(
    String artist, {
    String? mbid,
    bool allowNameFallback = true,
  }) {
    if (apiKey.trim().isEmpty) return Future.value(null);

    final name = artist.trim();
    final id = (mbid ?? '').trim();

    final cacheKey =
        id.isNotEmpty ? 'img_mbid:$id' : 'img_name:${name.toLowerCase()}';

    return _artistImageCache.putIfAbsent(cacheKey, () async {
      // 1) MBID -> getinfo
      if (id.isNotEmpty) {
        final artistData = await _fetchArtistGetInfoJson(mbid: id);
        final url = _pickBestImageUrl(artistData?['image']);
        if (url != null) return url;

        if (!allowNameFallback) return null;
        // else continue to name/search fallback
      }

      // 2) Name -> getinfo (autocorrect=1)
      if (name.isNotEmpty) {
        final artistData = await _fetchArtistGetInfoJson(artist: name);
        final url = _pickBestImageUrl(artistData?['image']);
        if (url != null) return url;
      }

      // 3) NEW: Name -> artist.search fallback (often returns images even when getinfo doesn't)
      if (name.isNotEmpty) {
        final match = await _fetchBestArtistSearchMatch(
          queryName: name,
          preferredMbid: id.isNotEmpty ? id : null,
        );

        final url = _pickBestImageUrl(match?['image']);
        if (url != null) return url;
      }

      return null;
    });
  }

  Future<Map<String, dynamic>?> _fetchArtistGetInfoJson({
    String? artist,
    String? mbid,
  }) async {
    try {
      final a = (artist ?? '').trim();
      final id = (mbid ?? '').trim();
      if (a.isEmpty && id.isEmpty) return null;

      final url = Uri.parse(
        '$_baseUrl?method=artist.getinfo&api_key=$apiKey'
        '${id.isNotEmpty ? '&mbid=${Uri.encodeComponent(id)}' : ''}'
        '${id.isEmpty ? '&artist=${Uri.encodeComponent(a)}&autocorrect=1' : ''}'
        '&format=json',
      );

      final resp = await _client.get(url).timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body);
      if (data is! Map<String, dynamic>) return null;
      if (data.containsKey('error')) return null;

      final artistData = data['artist'];
      if (artistData is! Map) return null;

      return Map<String, dynamic>.from(artistData);
    } catch (_) {
      return null;
    }
  }

  /// artist.search fallback:
  /// - if preferredMbid is provided, try to match on mbid
  /// - else exact name match (case-insensitive)
  /// - else highest listeners
  Future<Map<String, dynamic>?> _fetchBestArtistSearchMatch({
    required String queryName,
    String? preferredMbid,
  }) async {
    try {
      final q = queryName.trim();
      if (q.isEmpty) return null;

      final url = Uri.parse(
        '$_baseUrl?method=artist.search&api_key=$apiKey'
        '&artist=${Uri.encodeComponent(q)}'
        '&limit=8'
        '&format=json',
      );

      final resp = await _client.get(url).timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body);
      if (data is! Map<String, dynamic>) return null;
      if (data.containsKey('error')) return null;

      final results = data['results'];
      if (results is! Map) return null;

      final matches = results['artistmatches'];
      if (matches is! Map) return null;

      final rawArtists = matches['artist'];
      final list = <Map<String, dynamic>>[];

      if (rawArtists is List) {
        for (final a in rawArtists) {
          if (a is Map) list.add(Map<String, dynamic>.from(a));
        }
      } else if (rawArtists is Map) {
        list.add(Map<String, dynamic>.from(rawArtists));
      }

      if (list.isEmpty) return null;

      final preferred = (preferredMbid ?? '').trim();
      if (preferred.isNotEmpty) {
        final byMbid = list.firstWhere(
          (a) => (a['mbid']?.toString().trim() ?? '') == preferred,
          orElse: () => const <String, dynamic>{},
        );
        if (byMbid.isNotEmpty) return byMbid;
      }

      final qLower = q.toLowerCase();
      final exact = list.firstWhere(
        (a) => (a['name']?.toString().trim().toLowerCase() ?? '') == qLower,
        orElse: () => const <String, dynamic>{},
      );
      if (exact.isNotEmpty) return exact;

      list.sort((a, b) {
        final la = int.tryParse(a['listeners']?.toString() ?? '') ?? 0;
        final lb = int.tryParse(b['listeners']?.toString() ?? '') ?? 0;
        return lb.compareTo(la);
      });

      return list.first;
    } catch (_) {
      return null;
    }
  }

  String? _pickBestImageUrl(dynamic imagesRaw) {
    if (imagesRaw is! List) return null;

    // Prefer biggest first (Last.fm typically uses these size labels)
    const preferred = ['mega', 'extralarge', 'large', 'medium', 'small'];

    String? pickForSize(String size) {
      for (final img in imagesRaw) {
        if (img is Map) {
          final s = img['size']?.toString();
          if (s == size) {
            final url = img['#text']?.toString().trim() ?? '';
            if (url.isNotEmpty) return url;
          }
        }
      }
      return null;
    }

    for (final size in preferred) {
      final u = pickForSize(size);
      if (u != null) return u;
    }

    // Fallback: any non-empty
    for (final img in imagesRaw) {
      if (img is Map) {
        final u = img['#text']?.toString().trim() ?? '';
        if (u.isNotEmpty) return u;
      }
    }

    return null;
  }

  // -----------------------
  // Batch helpers
  // -----------------------

  /// Batch fetch popularity for multiple albums (unchanged behavior).
  Future<Map<String, int>> getAlbumListenerCounts(
    List<({String artist, String album, String id})> albums,
  ) async {
    final results = <String, int>{};
    if (albums.isEmpty) return results;

    // Fetch in parallel, max 5 at a time to avoid rate limits
    final batches = <List<({String artist, String album, String id})>>[];
    for (var i = 0; i < albums.length; i += 5) {
      batches.add(albums.sublist(
        i,
        i + 5 > albums.length ? albums.length : i + 5,
      ));
    }

    for (final batch in batches) {
      final futures = batch.map((a) async {
        final info = await getAlbumInfo(a.artist, a.album);
        return (a.id, info?.listeners ?? 0);
      });

      final batchResults = await Future.wait(futures);
      for (final (id, listeners) in batchResults) {
        results[id] = listeners;
      }
    }

    return results;
  }

  /// Batch fetch popularity for multiple artists.
  ///
  /// ✅ Uses MBID (your MusicBrainz id) to disambiguate.
  /// ✅ If a name appears multiple times in this batch, we DO NOT fallback to name
  ///    for those duplicates (prevents the wrong artist inheriting big stats).
  Future<Map<String, int>> getArtistListenerCounts(
    List<({String name, String id})> artists,
  ) async {
    final results = <String, int>{};
    if (artists.isEmpty) return results;

    // Detect duplicate names in the current result set.
    final nameCounts = <String, int>{};
    for (final a in artists) {
      final key = a.name.trim().toLowerCase();
      nameCounts[key] = (nameCounts[key] ?? 0) + 1;
    }

    final batches = <List<({String name, String id})>>[];
    for (var i = 0; i < artists.length; i += 5) {
      batches.add(artists.sublist(
        i,
        i + 5 > artists.length ? artists.length : i + 5,
      ));
    }

    for (final batch in batches) {
      final futures = batch.map((a) async {
        final key = a.name.trim().toLowerCase();
        final hasDuplicateName = (nameCounts[key] ?? 0) > 1;

        final info = await getArtistInfo(
          a.name,
          mbid: a.id, // treat `id` as MBID (MusicBrainz artistId)
          allowNameFallback: !hasDuplicateName,
        );

        return (a.id, info?.listeners ?? 0);
      });

      final batchResults = await Future.wait(futures);
      for (final (id, listeners) in batchResults) {
        results[id] = listeners;
      }
    }

    return results;
  }
}

class LastFmAlbumInfo {
  LastFmAlbumInfo({
    required this.name,
    required this.artist,
    required this.listeners,
    required this.playcount,
  });

  final String name;
  final String artist;
  final int listeners;
  final int playcount;
}

class LastFmArtistInfo {
  LastFmArtistInfo({
    required this.name,
    required this.listeners,
    required this.playcount,
  });

  final String name;
  final int listeners;
  final int playcount;
}
