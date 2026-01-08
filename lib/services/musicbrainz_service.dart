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

  final String id;
  final String title;
  final String? primaryArtistId;
  final String primaryArtistName;
  final String? firstReleaseDate;
  final String? primaryType;
}

/// Artist details from MusicBrainz
class MbArtist {
  MbArtist({
    required this.id,
    required this.name,
    this.type,
    this.country,
    this.beginArea,
    this.beginDate,
    this.endDate,
  });

  final String id;
  final String name;
  final String? type;
  final String? country;
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

  Future<List<MbReleaseGroup>> searchReleaseGroups(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];

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
    final list = (decoded['release-groups'] as List<dynamic>? ?? []);

    return list.map((raw) {
      final m = raw as Map<String, dynamic>;
      final title = (m['title'] as String?) ?? '';
      final id = (m['id'] as String?) ?? '';

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

  /// Fetch artist details by MBID
  static Future<MbArtist?> fetchArtistDetails(String artistId) async {
    if (artistId.isEmpty) return null;

    final url = Uri.parse(
      'https://musicbrainz.org/ws/2/artist/$artistId?fmt=json',
    );

    final resp = await http.get(url, headers: {
      'User-Agent': 'MusicAllApp/0.1 (contact: quentincoxmusic@gmail.com)',
      'Accept': 'application/json',
    });

    if (resp.statusCode != 200) return null;

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final lifeSpan = data['life-span'] as Map<String, dynamic>?;
    final beginArea = data['begin-area'] as Map<String, dynamic>?;

    return MbArtist(
      id: data['id'] as String,
      name: data['name'] as String? ?? '',
      type: data['type'] as String?,
      country: data['country'] as String?,
      beginArea: beginArea?['name'] as String?,
      beginDate: lifeSpan?['begin'] as String?,
      endDate: lifeSpan?['end'] as String?,
    );
  }

  /// Fetch artist's release groups (discography)
  static Future<List<Map<String, dynamic>>> fetchArtistReleaseGroups(String artistId) async {
    if (artistId.isEmpty) return [];

    final url = Uri.parse(
      'https://musicbrainz.org/ws/2/release-group?artist=$artistId&type=album|ep|single&fmt=json&limit=100',
    );

    final resp = await http.get(url, headers: {
      'User-Agent': 'MusicAllApp/0.1 (contact: quentincoxmusic@gmail.com)',
      'Accept': 'application/json',
    });

    if (resp.statusCode != 200) return [];

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final groups = data['release-groups'] as List<dynamic>? ?? [];

    return groups.map((g) {
      final m = g as Map<String, dynamic>;
      return {
        'id': m['id'] as String? ?? '',
        'title': m['title'] as String? ?? '',
        'primaryType': m['primary-type'] as String?,
        'firstReleaseDate': m['first-release-date'] as String?,
      };
    }).where((m) => (m['id'] as String).isNotEmpty).toList();
  }
}