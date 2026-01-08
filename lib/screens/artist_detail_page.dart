import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ArtistDetailPage extends StatelessWidget {
  const ArtistDetailPage({
    super.key,
    required this.artistId,
    required this.artistName,
  });

  final String artistId;   // MusicBrainz artist MBID
  final String artistName; // for the title

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final albumsQuery = FirebaseFirestore.instance
        .collection('albums')
        .where('primaryArtistId', isEqualTo: artistId);

    return Scaffold(
      appBar: AppBar(
        title: Text(artistName),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: albumsQuery.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            final msg = snap.error.toString();

            // Helpful special case for index problems
            final looksLikeIndexError =
                msg.contains('FAILED_PRECONDITION') &&
                msg.contains('indexes');

            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                looksLikeIndexError
                    ? 'Could not load albums (Firestore index not ready yet).\n'
                      'If you just created the index, wait a minute and try again.'
                    : 'Could not load albums: $msg',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            );
          }

          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          var docs = snap.data?.docs ?? const [];

          if (docs.isEmpty) {
            return const Center(
              child: Text('No albums stored for this artist yet.'),
            );
          }

          // Sort client-side by firstReleaseDate (descending)
          docs = [...docs]; // make a copy just in case
          docs.sort((a, b) {
            final aDate = (a.data()['firstReleaseDate'] as String? ?? '');
            final bDate = (b.data()['firstReleaseDate'] as String? ?? '');
            // “YYYY-MM-DD” sorts lexicographically
            return bDate.compareTo(aDate);
          });

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const Divider(height: 0),
            itemBuilder: (context, i) {
              final data = docs[i].data();
              final title = (data['title'] as String?) ?? 'Untitled album';
              final date = (data['firstReleaseDate'] as String?) ?? '';
              final type = (data['primaryType'] as String?) ?? '';

              final subtitlePieces = <String>[];
              if (date.isNotEmpty) subtitlePieces.add(date);
              if (type.isNotEmpty) subtitlePieces.add(type);

              return ListTile(
                title: Text(title),
                subtitle: subtitlePieces.isEmpty
                    ? null
                    : Text(subtitlePieces.join(' • ')),
                onTap: () {
                  // Optional: navigate to AlbumDetailPage if you want
                  // Navigator.of(context).push(
                  //   MaterialPageRoute(
                  //     builder: (_) => AlbumDetailPage(albumId: data['id']),
                  //   ),
                  // );
                },
              );
            },
          );
        },
      ),
    );
  }
}
