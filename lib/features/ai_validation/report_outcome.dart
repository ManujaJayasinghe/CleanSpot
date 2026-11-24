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
    required this.isDuplicate,
    required this.decision,
    required this.checkedAt,
  });

  /// The live photo and GPS fix that were checked (always a successful capture).
  final CaptureResult capture;

  /// The AI's verdict (never an error; errors are reported as a failed check).
  final ValidationResult validation;

  final bool isDuplicate;
  final ReportDecision decision;
  final DateTime checkedAt;

  bool get eligible => decision.eligible;
}

/// Called once per completed check with a final approved or rejected decision.
/// It is NOT called when the check itself failed (network error and so on);
/// the user is offered a retry instead.
typedef ReportDecisionCallback = void Function(ReportOutcome outcome);
