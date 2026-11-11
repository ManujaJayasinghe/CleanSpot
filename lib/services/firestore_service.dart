import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/coupon_model.dart';
import '../models/redemption_model.dart';
import '../models/report_model.dart';
import '../models/user_model.dart';

class FirestoreService {
  FirestoreService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _userRef(String uid) =>
      _db.collection('users').doc(uid);

  CollectionReference<Map<String, dynamic>> get _reportsRef =>
      _db.collection('reports');

  CollectionReference<Map<String, dynamic>> get _reportPhotosRef =>
      _db.collection('reportPhotos');

  CollectionReference<Map<String, dynamic>> get _couponsRef =>
      _db.collection('coupons');

  CollectionReference<Map<String, dynamic>> get _redemptionsRef =>
      _db.collection('redemptions');

  /// Creates users/{uid} with 0 points on first sign-in. No-op if it exists.
  Future<void> createUserIfMissing(String uid, String displayName) async {
    final ref = _userRef(uid);
    final snap = await ref.get();
    if (snap.exists) return;
    final user = UserModel(
      uid: uid,
      displayName: displayName,
      pointsBalance: 0,
      createdAt: DateTime.now(),
    );
    await ref.set(user.toMap());
  }

  Stream<UserModel?> watchUser(String uid) {
    return _userRef(uid).snapshots().map(
          (s) => s.exists ? UserModel.fromMap(s.id, s.data()!) : null,
        );
  }

  // ==========================================
  // Part A: Reports & Photos
  // ==========================================

  /// Submits a new hazard report to Firestore:
  /// 1. Creates `reports/{reportId}` with metadata and `photoId: reportId`
  /// 2. If [photoBase64] is provided, saves to `reportPhotos/{reportId}`
  Future<String> submitReport(ReportModel report, {String? photoBase64}) async {
    final reportDoc = _reportsRef.doc();
    final reportId = reportDoc.id;

    final batch = _db.batch();

    final reportData = report.toMap();
    reportData['photoId'] = reportId;
    batch.set(reportDoc, reportData);

    if (photoBase64 != null && photoBase64.isNotEmpty) {
      final photoDoc = _reportPhotosRef.doc(reportId);
      batch.set(photoDoc, {
        'photoBase64': photoBase64,
        'reportId': reportId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
    return reportId;
  }

  /// Fetches a single report's base64 photo on-demand from `reportPhotos/{photoId}`
  Future<String?> getReportPhotoBase64(String photoId) async {
    try {
      final snap = await _reportPhotosRef.doc(photoId).get();
      if (!snap.exists) return null;
      return snap.data()?['photoBase64'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Streams reports submitted by the given user (ordered by creation date desc)
  /// Note: Only reads lightweight metadata from `reports/{id}`, never reads `reportPhotos`.
  Stream<List<ReportModel>> watchUserReports(String uid) {
    return _reportsRef
        .where('uid', isEqualTo: uid)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => ReportModel.fromMap(d.id, d.data()))
              .toList();
          // Sort client-side in case composite index is not yet built
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  /// Streams all valid/approved reports for the risk map.
  /// Never reads `reportPhotos`.
  Stream<List<ReportModel>> watchValidReports() {
    return _reportsRef
        .where('status', isEqualTo: 'valid')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => ReportModel.fromMap(d.id, d.data())).toList());
  }

  // ==========================================
  // Part B: Rewards & Redemptions
  // ==========================================

  /// Streams available coupons for the reward shop
  Stream<List<CouponModel>> watchAvailableCoupons() {
    return _couponsRef
        .where('available', isEqualTo: true)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => CouponModel.fromMap(d.id, d.data()))
              .toList();
          list.sort((a, b) => a.cost.compareTo(b.cost));
          return list;
        });
  }

  /// Streams coupons redeemed by a specific user
  Stream<List<RedemptionModel>> watchUserRedemptions(String uid) {
    return _redemptionsRef
        .where('uid', isEqualTo: uid)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => RedemptionModel.fromMap(d.id, d.data()))
              .toList();
          list.sort((a, b) => b.redeemedAt.compareTo(a.redeemedAt));
          return list;
        });
  }

  /// Atomically redeems a coupon for a user.
  Future<String> redeemCoupon({
    required String uid,
    required CouponModel coupon,
  }) async {
    return await _db.runTransaction<String>((transaction) async {
      final userDocRef = _userRef(uid);
      final couponDocRef = _couponsRef.doc(coupon.id);

      final userSnapshot = await transaction.get(userDocRef);
      if (!userSnapshot.exists) {
        throw Exception('User account not found.');
      }

      final userData = userSnapshot.data()!;
      final currentPoints = (userData['points'] ?? userData['pointsBalance'] as num?)?.toInt() ?? 0;

      if (currentPoints < coupon.cost) {
        throw Exception('not_enough_points');
      }

      final couponSnapshot = await transaction.get(couponDocRef);
      if (couponSnapshot.exists) {
        final cData = couponSnapshot.data()!;
        final isAvailable = cData['available'] is bool ? cData['available'] as bool : true;
        if (!isAvailable) {
          throw Exception('coupon_already_redeemed');
        }
      }

      // 1. Deduct points
      final newPoints = currentPoints - coupon.cost;
      transaction.update(userDocRef, {
        'points': newPoints,
        'pointsBalance': newPoints,
      });

      // 2. Mark coupon as unavailable
      transaction.update(couponDocRef, {
        'available': false,
        'status': 'redeemed',
      });

      // 3. Add to redemptions collection
      final newRedemptionRef = _redemptionsRef.doc();
      final redemption = RedemptionModel(
        id: newRedemptionRef.id,
        uid: uid,
        couponId: coupon.id,
        code: coupon.code,
        title: coupon.title,
        description: coupon.description,
        cost: coupon.cost,
        redeemedAt: DateTime.now(),
      );
      transaction.set(newRedemptionRef, redemption.toMap());

      return coupon.code;
    });
  }
}
