// lib/models/listening_log.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class ListeningLog {
  final String id;
  final String albumId;
  final String albumTitle;
  final String artistName;
  final String? trackId;
  final String? trackTitle;
  final DateTime listenedAt;
  final int durationSeconds;

  ListeningLog({
    required this.id,
    required this.albumId,
    required this.albumTitle,
    required this.artistName,
    this.trackId,
    this.trackTitle,
    required this.listenedAt,
    required this.durationSeconds,
  });

  factory ListeningLog.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) {
      throw Exception('ListeningLog document is empty');
    }

    return ListeningLog(
      id: doc.id,
      albumId: data['albumId'] ?? '',
      albumTitle: data['albumTitle'] ?? '',
      artistName: data['artistName'] ?? '',
      trackId: data['trackId'],
      trackTitle: data['trackTitle'],
      listenedAt: (data['listenedAt'] as Timestamp).toDate(),
      durationSeconds: data['durationSeconds'] ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'albumId': albumId,
        'albumTitle': albumTitle,
        'artistName': artistName,
        if (trackId != null) 'trackId': trackId,
        if (trackTitle != null) 'trackTitle': trackTitle,
        'listenedAt': Timestamp.fromDate(listenedAt),
        'durationSeconds': durationSeconds,
      };

  String get formattedDuration {
    final hours = durationSeconds ~/ 3600;
    final minutes = (durationSeconds % 3600) ~/ 60;
    final seconds = durationSeconds % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m ${seconds}s';
  }
}