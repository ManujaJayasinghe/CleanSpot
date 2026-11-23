import 'dart:typed_data';

import 'package:clean_spot/features/ai_validation/capture_result.dart';
import 'package:clean_spot/features/ai_validation/report_check_controller.dart';
import 'package:clean_spot/features/ai_validation/validation_result.dart';
import 'package:flutter_test/flutter_test.dart';

final _jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);

CaptureResult goodCapture() => CaptureResult.success(
      jpegBytes: _jpeg,
      latitude: 7.2906,
      longitude: 80.6337,
      accuracyMeters: 8,
    );

const ValidationResult siteResult = ValidationResult(
  isBreedingSite: true,
  category: SiteCategory.stagnantWater,
  confidence: 0.95,
  looksFake: false,
  reason: 'Standing water in a pot.',
);

final fixedTime = DateTime(2026, 11, 10, 9, 41);

void main() {
  test('approves a good photo and reports both phases in order', () async {
    final phases = <CheckPhase>[];
    Uint8List? validated;
    double? dupLat;
    final controller = ReportCheckController(
      validate: (bytes) async {
        validated = bytes;
        return siteResult;
      },
      stillPresentCheck: (lat, lng) async {
        dupLat = lat;
        return null;
      },
      now: () => fixedTime,
    );

    final result = await controller.check(goodCapture(), onPhase: phases.add);

    expect(result.isSuccess, isTrue);
    expect(phases, [CheckPhase.validating, CheckPhase.checkingDuplicates]);
    expect(validated, _jpeg);
    expect(dupLat, 7.2906);
    final outcome = result.outcome!;
    expect(outcome.eligible, isTrue);
    expect(outcome.isStillPresent, isFalse);
    expect(outcome.existingReportId, isNull);
    expect(outcome.validation.category, SiteCategory.stagnantWater);
    expect(outcome.decision.reason, 'Standing water in a pot.');
    expect(outcome.checkedAt, fixedTime);
    expect(outcome.capture.latitude, 7.2906);
  });

  test('an already reported site is a still-present outcome', () async {
    final controller = ReportCheckController(
      validate: (_) async => siteResult,
      stillPresentCheck: (_, _) async => 'existing-1',
    );
    final result = await controller.check(goodCapture());
    expect(result.isSuccess, isTrue);
    final outcome = result.outcome!;
    expect(outcome.eligible, isFalse, reason: 'no new report, no points');
    expect(outcome.isStillPresent, isTrue);
    expect(outcome.existingReportId, 'existing-1');
  });

  test('an AI rejection is a rejected outcome with the AI reason', () async {
    final controller = ReportCheckController(
      validate: (_) async => const ValidationResult(
        isBreedingSite: false,
        category: SiteCategory.none,
        confidence: 0.9,
        looksFake: false,
        reason: 'This is an indoor room.',
      ),
      stillPresentCheck: (_, _) async => null,
    );
    final result = await controller.check(goodCapture());
    expect(result.isSuccess, isTrue);
    expect(result.outcome!.eligible, isFalse);
    expect(result.outcome!.decision.reason, 'This is an indoor room.');
  });

  group('failures are retryable and never verified', () {
    test('AI error result', () async {
      var dupCalled = false;
      final controller = ReportCheckController(
        validate: (_) async => const ValidationResult.error('quota exceeded'),
        stillPresentCheck: (_, _) async {
          dupCalled = true;
          return null;
        },
      );
      final result = await controller.check(goodCapture());
      expect(result.isSuccess, isFalse);
      expect(result.outcome, isNull);
      expect(result.userMessage, ReportCheckController.retryMessage);
      expect(result.detail, 'quota exceeded');
      expect(dupCalled, isFalse, reason: 'no duplicate check after AI failure');
    });

    test('validate throws', () async {
      final controller = ReportCheckController(
        validate: (_) async => throw Exception('boom'),
        stillPresentCheck: (_, _) async => null,
      );
      final result = await controller.check(goodCapture());
      expect(result.isSuccess, isFalse);
      expect(result.userMessage, ReportCheckController.retryMessage);
      expect(result.detail, contains('boom'));
    });

    test('duplicate check throws', () async {
      final controller = ReportCheckController(
        validate: (_) async => siteResult,
        stillPresentCheck: (_, _) async => throw Exception('firestore down'),
      );
      final result = await controller.check(goodCapture());
      expect(result.isSuccess, isFalse);
      expect(result.outcome, isNull);
      expect(result.detail, contains('firestore down'));
    });

    test('failed capture is rejected without calling the AI', () async {
      var called = false;
      final controller = ReportCheckController(
        validate: (_) async {
          called = true;
          return siteResult;
        },
        stillPresentCheck: (_, _) async => null,
      );
      final result = await controller.check(
        const CaptureResult.failure(CaptureFailure.cancelled, 'none'),
      );
      expect(result.isSuccess, isFalse);
      expect(called, isFalse);
    });
  });
}
