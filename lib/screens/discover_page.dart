// lib/screens/discover_page.dart

import 'dart:async';

import 'package:flutter/material.dart';
import '../widgets/album_thumb.dart';
import '../services/musicbrainz_service.dart';
import '../services/album_service.dart';
import '../utils/error_handler.dart';
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
      if (text.contains('HandshakeException') || 
          text.contains('SocketException')) {
        message = 'Check your internet connection and try again.';
      } else if (text.contains('TimeoutException')) {
        message = 'Request timed out. Please try again.';
      }

      setState(() {
        _error = message;
        _loading = false;
      });
    }
  }

  Future<void> _onAlbumTap(MbReleaseGroup rg) async {
    if (!mounted) return;

    try {
      // Show loading
      ErrorHandler.showLoading(context, message: 'Loading album...');

      // Create / update Firestore album data
      await AlbumService.upsertFromMusicBrainz(rg);

      // Hide loading
      if (!mounted) return;
      ErrorHandler.hideLoading(context);

      // Navigate to the album detail page
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AlbumDetailPage(albumId: rg.id),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ErrorHandler.hideLoading(context);
      ErrorHandler.handle(
        context,
        e,
        customMessage: 'Could not load album. Please try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            color: theme.colorScheme.surface,
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _controller,
              onChanged: _onQueryChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: 'Search albums or artists',
                hintText: 'Try "Pink Floyd" or "Wish You Were Here"',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.search),
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

          // Loading indicator
          if (_loading) const LinearProgressIndicator(),

          // Error message
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: theme.colorScheme.errorContainer,
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Results
          Expanded(
            child: _buildResultsList(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList(ThemeData theme) {
    if (_results.isEmpty && !_loading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 64,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Search for an album or artist',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Discover new music and rate your favorites',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final r = _results[i];
        final subtitleParts = <String>[];

        if ((r.firstReleaseDate ?? '').isNotEmpty) {
          // Extract year from date
          final year = r.firstReleaseDate!.split('-').first;
          subtitleParts.add(year);
        }
        if ((r.primaryType ?? '').isNotEmpty) {
          subtitleParts.add(r.primaryType!);
        }

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: AlbumThumb(
            releaseId: r.id,
            size: 56,
          ),
          title: Text(
            r.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            [
              r.primaryArtistName,
              if (subtitleParts.isNotEmpty) subtitleParts.join(' • '),
            ].join('\n'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _onAlbumTap(r),
        );
      },
    );
  }
}