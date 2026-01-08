// lib/services/listening_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/listening_log.dart';

class ListeningService {
  static final _db = FirebaseFirestore.instance;

  /// Log a listening session
  static Future<void> logListen({
    required String uid,
    required String albumId,
    required String albumTitle,
    required String artistName,
    String? trackId,
    String? trackTitle,
    required int durationSeconds,
  }) async {
    try {
      await _db.collection('users').doc(uid).collection('listeningLogs').add({
        'albumId': albumId,
        'albumTitle': albumTitle,
        'artistName': artistName,
        if (trackId != null) 'trackId': trackId,
        if (trackTitle != null) 'trackTitle': trackTitle,
        'listenedAt': FieldValue.serverTimestamp(),
        'durationSeconds': durationSeconds,
      });
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('⚠️ Failed to log listen: $e\n$st');
      }
    }
  }

  /// Get total listening minutes for a user
  static Future<int> getTotalMinutes(String uid) async {
    try {
      final snapshot = await _db
          .collection('users')
          .doc(uid)
          .collection('listeningLogs')
          .get();

      int totalSeconds = 0;
      for (final doc in snapshot.docs) {
        totalSeconds += (doc.data()['durationSeconds'] as int?) ?? 0;
      }
      return totalSeconds ~/ 60;
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Failed to get total minutes: $e');
      return 0;
    }
  }

  /// Get listening minutes for a specific time period
  static Future<int> getMinutesInPeriod(
    String uid, {
    required DateTime start,
    required DateTime end,
  }) async {
    try {
      final snapshot = await _db
          .collection('users')
          .doc(uid)
          .collection('listeningLogs')
          .where('listenedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('listenedAt', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .get();

      int totalSeconds = 0;
      for (final doc in snapshot.docs) {
        totalSeconds += (doc.data()['durationSeconds'] as int?) ?? 0;
      }
      return totalSeconds ~/ 60;
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Failed to get period minutes: $e');
      return 0;
    }
  }

  /// Get recent listening history
  static Future<List<ListeningLog>> getRecentHistory(
    String uid, {
    int limit = 20,
  }) async {
    try {
      final snapshot = await _db
          .collection('users')
          .doc(uid)
          .collection('listeningLogs')
          .orderBy('listenedAt', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs.map((d) => ListeningLog.fromFirestore(d)).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Failed to get history: $e');
      return [];
    }
  }

  /// Get top artists by listening time
  static Future<Map<String, int>> getTopArtists(String uid, {int limit = 10}) async {
    try {
      final snapshot = await _db
          .collection('users')
          .doc(uid)
          .collection('listeningLogs')
          .get();

      final Map<String, int> artistMinutes = {};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final artist = data['artistName'] as String? ?? 'Unknown';
        final seconds = (data['durationSeconds'] as int?) ?? 0;
        artistMinutes[artist] = (artistMinutes[artist] ?? 0) + seconds;
      }

      // Sort by minutes and take top N
      final sorted = artistMinutes.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      return Map.fromEntries(sorted.take(limit));
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Failed to get top artists: $e');
      return {};
    }
  }
}