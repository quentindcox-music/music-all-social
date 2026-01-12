// lib/screens/album_detail_page.dart

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

import '../services/recently_viewed_service.dart';
import '../services/musicbrainz_service.dart';
import 'artist_detail_page.dart';
import 'review_editor_page.dart';

class AlbumDetailPage extends StatefulWidget {
  const AlbumDetailPage({super.key, required this.albumId});

  /// This is a MusicBrainz *release-group* id (same as your album doc id in Firestore).
  final String albumId;

  @override
  State<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends State<AlbumDetailPage> {
  // Palette / gradient
  Color? _dominantColor;
  String? _paletteForCoverUrl;

  Future<void> _generatePalette(String coverUrl, ThemeData theme) async {
    if (coverUrl.isEmpty) return;
    if (_paletteForCoverUrl == coverUrl && _dominantColor != null) return;

    try {
      final palette = await PaletteGenerator.fromImageProvider(
        NetworkImage(coverUrl),
        maximumColorCount: 20,
      );

      final color = palette.vibrantColor?.color ??
          palette.lightVibrantColor?.color ??
          palette.mutedColor?.color ??
          palette.dominantColor?.color ??
          theme.colorScheme.primary;

      if (!mounted) return;
      setState(() {
        _paletteForCoverUrl = coverUrl;
        _dominantColor = color;
      });
    } catch (_) {}
  }

  // Track sync state
  bool _syncingTracks = false;
  String? _trackSyncError;
  bool _trackSyncTriggered = false;

  // Prevent repeated recently-viewed writes
  bool _markedViewed = false;

  Future<bool> _shouldSyncTracks(
    DocumentReference<Map<String, dynamic>> albumRef, {
    Duration ttl = const Duration(days: 7),
  }) async {
    final existing = await albumRef.collection('tracks').limit(1).get();
    if (existing.docs.isEmpty) return true;

    final albumSnap = await albumRef.get();
    final ts = albumSnap.data()?['lastTracksSyncAt'] as Timestamp?;
    if (ts == null) return true;

    return DateTime.now().difference(ts.toDate()) > ttl;
  }

  Future<void> _syncTracklist(
    DocumentReference<Map<String, dynamic>> albumRef, {
    bool force = false,
  }) async {
    if (_syncingTracks) return;

    try {
      if (!force) {
        final should = await _shouldSyncTracks(albumRef);
        if (!should) return;
      }

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

      await albumRef.set({
        'primaryReleaseId': result.releaseId,
        'lastTracksSyncAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Clean old tracks (optional)
      final old = await albumRef.collection('tracks').get();
      if (old.docs.isNotEmpty) {
        WriteBatch delBatch = FirebaseFirestore.instance.batch();
        int delCount = 0;
        for (final d in old.docs) {
          delBatch.delete(d.reference);
          delCount++;
          if (delCount >= 450) {
            await delBatch.commit();
            delBatch = FirebaseFirestore.instance.batch();
            delCount = 0;
          }
        }
        if (delCount > 0) await delBatch.commit();
      }

      WriteBatch batch = FirebaseFirestore.instance.batch();
      int count = 0;

      Future<void> commit({bool forceCommit = false}) async {
        if (count == 0) return;
        if (forceCommit || count >= 450) {
          await batch.commit();
          batch = FirebaseFirestore.instance.batch();
          count = 0;
        }
      }

      for (final t in result.tracks) {
        final disc = (t['disc'] as int?) ?? 1;
        final pos = (t['position'] as int?) ?? 0;
        final trackId = 'd$disc-p$pos';

        final ref = albumRef.collection('tracks').doc(trackId);
        batch.set(
          ref,
          {
            'id': trackId,
            'title': (t['title'] as String?)?.trim().isNotEmpty == true
                ? (t['title'] as String).trim()
                : 'Untitled track',
            'disc': disc,
            'position': pos,
            if (t['durationSeconds'] != null) 'durationSeconds': t['durationSeconds'],
            if (t['recordingId'] != null) 'recordingId': t['recordingId'],
            'updatedAt': FieldValue.serverTimestamp(),
            'source': 'musicbrainz',
          },
          SetOptions(merge: true),
        );

        count++;
        await commit();
      }

      await commit(forceCommit: true);
    } catch (e) {
      if (mounted) setState(() => _trackSyncError = e.toString());
    } finally {
      if (mounted) setState(() => _syncingTracks = false);
    }
  }

  Future<void> _toggleFavoriteAlbum({
    required String uid,
    required String albumId,
    required String title,
    required String primaryArtistName,
    required String primaryArtistId,
    required String coverUrl,
  }) async {
    if (uid.isEmpty) return;

    final favRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('favorites_albums')
        .doc(albumId);

    final snap = await favRef.get();
    if (snap.exists) {
      await favRef.delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Removed from favorites')),
        );
      }
    } else {
      await favRef.set({
        'albumId': albumId,
        'title': title,
        'primaryArtistName': primaryArtistName,
        if (primaryArtistId.trim().isNotEmpty) 'primaryArtistId': primaryArtistId.trim(),
        'coverUrl': coverUrl,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Added to favorites')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final albumRef =
        FirebaseFirestore.instance.collection('albums').doc(widget.albumId);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final theme = Theme.of(context);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: albumRef.snapshots(),
      builder: (context, albumSnap) {
        if (albumSnap.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Album')),
            body: Center(
              child: Text('Something went wrong: ${albumSnap.error}'),
            ),
          );
        }

        if (!albumSnap.hasData) {
          return Scaffold(
            appBar: AppBar(title: Text('Album')),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final album = albumSnap.data?.data();
        if (album == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Album')),
            body: Center(child: Text('Album "${widget.albumId}" not found.')),
          );
        }

        final title = (album['title'] ?? '') as String;
        final artist = (album['primaryArtistName'] ?? '') as String;

        // Support both legacy and new field names.
        final primaryArtistId = (album['primaryArtistId'] as String?) ??
            (album['primaryArtistID'] as String?) ??
            '';

        final firstReleaseDate = (album['firstReleaseDate'] ?? '') as String?;
        final primaryType = (album['primaryType'] ?? '') as String?;
        final coverUrl = (album['coverUrl'] as String?)?.trim() ?? '';

        // Mark viewed once per open (prevents repeated writes on rebuilds)
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

        _generatePalette(coverUrl, theme);

        if (!_trackSyncTriggered) {
          _trackSyncTriggered = true;
          // ignore: discarded_futures
          _syncTracklist(albumRef);
        }

        final releaseLabel = formatReleaseDate(firstReleaseDate);
        final baseColor = _dominantColor ?? theme.colorScheme.surface;
        final darkenedColor = Color.lerp(baseColor, Colors.black, 0.4)!;
        final bottomColor = theme.colorScheme.surface;

        final favRef = uid.isEmpty
            ? null
            : FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .collection('favorites_albums')
                .doc(widget.albumId);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Album'),
            actions: [
              if (favRef != null)
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: favRef.snapshots(),
                  builder: (context, favSnap) {
                    final isFav = favSnap.data?.exists == true;
                    return IconButton(
                      tooltip: isFav ? 'Unfavorite' : 'Favorite',
                      icon: Icon(isFav ? Icons.favorite : Icons.favorite_border),
                      onPressed: () => _toggleFavoriteAlbum(
                        uid: uid,
                        albumId: widget.albumId,
                        title: title,
                        primaryArtistName: artist,
                        primaryArtistId: primaryArtistId,
                        coverUrl: coverUrl,
                      ),
                    );
                  },
                ),
            ],
          ),
          body: ListView(
            padding: EdgeInsets.zero,
            children: [
              // Hero area
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.6, 1.0],
                    colors: [
                      darkenedColor,
                      darkenedColor.withValues(alpha: 0.6),
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
                              ? Image.network(
                                  coverUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) =>
                                      _AlbumArtPlaceholder(title: title),
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
                            color: const Color.fromARGB(255, 146, 106, 255)
                                .withValues(alpha: 0.95),
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
                          color: const Color.fromARGB(255, 146, 106, 255)
                              .withValues(alpha: 0.95),
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

              // Tracklist Header + Controls
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
                          : () => _syncTracklist(albumRef, force: true),
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

              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: albumRef
                    .collection('tracks')
                    .orderBy('disc')
                    .orderBy('position')
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    debugPrint('Tracklist error: ${snap.error}');
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text(
                        'Could not load tracklist.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    );
                  }

                  if (!snap.hasData) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }

                  final docs = snap.data?.docs ?? [];
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
                              onPressed: () => _syncTracklist(albumRef, force: true),
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

                      final tTitle = (data['title'] as String?)?.trim().isNotEmpty == true
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

              _YourReviewSection(
                albumRef: albumRef,
                uid: uid,
                albumId: widget.albumId,
              ),
              const SizedBox(height: 24),
              _CommunityReviewsSection(
                albumRef: albumRef,
                uid: uid,
              ),
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
    final initial = title.trim().isEmpty
        ? '?'
        : title.trim().characters.first.toUpperCase();

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

class _YourReviewSection extends StatelessWidget {
  const _YourReviewSection({
    required this.albumRef,
    required this.uid,
    required this.albumId,
  });

  final DocumentReference<Map<String, dynamic>> albumRef;
  final String uid;
  final String albumId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final myReviewRef = albumRef.collection('reviews').doc(uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: myReviewRef.snapshots(),
      builder: (context, reviewSnap) {
        if (reviewSnap.hasError) {
          return Center(
            child: Text('Could not load your review: ${reviewSnap.error}'),
          );
        }

        if (!reviewSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final review = reviewSnap.data?.data();
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
                    if (text.trim().isEmpty)
                      Text('(No written review)', style: theme.textTheme.bodySmall),
                  ] else
                    Text('You have not rated this album yet.',
                        style: theme.textTheme.bodyMedium),
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
                              await myReviewRef.delete();
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

class _CommunityReviewsSection extends StatelessWidget {
  const _CommunityReviewsSection({
    required this.albumRef,
    required this.uid,
  });

  final DocumentReference<Map<String, dynamic>> albumRef;
  final String uid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: albumRef
          .collection('reviews')
          .orderBy('updatedAt', descending: true)
          .limit(200)
          .snapshots(),
      builder: (context, listSnap) {
        if (listSnap.hasError) {
          return Center(child: Text('Could not load reviews: ${listSnap.error}'));
        }

        if (!listSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = listSnap.data?.docs ?? const [];

        int count = 0;
        double sum = 0;
        for (final d in docs) {
          final data = d.data();
          final ratingValue = data['rating'];
          if (ratingValue is num) {
            sum += ratingValue.toDouble();
            count += 1;
          }
        }
        final double? avg = count == 0 ? null : (sum / count);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Community Reviews: $count'),
                      Text(
                        avg == null ? 'Avg: -' : 'Avg: ${avg.toStringAsFixed(1)}/10',
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Recent reviews',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              if (docs.isEmpty)
                const Text('No reviews yet.')
              else
                Column(
                  children: docs.take(20).map((d) {
                    final data = d.data();
                    final ratingNum = data['rating'];
                    final rating = ratingNum is num ? ratingNum.toDouble() : 0.0;
                    final text = (data['text'] as String? ?? '').trim();
                    final who = d.id;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: _DisplayNameChip(uid: who),
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

class _DisplayNameChip extends StatelessWidget {
  const _DisplayNameChip({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userRef.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final name = (data?['displayName'] as String?)?.trim();

        final display = (name != null && name.isNotEmpty)
            ? name
            : uid.substring(0, uid.length >= 6 ? 6 : uid.length);

        return Chip(label: Text(display));
      },
    );
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
