import 'dart:typed_data';

import 'ai_validation_service.dart';
import 'capture_result.dart';
import 'duplicate_check.dart' as duplicates;
import 'report_decision.dart';
import 'report_outcome.dart';
import 'validation_result.dart';

/// Which part of the check is running (for the progress checklist).
enum CheckPhase { validating, checkingDuplicates }

/// Result of running the whole check: either a [ReportOutcome] or a failure
/// that should be offered as a retry. A failure is never a verified report.
class ReportCheckResult {
  const ReportCheckResult.success(ReportOutcome this.outcome)
      : userMessage = null,
        detail = null;

  const ReportCheckResult.failure(String this.userMessage, [this.detail])
      : outcome = null;

  final ReportOutcome? outcome;

  /// Friendly text for the retry screen.
  final String? userMessage;

  /// Technical detail for logs only.
  final String? detail;

  bool get isSuccess => outcome != null;
}

/// Runs validatePhoto, then the duplicate check, then decide().
///
/// This keeps the check logic out of the Report screen. Dependencies can be
/// replaced (for tests) through the constructor.
class ReportCheckController {
  ReportCheckController({
    Future<ValidationResult> Function(Uint8List jpegBytes)? validate,
    Future<String?> Function(double latitude, double longitude)?
        stillPresentCheck,
    DateTime Function()? now,
  })  : _validate = validate ?? AiValidationService().validatePhoto,
        _findExisting = stillPresentCheck ?? duplicates.findStillPresentReport,
        _now = now ?? DateTime.now;

  static const retryMessage =
      "We couldn't check your photo. Please check your connection and try "
      'again.';

  final Future<ValidationResult> Function(Uint8List) _validate;
  final Future<String?> Function(double, double) _findExisting;
  final DateTime Function() _now;

  /// Never throws. [onPhase] reports progress.
  Future<ReportCheckResult> check(
    CaptureResult capture, {
    void Function(CheckPhase phase)? onPhase,
  }) async {
    final bytes = capture.jpegBytes;
    if (!capture.isOk || bytes == null) {
      return const ReportCheckResult.failure(
        'There is no valid photo to check. Please take a photo first.',
        'capture was not successful',
      );
    }

    onPhase?.call(CheckPhase.validating);
    final ValidationResult validation;
    try {
      validation = await _validate(bytes);
    } catch (e) {
      return ReportCheckResult.failure(retryMessage, 'validation threw: $e');
    }
    if (validation.isError) {
      return ReportCheckResult.failure(retryMessage, validation.error);
    }

    onPhase?.call(CheckPhase.checkingDuplicates);
    final String? existingReportId;
    try {
      existingReportId =
          await _findExisting(capture.latitude!, capture.longitude!);
    } catch (e) {
      return ReportCheckResult.failure(
        retryMessage,
        'duplicate check threw: $e',
      );
    }

    return ReportCheckResult.success(
      ReportOutcome(
        capture: capture,
        validation: validation,
        existingReportId: existingReportId,
        decision: decide(validation, capture, existingReportId),
        checkedAt: _now(),
      ),
    );
  }
}
