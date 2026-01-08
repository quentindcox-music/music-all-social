// lib/screens/home_page.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'album_detail_page.dart';
import 'artist_detail_page.dart';
import 'package:music_all_app/widgets/home_header.dart';
import 'package:music_all_app/widgets/hero_carousel.dart';
import 'package:music_all_app/widgets/recently_viewed_section.dart';

class HomePage extends StatelessWidget {
  final void Function(int)? onNavigateToTab;
  
  const HomePage({super.key, this.onNavigateToTab});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = FirebaseAuth.instance.currentUser;

    final demoItems = <CarouselItem>[
      CarouselItem(
        title: 'Wish You Were Here',
        subtitle: 'Pink Floyd • Classic favorite',
        badge: 'Trending album',
        imageUrl: null,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const AlbumDetailPage(
                albumId: 'test-album-1',
              ),
            ),
          );
        },
      ),
      CarouselItem(
        title: 'David Bowie',
        subtitle: 'Artist people are revisiting',
        badge: 'Trending artist',
        imageUrl: null,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const ArtistDetailPage(
                artistId: 'demo-artist-bowie',
                artistName: 'David Bowie',
              ),
            ),
          );
        },
      ),
      CarouselItem(
        title: 'What are people listening to this week?',
        subtitle: 'Explore new albums based on community ratings.',
        badge: 'Discover',
        imageUrl: null,
        onTap: () {
          onNavigateToTab?.call(1); // Go to Discover
        },
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Music All'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Notifications coming soon!')),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.delayed(const Duration(seconds: 1));
        },
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const WelcomeBackHeader(),
              const SizedBox(height: 8),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: HeroCarousel(items: demoItems),
              ),

              const SizedBox(height: 24),

              if (user != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Recently Viewed',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          // TODO: Navigate to full recently viewed page
                        },
                        child: const Text('View all'),
                      ),
                    ],
                  ),
                ),
                RecentlyViewedSection(uid: user.uid),
                const SizedBox(height: 24),
              ],

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Quick Actions',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    _QuickActionCard(
                      icon: Icons.search,
                      title: 'Discover Music',
                      subtitle: 'Find new albums and artists',
                      color: theme.colorScheme.primaryContainer,
                      onTap: () => onNavigateToTab?.call(1), // Discover tab
                    ),
                    const SizedBox(height: 12),
                    _QuickActionCard(
                      icon: Icons.star_outline,
                      title: 'Your Reviews',
                      subtitle: 'See what you\'ve rated',
                      color: theme.colorScheme.secondaryContainer,
                      onTap: () => onNavigateToTab?.call(2), // Stats tab
                    ),
                    const SizedBox(height: 12),
                    _QuickActionCard(
                      icon: Icons.bar_chart,
                      title: 'Your Stats',
                      subtitle: 'View your listening statistics',
                      color: theme.colorScheme.tertiaryContainer,
                      onTap: () => onNavigateToTab?.call(2), // Stats tab
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Community Activity',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 48,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'See what others are listening to',
                          style: theme.textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Coming soon',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}