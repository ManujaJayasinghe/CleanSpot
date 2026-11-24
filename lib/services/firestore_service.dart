import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/coupon_model.dart';
import '../models/redemption_model.dart';
import '../models/report_model.dart';
import '../models/user_model.dart';
import 'report_write_plan.dart';

class FirestoreService {
  FirestoreService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseFirestore.instance,
        _authOverride = auth;

  final FirebaseFirestore _db;
  final FirebaseAuth? _authOverride;

  /// The signed-in user's uid (looked up when needed, so tests that never use
  /// it do not need Firebase auth).
  String? get _currentUid =>
      (_authOverride ?? FirebaseAuth.instance).currentUser?.uid;

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

  /// Marks an existing report as still present (the "still present" rule):
  /// adds one to `confirmationCount` and sets `lastConfirmedAt` to server time.
  /// Nothing else is written: no new report, no photo and no points.
  ///
  /// [confirmationId] identifies this one confirmation (create it once per
  /// outcome, like a report id). Runs in a transaction that reads the report
  /// from the server first: if it already carries this [confirmationId] (an
  /// earlier attempt succeeded but its reply was lost), nothing is written, so
  /// a retry never counts twice. Throws on any failure, including offline and
  /// a report that no longer exists.
  Future<void> markReportStillPresent(
    String reportId, {
    required String confirmationId,
  }) async {
    final reportRef = _reportsRef.doc(reportId);
    final update = buildStillPresentUpdate(confirmationId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(reportRef);
      if (!snap.exists) {
        throw StateError('Report $reportId no longer exists.');
      }
      if (snap.data()?['lastConfirmationId'] == confirmationId) return;
      tx.update(reportRef, update);
    });
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

  /// Marks a report as cleared (the site was dealt with). For authority and
  /// admin dashboards only; firestore.rules rejects anyone else.
  ///
  /// In ONE batch: `reports/{id}` becomes status 'cleared' with `clearedBy`
  /// (the signed-in uid) and a server-time `clearedAt`, and the
  /// `reportPhotos/{id}` photo is deleted. A cleared report is no longer
  /// 'valid', so it leaves the map and is not found by the still-present check.
  /// Throws on any failure, including a report that is not currently 'valid'.
  Future<void> markReportCleared(String reportId) async {
    final uid = _currentUid;
    if (uid == null) throw StateError('Not signed in.');
    final batch = _db.batch()
      ..update(_reportsRef.doc(reportId), buildClearedUpdate(uid))
      ..delete(_reportPhotosRef.doc(reportId));
    await batch.commit();
    _photoCache.remove(reportId);
  }

  // ==========================================
  // Part C: Admin
  // ==========================================

  /// Sets a user's role: 'user', 'admin' or 'authority'. Admin only.
  Future<void> setUserRole(String uid, String role) async {
    if (!kUserRoles.contains(role)) {
      throw ArgumentError.value(role, 'role', 'Must be one of $kUserRoles.');
    }
    await _userRef(uid).update({'role': role});
  }

  /// Blocks or unblocks a user. A blocked user is signed out of the app and the
  /// rules stop them saving anything. Admin only.
  Future<void> setUserBlocked(String uid, bool blocked) async {
    await _userRef(uid).update({'blocked': blocked});
  }

  /// Streams every user (name order), for the admin dashboard. Admin only.
  Stream<List<UserModel>> watchAllUsers() {
    return _db.collection('users').snapshots().map((snap) {
      final list = snap.docs
          .map((d) => UserModel.fromMap(d.id, d.data()))
          .toList();
      list.sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
      return list;
    });
  }

