import 'dart:convert';
import 'package:http/http.dart' as http;

class DeezerService {
  static Future<List<DeezerTrack>> getArtistTopTracks(String artistName) async {
    if (artistName.isEmpty) return [];

    try {
      // First search for the artist
      final searchUrl = Uri.parse(
        'https://api.deezer.com/search/artist?q=${Uri.encodeQueryComponent(artistName)}&limit=1',
      );
      final searchResp = await http.get(searchUrl).timeout(const Duration(seconds: 10));
      
      if (searchResp.statusCode != 200) return [];
      
      final searchData = json.decode(searchResp.body) as Map<String, dynamic>;
      final artists = searchData['data'] as List?;
      
      if (artists == null || artists.isEmpty) return [];
      
      final artistId = artists[0]['id'];
      
      // Get top tracks for the artist
      final tracksUrl = Uri.parse('https://api.deezer.com/artist/$artistId/top?limit=5');
      final tracksResp = await http.get(tracksUrl).timeout(const Duration(seconds: 10));
      
      if (tracksResp.statusCode != 200) return [];
      
      final tracksData = json.decode(tracksResp.body) as Map<String, dynamic>;
      final tracks = tracksData['data'] as List?;
      
      if (tracks == null) return [];
      
      return tracks.map((t) => DeezerTrack.fromJson(t as Map<String, dynamic>)).toList();
    } catch (e) {
      return [];
    }
  }
}

class DeezerTrack {
  final String id;
  final String title;
  final int durationSeconds;
  final String? albumCoverUrl;
  final String? albumTitle;
  final String? previewUrl; // 30-second preview MP3

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
      title: json['title'] as String? ?? '',
      durationSeconds: json['duration'] as int? ?? 0,
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