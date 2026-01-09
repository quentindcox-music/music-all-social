import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _nameController = TextEditingController();
  final _photoController = TextEditingController();

  bool _saving = false;
  bool _editMode = false;

  @override
  void dispose() {
    _nameController.dispose();
    _photoController.dispose();
    super.dispose();
  }

  Future<void> _save(String uid) async {
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'displayName': _nameController.text.trim(),
        'photoUrl': _photoController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated')),
      );

      // Auto-exit edit mode after save
      setState(() => _editMode = false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _openFollowers(String uid) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FollowersListPage(uid: uid)),
    );
  }

  void _openFollowing(String uid) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FollowingListPage(uid: uid)),
    );
  }

  void _openLists(String uid) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MyListsPage(uid: uid)),
    );
  }

  void _openLatestReviews(String uid) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LatestReviewsPage(uid: uid)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

    final followersRef = userRef.collection('followers');
    final followingRef = userRef.collection('following');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            tooltip: _editMode ? 'Done' : 'Edit profile',
            onPressed: () => setState(() => _editMode = !_editMode),
            icon: Icon(_editMode ? Icons.check : Icons.edit),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: userRef.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }

          final data = snap.data?.data() ?? {};
          final displayName =
              (data['displayName'] as String?)?.trim().isNotEmpty == true
                  ? (data['displayName'] as String)
                  : 'Listener';
          final photoUrl = (data['photoUrl'] as String?)?.trim() ?? '';

          // Keep controllers in sync when not actively editing/saving
          if (!_saving && !_editMode) {
            _nameController.text = displayName;
            _photoController.text = photoUrl;
          } else if (!_saving && _editMode) {
            if (_nameController.text.trim().isEmpty) {
              _nameController.text = displayName;
            }
            if (_photoController.text.trim().isEmpty) {
              _photoController.text = photoUrl;
            }
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ---------- Header ----------
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          _ProfileAvatar(
                            photoUrl: photoUrl,
                            displayName: displayName,
                            radius: 34,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayName,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'MusicAll member',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Followers / Following counts
                      Row(
                        children: [
                          Expanded(
                            child: _CountChip(
                              label: 'Followers',
                              stream: followersRef.snapshots(),
                              onTap: () => _openFollowers(uid),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _CountChip(
                              label: 'Following',
                              stream: followingRef.snapshots(),
                              onTap: () => _openFollowing(uid),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ---------- Navigation sections ----------
              Text(
                'Your activity',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),

              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _NavRow(
                      icon: Icons.list_alt,
                      title: 'Lists you’ve created',
                      subtitle: 'Your custom collections',
                      onTap: () => _openLists(uid),
                    ),
                    const Divider(height: 1),
                    _NavRow(
                      icon: Icons.rate_review,
                      title: 'Latest reviews',
                      subtitle: 'See what you’ve rated recently',
                      onTap: () => _openLatestReviews(uid),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // ---------- Edit section (hidden unless editMode) ----------
              if (_editMode) ...[
                Text(
                  'Edit profile',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),

                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _photoController,
                  decoration: const InputDecoration(
                    labelText: 'Photo URL (optional)',
                    border: OutlineInputBorder(),
                    hintText: 'https://...',
                  ),
                ),
                const SizedBox(height: 12),

                FilledButton.icon(
                  onPressed: _saving ? null : () => _save(uid),
                  icon: const Icon(Icons.save),
                  label: Text(_saving ? 'Saving…' : 'Save'),
                ),

                const SizedBox(height: 18),
              ],

              // ---------- Account section ----------
              Text(
                'Account',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),

              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'User ID',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(uid),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () => FirebaseAuth.instance.signOut(),
                        icon: const Icon(Icons.logout),
                        label: const Text('Sign out'),
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

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.photoUrl,
    required this.displayName,
    required this.radius,
  });

  final String photoUrl;
  final String displayName;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = displayName.trim().isNotEmpty
        ? displayName.trim()[0].toUpperCase()
        : '?';

    return CircleAvatar(
      radius: radius,
      backgroundColor: theme.colorScheme.primaryContainer,
      backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
      child: photoUrl.isEmpty
          ? Text(
              initial,
              style: TextStyle(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w800,
                fontSize: radius * 0.9,
              ),
            )
          : null,
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.label,
    required this.stream,
    required this.onTap,
  });

  final String label;
  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: stream,
          builder: (context, snap) {
            final count = snap.data?.size ?? 0;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  count.toString(),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

// ----------------- Followers / Following placeholders -----------------

class FollowersListPage extends StatelessWidget {
  const FollowersListPage({super.key, required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Followers')),
      body: Center(
        child: Text('Followers list for $uid (TODO)'),
      ),
    );
  }
}

class FollowingListPage extends StatelessWidget {
  const FollowingListPage({super.key, required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Following')),
      body: Center(
        child: Text('Following list for $uid (TODO)'),
      ),
    );
  }
}

// ----------------- REAL: Lists -----------------
// Firestore:
// lists/{listId} fields: ownerUid, title, description, itemCount, createdAt, updatedAt
// lists/{listId}/items/{albumId} optional later

class MyListsPage extends StatelessWidget {
  const MyListsPage({super.key, required this.uid});
  final String uid;

  Future<void> _createList(BuildContext context) async {
    final controller = TextEditingController();

    final title = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create a list'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. Favorite albums',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (title == null || title.trim().isEmpty) return;

    await FirebaseFirestore.instance.collection('lists').add({
      'ownerUid': uid,
      'title': title.trim(),
      'description': '',
      'itemCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('List created')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final query = FirebaseFirestore.instance
        .collection('lists')
        .where('ownerUid', isEqualTo: uid)
        .orderBy('updatedAt', descending: true)
        .limit(200);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your lists'),
        actions: [
          IconButton(
            tooltip: 'Create list',
            icon: const Icon(Icons.add),
            onPressed: () => _createList(context),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.list_alt,
                      size: 64,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'No lists yet',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Create lists to save albums and share collections.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => _createList(context),
                      icon: const Icon(Icons.add),
                      label: const Text('Create your first list'),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final d = docs[i];
              final data = d.data();
              final title = (data['title'] as String?)?.trim();
              final count = (data['itemCount'] as num?)?.toInt() ?? 0;

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.queue_music, color: theme.colorScheme.onPrimaryContainer),
                ),
                title: Text(
                  title?.isNotEmpty == true ? title! : 'Untitled list',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '$count items',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('List detail page coming next')),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

// ----------------- REAL: Latest Reviews -----------------
// Uses your existing structure: albums/{albumId}/reviews/{uid}

class LatestReviewsPage extends StatefulWidget {
  const LatestReviewsPage({super.key, required this.uid});
  final String uid;

  @override
  State<LatestReviewsPage> createState() => _LatestReviewsPageState();
}

class _LatestReviewsPageState extends State<LatestReviewsPage> {
  final Map<String, Future<DocumentSnapshot<Map<String, dynamic>>>> _albumCache = {};

  Future<DocumentSnapshot<Map<String, dynamic>>> _albumDoc(String albumId) {
    return _albumCache.putIfAbsent(
      albumId,
      () => FirebaseFirestore.instance.collection('albums').doc(albumId).get(),
    );
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.month}/${dt.day}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final query = FirebaseFirestore.instance
        .collectionGroup('reviews')
        .where(FieldPath.documentId, isEqualTo: widget.uid)
        .orderBy('updatedAt', descending: true)
        .limit(50);

    return Scaffold(
      appBar: AppBar(title: const Text('Latest reviews')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return Center(
              child: Text(
                'No reviews yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            );
          }

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final reviewDoc = docs[i];
              final data = reviewDoc.data();

              // albums/{albumId}/reviews/{uid}
              final albumId = reviewDoc.reference.parent.parent?.id ?? '';

              final ratingNum = data['rating'];
              final rating = ratingNum is num ? ratingNum.toDouble() : 0.0;
              final text = (data['text'] as String? ?? '').trim();
              final updatedAt = data['updatedAt'] as Timestamp?;
              final timeLabel = _formatDate(updatedAt);

              return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: _albumDoc(albumId),
                builder: (context, albumSnap) {
                  final album = albumSnap.data?.data();
                  final title = (album?['title'] as String?)?.trim();
                  final artist = (album?['primaryArtistName'] as String?)?.trim();
                  final coverUrl = (album?['coverUrl'] as String?)?.trim() ?? '';

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 52,
                        height: 52,
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: coverUrl.isNotEmpty
                            ? Image.network(
                                coverUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const Icon(Icons.album),
                              )
                            : const Icon(Icons.album),
                      ),
                    ),
                    title: Text(
                      title?.isNotEmpty == true ? title! : 'Album',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (artist?.isNotEmpty == true)
                          Text(
                            artist!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              '${rating.toStringAsFixed(1)}/10',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            if (timeLabel.isNotEmpty) ...[
                              Text(
                                ' • ',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                              Text(
                                timeLabel,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (text.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
