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
  });

  /// Release Group MBID
  final String id;

  final String title;

  /// Artist MBID (nullable because MB may not always provide it)
  final String? primaryArtistId;

  final String primaryArtistName;

  /// "1998" or "1998-01-01"
  final String? firstReleaseDate;

  /// "Album", "EP", etc.
  final String? primaryType;
}

class MusicBrainzService {
  MusicBrainzService({
    http.Client? client,
    this.appUserAgent =
        'MusicAllApp/0.1 (contact: quentincoxmusic@gmail.com)',
  }) : _client = client ?? http.Client();

  final http.Client _client;

  /// MusicBrainz asks clients to send a proper User-Agent.
  final String appUserAgent;

  /// Simple search for "album-like" release-groups.
  /// Uses WS/2 search endpoint with fmt=json.
  Future<List<MbReleaseGroup>> searchReleaseGroups(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    // Basic Lucene query; you can get fancier later.
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
      // Often means you’re hitting rate limit.
      throw Exception('MusicBrainz rate limit (503). Try again in a moment.');
    }
    if (resp.statusCode != 200) {
      throw Exception('MusicBrainz error: ${resp.statusCode}');
    }

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = (decoded['release-groups'] as List<dynamic>? ?? []);

    return list.map((raw) {
      final m = raw as Map<String, dynamic>;

      final title = (m['title'] as String?) ?? '';
      final id = (m['id'] as String?) ?? '';

      // artist-credit is an array; take the first credit’s name + id.
      String artistName = '';
      String? artistId;
      final artistCredit = m['artist-credit'];
      if (artistCredit is List && artistCredit.isNotEmpty) {
        final first = artistCredit.first;
        if (first is Map) {
          if (first['name'] is String) {
            artistName = first['name'] as String;
          }
          final artistObj = first['artist'];
          if (artistObj is Map && artistObj['id'] is String) {
            artistId = artistObj['id'] as String;
          }
        }
      }

      return MbReleaseGroup(
        id: id,
        title: title,
        primaryArtistId: artistId,
        primaryArtistName: artistName,
        firstReleaseDate: m['first-release-date'] as String?,
        primaryType: m['primary-type'] as String?,
      );
    }).where((r) => r.id.isNotEmpty && r.title.isNotEmpty).toList();
  }
}
