import 'dart:convert';
import 'package:http/http.dart' as http;

class LastFmService {
  LastFmService({required this.apiKey});

  final String apiKey;
  static const _baseUrl = 'https://ws.audioscrobbler.com/2.0/';

  /// Get album info with listener count
  Future<LastFmAlbumInfo?> getAlbumInfo(String artist, String album) async {
    try {
      final url = Uri.parse(
        '$_baseUrl?method=album.getinfo&api_key=$apiKey'
        '&artist=${Uri.encodeComponent(artist)}'
        '&album=${Uri.encodeComponent(album)}&format=json',
      );

      final resp = await http.get(url).timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final albumData = data['album'] as Map<String, dynamic>?;
      if (albumData == null) return null;

      return LastFmAlbumInfo(
        name: albumData['name'] as String? ?? '',
        artist: albumData['artist'] as String? ?? '',
        listeners: int.tryParse(albumData['listeners']?.toString() ?? '') ?? 0,
        playcount: int.tryParse(albumData['playcount']?.toString() ?? '') ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// Get artist info with listener count
  Future<LastFmArtistInfo?> getArtistInfo(String artist) async {
    try {
      final url = Uri.parse(
        '$_baseUrl?method=artist.getinfo&api_key=$apiKey'
        '&artist=${Uri.encodeComponent(artist)}&format=json',
      );

      final resp = await http.get(url).timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final artistData = data['artist'] as Map<String, dynamic>?;
      if (artistData == null) return null;

      final stats = artistData['stats'] as Map<String, dynamic>?;

      return LastFmArtistInfo(
        name: artistData['name'] as String? ?? '',
        listeners: int.tryParse(stats?['listeners']?.toString() ?? '') ?? 0,
        playcount: int.tryParse(stats?['playcount']?.toString() ?? '') ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// NEW: Get best available artist image URL (Last.fm)
  /// Returns the largest image available (typically "extralarge" or "mega").
  Future<String?> getArtistImageUrl(String artist) async {
    try {
      final url = Uri.parse(
        '$_baseUrl?method=artist.getinfo&api_key=$apiKey'
        '&artist=${Uri.encodeComponent(artist)}&format=json',
      );

      final resp = await http.get(url).timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final artistData = data['artist'] as Map<String, dynamic>?;
      if (artistData == null) return null;

      final images = artistData['image'];
      if (images is! List) return null;

      // Prefer biggest first
      const preferred = ['mega', 'extralarge', 'large', 'medium', 'small'];

      String? pickForSize(String size) {
        for (final img in images) {
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
      for (final img in images) {
        if (img is Map) {
          final u = img['#text']?.toString().trim() ?? '';
          if (u.isNotEmpty) return u;
        }
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  /// Batch fetch popularity for multiple albums (for sorting search results)
  Future<Map<String, int>> getAlbumListenerCounts(
    List<({String artist, String album, String id})> albums,
  ) async {
    final results = <String, int>{};

    // Fetch in parallel, max 5 at a time to avoid rate limits
    final batches = <List<({String artist, String album, String id})>>[];
    for (var i = 0; i < albums.length; i += 5) {
      batches.add(albums.sublist(
          i, i + 5 > albums.length ? albums.length : i + 5));
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

  /// Batch fetch popularity for multiple artists
  Future<Map<String, int>> getArtistListenerCounts(
    List<({String name, String id})> artists,
  ) async {
    final results = <String, int>{};

    final batches = <List<({String name, String id})>>[];
    for (var i = 0; i < artists.length; i += 5) {
      batches.add(artists.sublist(
          i, i + 5 > artists.length ? artists.length : i + 5));
    }

    for (final batch in batches) {
      final futures = batch.map((a) async {
        final info = await getArtistInfo(a.name);
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
