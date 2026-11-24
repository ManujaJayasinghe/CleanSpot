import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/report_model.dart';

/// Points added to the reporter for each report saved with status 'valid'.
/// This is the only place the amount is defined.
const int kPointsPerValidReport = 10;

/// Status of an approved report, and of one the AI rejected.
const String reportStatusValid = 'valid';
const String reportStatusRejected = 'rejected';

/// What to write for one report. Built by [buildReportWritePlan] so the rules
/// (what a valid and a rejected report each write) can be tested without
/// Firebase; `FirestoreService.submitReport` writes the plan in ONE batch.
class ReportWritePlan {
  const ReportWritePlan({
    required this.reportData,
    required this.photoData,
    required this.userPointsData,
    required this.pointsAwarded,
  });

  /// The `reports/{id}` document. Never contains the photo.
  final Map<String, dynamic> reportData;

  /// The `reportPhotos/{id}` document, or null when there is no photo to store.
  final Map<String, dynamic>? photoData;

  /// The merge written to `users/{uid}`, or null when no points are awarded.
  final Map<String, dynamic>? userPointsData;

  /// Points this plan adds to the user (0 when [userPointsData] is null).
  final int pointsAwarded;
}

/// A 'valid' report writes: reports + reportPhotos + a points increment.
/// A 'rejected' report writes only the reports document (with the AI fields
/// and geohash): no photo and no points.
///
/// Throws [ArgumentError] for an unknown status, a missing uid, or a valid
/// report without a photo.
ReportWritePlan buildReportWritePlan(
  ReportModel report,
  String reportId, {
  String? photoBase64,
  int points = kPointsPerValidReport,
}) {
  if (report.uid.isEmpty) {
    throw ArgumentError('A report needs the uid of the signed-in user.');
  }

  final reportData = report.toMap()
    // Server time, not the phone's clock (the duplicate check's 7-day window
    // relies on it).
    ..['createdAt'] = FieldValue.serverTimestamp();

  switch (report.status) {
    case reportStatusValid:
      if (photoBase64 == null || photoBase64.isEmpty) {
        throw ArgumentError('A valid report needs its photo.');
      }
      reportData['photoId'] = reportId;
      return ReportWritePlan(
        reportData: reportData,
        photoData: {
          'photoBase64': photoBase64,
          'reportId': reportId,
          'createdAt': FieldValue.serverTimestamp(),
        },
        // UserModel reads `points` first and falls back to `pointsBalance`
        // (redeemCoupon updates both), so both are incremented to stay equal.
        userPointsData: {
          'pointsBalance': FieldValue.increment(points),
          'points': FieldValue.increment(points),
        },
        pointsAwarded: points,
      );
    case reportStatusRejected:
      // No photo is stored, so there is nothing for photoId to point at.
      reportData['photoId'] = '';
      return ReportWritePlan(
        reportData: reportData,
        photoData: null,
        userPointsData: null,
        pointsAwarded: 0,
      );
    default:
      throw ArgumentError.value(
        report.status,
        'status',
        "Only 'valid' and 'rejected' reports are saved by the AI flow.",
      );
  }
}
