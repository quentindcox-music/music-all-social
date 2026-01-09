// lib/screens/discover_page.dart

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../widgets/album_thumb.dart';
import '../services/musicbrainz_service.dart';
import '../services/lastfm_service.dart';
import '../services/album_service.dart';
import '../services/fanart_service.dart';
import '../utils/error_handler.dart';
import 'album_detail_page.dart';
import 'artist_detail_page.dart';

enum SearchMode { albums, artists }

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  final _mbService = MusicBrainzService(
    appUserAgent: 'MusicAllApp/0.1 (contact: quentincoxmusic@gmail.com)',
  );

  late final LastFmService _lastFmService;

  final _controller = TextEditingController();
  Timer? _debounce;

  bool _loading = false;
  bool _loadingPopularity = false;
  String? _error;
  SearchMode _searchMode = SearchMode.albums;

  List<MbReleaseGroup> _albumResults = const [];
  List<MbArtistSearchResult> _artistResults = const [];
  Map<String, int> _listenerCounts = {};

  // --------- NEW: memoized artist avatar URLs (Fanart -> Last.fm) ----------
  final Map<String, Future<String?>> _artistAvatarFutureById = {};
  final Map<String, String?> _artistAvatarUrlById = {};

  Future<String?> _getArtistAvatarUrl(MbArtistSearchResult artist) {
    final id = artist.id;

    // resolved already
    if (_artistAvatarUrlById.containsKey(id)) {
      return Future.value(_artistAvatarUrlById[id]);
    }

    // in flight
    final existing = _artistAvatarFutureById[id];
    if (existing != null) return existing;

    final fut = () async {
      // 1) Fanart (best quality)
      try {
        final images = await FanartService.getArtistImages(id);
        final url = (images?.artistThumb ?? images?.artistBackground)?.trim();
        if (url != null && url.isNotEmpty) {
          _artistAvatarUrlById[id] = url;
          return url;
        }
      } catch (_) {
        // ignore and fall back
      }

      // 2) Last.fm (better coverage)
      try {
        final url = (await _lastFmService.getArtistImageUrl(artist.name))?.trim();
        if (url != null && url.isNotEmpty) {
          _artistAvatarUrlById[id] = url;
          return url;
        }
      } catch (_) {
        // ignore and fall back
      }

      // 3) nothing
      _artistAvatarUrlById[id] = null;
      return null;
    }();

    _artistAvatarFutureById[id] = fut;
    return fut;
  }

  void _clearArtistAvatarCacheForNewSearch() {
    _artistAvatarFutureById.clear();
    _artistAvatarUrlById.clear();
  }
  // ----------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _lastFmService = LastFmService(
      apiKey: dotenv.env['LASTFM_API_KEY'] ?? '',
    );
  }

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
        _albumResults = const [];
        _artistResults = const [];
        _listenerCounts = {};
        _error = null;
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _listenerCounts = {};
    });

    try {
      if (_searchMode == SearchMode.albums) {
        final res = await _mbService.searchReleaseGroups(query);
        if (!mounted) return;
        setState(() {
          _albumResults = res;
          _loading = false;
        });

        _fetchAlbumPopularity(res);
      } else {
        _clearArtistAvatarCacheForNewSearch();

        final res = await _mbService.searchArtists(query);
        if (!mounted) return;
        setState(() {
          _artistResults = res;
          _loading = false;
        });

        _fetchArtistPopularity(res);
      }
    } catch (e) {
      if (!mounted) return;

      String message = 'Something went wrong. Please try again.';
      final text = e.toString();
      if (text.contains('HandshakeException') || text.contains('SocketException')) {
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

  Future<void> _fetchAlbumPopularity(List<MbReleaseGroup> albums) async {
    if (albums.isEmpty) return;

    setState(() => _loadingPopularity = true);

    try {
      final albumList = albums
          .map((a) => (artist: a.primaryArtistName, album: a.title, id: a.id))
          .toList();

      final counts = await _lastFmService.getAlbumListenerCounts(albumList);

      if (!mounted) return;
      setState(() {
        _listenerCounts = counts;
        _loadingPopularity = false;

        _albumResults = List.from(_albumResults)
          ..sort((a, b) {
            final aCount = _listenerCounts[a.id] ?? 0;
            final bCount = _listenerCounts[b.id] ?? 0;
            return bCount.compareTo(aCount);
          });
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingPopularity = false);
    }
  }

  Future<void> _fetchArtistPopularity(List<MbArtistSearchResult> artists) async {
    if (artists.isEmpty) return;

    setState(() => _loadingPopularity = true);

    try {
      final artistList = artists.map((a) => (name: a.name, id: a.id)).toList();

      final counts = await _lastFmService.getArtistListenerCounts(artistList);

      if (!mounted) return;
      setState(() {
        _listenerCounts = counts;
        _loadingPopularity = false;

        _artistResults = List.from(_artistResults)
          ..sort((a, b) {
            final aCount = _listenerCounts[a.id] ?? 0;
            final bCount = _listenerCounts[b.id] ?? 0;
            return bCount.compareTo(aCount);
          });
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingPopularity = false);
    }
  }

  void _switchMode(SearchMode mode) {
    if (_searchMode == mode) return;
    setState(() {
      _searchMode = mode;
      _albumResults = const [];
      _artistResults = const [];
      _listenerCounts = {};
    });
    if (_controller.text.trim().isNotEmpty) {
      _search(_controller.text);
    }
  }

  String _formatListeners(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M listeners';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(0)}K listeners';
    } else if (count > 0) {
      return '$count listeners';
    }
    return '';
  }

  Future<void> _onAlbumTap(MbReleaseGroup rg) async {
    if (!mounted) return;

    try {
      ErrorHandler.showLoading(context, message: 'Loading album...');
      await AlbumService.upsertFromMusicBrainz(rg);
      if (!mounted) return;
      ErrorHandler.hideLoading(context);

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

  void _onArtistTap(MbArtistSearchResult artist) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArtistDetailPage(
          artistId: artist.id,
          artistName: artist.name,
        ),
      ),
    );
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
          Container(
            color: theme.colorScheme.surface,
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _controller,
              onChanged: _onQueryChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: _searchMode == SearchMode.albums
                    ? 'Search albums'
                    : 'Search artists',
                hintText: _searchMode == SearchMode.albums
                    ? 'Try "Animals" or "Dark Side of the Moon"'
                    : 'Try "Pink Floyd" or "Radiohead"',
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: _ModeChip(
                    label: 'Albums',
                    icon: Icons.album,
                    selected: _searchMode == SearchMode.albums,
                    onTap: () => _switchMode(SearchMode.albums),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ModeChip(
                    label: 'Artists',
                    icon: Icons.person,
                    selected: _searchMode == SearchMode.artists,
                    onTap: () => _switchMode(SearchMode.artists),
                  ),
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_loadingPopularity && !_loading)
            LinearProgressIndicator(
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
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
          Expanded(
            child: _searchMode == SearchMode.albums
                ? _buildAlbumResults(theme)
                : _buildArtistResults(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumResults(ThemeData theme) {
    if (_albumResults.isEmpty && !_loading) {
      return _buildEmptyState(theme);
    }

    return ListView.separated(
      itemCount: _albumResults.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final r = _albumResults[i];
        final listeners = _listenerCounts[r.id] ?? 0;
        final listenersText = _formatListeners(listeners);

        final subtitleParts = <String>[];
        if ((r.firstReleaseDate ?? '').isNotEmpty) {
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
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                r.primaryArtistName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Row(
                children: [
                  if (subtitleParts.isNotEmpty)
                    Text(
                      subtitleParts.join(' • '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  if (subtitleParts.isNotEmpty && listenersText.isNotEmpty)
                    Text(
                      ' • ',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  if (listenersText.isNotEmpty)
                    Text(
                      listenersText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ],
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _onAlbumTap(r),
        );
      },
    );
  }

  Widget _buildArtistResults(ThemeData theme) {
    if (_artistResults.isEmpty && !_loading) {
      return _buildEmptyState(theme);
    }

    return ListView.separated(
      itemCount: _artistResults.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final artist = _artistResults[i];
        final listeners = _listenerCounts[artist.id] ?? 0;
        final listenersText = _formatListeners(listeners);

        final subtitleParts = <String>[];
        if (artist.type != null && artist.type!.isNotEmpty) {
          subtitleParts.add(artist.type!);
        }
        if (artist.country != null && artist.country!.isNotEmpty) {
          subtitleParts.add(artist.country!);
        }

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: _ArtistAvatar(
            artist: artist,
            theme: theme,
            urlFuture: _getArtistAvatarUrl(artist),
          ),
          title: Text(
            artist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (subtitleParts.isNotEmpty || listenersText.isNotEmpty)
                Row(
                  children: [
                    if (subtitleParts.isNotEmpty)
                      Text(
                        subtitleParts.join(' • '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    if (subtitleParts.isNotEmpty && listenersText.isNotEmpty)
                      Text(
                        ' • ',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    if (listenersText.isNotEmpty)
                      Text(
                        listenersText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              if (artist.disambiguation != null &&
                  artist.disambiguation!.isNotEmpty)
                Text(
                  artist.disambiguation!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _onArtistTap(artist),
        );
      },
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _searchMode == SearchMode.albums ? Icons.album : Icons.person_search,
            size: 64,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            _searchMode == SearchMode.albums
                ? 'Search for an album'
                : 'Search for an artist',
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
}

class _ArtistAvatar extends StatelessWidget {
  const _ArtistAvatar({
    required this.artist,
    required this.theme,
    required this.urlFuture,
  });

  final MbArtistSearchResult artist;
  final ThemeData theme;
  final Future<String?> urlFuture;

  @override
  Widget build(BuildContext context) {
    final initial =
        artist.name.trim().isNotEmpty ? artist.name.trim()[0].toUpperCase() : '?';

    return FutureBuilder<String?>(
      future: urlFuture,
      builder: (context, snap) {
        final url = (snap.data ?? '').trim();

        if (url.isNotEmpty) {
          return CircleAvatar(
            radius: 28,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            backgroundImage: CachedNetworkImageProvider(url),
          );
        }

        if (snap.connectionState == ConnectionState.waiting) {
          return CircleAvatar(
            radius: 28,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary.withValues(alpha: 0.8),
              ),
            ),
          );
        }

        return CircleAvatar(
          radius: 28,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            initial,
            style: TextStyle(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w800,
            ),
          ),
        );
      },
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
