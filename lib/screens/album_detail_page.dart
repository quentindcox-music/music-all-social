// lib/screens/album_detail_page.dart

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';

import '../providers/album_providers.dart';
import '../providers/favorites_controller.dart';
import '../providers/favorites_providers.dart';
import '../providers/firebase_providers.dart';
import '../providers/review_providers.dart';
import '../providers/user_profile_providers.dart';
import '../services/musicbrainz_service.dart';
import '../services/recently_viewed_service.dart';
import 'artist_detail_page.dart';
import 'review_editor_page.dart';

class AlbumDetailPage extends ConsumerStatefulWidget {
  const AlbumDetailPage({super.key, required this.albumId});

  /// This is a MusicBrainz *release-group* id (same as your album doc id in Firestore).
  final String albumId;

  @override
  ConsumerState<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends ConsumerState<AlbumDetailPage> {
  // -----------------------------
  // Palette / gradient (Improved)
  // -----------------------------
  Color? _dominantColor;
  String? _paletteForCoverUrl;

  static final Map<String, Color> _dominantColorCache = <String, Color>{};
  static final Map<String, Future<Color>> _dominantColorFutures = <String, Future<Color>>{};

  // -----------------------------
  // Track sync state (Optimized)
  // -----------------------------
  bool _syncingTracks = false;
  String? _trackSyncError;
  bool _trackSyncTriggered = false;

  // Prevent repeated recently-viewed writes
  bool _markedViewed = false;

  late final ProviderSubscription<Map<String, dynamic>?> _albumSub;
  late final ProviderSubscription<String> _uidSub;

  // ✅ Listen to favorite controller errors once (no duplicate snackbars).
  late final ProviderSubscription<AsyncValue<void>> _favOpSub;

  @override
  void initState() {
    super.initState();

    _albumSub = ref.listenManual<Map<String, dynamic>?>(
      albumDataProvider(widget.albumId),
      (prev, next) => _maybeRunEffects(album: next, uid: ref.read(uidProvider)),
    );

    _uidSub = ref.listenManual<String>(
      uidProvider,
      (prev, next) => _maybeRunEffects(
        album: ref.read(albumDataProvider(widget.albumId)),
        uid: next,
      ),
    );

    _favOpSub = ref.listenManual<AsyncValue<void>>(
      favoriteAlbumControllerProvider(widget.albumId),
      (prev, next) {
        next.whenOrNull(
          error: (e, _) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Favorite failed: $e')),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _albumSub.close();
    _uidSub.close();
    _favOpSub.close();
    super.dispose();
  }

  void _maybeRunEffects({required Map<String, dynamic>? album, required String uid}) {
    if (album == null) return;

    final title = (album['title'] ?? '') as String;
    final artist = (album['primaryArtistName'] ?? '') as String;
    final coverUrl = (album['coverUrl'] as String?)?.trim() ?? '';

    final primaryArtistId =
        (album['primaryArtistId'] as String?) ?? (album['primaryArtistID'] as String?) ?? '';

    final syncVersionNum = album['tracksSyncVersion'] as num?;
    final int syncVersion = syncVersionNum?.toInt() ?? 0;

    // Mark viewed once per open (also works if user signs in while on page)
    if (uid.isNotEmpty && !_markedViewed) {
      _markedViewed = true;
      // ignore: discarded_futures
      RecentlyViewedService.markAlbumViewed(
        uid: uid,
        albumId: widget.albumId,
        title: title,
        primaryArtistName: artist,
        primaryArtistId: primaryArtistId,
        coverUrl: coverUrl,
      );
    }

    // Auto-sync tracklist once (never from build)
    if (!_trackSyncTriggered) {
      _trackSyncTriggered = true;

      final shouldSync = _shouldSyncTracksFromAlbumDoc(album, ttl: const Duration(days: 7));
      if (shouldSync) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          // ignore: discarded_futures
          _syncTracklist(
            ref.read(albumRefProvider(widget.albumId)),
            currentSyncVersion: syncVersion,
            force: false,
          );
        });
      }
    }
  }

  void _ensurePaletteForCoverUrl(String coverUrl, ThemeData theme) {
    final url = coverUrl.trim();
    if (url.isEmpty) return;

    if (_paletteForCoverUrl == url && _dominantColor != null) return;

    final cached = _dominantColorCache[url];
    if (cached != null) {
      _paletteForCoverUrl = url;
      if (_dominantColor != cached) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_paletteForCoverUrl != url) return;
          setState(() => _dominantColor = cached);
        });
      }
      return;
    }

    _paletteForCoverUrl = url;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      final requestUrl = url;

      final future = _dominantColorFutures.putIfAbsent(requestUrl, () async {
        try {
          final provider = CachedNetworkImageProvider(requestUrl);

          try {
            await precacheImage(provider, context);
          } catch (e, st) {
            debugPrint('precacheImage failed for $requestUrl: $e');
            debugPrint('$st');
          }

          final palette = await PaletteGenerator.fromImageProvider(
            provider,
            size: const Size(128, 128),
            maximumColorCount: 16,
          );

          final color = palette.vibrantColor?.color ??
              palette.lightVibrantColor?.color ??
              palette.mutedColor?.color ??
              palette.dominantColor?.color ??
              theme.colorScheme.primary;

          return color;
        } catch (e, st) {
          debugPrint('Palette generation failed for $requestUrl: $e');
          debugPrint('$st');
          return theme.colorScheme.primary;
        }
      });

      final color = await future;

      if (!mounted) return;
      if (_paletteForCoverUrl != requestUrl) return;

      _dominantColorCache[requestUrl] = color;

      if (_dominantColor != color) {
        setState(() => _dominantColor = color);
      }
    });
  }

  bool _shouldSyncTracksFromAlbumDoc(
    Map<String, dynamic> album, {
    Duration ttl = const Duration(days: 7),
  }) {
    final countNum = album['tracksCount'] as num?;
    final tracksCount = countNum?.toInt() ?? 0;

    final ts = album['lastTracksSyncAt'] as Timestamp?;
    if (tracksCount <= 0) return true;
    if (ts == null) return true;

    return DateTime.now().difference(ts.toDate()) > ttl;
  }

  Future<void> _syncTracklist(
    DocumentReference<Map<String, dynamic>> albumRef, {
    required int currentSyncVersion,
    bool force = false,
  }) async {
    if (_syncingTracks) return;

    try {
      if (mounted) {
        setState(() {
          _syncingTracks = true;
          _trackSyncError = null;
        });
      }

      final result = await MusicBrainzService.fetchTracklistForReleaseGroup(
        widget.albumId,
        userAgent: 'MusicAllApp/0.1 (contact: quentincoxmusic@gmail.com)',
      );

      final int newVersion = currentSyncVersion + 1;

      WriteBatch batch = ref.read(firestoreProvider).batch();
      int count = 0;

      Future<void> commit({bool forceCommit = false}) async {
        if (count == 0) return;
        if (forceCommit || count >= 450) {
          await batch.commit();
          batch = ref.read(firestoreProvider).batch();
          count = 0;
        }
      }

      for (final t in result.tracks) {
        final disc = (t['disc'] as int?) ?? 1;
        final pos = (t['position'] as int?) ?? 0;
        final trackId = 'd$disc-p$pos';

        final refDoc = albumRef.collection('tracks').doc(trackId);
        batch.set(
          refDoc,
          {
            'id': trackId,
            'title': (t['title'] as String?)?.trim().isNotEmpty == true
                ? (t['title'] as String).trim()
                : 'Untitled track',
            'disc': disc,
            'position': pos,
            if (t['durationSeconds'] != null) 'durationSeconds': t['durationSeconds'],
            if (t['recordingId'] != null) 'recordingId': t['recordingId'],
            'syncVersion': newVersion,
            'updatedAt': FieldValue.serverTimestamp(),
            'source': 'musicbrainz',
          },
          SetOptions(merge: true),
        );

        count++;
        await commit();
      }

      await commit(forceCommit: true);

      await albumRef.set({
        'primaryReleaseId': result.releaseId,
        'tracksCount': result.tracks.length,
        'tracksSyncVersion': newVersion,
        'lastTracksSyncAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e, st) {
      debugPrint('Track sync failed for album ${widget.albumId}: $e');
      debugPrint('$st');
      if (mounted) setState(() => _trackSyncError = e.toString());
    } finally {
      if (mounted) setState(() => _syncingTracks = false);
    }
  }

  Future<void> _toggleFavoriteAlbum({
    required bool isFav,
    required String uid,
    required String albumId,
    required String title,
    required String primaryArtistName,
    required String primaryArtistId,
    required String coverUrl,
  }) async {
    if (uid.isEmpty) return;

    final notifier = ref.read(favoriteAlbumControllerProvider(albumId).notifier);

    await notifier.toggle(
      isCurrentlyFav: isFav,
      payload: FavoriteAlbumPayload(
        albumId: albumId,
        title: title,
        primaryArtistName: primaryArtistName,
        primaryArtistId: primaryArtistId,
        coverUrl: coverUrl,
      ),
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isFav ? 'Removed from favorites' : 'Added to favorites'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final uid = ref.watch(uidProvider);
    final albumRef = ref.watch(albumRefProvider(widget.albumId));

    // still derived from your existing favorites stream providers
    final isFav = ref.watch(isFavoriteAlbumProvider(widget.albumId));

    // busy flag from controller
    final favBusy = ref.watch(favoriteAlbumBusyProvider(widget.albumId));

    final albumAsync = ref.watch(albumDocProvider(widget.albumId));

    return albumAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Album')),
        body: Center(child: Text('Something went wrong: $e')),
      ),
      data: (albumSnap) {
        final album = albumSnap.data();
        if (album == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Album')),
            body: Center(child: Text('Album "${widget.albumId}" not found.')),
          );
        }

        final title = (album['title'] ?? '') as String;
        final artist = (album['primaryArtistName'] ?? '') as String;

        final primaryArtistId =
            (album['primaryArtistId'] as String?) ?? (album['primaryArtistID'] as String?) ?? '';

        final firstReleaseDate = (album['firstReleaseDate'] ?? '') as String?;
        final primaryType = (album['primaryType'] ?? '') as String?;
        final coverUrl = (album['coverUrl'] as String?)?.trim() ?? '';

        final syncVersionNum = album['tracksSyncVersion'] as num?;
        final int syncVersion = syncVersionNum?.toInt() ?? 0;

        _ensurePaletteForCoverUrl(coverUrl, theme);

        final releaseLabel = formatReleaseDate(firstReleaseDate);

        final baseColor = _dominantColor ?? theme.colorScheme.surface;
        final topColor = Color.lerp(baseColor, Colors.black, 0.35)!;
        final bottomColor = theme.colorScheme.surface;

        final tracksAsync = ref.watch(tracksProvider(widget.albumId));

        return Scaffold(
          appBar: AppBar(
            title: const Text('Album'),
            actions: [
              if (uid.isNotEmpty)
                IconButton(
                  tooltip: isFav ? 'Unfavorite' : 'Favorite',
                  onPressed: favBusy
                      ? null
                      : () => _toggleFavoriteAlbum(
                            isFav: isFav,
                            uid: uid,
                            albumId: widget.albumId,
                            title: title,
                            primaryArtistName: artist,
                            primaryArtistId: primaryArtistId,
                            coverUrl: coverUrl,
                          ),
                  icon: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(isFav ? Icons.favorite : Icons.favorite_border),
                      if (favBusy)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                ),
            ],
          ),
          body: ListView(
            padding: EdgeInsets.zero,
            children: [
              // Hero
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.6, 1.0],
                    colors: [
                      topColor.withValues(alpha: 0.95),
                      topColor.withValues(alpha: 0.55),
                      bottomColor,
                    ],
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          height: 220,
                          width: 220,
                          child: coverUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: coverUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (_, _) => _AlbumArtPlaceholder(title: title),
                                  errorWidget: (_, _, _) => _AlbumArtPlaceholder(title: title),
                                )
                              : _AlbumArtPlaceholder(title: title),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (primaryArtistId.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ArtistDetailPage(
                                artistId: primaryArtistId,
                                artistName: artist,
                              ),
                            ),
                          );
                        },
                        child: Text(
                          artist,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.primary.withValues(alpha: 0.95),
                            letterSpacing: 0.3,
                          ),
                        ),
                      )
                    else
                      Text(
                        artist,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.primary.withValues(alpha: 0.95),
                        ),
                      ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      alignment: WrapAlignment.center,
                      children: [
                        if (releaseLabel != null)
                          _InfoChip(
                            icon: Icons.calendar_today_outlined,
                            label: releaseLabel,
                          ),
                        if (primaryType != null && primaryType.trim().isNotEmpty)
                          _InfoChip(
                            icon: Icons.album_outlined,
                            label: primaryType,
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Tracklist header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Tracklist',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (_syncingTracks)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    IconButton(
                      tooltip: 'Refresh tracklist',
                      onPressed: _syncingTracks
                          ? null
                          : () {
                              // ignore: discarded_futures
                              _syncTracklist(
                                albumRef,
                                currentSyncVersion: syncVersion,
                                force: true,
                              );
                            },
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),

              if (_trackSyncError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Text(
                    'Track sync error: $_trackSyncError',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),

              // Tracklist body
              tracksAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Could not load tracklist.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
                data: (snap) {
                  final docs = snap.docs;
                  if (docs.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _syncingTracks ? 'Fetching tracklist…' : 'No tracklist available yet.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (!_syncingTracks)
                            FilledButton.icon(
                              onPressed: () {
                                // ignore: discarded_futures
                                _syncTracklist(
                                  albumRef,
                                  currentSyncVersion: syncVersion,
                                  force: true,
                                );
                              },
                              icon: const Icon(Icons.download),
                              label: const Text('Fetch Tracklist'),
                            ),
                        ],
                      ),
                    );
                  }

                  final hasMultipleDiscs = docs.any((d) {
                    final disc = d.data()['disc'];
                    return disc is num && disc > 1;
                  });

                  return Column(
                    children: docs.map((d) {
                      final data = d.data();
                      final trackNum = (data['position'] as num?)?.toInt() ?? 0;
                      final disc = (data['disc'] as num?)?.toInt() ?? 1;

                      final tTitle =
                          (data['title'] as String?)?.trim().isNotEmpty == true
                              ? (data['title'] as String).trim()
                              : 'Untitled track';

                      final durNum = data['durationSeconds'] as num?;
                      String durationLabel = '';
                      if (durNum != null) {
                        final totalSeconds = durNum.round();
                        final minutes = totalSeconds ~/ 60;
                        final seconds = totalSeconds % 60;
                        durationLabel = '$minutes:${seconds.toString().padLeft(2, '0')}';
                      }

                      final discPrefix = hasMultipleDiscs ? 'Disc $disc ' : '';

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 24,
                              child: Text(
                                trackNum.toString(),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    tTitle,
                                    style: theme.textTheme.titleMedium?.copyWith(fontSize: 16),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (discPrefix.isNotEmpty)
                                    Text(
                                      discPrefix,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.outline,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            if (durationLabel.isNotEmpty)
                              Text(
                                durationLabel,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),

              const SizedBox(height: 24),

              // ✅ Reviews now Riverpod-powered
              _YourReviewSection(albumId: widget.albumId, uid: uid),
              const SizedBox(height: 24),
              _CommunityReviewsSection(albumId: widget.albumId, uid: uid),

              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

class _AlbumArtPlaceholder extends StatelessWidget {
  const _AlbumArtPlaceholder({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = title.trim().isEmpty ? '?' : title.trim().characters.first.toUpperCase();

    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: theme.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white70),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------
// Reviews (Riverpod version)
// ---------------------------

class _YourReviewSection extends ConsumerWidget {
  const _YourReviewSection({
    required this.albumId,
    required this.uid,
  });

  final String albumId;
  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    if (uid.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final reviewAsync = ref.watch(myReviewProvider((albumId: albumId, uid: uid)));

    return reviewAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load your review: $e')),
      data: (review) {
        final hasReview = review != null;

        final rating = hasReview ? (review['rating'] as num? ?? 0).toDouble() : 0.0;
        final text = hasReview ? (review['text'] as String? ?? '') : '';

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your review',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  if (hasReview) ...[
                    Row(
                      children: [
                        RatingStars(rating: rating),
                        const SizedBox(width: 8),
                        Text(
                          '${rating.toStringAsFixed(1)}/10',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (text.trim().isNotEmpty) Text(text),
                    if (text.trim().isEmpty) Text('(No written review)', style: theme.textTheme.bodySmall),
                  ] else
                    Text(
                      'You have not rated this album yet.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ReviewEditorPage(
                                albumId: albumId,
                                existingRating: hasReview ? rating : null,
                                existingText: hasReview ? text : null,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.rate_review),
                        label: Text(hasReview ? 'Edit Rating / Review' : 'Rate This album'),
                      ),
                      const SizedBox(width: 12),
                      if (hasReview)
                        TextButton(
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete Review?'),
                                content: const Text('This cannot be undone.'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );

                            if (ok == true) {
                              await ref
                                  .read(firestoreProvider)
                                  .collection('albums')
                                  .doc(albumId)
                                  .collection('reviews')
                                  .doc(uid)
                                  .delete();

                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Review Deleted')),
                                );
                              }
                            }
                          },
                          child: const Text('Delete'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CommunityReviewsSection extends ConsumerWidget {
  const _CommunityReviewsSection({
    required this.albumId,
    required this.uid,
  });

  final String albumId;
  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final reviewsAsync = ref.watch(communityReviewsProvider(albumId));
    final statsAsync = ref.watch(communityReviewStatsProvider(albumId));

    return reviewsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load reviews: $e')),
      data: (docs) {
        final displayDocs = docs.take(20).toList();

        final uids = displayDocs.map((d) => d.id).toSet().toList()..sort();
        final uidsKey = uids.join('|');

        final namesAsync = ref.watch(displayNameMapProvider(uidsKey));

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: statsAsync.when(
                    loading: () => const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Community Reviews: …'),
                        Text('Avg: …'),
                      ],
                    ),
                    error: (_, _) => const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Community Reviews: -'),
                        Text('Avg: -'),
                      ],
                    ),
                    data: (stats) => Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Community Reviews: ${stats.count}'),
                        Text(
                          stats.avg == null ? 'Avg: -' : 'Avg: ${stats.avg!.toStringAsFixed(1)}/10',
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Recent reviews',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              if (displayDocs.isEmpty)
                const Text('No reviews yet.')
              else
                namesAsync.when(
                  loading: () => Column(
                    children: displayDocs.map((d) {
                      final data = d.data();
                      final ratingNum = data['rating'];
                      final rating = ratingNum is num ? ratingNum.toDouble() : 0.0;
                      final text = (data['text'] as String? ?? '').trim();
                      final who = d.id;
                      final fallback = who.substring(0, who.length >= 6 ? 6 : who.length);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: Chip(label: Text(fallback)),
                          title: Row(
                            children: [
                              RatingStars(rating: rating, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                '${rating.toStringAsFixed(1)}/10',
                                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          subtitle: text.isEmpty
                              ? Text('(No written review)', style: theme.textTheme.bodySmall)
                              : Text(text, maxLines: 3, overflow: TextOverflow.ellipsis),
                          trailing: who == uid
                              ? Text(
                                  'You',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                )
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  error: (_, _) => const Text('Could not load user names.'),
                  data: (nameMap) => Column(
                    children: displayDocs.map((d) {
                      final data = d.data();
                      final ratingNum = data['rating'];
                      final rating = ratingNum is num ? ratingNum.toDouble() : 0.0;
                      final text = (data['text'] as String? ?? '').trim();
                      final who = d.id;

                      final fallback = who.substring(0, who.length >= 6 ? 6 : who.length);
                      final display = (nameMap[who] ?? fallback).trim();

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: Chip(label: Text(display)),
                          title: Row(
                            children: [
                              RatingStars(rating: rating, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                '${rating.toStringAsFixed(1)}/10',
                                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          subtitle: text.isEmpty
                              ? Text('(No written review)', style: theme.textTheme.bodySmall)
                              : Text(text, maxLines: 3, overflow: TextOverflow.ellipsis),
                          trailing: who == uid
                              ? Text(
                                  'You',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                )
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class RatingStars extends StatelessWidget {
  const RatingStars({super.key, required this.rating, this.size = 18});

  final double rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final fiveScale = rating / 2.0;
    int full = fiveScale.floor().clamp(0, 5);
    final double frac = fiveScale - full;
    bool hasHalf = frac >= 0.25 && frac < 0.75;
    if (full == 5) hasHalf = false;

    final icons = <Widget>[];
    for (int i = 0; i < full; i++) {
      icons.add(Icon(Icons.star, size: size, color: theme.colorScheme.primary));
    }
    if (hasHalf) {
      icons.add(Icon(Icons.star_half, size: size, color: theme.colorScheme.primary));
    }
    while (icons.length < 5) {
      icons.add(Icon(Icons.star_border, size: size, color: theme.colorScheme.primary));
    }

    return Row(mainAxisSize: MainAxisSize.min, children: icons);
  }
}

String? formatReleaseDate(String? iso) {
  if (iso == null || iso.trim().isEmpty) return null;

  final trimmed = iso.trim();

  try {
    final dt = DateTime.parse(trimmed);
    const monthNames = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final m = monthNames[dt.month - 1];
    return '$m ${dt.day}, ${dt.year}';
  } catch (_) {}

  final parts = trimmed.split('-');
  if (parts.length == 1) {
    return parts[0];
  } else if (parts.length == 2) {
    const monthNames = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final year = parts[0];
    final monthIndex = int.tryParse(parts[1]) ?? 1;
    final m = monthNames[(monthIndex - 1).clamp(0, 11)];
    return '$m $year';
  } else {
    return trimmed;
  }
}
