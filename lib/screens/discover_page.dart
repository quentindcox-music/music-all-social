import 'dart:async';

import 'package:flutter/material.dart';
import '../widgets/album_thumb.dart';
import '../services/musicbrainz_service.dart';
import '../services/album_service.dart';
import 'album_detail_page.dart';

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  final _service = MusicBrainzService(
    appUserAgent: 'MusicAllApp/0.1 (contact: quentincoxmusic@gmail.com)',
  );

  final _controller = TextEditingController();
  Timer? _debounce;

  bool _loading = false;
  String? _error;
  List<MbReleaseGroup> _results = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      _search(value);
    });
  }

  Future<void> _search(String q) async {
    final query = q.trim();
    if (query.isEmpty) {
      setState(() {
        _results = const [];
        _error = null;
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await _service.searchReleaseGroups(query);

      if (!mounted) return;
      setState(() {
        _results = res;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      String message = 'Something went wrong. Please try again.';
      final text = e.toString();
      if (text.contains('HandshakeException')) {
        message =
            'Check your internet '
            'connection and try again.';
      }

      setState(() {
        _error = message;
        _loading = false;
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Discover')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _controller,
              onChanged: _onQueryChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: 'Search albums / artists',
                border: const OutlineInputBorder(),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _controller.clear();
                          _search('');
                          setState(() {});
                        },
                        icon: const Icon(Icons.clear),
                      ),
              ),
            ),
          ),

          if (_loading) const LinearProgressIndicator(),

          if (_error != null)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                _error!,
                style:
                    TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),

          Expanded(
            child: _results.isEmpty
                ? const Center(
                    child: Text('Search for an album or artist.'),
                  )
                : ListView.separated(
                    itemCount: _results.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 0),
 itemBuilder: (context, i) {
  final r = _results[i];
  final subtitleParts = <String>[];

  if ((r.firstReleaseDate ?? '').isNotEmpty) {
    subtitleParts.add(r.firstReleaseDate!);
  }
  if ((r.primaryType ?? '').isNotEmpty) {
    subtitleParts.add(r.primaryType!);
  }

  return ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),

    // 🔹 album thumbnail
    leading: AlbumThumb(
      releaseId: r.id,
    ),

    title: Text(r.title),

    subtitle: Text(
      [
        r.primaryArtistName,
        if (subtitleParts.isNotEmpty)
          '• ${subtitleParts.join(' • ')}',
      ].join(' '),
    ),

    trailing: const Icon(Icons.chevron_right),

    onTap: () async {
      try {
        // show loading spinner while creating album entry
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const Center(
            child: CircularProgressIndicator(),
          ),
        );

        // create / update Firestore album data
        await AlbumService.upsertFromMusicBrainz(r);

        // close spinner
        if (context.mounted) Navigator.of(context).pop();

        // navigate to the album detail page
        if (!context.mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AlbumDetailPage(albumId: r.id),
          ),
        );
      } catch (e) {
        if (context.mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not create album: $e')),
          );
        }
      }
    },
  );
},
                  ),
          ),
        ],
      ),
    );
  }
} 