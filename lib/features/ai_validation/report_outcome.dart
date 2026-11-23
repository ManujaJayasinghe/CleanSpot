import 'capture_result.dart';
import 'report_decision.dart';
import 'validation_result.dart';

/// Everything the check produced for one photo. Handed to
/// [ReportDecisionCallback] when a final decision is made.
///
/// Nothing here has been saved anywhere: whoever owns report submission decides
/// what to store and whether to award points.
class ReportOutcome {
  const ReportOutcome({
    required this.capture,
    required this.validation,
    required this.existingReportId,
    required this.decision,
    required this.checkedAt,
  });

  /// The live photo and GPS fix that were checked (always a successful capture).
  final CaptureResult capture;

  /// The AI's verdict (never an error; errors are reported as a failed check).
  final ValidationResult validation;

  /// The valid report this photo is marked as "still present" on, or null
  /// for a new site.
  final String? existingReportId;

  final ReportDecision decision;
  final DateTime checkedAt;

  /// A new valid report that earns points.
  bool get eligible => decision.eligible;

  /// The site is already reported: update [existingReportId], save nothing new.
  bool get isStillPresent => decision.isStillPresent;
}

/// Called once per completed check with a final decision (approved, still
/// present or rejected).
/// It is NOT called when the check itself failed (network error and so on);
/// the user is offered a retry instead.
typedef ReportDecisionCallback = void Function(ReportOutcome outcome);
