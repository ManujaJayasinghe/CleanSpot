import 'ai_config.dart';
import 'capture_result.dart';
import 'validation_result.dart';

/// Whether a report photo is eligible, and a user-facing reason either way.
class ReportDecision {
  const ReportDecision.approved(this.reason) : eligible = true;
  const ReportDecision.rejected(this.reason) : eligible = false;

  final bool eligible;

  /// Short text that can be shown to the user as-is.
  final String reason;
}

/// Pure decision rule. A report is eligible only if ALL of these hold:
/// the AI check succeeded, the GPS fix is good (within 50 m), the photo does
/// not look fake, the AI says it is a breeding site with confidence of at least
/// [kMinConfidence], and it is not a duplicate of a recent nearby report.
///
/// An error result from the AI is never eligible.
ReportDecision decide(
  ValidationResult ai,
  CaptureResult capture,
  bool isDuplicate,
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
  if (isDuplicate) {
    return const ReportDecision.rejected(
      'A report for this spot was already submitted recently. Please choose a '
      'different site.',
    );
  }
  return ReportDecision.approved(ai.reason);
}