  /// Adds an available coupon to the reward shop. Admin only. Returns its id.
  Future<String> addCoupon({
    required String title,
    required String description,
    required int cost,
    required String code,
    int stock = 1,
    List<String>? codes,
  }) async {
    if (title.trim().isEmpty) {
      throw ArgumentError('A coupon needs a title.');
    }
    final effectiveCodes = (codes != null && codes.isNotEmpty)
        ? codes.map((c) => c.trim()).where((c) => c.isNotEmpty).toList()
        : [code.trim()];
    if (effectiveCodes.isEmpty || effectiveCodes.every((c) => c.isEmpty)) {
      throw ArgumentError('A coupon needs at least one code.');
    }
    if (cost < 0) throw ArgumentError.value(cost, 'cost', 'Cannot be negative.');
    final effectiveStock = stock > 0 ? stock : effectiveCodes.length;
    final primaryCode = code.trim().isNotEmpty ? code.trim() : effectiveCodes.first;

    final doc = _couponsRef.doc();
    await doc.set(
      CouponModel(
        id: doc.id,
        title: title.trim(),
        description: description.trim(),
        cost: cost,
        code: primaryCode,
        available: effectiveStock > 0,
        stock: effectiveStock,
        codes: effectiveCodes,
      ).toMap(),
    );
    return doc.id;
  }

  /// Deletes a coupon. Admin only.
  Future<void> removeCoupon(String couponId) async {
    await _couponsRef.doc(couponId).delete();
  }

  /// Streams all reports across all statuses, for admin statistics.
  /// Admin only. Never reads `reportPhotos`.
  Stream<List<ReportModel>> watchAllReports() {
    return _reportsRef.snapshots().map(
      (snap) => snap.docs
          .map((d) => ReportModel.fromMap(d.id, d.data()))
          .toList(),
    );
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

  /// Streams coupons for the reward shop (both in-stock and out-of-stock items)
  Stream<List<CouponModel>> watchAvailableCoupons() {
    return _couponsRef
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => CouponModel.fromMap(d.id, d.data()))
              .toList();
          // Sort by stock status (in-stock first), then by cost
          list.sort((a, b) {
            if (a.hasStock != b.hasStock) {
              return a.hasStock ? -1 : 1;
            }
            return a.cost.compareTo(b.cost);
          });
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
  /// Supports both multi-code pool (with stock) and single-code legacy coupons.
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
      if (!couponSnapshot.exists) {
        throw Exception('coupon_not_found');
      }

      final cData = couponSnapshot.data()!;
      final isAvailable = cData['available'] is bool ? cData['available'] as bool : true;
      if (!isAvailable) {
        throw Exception('coupon_already_redeemed');
      }

      // Check stock and codes array if present
      final rawCodes = cData['codes'];
      List<String> poolCodes = [];
      if (rawCodes is List) {
        poolCodes = rawCodes.map((e) => e.toString()).toList();
      }

      int currentStock = (cData['stock'] as num?)?.toInt() ??
          (poolCodes.isNotEmpty ? poolCodes.length : 1);

      if (currentStock <= 0) {
        throw Exception('coupon_already_redeemed');
      }

      // Determine which code to assign
      String codeToIssue;
      if (poolCodes.isNotEmpty) {
        codeToIssue = poolCodes.removeAt(0); // Pop first code
      } else {
        codeToIssue = cData['code'] as String? ?? coupon.code;
      }

      final newStock = currentStock - 1;
      final stillAvailable = newStock > 0 && (poolCodes.isEmpty ? newStock > 0 : poolCodes.isNotEmpty);

      // 1. Deduct points
      final newPoints = currentPoints - coupon.cost;
      transaction.update(userDocRef, {
        'points': newPoints,
        'pointsBalance': newPoints,
      });

      // 2. Update coupon stock and available status
      final Map<String, dynamic> couponUpdates = {
        'stock': newStock,
        'available': stillAvailable,
        'status': stillAvailable ? 'available' : 'redeemed',
      };
      if (rawCodes is List) {
        couponUpdates['codes'] = poolCodes;
      }
      transaction.update(couponDocRef, couponUpdates);

      // 3. Add to redemptions collection
      final newRedemptionRef = _redemptionsRef.doc();
      final redemption = RedemptionModel(
        id: newRedemptionRef.id,
        uid: uid,
        couponId: coupon.id,
        code: codeToIssue,
        title: coupon.title,
        description: coupon.description,
        cost: coupon.cost,
        redeemedAt: DateTime.now(),
      );
      transaction.set(newRedemptionRef, redemption.toMap());

      return codeToIssue;
    });
  }
}
