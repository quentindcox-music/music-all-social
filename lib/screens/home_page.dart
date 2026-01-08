// lib/home_page.dart (or lib/screens/home_page.dart)

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'album_detail_page.dart';
import 'artist_detail_page.dart';

// Widget imports from widgets folder
import 'package:music_all_app/widgets/home_header.dart';
import 'package:music_all_app/widgets/hero_carousel.dart';
import 'package:music_all_app/widgets/recently_viewed_section.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = FirebaseAuth.instance.currentUser; // may be null if signed out

    // For now: demo items. Later, map this from Firestore / APIs.
    final demoItems = <CarouselItem>[
      CarouselItem(
        title: 'Wish You Were Here',
        subtitle: 'Pink Floyd • Classic favorite',
        badge: 'Trending album',
        imageUrl: null, // plug in cover URL later if you like
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const AlbumDetailPage(
                albumId: 'test-album-1', // replace with real album IDs later
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
                artistId: 'demo-artist-bowie', // wire real MBID later
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
          // Later: maybe jump to Discover tab / page.
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Hook this up to Discover later ✨'),
            ),
          );
        },
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Music All'),
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // 👋 Welcome back, (username)
            const WelcomeBackHeader(),
            const SizedBox(height: 8),

            // 🎠 Hero carousel (news or trending albums/artists)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: HeroCarousel(items: demoItems),
            ),

            const SizedBox(height: 16),

            // 🕒 Recently viewed — only if we have a signed-in user
            if (user != null) ...[
              RecentlyViewedSection(uid: user.uid),
              const SizedBox(height: 24),
            ],

            // You can evolve this section later (recent activity, shortcuts, etc.)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Quick actions',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilledButton.icon(
                onPressed: () {
                  // Later: navigate to your Discover tab/page
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Hook this to Discover albums next 🎧'),
                    ),
                  );
                },
                icon: const Icon(Icons.search),
                label: const Text('Discover music'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
