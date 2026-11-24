import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/coupon_model.dart';
import '../models/redemption_model.dart';
import '../models/report_model.dart';
import '../models/user_model.dart';
import 'report_write_plan.dart';

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

  /// A fresh report id. Create it once per outcome and pass it to every attempt
  /// to save that report, so a retry can never create a second report.
  String newReportId() => _reportsRef.doc().id;

  /// Saves one AI-checked report. Throws on any failure (never swallows).
  ///
  /// Everything is written in ONE batch, so it all succeeds or none of it does:
  /// - status 'valid': `reports/{id}` + `reportPhotos/{id}` (the photo is stored
  ///   only here) + `users/{uid}` points incremented by [kPointsPerValidReport]
  /// - status 'rejected': only `reports/{id}`; no photo and no points
  ///
  /// Saving again with the same [reportId] (a retry) writes nothing and awards
  /// no second set of points if the report already exists on the server.
  /// Returns the report id.
  Future<String> submitReport(
    ReportModel report, {
    String? photoBase64,
    String? reportId,
  }) async {
    final reportRef = _reportsRef.doc(reportId ?? newReportId());
    final plan = buildReportWritePlan(
      report,
      reportRef.id,
      photoBase64: photoBase64,
    );

    // Already saved by an earlier attempt whose reply was lost: do not write
    // (or award points) a second time. Read from the server only, so being
    // offline fails here instead of queueing a write that could land later.
    final existing = await reportRef.get(
      const GetOptions(source: Source.server),
    );
    if (existing.exists) return reportRef.id;

    final batch = _db.batch()..set(reportRef, plan.reportData);
    final photoData = plan.photoData;
    if (photoData != null) {
      batch.set(_reportPhotosRef.doc(reportRef.id), photoData);
    }
    final pointsData = plan.userPointsData;
    if (pointsData != null) {
      batch.set(_userRef(report.uid), pointsData, SetOptions(merge: true));
    }
    await batch.commit();
    return reportRef.id;
  }

  // Photos already loaded this session, and loads in progress, shared by every
  // FirestoreService instance.
  static final Map<String, Uint8List> _photoCache = {};
  static final Map<String, Future<Uint8List?>> _photoLoads = {};

  /// Loads one report's photo from `reportPhotos/{reportId}.photoBase64`.
  ///
  /// Only ever called for a single report that is on screen. Lists, the map and
  /// the duplicate check read `reports` only. Cached in memory after the first
  /// load. Returns null if there is no photo or it could not be loaded (not
  /// cached, so a later call tries again).
  Future<Uint8List?> getReportPhoto(String reportId) {
    final cached = _photoCache[reportId];
    if (cached != null) return Future.value(cached);
    return _photoLoads[reportId] ??= _loadReportPhoto(reportId);
  }

  Future<Uint8List?> _loadReportPhoto(String reportId) async {
    try {
      final snap = await _reportPhotosRef.doc(reportId).get();
      final stored = snap.data()?['photoBase64'];
      if (!snap.exists || stored is! String || stored.isEmpty) return null;
      final payload = stored.contains(',') ? stored.split(',').last : stored;
      final bytes = base64Decode(payload.trim());
      _photoCache[reportId] = bytes;
      return bytes;
    } catch (_) {
      return null;
    } finally {
      _photoLoads.remove(reportId);
    }
  }

  /// Forgets cached photos (used by tests).
  static void clearPhotoCache() {
    _photoCache.clear();
    _photoLoads.clear();
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
