import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:music_all_app/services/musicbrainz_service.dart';
import 'package:music_all_app/services/fanart_service.dart';
import 'package:music_all_app/services/deezer_service.dart';
import 'album_detail_page.dart';
import 'package:firebase_auth/firebase_auth.dart';


/// ------------------------------
/// Firestore Discography Cache
/// ------------------------------
class DiscographyCacheService {
  DiscographyCacheService(this._db);

  final FirebaseFirestore _db;

  /// Returns true if we should sync (never synced OR older than ttl)
  Future<bool> shouldSyncArtist(
    String artistId, {
    Duration ttl = const Duration(hours: 24),
  }) async {
    final ref = _db.collection('artists').doc(artistId);
    final snap = await ref.get();
    final ts = snap.data()?['lastDiscographySyncAt'] as Timestamp?;
    if (ts == null) return true;

    final last = ts.toDate();
    return DateTime.now().difference(last) > ttl;
  }

  /// Upserts:
  /// - artists/{artistId}
  /// - albums/{releaseGroupId}
  ///
  /// NOTE: Firestore batches max 500 writes; we chunk.
  Future<void> upsertArtistAndAlbums({
    required String artistId,
    required String artistName,
    required List<Map<String, dynamic>> releaseGroups,
  }) async {
    final artistRef = _db.collection('artists').doc(artistId);
    await artistRef.set({
      'id': artistId,
      'name': artistName,
      'source': 'musicbrainz',
      'lastDiscographySyncAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    WriteBatch batch = _db.batch();
    int opCount = 0;

    Future<void> commitIfNeeded({bool force = false}) async {
      if (opCount == 0) return;
      if (force || opCount >= 450) {
        await batch.commit();
        batch = _db.batch();
        opCount = 0;
      }
    }

    for (final rg in releaseGroups) {
      final id = rg['id'] as String?;
      if (id == null || id.isEmpty) continue;

      final albumRef = _db.collection('albums').doc(id);

      final data = <String, dynamic>{
        'id': id,
        'title': (rg['title'] as String?) ?? 'Unknown',
        'firstReleaseDate': rg['firstReleaseDate'], // "YYYY", "YYYY-MM", or "YYYY-MM-DD"
        'primaryArtistId': artistId, // IMPORTANT: keep this exact casing everywhere
        'primaryArtistName': artistName,
        'primaryType': rg['primaryType'],
        'secondaryTypes': (rg['secondaryTypes'] as List?) ?? <String>[],
        'source': 'musicbrainz',
        'coverUrl': 'https://coverartarchive.org/release-group/$id/front-250',
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      };

      batch.set(albumRef, data, SetOptions(merge: true));
      opCount++;

      await commitIfNeeded();
    }

    await commitIfNeeded(force: true);
  }
}

class ArtistDetailPage extends StatefulWidget {
  const ArtistDetailPage({
    super.key,
    required this.artistId,
    required this.artistName,
  });

  final String artistId;
  final String artistName;

  @override
  State<ArtistDetailPage> createState() => _ArtistDetailPageState();
}

class _ArtistDetailPageState extends State<ArtistDetailPage> {
  MbArtist? _artist;
  ArtistImages? _artistImages;
  List<Map<String, dynamic>> _allReleases = [];
  List<DeezerTrack> _topTracks = [];

  bool _loadingHeader = true; // artist + images + top tracks
  bool _loadingAlbums = true; // firestore snapshot
  bool _syncing = false;

  String? _error;

  late final DiscographyCacheService _cache =
      DiscographyCacheService(FirebaseFirestore.instance);

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _albumsSub;

  @override
  void initState() {
    super.initState();
    _startAlbumsListener();
    _loadHeader();
    _refreshDiscographyIfNeeded(); // background
  }

  @override
  void dispose() {
    _albumsSub?.cancel();
    super.dispose();
  }

  /// Firestore-first: keep the UI always reflecting what’s stored in Firestore.
  void _startAlbumsListener() {
    final query = FirebaseFirestore.instance
        .collection('albums')
        .where('primaryArtistId', isEqualTo: widget.artistId)
        .orderBy('firstReleaseDate', descending: true);

    _albumsSub = query.snapshots().listen(
      (snap) {
        final releases = snap.docs.map((d) {
          final data = d.data();
          data['id'] ??= d.id;
          // Normalize secondaryTypes to List<String>
          final sec = data['secondaryTypes'];
          if (sec is! List) data['secondaryTypes'] = <String>[];
          return Map<String, dynamic>.from(data);
        }).toList();

        if (!mounted) return;
        setState(() {
          _allReleases = releases;
          _loadingAlbums = false;
        });
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _error = e.toString();
          _loadingAlbums = false;
        });
      },
    );
  }

  /// Network header bits (artist meta + images + top tracks)
  Future<void> _loadHeader() async {
    setState(() {
      _loadingHeader = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        MusicBrainzService.fetchArtistDetails(widget.artistId),
        FanartService.getArtistImages(widget.artistId),
        DeezerService.getArtistTopTracks(widget.artistName),
      ]);

      final artist = results[0] as MbArtist?;
      final images = results[1] as ArtistImages?;
      final topTracks = results[2] as List<DeezerTrack>;

      if (!mounted) return;
      setState(() {
        _artist = artist;
        _artistImages = images;
        _topTracks = topTracks;
        _loadingHeader = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingHeader = false;
      });
    }
  }

