import 'dart:typed_data';

import 'package:clean_spot/features/ai_validation/capture_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isAccuracyAcceptable', () {
    test('accepts accuracy up to 50 m', () {
      expect(isAccuracyAcceptable(0), isTrue);
      expect(isAccuracyAcceptable(5.5), isTrue);
      expect(isAccuracyAcceptable(49.9), isTrue);
      expect(isAccuracyAcceptable(50), isTrue);
    });

    test('rejects accuracy worse than 50 m', () {
      expect(isAccuracyAcceptable(50.1), isFalse);
      expect(isAccuracyAcceptable(120), isFalse);
      expect(isAccuracyAcceptable(5000), isFalse);
    });

    test('rejects invalid readings', () {
      expect(isAccuracyAcceptable(-1), isFalse);
      expect(isAccuracyAcceptable(double.nan), isFalse);
      expect(isAccuracyAcceptable(double.infinity), isFalse);
    });
  });

  group('looksLikeJpeg', () {
    test('accepts the JPEG signature', () {
      expect(looksLikeJpeg(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00])), isTrue);
      expect(looksLikeJpeg(Uint8List.fromList([0xFF, 0xD8, 0xFF])), isTrue);
    });

    test('rejects other formats and short input', () {
      // PNG
      expect(
        looksLikeJpeg(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])),
        isFalse,
      );
      // HEIC/ISO media starts with a size then "ftyp"
      expect(
        looksLikeJpeg(Uint8List.fromList([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70])),
        isFalse,
      );
      expect(looksLikeJpeg(Uint8List(0)), isFalse);
      expect(looksLikeJpeg(Uint8List.fromList([0xFF, 0xD8])), isFalse);
    });
  });

  group('CaptureResult', () {
    test('success holds the photo and a valid GPS fix', () {
      final r = CaptureResult.success(
        jpegBytes: Uint8List.fromList([0xFF, 0xD8, 0xFF]),
        latitude: 6.9271,
        longitude: 79.8612,
        accuracyMeters: 12,
      );
      expect(r.isOk, isTrue);
      expect(r.wasCancelled, isFalse);
      expect(r.failure, isNull);
      expect(r.message, isNull);
      expect(r.latitude, 6.9271);
      expect(r.accuracyMeters, 12);
    });

    test('failure has no photo or location and carries a message', () {
      const r = CaptureResult.failure(
        CaptureFailure.lowAccuracy,
        'GPS is not accurate enough.',
      );
      expect(r.isOk, isFalse);
      expect(r.jpegBytes, isNull);
      expect(r.latitude, isNull);
      expect(r.longitude, isNull);
      expect(r.accuracyMeters, isNull);
      expect(r.message, 'GPS is not accurate enough.');
    });

    test('only the cancelled failure counts as cancelled', () {
      for (final f in CaptureFailure.values) {
        final r = CaptureResult.failure(f, 'x');
        expect(r.wasCancelled, f == CaptureFailure.cancelled, reason: '$f');
        expect(r.isOk, isFalse);
      }
    });

    test('the accuracy limit is 50 m', () {
      expect(CaptureResult.maxAccuracyMeters, 50);
    });
  });
}
