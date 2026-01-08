import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserService {
  static final _db = FirebaseFirestore.instance;

static Future<void> upsertUser(User user) async {
  final ref = _db.collection('users').doc(user.uid);

  await ref.set({
    'uid': user.uid,
    'createdAt': FieldValue.serverTimestamp(),
    'lastSeenAt': FieldValue.serverTimestamp(),

    // defaults (can be edited later)
    'displayName': user.isAnonymous ? 'New listener' : (user.displayName ?? 'Listener'),
    'photoUrl': user.photoURL ?? '',
  }, SetOptions(merge: true));
}
}