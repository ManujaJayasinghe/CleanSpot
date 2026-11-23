import 'ai_config.dart';
import 'capture_result.dart';
import 'validation_result.dart';

/// What happens to a checked photo.
enum ReportDecisionKind {
  /// A new site: saved as a new 'valid' report and points are awarded.
  approved,

  /// The photo is fine, but the site is already reported: the existing report
  /// is marked as still present. No new report, no points.
  stillPresent,

  /// Not accepted: saved as a 'rejected' report, no points.
  rejected,
}

/// The decision for one photo, and a user-facing reason.
class ReportDecision {
  const ReportDecision.approved(this.reason)
      : kind = ReportDecisionKind.approved;
  const ReportDecision.stillPresent(this.reason)
      : kind = ReportDecisionKind.stillPresent;
  const ReportDecision.rejected(this.reason)
      : kind = ReportDecisionKind.rejected;

  final ReportDecisionKind kind;

  /// Short text that can be shown to the user as-is.
  final String reason;

  /// A new valid report that earns points.
  bool get eligible => kind == ReportDecisionKind.approved;

  bool get isStillPresent => kind == ReportDecisionKind.stillPresent;
}

/// Shown when a photo is accepted but the site is already reported.
const String kStillPresentMessage =
    "Thanks, this site is already reported. We've marked it as still present.";

/// Pure decision rule.
///
/// A photo passes only if ALL of these hold: the AI check succeeded, the GPS
/// fix is good (within 50 m), the photo does not look fake, and the AI says it
/// is a breeding site with confidence of at least [kMinConfidence]. Otherwise
/// it is rejected.
///
/// A passing photo is [ReportDecisionKind.stillPresent] when
/// [existingReportId] is set (a valid report already covers this spot; see
/// `findStillPresentReport`), and [ReportDecisionKind.approved] otherwise.
///
/// An error result from the AI is never eligible.
ReportDecision decide(
  ValidationResult ai,
  CaptureResult capture,
  String? existingReportId,
) {
  if (ai.isError) {
    return const ReportDecision.rejected(ValidationResult.retryMessage);
  }
  if (!capture.isOk ||
      !isAccuracyAcceptable(capture.accuracyMeters ?? double.infinity)) {
    return const ReportDecision.rejected(
      'We could not confirm where the photo was taken. Please retake it with '
      'location turned on.',
    );
  }
  if (ai.looksFake) {
    return const ReportDecision.rejected(
      'This looks like a picture of a screen, a printout or an edited image. '
      'Please take a live photo of the site.',
    );
  }
  if (!ai.isBreedingSite) {
    return ReportDecision.rejected(ai.reason);
  }
  if (ai.confidence < kMinConfidence) {
    return const ReportDecision.rejected(
      "We couldn't be sure this is a breeding site. Try a clearer, closer "
      'photo of the standing water.',
    );
  }
  if (existingReportId != null) {
    return const ReportDecision.stillPresent(kStillPresentMessage);
  }
  return ReportDecision.approved(ai.reason);
}
