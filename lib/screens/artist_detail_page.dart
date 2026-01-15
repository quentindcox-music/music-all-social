import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:music_all_app/providers/artist_providers.dart';
import 'package:music_all_app/providers/firebase_providers.dart';
import 'package:music_all_app/services/discography_cache_service.dart';
import 'package:music_all_app/services/musicbrainz_service.dart';
import 'package:music_all_app/services/deezer_service.dart'; // DeezerTrack
import 'package:music_all_app/services/fanart_service.dart'; // ArtistImages

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

  @override
  void initState() {
    super.initState();

    _cache = DiscographyCacheService(ref.read(firestoreProvider));

    // Once the albums provider has a value, trigger background sync if needed.
    _albumsSub = ref.listenManual<AsyncValue<List<Map<String, dynamic>>>>(
      artistAlbumsProvider(widget.artistId),
      (prev, next) {
        final albums = next.valueOrNull;
        if (albums == null) return;
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

  // --- Filtering / Sorting ---
  List<Map<String, dynamic>> _sortByDateDescending(List<Map<String, dynamic>> albums) {
    albums.sort((a, b) {
      final dateA = a['firstReleaseDate'] as String? ?? '0000';
      final dateB = b['firstReleaseDate'] as String? ?? '0000';
      return dateB.compareTo(dateA);
    });
    return albums;
  }

  List<Map<String, dynamic>> _studioAlbums(List<Map<String, dynamic>> all) {
    const excludeTypes = [
      'Live',
      'Compilation',
      'Soundtrack',
      'Spokenword',
      'Interview',
      'DJ-mix',
    ];

    final albums = all.where((r) {
      final type = r['primaryType'] as String?;
      final secondary = r['secondaryTypes'] as List?;
      if (type != 'Album') return false;
      if (secondary == null || secondary.isEmpty) return true;
      return !secondary.any((s) => excludeTypes.contains(s));
    }).toList();

    return _sortByDateDescending(albums);
  }

  List<Map<String, dynamic>> _liveAlbums(List<Map<String, dynamic>> all) {
    final albums = all.where((r) {
      final secondary = r['secondaryTypes'] as List?;
      return secondary != null && secondary.contains('Live');
    }).toList();
    return _sortByDateDescending(albums);
  }

  List<Map<String, dynamic>> _singlesEps(List<Map<String, dynamic>> all) {
    final albums = all.where((r) {
      final type = r['primaryType'] as String?;
      return type == 'Single' || type == 'EP';
    }).toList();
    return _sortByDateDescending(albums);
  }

  List<Map<String, dynamic>> _compilations(List<Map<String, dynamic>> all) {
    final albums = all.where((r) {
      final secondary = r['secondaryTypes'] as List?;
      return secondary != null && secondary.contains('Compilation');
    }).toList();
    return _sortByDateDescending(albums);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final headerAsync = ref.watch(
      artistHeaderProvider((artistId: widget.artistId, artistName: widget.artistName)),
    );

    final albumsAsync = ref.watch(artistAlbumsProvider(widget.artistId));

    final header = headerAsync.valueOrNull;
    final allReleases = albumsAsync.valueOrNull ?? <Map<String, dynamic>>[];

    final showBlockingLoader = headerAsync.isLoading && albumsAsync.isLoading && _syncError == null;

    if (showBlockingLoader) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_syncError != null) {
      return Scaffold(body: Center(child: Text('Error: $_syncError')));
    }

    final artist = header?.artist;
    final images = header?.images;
    final topTracks = header?.topTracks ?? const <DeezerTrack>[];

    final studio = _studioAlbums(allReleases);
    final singles = _singlesEps(allReleases);
    final live = _liveAlbums(allReleases);
    final comps = _compilations(allReleases);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            stretch: true,
            backgroundColor: theme.colorScheme.surface,
            actions: [
              FavoriteArtistButton(
                artistId: widget.artistId,
                artistName: widget.artistName,
                imageUrl: images?.artistThumb ?? images?.artistBackground,
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
              background: _buildHeroImage(theme, images),
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
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ),

          if (topTracks.isNotEmpty)
            SliverToBoxAdapter(child: _buildTopTracksSection(context, topTracks)),

          if (albumsAsync.isLoading && allReleases.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else ...[
            if (studio.isNotEmpty) _buildSection(context, title: 'Albums', releases: studio, maxItems: 6),
            if (singles.isNotEmpty) _buildSection(context, title: 'Singles & EPs', releases: singles, maxItems: 6),
            if (live.isNotEmpty) _buildSection(context, title: 'Live Albums', releases: live, maxItems: 6),
            if (comps.isNotEmpty) _buildSection(context, title: 'Compilations', releases: comps, maxItems: 6),
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

  Widget _buildTopTracksSection(BuildContext context, List<DeezerTrack> topTracks) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Text(
            'Top Songs',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        ...List.generate(topTracks.length, (index) {
          final track = topTracks[index];
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
                      child: track.albumCoverUrl != null
                          ? Image.network(
                              track.albumCoverUrl!,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
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
                          if (track.albumTitle != null)
                            Text(
                              track.albumTitle!,
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
        }),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required List<Map<String, dynamic>> releases,
    required int maxItems,
  }) {
    final theme = Theme.of(context);
    final showSeeAll = releases.length > maxItems;
    final displayItems = releases.take(maxItems).toList();

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
                            releases: releases,
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
                final title = (album['title'] as String?) ?? 'Unknown';
                final year = album['firstReleaseDate'] as String?;
                final coverUrl = (album['coverUrl'] as String?)?.trim();

                return Padding(
                  padding: EdgeInsets.only(right: index < displayItems.length - 1 ? 10 : 0),
                  child: _HorizontalAlbumCard(
                    albumId: albumId,
                    title: title,
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

  Widget _buildHeroImage(ThemeData theme, ArtistImages? images) {
    final bgUrl = images?.artistBackground;
    final thumbUrl = images?.artistThumb;
    final imageUrl = bgUrl ?? thumbUrl;

    if (imageUrl != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
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

    final fallback = 'https://coverartarchive.org/release-group/$albumId/front-250';
    final imageUrl = (coverUrl != null && coverUrl!.isNotEmpty) ? coverUrl! : fallback;

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

/// ✅ Put back in this file so your existing usage compiles.
class FavoriteArtistButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      return IconButton(
        onPressed: null,
        tooltip: 'Sign in to favorite',
        icon: const Icon(Icons.favorite_border, color: Colors.white),
      );
    }

    final favRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('favorites_artists')
        .doc(artistId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: favRef.snapshots(),
      builder: (context, snap) {
        final isFav = snap.data?.exists == true;

        return IconButton(
          tooltip: isFav ? 'Unfavorite' : 'Favorite',
          icon: Icon(isFav ? Icons.favorite : Icons.favorite_border, color: Colors.white),
          onPressed: () async {
            if (isFav) {
              await favRef.delete();
              return;
            }

            await favRef.set({
              'artistId': artistId,
              'name': artistName,
              'imageUrl': (imageUrl ?? '').trim(),
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          },
        );
      },
    );
  }
}

/// ✅ Put back in this file so your existing usage compiles.
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
