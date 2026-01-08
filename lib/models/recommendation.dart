// lib/models/recommendation.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class Recommendation {
  final String id;
  final String fromUserId;
  final String fromUserName;
  final String toUserId;
  final String albumId;
  final String albumTitle;
  final String artistName;
  final String? message;
  final DateTime createdAt;
  final bool isRead;

  Recommendation({
    required this.id,
    required this.fromUserId,
    required this.fromUserName,
    required this.toUserId,
    required this.albumId,
    required this.albumTitle,
    required this.artistName,
    this.message,
    required this.createdAt,
    this.isRead = false,
  });

  factory Recommendation.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) {
      throw Exception('Recommendation document is empty');
    }

    return Recommendation(
      id: doc.id,
      fromUserId: data['fromUserId'] ?? '',
      fromUserName: data['fromUserName'] ?? '',
      toUserId: data['toUserId'] ?? '',
      albumId: data['albumId'] ?? '',
      albumTitle: data['albumTitle'] ?? '',
      artistName: data['artistName'] ?? '',
      message: data['message'],
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      isRead: data['isRead'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'fromUserId': fromUserId,
        'fromUserName': fromUserName,
        'toUserId': toUserId,
        'albumId': albumId,
        'albumTitle': albumTitle,
        'artistName': artistName,
        if (message != null) 'message': message,
        'createdAt': Timestamp.fromDate(createdAt),
        'isRead': isRead,
      };
}