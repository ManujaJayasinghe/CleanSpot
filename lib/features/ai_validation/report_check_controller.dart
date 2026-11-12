import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

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
    Future<bool> Function(double latitude, double longitude)? duplicateCheck,
    DateTime Function()? now,
  })  : _validate = validate ?? AiValidationService().validatePhoto,
        _isDuplicate = duplicateCheck ?? duplicates.isDuplicate,
        _now = now ?? DateTime.now;

  static const retryMessage =
      "We couldn't check your photo. Please check your connection and try "
      'again.';

  final Future<ValidationResult> Function(Uint8List) _validate;
  final Future<bool> Function(double, double) _isDuplicate;
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

    final total = Stopwatch()..start();
    onPhase?.call(CheckPhase.validating);
    final ValidationResult validation;
    final validateTimer = Stopwatch()..start();
    try {
      validation = await _validate(bytes);
    } catch (e) {
      return ReportCheckResult.failure(retryMessage, 'validation threw: $e');
    }
    if (kDebugMode) {
      debugPrint('AI TIMING: validate (App Check + Gemini + parse)='
          '${validateTimer.elapsedMilliseconds} ms');
    }
    if (validation.isError) {
      return ReportCheckResult.failure(retryMessage, validation.error);
    }

    onPhase?.call(CheckPhase.checkingDuplicates);
    final bool duplicate;
    final duplicateTimer = Stopwatch()..start();
    try {
      duplicate = await _isDuplicate(capture.latitude!, capture.longitude!);
    } catch (e) {
      return ReportCheckResult.failure(
        retryMessage,
        'duplicate check threw: $e',
      );
    }
    if (kDebugMode) {
      debugPrint('AI TIMING: duplicate check='
          '${duplicateTimer.elapsedMilliseconds} ms');
      debugPrint('AI TIMING: total=${total.elapsedMilliseconds} ms');
      debugPrint('AI RESULT: isBreedingSite=${validation.isBreedingSite} '
          'category=${validation.category.wireValue} '
          'confidence=${validation.confidence} looksFake=${validation.looksFake} '
          'reason="${validation.reason}"');
    }

    return ReportCheckResult.success(
      ReportOutcome(
        capture: capture,
        validation: validation,
        isDuplicate: duplicate,
        decision: decide(validation, capture, duplicate),
        checkedAt: _now(),
      ),
    );
  }
}
