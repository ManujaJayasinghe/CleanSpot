import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/report_model.dart';

/// Points added to the reporter for each report saved with status 'valid'.
/// This is the only place the amount is defined.
const int kPointsPerValidReport = 10;

/// Status of an approved report, of one the AI rejected, and of one an
/// authority or admin marked as cleared (the site was dealt with).
const String reportStatusValid = 'valid';
const String reportStatusRejected = 'rejected';
const String reportStatusCleared = 'cleared';

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

/// The update written to an existing `reports/{id}` when a new photo marks the
/// site as still present: one more confirmation, a server-time
/// `lastConfirmedAt`, and [confirmationId] so a retry of the same confirmation
/// can be recognised and skipped. No new report, no photo, no points.
Map<String, dynamic> buildStillPresentUpdate(String confirmationId) {
  if (confirmationId.isEmpty) {
    throw ArgumentError('A still-present update needs a confirmation id.');
  }
  return {
    'confirmationCount': FieldValue.increment(1),
    'lastConfirmedAt': FieldValue.serverTimestamp(),
    'lastConfirmationId': confirmationId,
  };
}

/// The update written to `reports/{id}` when an authority or admin marks the
/// site as cleared: status 'cleared', who did it ([clearedBy], a uid) and a
/// server-time `clearedAt`. The report keeps its other fields; its photo
/// document is deleted separately. A cleared report is no longer 'valid', so it
/// leaves the map and does not count for the still-present check.
Map<String, dynamic> buildClearedUpdate(String clearedBy) {
  if (clearedBy.isEmpty) {
    throw ArgumentError('A cleared report needs the uid of who cleared it.');
  }
  return {
    'status': reportStatusCleared,
    'clearedBy': clearedBy,
    'clearedAt': FieldValue.serverTimestamp(),
  };
}
