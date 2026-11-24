import 'package:cloud_firestore/cloud_firestore.dart';

import '../features/ai_validation/validation_result.dart';

class ReportModel {
  final String id;
  final String uid;

  /// Id of the `reportPhotos` document. The photo itself is never stored in the
  /// `reports` document; load it with `FirestoreService.getReportPhoto`.
  final String photoId;

  /// Only filled when reading old documents that still hold the photo
  /// (`imageUrl` / `photoUrl`). Never written back by [toMap].
  final String imageUrl;
  final double lat;
  final double lng;

  /// Site type as a wire value: stagnant_water, tire, blocked_drain,
  /// container, other or none (old documents are normalized when read).
  final String type;
  final String description;
  final String status; // 'pending' | 'valid' | 'rejected' | 'cleared'
  final GeoPoint location;
  final String geohash;
  final int confirmationCount;
  final DateTime createdAt;
  final DateTime lastConfirmedAt;

  /// Set by the AI photo check; null on reports created before it existed.
  final String? aiCategory;
  final double? aiConfidence;
  final String? aiReason;

  /// Set when an authority or admin marks the site as cleared (status
  /// 'cleared'): who did it and when. Null otherwise.
  final String? clearedBy;
  final DateTime? clearedAt;

  const ReportModel({
    required this.id,
    required this.uid,
    this.photoId = '',
    this.imageUrl = '',
    required this.lat,
    required this.lng,
    this.type = 'other',
    this.description = '',
    required this.status,
    required this.location,
    this.geohash = '',
    this.confirmationCount = 0,
    required this.createdAt,
    required this.lastConfirmedAt,
    this.aiCategory,
    this.aiConfidence,
    this.aiReason,
    this.clearedBy,
    this.clearedAt,
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
      type: SiteCategory.normalizeStored(map['type'] as String?) ?? 'other',
      description: map['description'] as String? ?? '',
      status: map['status'] as String? ?? 'pending',
      location: loc,
      geohash: map['geohash'] as String? ?? '',
      confirmationCount: (map['confirmationCount'] as num?)?.toInt() ?? 0,
      createdAt: created,
      lastConfirmedAt:
          (map['lastConfirmedAt'] as Timestamp?)?.toDate() ?? created,
      aiCategory: SiteCategory.normalizeStored(map['aiCategory'] as String?),
      aiConfidence: (map['aiConfidence'] as num?)?.toDouble(),
      aiReason: map['aiReason'] as String?,
      clearedBy: map['clearedBy'] as String?,
      clearedAt: (map['clearedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'photoId': photoId.isNotEmpty ? photoId : id,
      'lat': lat,
      'lng': lng,
      'type': type,
      'description': description,
      'status': status,
      'location': location,
      'geohash': geohash,
      'confirmationCount': confirmationCount,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastConfirmedAt': Timestamp.fromDate(lastConfirmedAt),
      if (aiCategory != null) 'aiCategory': aiCategory,
      if (aiConfidence != null) 'aiConfidence': aiConfidence,
      if (aiReason != null) 'aiReason': aiReason,
      if (clearedBy != null) 'clearedBy': clearedBy,
      if (clearedAt != null) 'clearedAt': Timestamp.fromDate(clearedAt!),
      // Backwards compatibility for existing team code
      'reporterId': uid,
    };
  }

  // Compatibility getters
  String get reporterId => uid;
  String get photoUrl => imageUrl;
}
