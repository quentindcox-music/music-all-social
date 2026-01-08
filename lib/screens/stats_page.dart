import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'user_reviews_list_page.dart';

class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    // All reviews; we'll filter by uid in Dart.
    final reviewsStream =
        FirebaseFirestore.instance.collectionGroup('reviews').snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stats'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: reviewsStream,
        builder: (context, snap) {
          // 1. Errors
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Error loading stats:\n${snap.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          // 2. Initial load
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          // 3. Filter to this user’s reviews
          final allDocs = snap.data!.docs;
          final userDocs = allDocs.where((d) => d.id == uid).toList();

          // ---- Compute stats ----

          int writtenReviews = 0; // non-empty text
          final ratedAlbumIds = <String>{};

          // For rating spread
          // buckets from 0 to 10 (integers)
          final Map<int, int> ratingBuckets = {
            for (var i = 0; i <= 10; i++) i: 0,
          };

          for (final d in userDocs) {
            final data = d.data();

            // Written review?
            final text = (data['text'] as String?)?.trim() ?? '';
            if (text.isNotEmpty) {
              writtenReviews++;
            }

            // Numeric rating?
            final ratingValue = data['rating'];
            if (ratingValue is num) {
              final rating = ratingValue.toDouble();

              // Bucket: round to nearest integer 0–10
              var bucket = rating.round();
              if (bucket < 0) bucket = 0;
              if (bucket > 10) bucket = 10;

              ratingBuckets[bucket] = (ratingBuckets[bucket] ?? 0) + 1;

              // Album id for this review
              final albumRef = d.reference.parent.parent;
              if (albumRef != null) {
                ratedAlbumIds.add(albumRef.id);
              }
            }
          }

          final albumsRated = ratedAlbumIds.length;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Your Activity',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),

// Albums rated + written reviews (centered tiles with navigation)
Row(
  children: [
    // Albums Rated tile
    Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const UserReviewsListPage(
                mode: UserReviewsListMode.ratedAlbums,
              ),
            ),
          );
        },
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$albumsRated',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Albums Rated',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    ),

    // Written Reviews tile
    Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const UserReviewsListPage(
                mode: UserReviewsListMode.writtenReviews,
              ),
            ),
          );
        },
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$writtenReviews',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Written Reviews',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  ],
),



              const SizedBox(height: 12),

              // Rating spread chart (Letterboxd-style)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: RatingSpreadChart(buckets: ratingBuckets),
                ),
              ),

              const SizedBox(height: 24),

              Text(
                'Listening history',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Coming soon',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'This is where daily/weekly listening time, '
                        'streaks, and breakdowns by artist/genre will go.',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class RatingSpreadChart extends StatefulWidget {
  const RatingSpreadChart({super.key, required this.buckets});

  final Map<int, int> buckets; // key: 0–10, value: count

  @override
  State<RatingSpreadChart> createState() => _RatingSpreadChartState();
}

class _RatingSpreadChartState extends State<RatingSpreadChart> {
  int? _activeRating; // which bar is currently pressed

  double _dynamicMaxHeight(int total) {
    // Your 32px starter height
    if (total <= 2) return 32;
    if (total <= 5) return 80;
    if (total <= 15) return 120;
    if (total <= 40) return 160;
    return 200;
  }

  void _setActive(int rating) {
    setState(() => _activeRating = rating);
  }

  void _clearActive() {
    setState(() => _activeRating = null);
  }

  @override
  Widget build(BuildContext context) {
    final buckets = widget.buckets;
    final totalRatings = buckets.values.fold<int>(0, (acc, v) => acc + v);

    if (totalRatings == 0) {
      return const Text('No ratings yet.');
    }

    final maxCount = buckets.values.reduce((a, b) => a > b ? a : b);
    final maxBarHeight = _dynamicMaxHeight(totalRatings);
    final primary = Theme.of(context).colorScheme.primary;
    final tooltipBg = Theme.of(context).colorScheme.surfaceContainerHighest;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Rating Spread',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        SizedBox(
          // bars + tooltip row + axis labels
          height: maxBarHeight + 72,
          child: Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: List.generate(11, (i) {
                    final rating = i; // 0–10
                    final count = buckets[rating] ?? 0;
                    final normalized =
                        maxCount == 0 ? 0.0 : count / maxCount;
                    final height = normalized * maxBarHeight;
                    final isActive = _activeRating == rating && count > 0;

                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (_) => _setActive(rating),
                          onTapUp: (_) => _clearActive(),
                          onTapCancel: _clearActive,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              // Fixed-height tooltip row for *all* bars,
                              // so we never overflow when one appears.
                              SizedBox(
                                height: 36,
                                child: Center(
                                  child: AnimatedOpacity(
                                    opacity: isActive ? 1.0 : 0.0,
                                    duration:
                                        const Duration(milliseconds: 120),
                                    child: isActive
                                        ? Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // pill with number
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: tooltipBg,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  '$count',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelMedium
                                                      ?.copyWith(
                                                        fontSize: 11,
                                                      ),
                                                ),
                                              ),
                                              // little arrow pointing down
                                              Icon(
                                                Icons.arrow_drop_down,
                                                size: 14,
                                                color: tooltipBg,
                                              ),
                                            ],
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              // The bar itself
                              Align(
                                alignment: Alignment.bottomCenter,
                                child: AnimatedContainer(
                                  duration: const Duration(
                                      milliseconds: 250),
                                  height: height,
                                  decoration: BoxDecoration(
                                    color: primary.withValues(
                                      alpha: count == 0 ? 0.12 : 0.85,
                                    ),
                                    borderRadius:
                                        const BorderRadius.vertical(
                                      top: Radius.circular(4),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 4),
              // X-axis labels (0–10)
              Row(
                children: List.generate(11, (i) {
                  return Expanded(
                    child: Center(
                      child: Text(
                        '$i',
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(fontSize: 10),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
