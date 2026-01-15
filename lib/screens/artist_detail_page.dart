import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:music_all_app/providers/artist_providers.dart';
import 'package:music_all_app/providers/favorites_controller.dart';
import 'package:music_all_app/providers/favorites_providers.dart';
import 'package:music_all_app/providers/firebase_providers.dart';
import 'package:music_all_app/services/discography_cache_service.dart';
import 'package:music_all_app/services/musicbrainz_service.dart';
import 'package:music_all_app/services/deezer_service.dart';
import 'package:music_all_app/services/fanart_service.dart';

import 'album_detail_page.dart';

class ArtistDetailPage extends ConsumerStatefulWidget {
  const ArtistDetailPage({
    super.key,
    required this.artistId,
    required this.artistName,
  });

  final String artistId;
  final String artistName;

  @override
  ConsumerState<ArtistDetailPage> createState() => _ArtistDetailPageState();
}

class _ArtistDetailPageState extends ConsumerState<ArtistDetailPage> {
  bool _syncing = false;
  String? _syncError;
  bool _syncTriggered = false;

  late final DiscographyCacheService _cache;
  ProviderSubscription<AsyncValue<List<Map<String, dynamic>>>>? _albumsSub;

  static const double _expandedHeight = 280;

  @override
  void initState() {
    super.initState();

    _cache = DiscographyCacheService(ref.read(firestoreProvider));

    // Once albums provider has real data (not loading/error), trigger background sync if needed.
    _albumsSub = ref.listenManual<AsyncValue<List<Map<String, dynamic>>>>(
      artistAlbumsProvider(widget.artistId),
      (prev, next) {
        if (next.isLoading || next.hasError) return;
        final albums = next.value ?? const <Map<String, dynamic>>[];
        // ignore: discarded_futures
        _maybeRefreshDiscography(albums);
      },
    );
  }

  @override
  void dispose() {
    _albumsSub?.close();
    super.dispose();
  }

