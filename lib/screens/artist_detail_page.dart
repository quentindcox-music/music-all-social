import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:music_all_app/services/musicbrainz_service.dart';
import 'package:music_all_app/services/fanart_service.dart';
import 'package:music_all_app/widgets/album_thumb.dart';
import 'album_detail_page.dart';

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
  List<Map<String, dynamic>> _albums = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadArtist();
  }

  Future<void> _loadArtist() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Fetch artist details and images in parallel
      final results = await Future.wait([
        MusicBrainzService.fetchArtistDetails(widget.artistId),
        FanartService.getArtistImages(widget.artistId),
        MusicBrainzService.fetchArtistReleaseGroups(widget.artistId),
      ]);

      final artist = results[0] as MbArtist?;
      final images = results[1] as ArtistImages?;
      final albums = results[2] as List<Map<String, dynamic>>;

      if (!mounted) return;
      setState(() {
        _artist = artist;
        _artistImages = images;
        _albums = albums;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : CustomScrollView(
                  slivers: [
                    // Hero header with artist image
                    SliverAppBar(
                      expandedHeight: 300,
                      pinned: true,
                      stretch: true,
                      backgroundColor: theme.colorScheme.surface,
                      flexibleSpace: FlexibleSpaceBar(
                        title: Text(
                          widget.artistName,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
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

                    // Artist info section
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Artist metadata chips
                            if (_artist != null) ...[
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (_artist!.type != null)
                                    _InfoChip(
                                      icon: Icons.person_outline,
                                      label: _artist!.type!,
                                    ),
                                  if (_artist!.country != null)
                                    _InfoChip(
                                      icon: Icons.location_on_outlined,
                                      label: _artist!.country!,
                                    ),
                                  if (_artist!.beginArea != null)
                                    _InfoChip(
                                      icon: Icons.home_outlined,
                                      label: _artist!.beginArea!,
                                    ),
                                  if (_artist!.lifeSpan != null)
                                    _InfoChip(
                                      icon: Icons.calendar_today_outlined,
                                      label: _artist!.lifeSpan!,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 16),
                            ],

                            // Discography header
                            Text(
                              'Discography',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_albums.length} releases',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Albums grid
                    if (_albums.isNotEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverGrid(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                            childAspectRatio: 0.75,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final album = _albums[index];
                              final id = album['id'] as String;
                              final title = album['title'] as String? ?? 'Unknown';
                              final year = album['firstReleaseDate'] as String?;
                              final type = album['primaryType'] as String?;

                              return _AlbumCard(
                                albumId: id,
                                title: title,
                                year: year,
                                type: type,
                              );
                            },
                            childCount: _albums.length,
                          ),
                        ),
                      ),

                    const SliverToBoxAdapter(
                      child: SizedBox(height: 32),
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
            placeholder: (_, _) => Container(
              color: theme.colorScheme.primaryContainer,
            ),
            errorWidget: (_, _, _) => _buildPlaceholder(theme),
          ),
          // Gradient overlay for text readability
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.7),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return _buildPlaceholder(theme);
  }

  Widget _buildPlaceholder(ThemeData theme) {
    final initial = widget.artistName.isNotEmpty
        ? widget.artistName[0].toUpperCase()
        : '?';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.secondary,
          ],
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

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onPrimaryContainer),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({
    required this.albumId,
    required this.title,
    this.year,
    this.type,
  });

  final String albumId;
  final String title;
  final String? year;
  final String? type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AlbumDetailPage(albumId: albumId),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AlbumThumb(releaseId: albumId),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (year != null || type != null)
            Text(
              [
                if (year != null) year!.split('-').first,
                if (type != null) type,
              ].join(' • '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
        ],
      ),
    );
  }
}