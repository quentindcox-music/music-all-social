import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_providers.dart';

/// Fetch displayNames for a set of uids, keyed by a stable string "uid1|uid2|...".
/// Uses whereIn(FieldPath.documentId) and chunks to Firestore's limit (30).
final displayNameMapProvider =
    FutureProvider.family<Map<String, String>, String>((ref, uidsKey) async {
  final firestore = ref.watch(firestoreProvider);

  final uids = uidsKey
      .split('|')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet()
      .toList()
    ..sort();

  if (uids.isEmpty) return <String, String>{};

  const chunkSize = 30;
  final out = <String, String>{};

  for (int i = 0; i < uids.length; i += chunkSize) {
    final chunk = uids.sublist(
      i,
      (i + chunkSize) > uids.length ? uids.length : (i + chunkSize),
    );

    final snap = await firestore
        .collection('users')
        .where(FieldPath.documentId, whereIn: chunk)
        .get();

    for (final doc in snap.docs) {
      final name = (doc.data()['displayName'] as String?)?.trim();
      if (name != null && name.isNotEmpty) {
        out[doc.id] = name;
      }
    }
  }

  return out;
});