  Future<void> _maybeRefreshDiscography(List<Map<String, dynamic>> existingAlbums) async {
    if (_syncTriggered) return;
    _syncTriggered = true;

    try {
      final hasAnyAlbums = existingAlbums.isNotEmpty;

      final shouldSync = !hasAnyAlbums ||
          await _cache.shouldSyncArtist(
            widget.artistId,
            ttl: const Duration(hours: 24),
          );

      if (!shouldSync) return;

      if (mounted) setState(() => _syncing = true);

      final albums = await MusicBrainzService.fetchArtistReleaseGroups(widget.artistId);

      await _cache.upsertArtistAndAlbums(
        artistId: widget.artistId,
        artistName: widget.artistName,
        releaseGroups: albums,
      );
    } catch (e) {
      if (mounted) setState(() => _syncError = e.toString());
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _forceRefreshDiscography() async {
    if (_syncing) return;

    try {
      if (mounted) {
        setState(() {
          _syncing = true;
          _syncError = null;
        });
      }

      final albums = await MusicBrainzService.fetchArtistReleaseGroups(widget.artistId);

      await _cache.upsertArtistAndAlbums(
        artistId: widget.artistId,
        artistName: widget.artistName,
        releaseGroups: albums,
      );
    } catch (e) {
      if (mounted) setState(() => _syncError = e.toString());
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  int _compareReleaseDateDesc(Map<String, dynamic> a, Map<String, dynamic> b) {
    final dateA = (a['firstReleaseDate'] as String?) ?? '0000';
    final dateB = (b['firstReleaseDate'] as String?) ?? '0000';
    return dateB.compareTo(dateA);
  }

  ({
    List<Map<String, dynamic>> studio,
    List<Map<String, dynamic>> singles,
    List<Map<String, dynamic>> live,
    List<Map<String, dynamic>> comps
  }) _categorize(List<Map<String, dynamic>> all) {
    const excludeTypes = {
      'Live',
      'Compilation',
      'Soundtrack',
      'Spokenword',
      'Interview',
      'DJ-mix',
    };

    final studio = <Map<String, dynamic>>[];
    final singles = <Map<String, dynamic>>[];
    final live = <Map<String, dynamic>>[];
    final comps = <Map<String, dynamic>>[];

    for (final r in all) {
      final type = r['primaryType'] as String?;
      final secondaryRaw = r['secondaryTypes'];
      final secondary = (secondaryRaw is List)
          ? secondaryRaw.map((e) => e.toString()).toList()
          : const <String>[];

      final isLive = secondary.contains('Live');
      final isComp = secondary.contains('Compilation');

      if (isLive) live.add(r);
      if (isComp) comps.add(r);

      if (type == 'Single' || type == 'EP') {
        singles.add(r);
        continue;
      }

      if (type == 'Album') {
        final isExcluded = secondary.any(excludeTypes.contains);
        if (!isExcluded) studio.add(r);
      }
    }

    studio.sort(_compareReleaseDateDesc);
    singles.sort(_compareReleaseDateDesc);
    live.sort(_compareReleaseDateDesc);
    comps.sort(_compareReleaseDateDesc);

    return (studio: studio, singles: singles, live: live, comps: comps);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final headerAsync = ref.watch(
      artistHeaderProvider((artistId: widget.artistId, artistName: widget.artistName)),
    );
    final albumsAsync = ref.watch(artistAlbumsProvider(widget.artistId));

    final header = headerAsync.valueOrNull;
    final allReleases = albumsAsync.valueOrNull ?? const <Map<String, dynamic>>[];

    final showBlockingLoader = headerAsync.isLoading && albumsAsync.isLoading && _syncError == null;
    if (showBlockingLoader) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_syncError != null) {
      return Scaffold(body: Center(child: Text('Error: $_syncError')));
    }

    if (albumsAsync.hasError && allReleases.isEmpty) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Could not load discography.', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(artistAlbumsProvider(widget.artistId)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final artist = header?.artist;
    final images = header?.images;
    final topTracks = header?.topTracks ?? const <DeezerTrack>[];

    // ✅ NEW: best effort image (Fanart -> Last.fm -> Deezer)
    final bestImageUrl = (header?.bestImageUrl ?? '').trim();
    final listeners = header?.lastFmListeners ?? 0;
    final listenersText = _formatListeners(listeners);

    final sections = _categorize(List<Map<String, dynamic>>.unmodifiable(allReleases));

    // Image decode cache sizing (px, not dp)
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final heroCacheW = (size.width * dpr).round().clamp(200, 4096);
    final heroCacheH = (_expandedHeight * dpr).round().clamp(200, 4096);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: _expandedHeight,
            pinned: true,
            stretch: true,
            backgroundColor: theme.colorScheme.surface,
            actions: [
              FavoriteArtistButton(
                artistId: widget.artistId,
                artistName: widget.artistName,
                // ✅ Store best image (not just Fanart)
                imageUrl: bestImageUrl.isNotEmpty
                    ? bestImageUrl
                    : (images?.artistThumb ?? images?.artistBackground),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                widget.artistName,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  shadows: [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.7),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
              background: _buildHeroImage(
                theme: theme,
                images: images,
                bestImageUrl: bestImageUrl,
                memCacheWidth: heroCacheW,
                memCacheHeight: heroCacheH,
              ),
            ),
          ),

          if (_syncing)
            const SliverToBoxAdapter(
              child: LinearProgressIndicator(minHeight: 2),
            ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: artist != null
                  ? Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (artist.type != null) _InfoChip(Icons.person_outline, artist.type!),
                        if (artist.country != null) _InfoChip(Icons.location_on_outlined, artist.country!),
                        if (artist.beginArea != null) _InfoChip(Icons.home_outlined, artist.beginArea!),
                        if (artist.lifeSpan != null) _InfoChip(Icons.calendar_today_outlined, artist.lifeSpan!),
                        // ✅ NEW: show listeners when available (helps disambiguate duplicates)
                        if (listenersText.isNotEmpty) _InfoChip(Icons.headphones, listenersText),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ),

          // ✅ Lazy top-tracks rendering (SliverList instead of Column)
          if (topTracks.isNotEmpty) ..._buildTopTracksSlivers(context, topTracks),

          if (albumsAsync.isLoading && allReleases.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else ...[
            if (sections.studio.isNotEmpty)
              _buildSection(context, title: 'Albums', releases: sections.studio, maxItems: 6),
            if (sections.singles.isNotEmpty)
              _buildSection(context, title: 'Singles & EPs', releases: sections.singles, maxItems: 6),
            if (sections.live.isNotEmpty)
              _buildSection(context, title: 'Live Albums', releases: sections.live, maxItems: 6),
            if (sections.comps.isNotEmpty)
              _buildSection(context, title: 'Compilations', releases: sections.comps, maxItems: 6),
            if (allReleases.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Text('No discography cached yet.', style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _syncing ? null : _forceRefreshDiscography,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Fetch Discography'),
                      ),
                    ],
                  ),
                ),
              ),
          ],

          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  List<Widget> _buildTopTracksSlivers(BuildContext context, List<DeezerTrack> topTracks) {
    final theme = Theme.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final artPx = (48 * dpr).round().clamp(48, 512);

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Text(
            'Top Songs',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
      ),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final track = topTracks[index];
            final cover = track.albumCoverUrl?.trim();
            final hasCover = cover != null && cover.isNotEmpty;

            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {},
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text(
                          '${index + 1}',
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                        ),
                      ),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: hasCover
                            ? CachedNetworkImage(
                                imageUrl: cover,
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                                memCacheWidth: artPx,
                                memCacheHeight: artPx,
                                placeholder: (_, _) => Container(
                                  width: 48,
                                  height: 48,
                                  color: Colors.grey[800],
                                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                ),
                                errorWidget: (_, _, _) => Container(
                                  width: 48,
                                  height: 48,
                                  color: Colors.grey[800],
                                  child: const Icon(Icons.music_note, size: 24),
                                ),
                              )
                            : Container(
                                width: 48,
                                height: 48,
                                color: Colors.grey[800],
                                child: const Icon(Icons.music_note, size: 24),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title,
                              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if ((track.albumTitle ?? '').trim().isNotEmpty)
                              Text(
                                track.albumTitle!.trim(),
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      Text(
                        track.formattedDuration,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
          childCount: topTracks.length,
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 8)),
    ];
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required List<Map<String, dynamic>> releases,
    required int maxItems,
  }) {
    final theme = Theme.of(context);
    final showSeeAll = releases.length > maxItems;
    final displayItems = releases.take(maxItems).toList(growable: false);

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (showSeeAll)
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ArtistDiscographyPage(
                            artistName: widget.artistName,
                            sectionTitle: title,
                            releases: List<Map<String, dynamic>>.unmodifiable(releases),
                          ),
                        ),
                      );
                    },
                    child: Row(
                      children: [
                        Text(
                          'See All',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.primary),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 160,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: displayItems.length,
              itemBuilder: (context, index) {
                final album = displayItems[index];

                final albumId = (album['id'] as String?) ?? '';
                final albumTitle = (album['title'] as String?) ?? 'Unknown';
                final year = album['firstReleaseDate'] as String?;
                final coverUrl = (album['coverUrl'] as String?)?.trim();

                return Padding(
                  padding: EdgeInsets.only(right: index < displayItems.length - 1 ? 10 : 0),
                  child: _HorizontalAlbumCard(
                    albumId: albumId,
                    title: albumTitle,
                    year: year,
                    coverUrl: coverUrl,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroImage({
    required ThemeData theme,
    required ArtistImages? images,
    required String bestImageUrl,
    required int memCacheWidth,
    required int memCacheHeight,
  }) {
    // ✅ Prefer provider's bestImageUrl (Fanart -> Last.fm -> Deezer)
    final preferred = bestImageUrl.trim();
    // Fallback to any Fanart fields if provider didn't resolve one
    final bgUrl = images?.artistBackground?.trim() ?? '';
    final thumbUrl = images?.artistThumb?.trim() ?? '';

    final imageUrl = preferred.isNotEmpty
        ? preferred
        : (bgUrl.isNotEmpty ? bgUrl : (thumbUrl.isNotEmpty ? thumbUrl : ''));

    if (imageUrl.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            memCacheWidth: memCacheWidth,
            memCacheHeight: memCacheHeight,
            placeholder: (_, _) => Container(color: theme.colorScheme.primaryContainer),
            errorWidget: (_, _, _) => _buildPlaceholder(theme),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)],
              ),
            ),
          ),
        ],
      );
    }

    return _buildPlaceholder(theme);
  }

  Widget _buildPlaceholder(ThemeData theme) {
    final initial = widget.artistName.isNotEmpty ? widget.artistName[0].toUpperCase() : '?';
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: theme.textTheme.displayLarge?.copyWith(
            color: Colors.white.withValues(alpha: 0.5),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _HorizontalAlbumCard extends StatelessWidget {
  const _HorizontalAlbumCard({
    required this.albumId,
    required this.title,
    this.year,
    this.coverUrl,
  });

  final String albumId;
  final String title;
  final String? year;
  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final dpr = MediaQuery.devicePixelRatioOf(context);
    final px = (100 * dpr).round().clamp(100, 512);

    final fallback = 'https://coverartarchive.org/release-group/$albumId/front-250';
    final imageUrl = (coverUrl != null && coverUrl!.trim().isNotEmpty) ? coverUrl!.trim() : fallback;

    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => AlbumDetailPage(albumId: albumId)));
      },
      child: SizedBox(
        width: 100,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                width: 100,
                height: 100,
                fit: BoxFit.cover,
                memCacheWidth: px,
                memCacheHeight: px,
                placeholder: (_, _) => Container(
                  width: 100,
                  height: 100,
                  color: Colors.grey[800],
                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                errorWidget: (_, _, _) => Container(
                  width: 100,
                  height: 100,
                  color: Colors.grey[800],
                  child: const Icon(Icons.album, color: Colors.grey, size: 32),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (year != null)
              Text(
                year!.split('-').first,
                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onPrimaryContainer),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: theme.colorScheme.onPrimaryContainer)),
        ],
      ),
    );
  }
}

