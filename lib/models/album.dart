// lib/models/album.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class Album {
  final String id;
  final String title;
  final String primaryArtistName;
  final String? primaryArtistId;
  final String? firstReleaseDate;
  final String? primaryType;
  final String source;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Album({
    required this.id,
    required this.title,
    required this.primaryArtistName,
    this.primaryArtistId,
    this.firstReleaseDate,
    this.primaryType,
    this.source = 'musicbrainz',
    this.createdAt,
    this.updatedAt,
  });

  factory Album.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) {
      throw Exception('Album document is empty');
    }

    return Album(
      id: doc.id,
      title: data['title'] ?? '',
      primaryArtistName: data['primaryArtistName'] ?? '',
      primaryArtistId: data['primaryArtistId'],
      firstReleaseDate: data['firstReleaseDate'],
      primaryType: data['primaryType'],
      source: data['source'] ?? 'musicbrainz',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'title': title,
      'primaryArtistName': primaryArtistName,
      'primaryArtistId': primaryArtistId ?? '',
      'firstReleaseDate': firstReleaseDate ?? '',
      'primaryType': primaryType ?? '',
      'source': source,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  Album copyWith({
    String? id,
    String? title,
    String? primaryArtistName,
    String? primaryArtistId,
    String? firstReleaseDate,
    String? primaryType,
    String? source,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Album(
      id: id ?? this.id,
      title: title ?? this.title,
      primaryArtistName: primaryArtistName ?? this.primaryArtistName,
      primaryArtistId: primaryArtistId ?? this.primaryArtistId,
      firstReleaseDate: firstReleaseDate ?? this.firstReleaseDate,
      primaryType: primaryType ?? this.primaryType,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class Track {
  final int position;
  final String title;
  final double? durationSeconds;

  Track({
    required this.position,
    required this.title,
    this.durationSeconds,
  });

  factory Track.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) {
      throw Exception('Track document is empty');
    }

    return Track(
      position: data['position'] ?? 0,
      title: data['title'] ?? '',
      durationSeconds: (data['durationSeconds'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'position': position,
      'title': title,
      if (durationSeconds != null) 'durationSeconds': durationSeconds,
    };
  }

  String get formattedDuration {
    if (durationSeconds == null) return '';
    final minutes = (durationSeconds! / 60).floor();
    final seconds = (durationSeconds! % 60).floor();
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}