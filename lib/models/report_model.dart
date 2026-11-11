import 'package:cloud_firestore/cloud_firestore.dart';

class ReportModel {
  final String id;
  final String uid;
  final String photoId;
  final String imageUrl; // Kept for backwards compatibility / optional direct url
  final double lat;
  final double lng;
  final String type;
  final String description;
  final String status; // 'pending' | 'valid' | 'rejected'
  final String? aiReason;
  final GeoPoint location;
  final String geohash;
  final int confirmationCount;
  final DateTime createdAt;
  final DateTime lastConfirmedAt;

  const ReportModel({
    required this.id,
    required this.uid,
    this.photoId = '',
    this.imageUrl = '',
    required this.lat,
    required this.lng,
    this.type = 'Other',
    this.description = '',
    required this.status,
    this.aiReason,
    required this.location,
    this.geohash = '',
    this.confirmationCount = 0,
    required this.createdAt,
    required this.lastConfirmedAt,
  });

  factory ReportModel.fromMap(String id, Map<String, dynamic> map) {
    final created = (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    final loc = map['location'] as GeoPoint? ??
        (map['lat'] != null && map['lng'] != null
            ? GeoPoint((map['lat'] as num).toDouble(), (map['lng'] as num).toDouble())
            : const GeoPoint(0, 0));

    final latVal = (map['lat'] as num?)?.toDouble() ?? loc.latitude;
    final lngVal = (map['lng'] as num?)?.toDouble() ?? loc.longitude;
    final photoIdVal = map['photoId'] as String? ?? id;
    final imageVal = map['imageUrl'] as String? ?? map['photoUrl'] as String? ?? '';
    final userVal = map['uid'] as String? ?? map['reporterId'] as String? ?? '';

    return ReportModel(
      id: id,
      uid: userVal,
      photoId: photoIdVal,
      imageUrl: imageVal,
      lat: latVal,
      lng: lngVal,
      type: map['type'] as String? ?? 'Other',
      description: map['description'] as String? ?? '',
      status: map['status'] as String? ?? 'pending',
      aiReason: map['aiReason'] as String?,
      location: loc,
      geohash: map['geohash'] as String? ?? '',
      confirmationCount: (map['confirmationCount'] as num?)?.toInt() ?? 0,
      createdAt: created,
      lastConfirmedAt:
          (map['lastConfirmedAt'] as Timestamp?)?.toDate() ?? created,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'photoId': photoId.isNotEmpty ? photoId : id,
      if (imageUrl.isNotEmpty) 'imageUrl': imageUrl,
      'lat': lat,
      'lng': lng,
      'type': type,
      'description': description,
      'status': status,
      if (aiReason != null) 'aiReason': aiReason,
      'location': location,
      'geohash': geohash,
      'confirmationCount': confirmationCount,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastConfirmedAt': Timestamp.fromDate(lastConfirmedAt),
      // Backwards compatibility for existing team code
      'reporterId': uid,
      'photoUrl': imageUrl,
    };
  }

  // Compatibility getters
  String get reporterId => uid;
  String get photoUrl => imageUrl;
}