/// ✅ Riverpod favorite button (no StreamBuilder, no FirebaseAuth usage)
class FavoriteArtistButton extends ConsumerWidget {
  const FavoriteArtistButton({
    super.key,
    required this.artistId,
    required this.artistName,
    this.imageUrl,
  });

  final String artistId;
  final String artistName;
  final String? imageUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(uidProvider);
    if (uid.isEmpty) {
      return IconButton(
        onPressed: null,
        tooltip: 'Sign in to favorite',
        icon: const Icon(Icons.favorite_border, color: Colors.white),
      );
    }

    final isFav = ref.watch(isFavoriteArtistProvider(artistId));
    final busy = ref.watch(favoriteArtistBusyProvider(artistId));

    return IconButton(
      tooltip: isFav ? 'Unfavorite' : 'Favorite',
      onPressed: busy
          ? null
          : () async {
              try {
                await ref.read(favoriteArtistControllerProvider(artistId).notifier).toggle(
                      isCurrentlyFav: isFav,
                      payload: FavoriteArtistPayload(
                        artistId: artistId,
                        artistName: artistName,
                        imageUrl: (imageUrl ?? '').trim(),
                      ),
                    );

                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(isFav ? 'Removed from favorites' : 'Added to favorites')),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Favorite failed: $e')),
                );
              }
            },
      icon: Stack(
        alignment: Alignment.center,
        children: [
          Icon(isFav ? Icons.favorite : Icons.favorite_border, color: Colors.white),
          if (busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }
}

class ArtistDiscographyPage extends StatelessWidget {
  const ArtistDiscographyPage({
    super.key,
    required this.artistName,
    required this.sectionTitle,
    required this.releases,
  });

  final String artistName;
  final String sectionTitle;
  final List<Map<String, dynamic>> releases;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final px = (200 * dpr).round().clamp(200, 768);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(sectionTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(artistName, style: TextStyle(fontSize: 12, color: theme.colorScheme.outline)),
          ],
        ),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.7,
        ),
        itemCount: releases.length,
        itemBuilder: (context, index) {
          final album = releases[index];
          final id = (album['id'] as String?) ?? '';
          final title = (album['title'] as String?) ?? 'Unknown';
          final year = album['firstReleaseDate'] as String?;

          final fallback = 'https://coverartarchive.org/release-group/$id/front-250';
          final coverUrl = ((album['coverUrl'] as String?)?.trim().isNotEmpty == true)
              ? (album['coverUrl'] as String).trim()
              : fallback;

          return GestureDetector(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => AlbumDetailPage(albumId: id)));
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: CachedNetworkImage(
                      imageUrl: coverUrl,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      memCacheWidth: px,
                      placeholder: (_, _) => Container(color: Colors.grey[800]),
                      errorWidget: (_, _, _) => Container(
                        color: Colors.grey[800],
                        child: const Icon(Icons.album, color: Colors.grey),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (year != null)
                  Text(
                    year.split('-').first,
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