Future<void> _refreshDiscographyIfNeeded() async {
  try {
    final existing = await FirebaseFirestore.instance
        .collection('albums')
        .where('primaryArtistId', isEqualTo: widget.artistId)
        .limit(1)
        .get();

    final hasAnyAlbums = existing.docs.isNotEmpty;

    final shouldSync = !hasAnyAlbums ||
        await _cache.shouldSyncArtist(
          widget.artistId,
          ttl: const Duration(hours: 24),
        );

    if (!shouldSync) return;

    if (mounted) {
      setState(() => _syncing = true);
    }

    final albums =
        await MusicBrainzService.fetchArtistReleaseGroups(widget.artistId);

    await _cache.upsertArtistAndAlbums(
      artistId: widget.artistId,
      artistName: widget.artistName,
      releaseGroups: albums,
    );
  } catch (e) {
    if (mounted) {
      setState(() => _error = e.toString());
    }
  } finally {
    if (mounted) {
      setState(() => _syncing = false);
    }
  }
}


  // --- Filtering / Sorting (unchanged) ---
  List<Map<String, dynamic>> _sortByDateDescending(List<Map<String, dynamic>> albums) {
    albums.sort((a, b) {
      final dateA = a['firstReleaseDate'] as String? ?? '0000';
      final dateB = b['firstReleaseDate'] as String? ?? '0000';
      return dateB.compareTo(dateA);
    });
    return albums;
  }

  List<Map<String, dynamic>> get _studioAlbums {
    final albums = _allReleases.where((r) {
      final type = r['primaryType'] as String?;
      final secondary = r['secondaryTypes'] as List?;
      if (type != 'Album') return false;
      if (secondary == null || secondary.isEmpty) return true;
      final excludeTypes = ['Live', 'Compilation', 'Soundtrack', 'Spokenword', 'Interview', 'DJ-mix'];
      return !secondary.any((s) => excludeTypes.contains(s));
    }).toList();
    return _sortByDateDescending(albums);
  }

  List<Map<String, dynamic>> get _liveAlbums {
    final albums = _allReleases.where((r) {
      final secondary = r['secondaryTypes'] as List?;
      return secondary != null && secondary.contains('Live');
    }).toList();
    return _sortByDateDescending(albums);
  }

  List<Map<String, dynamic>> get _singlesEps {
    final albums = _allReleases.where((r) {
      final type = r['primaryType'] as String?;
      return type == 'Single' || type == 'EP';
    }).toList();
    return _sortByDateDescending(albums);
  }

  List<Map<String, dynamic>> get _compilations {
    final albums = _allReleases.where((r) {
      final secondary = r['secondaryTypes'] as List?;
      return secondary != null && secondary.contains('Compilation');
    }).toList();
    return _sortByDateDescending(albums);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final showBlockingLoader = _loadingHeader && _loadingAlbums && _error == null;

    return Scaffold(
      body: showBlockingLoader
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : CustomScrollView(
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
      imageUrl: _artistImages?.artistThumb ?? _artistImages?.artistBackground,
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
    background: _buildHeroImage(theme),
  ),
),


                    // Optional sync indicator
                    if (_syncing)
                      const SliverToBoxAdapter(
                        child: LinearProgressIndicator(minHeight: 2),
                      ),

                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: _artist != null
                            ? Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (_artist!.type != null)
                                    _InfoChip(Icons.person_outline, _artist!.type!),
                                  if (_artist!.country != null)
                                    _InfoChip(Icons.location_on_outlined, _artist!.country!),
                                  if (_artist!.beginArea != null)
                                    _InfoChip(Icons.home_outlined, _artist!.beginArea!),
                                  if (_artist!.lifeSpan != null)
                                    _InfoChip(Icons.calendar_today_outlined, _artist!.lifeSpan!),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),

                    if (_topTracks.isNotEmpty)
                      SliverToBoxAdapter(child: _buildTopTracksSection(context)),

                    // Discography (from Firestore cache)
                    if (_loadingAlbums && _allReleases.isEmpty)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      )
                    else ...[
                      if (_studioAlbums.isNotEmpty)
                        _buildSection(context, title: 'Albums', releases: _studioAlbums, maxItems: 6),
                      if (_singlesEps.isNotEmpty)
                        _buildSection(context, title: 'Singles & EPs', releases: _singlesEps, maxItems: 6),
                      if (_liveAlbums.isNotEmpty)
                        _buildSection(context, title: 'Live Albums', releases: _liveAlbums, maxItems: 6),
                      if (_compilations.isNotEmpty)
                        _buildSection(context, title: 'Compilations', releases: _compilations, maxItems: 6),
                      if (_allReleases.isEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                Text(
                                  'No discography cached yet.',
                                  style: theme.textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  onPressed: _syncing ? null : _refreshDiscographyIfNeeded,
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

  // ---- UI widgets unchanged from your version ----

  Widget _buildTopTracksSection(BuildContext context) {
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
        ...List.generate(_topTracks.length, (index) {
          final track = _topTracks[index];
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
                return Padding(
                  padding: EdgeInsets.only(right: index < displayItems.length - 1 ? 10 : 0),
                  child: _HorizontalAlbumCard(
                    albumId: album['id'] as String,
                    title: album['title'] as String? ?? 'Unknown',
                    year: album['firstReleaseDate'] as String?,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroImage(ThemeData theme) {
    final bgUrl = _artistImages?.artistBackground;
    final thumbUrl = _artistImages?.artistThumb;
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
  });

  final String albumId;
  final String title;
  final String? year;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coverUrl = 'https://coverartarchive.org/release-group/$albumId/front-250';

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
                imageUrl: coverUrl,
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
          icon: Icon(
            isFav ? Icons.favorite : Icons.favorite_border,
            color: Colors.white,
          ),
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
          final id = album['id'] as String;
          final title = album['title'] as String? ?? 'Unknown';
          final year = album['firstReleaseDate'] as String?;
          final coverUrl = 'https://coverartarchive.org/release-group/$id/front-250';

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
