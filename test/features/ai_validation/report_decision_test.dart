import 'dart:typed_data';

import 'package:clean_spot/features/ai_validation/ai_config.dart';
import 'package:clean_spot/features/ai_validation/capture_result.dart';
import 'package:clean_spot/features/ai_validation/report_decision.dart';
import 'package:clean_spot/features/ai_validation/validation_result.dart';
import 'package:flutter_test/flutter_test.dart';

ValidationResult ai({
  bool isBreedingSite = true,
  SiteCategory category = SiteCategory.tire,
  double confidence = 0.9,
  bool looksFake = false,
  String reason = 'A tyre is holding rainwater.',
}) =>
    ValidationResult(
      isBreedingSite: isBreedingSite,
      category: category,
      confidence: confidence,
      looksFake: looksFake,
      reason: reason,
    );

CaptureResult goodCapture({double accuracy = 10}) => CaptureResult.success(
      jpegBytes: Uint8List.fromList([0xFF, 0xD8, 0xFF]),
      latitude: 7.29,
      longitude: 80.63,
      accuracyMeters: accuracy,
    );

const failedCapture = CaptureResult.failure(
  CaptureFailure.locationTimeout,
  'no gps',
);

void main() {
  group('decide: approved', () {
    test('everything good is eligible and uses the AI reason', () {
      final d = decide(ai(), goodCapture(), null);
      expect(d.eligible, isTrue);
      expect(d.reason, 'A tyre is holding rainwater.');
    });

    test('confidence exactly at the threshold is eligible', () {
      expect(kMinConfidence, 0.7);
      expect(decide(ai(confidence: 0.7), goodCapture(), null).eligible, isTrue);
    });

    test('GPS accuracy exactly 50 m is eligible', () {
      expect(decide(ai(), goodCapture(accuracy: 50), null).eligible, isTrue);
    });
  });

  group('decide: every rejection', () {
    test('AI error is never eligible', () {
      final d = decide(
        const ValidationResult.error('network down'),
        goodCapture(),
        null,
      );
      expect(d.eligible, isFalse);
      expect(d.reason, ValidationResult.retryMessage);
    });

    test('failed capture is not eligible', () {
      final d = decide(ai(), failedCapture, null);
      expect(d.eligible, isFalse);
      expect(d.reason, contains('where the photo was taken'));
    });

    test('GPS worse than 50 m is not eligible', () {
      final d = decide(ai(), goodCapture(accuracy: 50.5), null);
      expect(d.eligible, isFalse);
      expect(d.reason, contains('where the photo was taken'));
    });

    test('a fake-looking photo is not eligible', () {
      final d = decide(ai(looksFake: true), goodCapture(), null);
      expect(d.eligible, isFalse);
      expect(d.reason, contains('live photo'));
    });

    test('not a breeding site is not eligible and shows the AI reason', () {
      final d = decide(
        ai(
          isBreedingSite: false,
          category: SiteCategory.none,
          reason: 'This looks like an indoor room.',
        ),
        goodCapture(),
        null,
      );
      expect(d.eligible, isFalse);
      expect(d.reason, 'This looks like an indoor room.');
    });

    test('confidence below the threshold is not eligible', () {
      final d = decide(ai(confidence: 0.69), goodCapture(), null);
      expect(d.eligible, isFalse);
      expect(d.reason, contains('clearer'));
    });


  });

  group('decide: priority when several things are wrong', () {
    test('AI error wins over everything', () {
      final d = decide(
        const ValidationResult.error('x'),
        failedCapture,
        'r1',
      );
      expect(d.reason, ValidationResult.retryMessage);
    });

    test('bad GPS is reported before fake or duplicate', () {
      final d = decide(ai(looksFake: true), goodCapture(accuracy: 200), 'r1');
      expect(d.reason, contains('where the photo was taken'));
    });

    test('fake is reported before not-a-site', () {
      final d = decide(
        ai(looksFake: true, isBreedingSite: false, category: SiteCategory.none),
        goodCapture(),
        null,
      );
      expect(d.reason, contains('live photo'));
    });
  });

  test('every rejection is ineligible regardless of reason text', () {
    final rejections = [
      decide(const ValidationResult.error('x'), goodCapture(), null),
      decide(ai(), failedCapture, null),
      decide(ai(looksFake: true), goodCapture(), null),
      decide(ai(isBreedingSite: false, category: SiteCategory.none), goodCapture(), null),
      decide(ai(confidence: 0.1), goodCapture(), null),
    ];
    for (final d in rejections) {
      expect(d.eligible, isFalse);
      expect(d.reason, isNotEmpty);
    }
  });

  group('decide: still present', () {
    test('a passing photo at an already reported site is still present', () {
      final d = decide(ai(), goodCapture(), 'r1');
      expect(d.kind, ReportDecisionKind.stillPresent);
      expect(d.isStillPresent, isTrue);
      expect(d.eligible, isFalse, reason: 'no new report and no points');
      expect(d.reason, kStillPresentMessage);
      expect(
        kStillPresentMessage,
        "Thanks, this site is already reported. We've marked it as still "
        'present.',
      );
    });

    test('a new site is approved', () {
      final d = decide(ai(), goodCapture(), null);
      expect(d.kind, ReportDecisionKind.approved);
      expect(d.isStillPresent, isFalse);
    });

    test('a failing photo is rejected even at an already reported site', () {
      final failing = [
        decide(const ValidationResult.error('x'), goodCapture(), 'r1'),
        decide(ai(), failedCapture, 'r1'),
        decide(ai(), goodCapture(accuracy: 200), 'r1'),
        decide(ai(looksFake: true), goodCapture(), 'r1'),
        decide(
          ai(isBreedingSite: false, category: SiteCategory.none),
          goodCapture(),
          'r1',
        ),
        decide(ai(confidence: 0.1), goodCapture(), 'r1'),
      ];
      for (final d in failing) {
        expect(d.kind, ReportDecisionKind.rejected);
        expect(d.isStillPresent, isFalse);
      }
    });
  });
}
