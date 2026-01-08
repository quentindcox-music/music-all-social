import 'dart:convert';
import 'package:http/http.dart' as http;

class FanartService {
  // Replace with your API key
  static const String _apiKey = 'd7605d9249cb427345ca53c4d22f5a60';
  static const String _baseUrl = 'https://webservice.fanart.tv/v3/music';

  /// Fetches artist images from Fanart.tv using MusicBrainz artist ID
  static Future<ArtistImages?> getArtistImages(String mbArtistId) async {
    if (mbArtistId.isEmpty) return null;

    try {
      final url = Uri.parse('$_baseUrl/$mbArtistId?api_key=$_apiKey');
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return ArtistImages.fromJson(data);
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}

class ArtistImages {
  final String? artistThumb;      // Square thumbnail
  final String? artistBackground; // Wide background/banner
  final String? hdLogo;           // HD logo if available
  final List<String> allThumbs;
  final List<String> allBackgrounds;

  ArtistImages({
    this.artistThumb,
    this.artistBackground,
    this.hdLogo,
    this.allThumbs = const [],
    this.allBackgrounds = const [],
  });

  factory ArtistImages.fromJson(Map<String, dynamic> json) {
    // Parse thumbnails
    final thumbList = <String>[];
    if (json['artistthumb'] is List) {
      for (final item in json['artistthumb']) {
        if (item is Map && item['url'] != null) {
          thumbList.add(item['url'] as String);
        }
      }
    }

    // Parse backgrounds
    final bgList = <String>[];
    if (json['artistbackground'] is List) {
      for (final item in json['artistbackground']) {
        if (item is Map && item['url'] != null) {
          bgList.add(item['url'] as String);
        }
      }
    }

    // Parse HD logo
    String? logo;
    if (json['hdmusiclogo'] is List && (json['hdmusiclogo'] as List).isNotEmpty) {
      logo = json['hdmusiclogo'][0]['url'] as String?;
    }

    return ArtistImages(
      artistThumb: thumbList.isNotEmpty ? thumbList.first : null,
      artistBackground: bgList.isNotEmpty ? bgList.first : null,
      hdLogo: logo,
      allThumbs: thumbList,
      allBackgrounds: bgList,
    );
  }

  bool get hasImages => artistThumb != null || artistBackground != null;
}