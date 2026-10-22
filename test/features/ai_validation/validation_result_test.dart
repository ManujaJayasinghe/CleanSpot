import 'dart:convert';

import 'package:clean_spot/features/ai_validation/validation_result.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> validJson() => {
      'isBreedingSite': true,
      'category': 'tire',
      'confidence': 0.92,
      'looksFake': false,
      'reason': 'A discarded tyre is holding rainwater.',
    };

String encode(Map<String, Object?> json) => jsonEncode(json);

void expectError(ValidationResult r) {
  expect(r.isError, isTrue);
  expect(r.isBreedingSite, isFalse);
  expect(r.category, SiteCategory.none);
  expect(r.confidence, 0);
  expect(r.reason, ValidationResult.retryMessage);
  expect(r.error, isNotEmpty);
}

void main() {
  group('ValidationResult.parse valid input', () {
    test('parses a complete result', () {
      final r = ValidationResult.parse(encode(validJson()));
      expect(r.isError, isFalse);
      expect(r.isBreedingSite, isTrue);
      expect(r.category, SiteCategory.tire);
      expect(r.confidence, 0.92);
      expect(r.looksFake, isFalse);
      expect(r.reason, 'A discarded tyre is holding rainwater.');
    });

    test('accepts an integer confidence', () {
      final json = validJson()..['confidence'] = 1;
      expect(ValidationResult.parse(encode(json)).confidence, 1.0);
    });

    test('accepts every category', () {
      for (final c in SiteCategory.values) {
        final json = validJson()
          ..['category'] = c.wireValue
          ..['isBreedingSite'] = c != SiteCategory.none;
        final r = ValidationResult.parse(encode(json));
        expect(r.isError, isFalse, reason: c.wireValue);
        expect(r.category, c);
      }
    });

    test('accepts not-a-site with category none', () {
      final json = validJson()
        ..['isBreedingSite'] = false
        ..['category'] = 'none'
        ..['confidence'] = 0.1;
      final r = ValidationResult.parse(encode(json));
      expect(r.isError, isFalse);
      expect(r.isBreedingSite, isFalse);
    });

    test('strips a markdown code fence', () {
      final r = ValidationResult.parse('```json\n${encode(validJson())}\n```');
      expect(r.isError, isFalse);
      expect(r.category, SiteCategory.tire);
    });

    test('trims the reason', () {
      final json = validJson()..['reason'] = '  Clear photo.  ';
      expect(ValidationResult.parse(encode(json)).reason, 'Clear photo.');
    });

    test('ignores unknown extra fields', () {
      final json = validJson()..['extra'] = 'x';
      expect(ValidationResult.parse(encode(json)).isError, isFalse);
    });
  });

  group('ValidationResult.parse failures become errors', () {
    test('null and empty input', () {
      expectError(ValidationResult.parse(null));
      expectError(ValidationResult.parse(''));
      expectError(ValidationResult.parse('   \n'));
    });

    test('malformed JSON', () {
      expectError(ValidationResult.parse('{"isBreedingSite": true,'));
      expectError(ValidationResult.parse('not json at all'));
    });

    test('truncated JSON (cut off mid-reply)', () {
      final text = encode(validJson());
      expectError(ValidationResult.parse(text.substring(0, text.length - 15)));
    });

    test('valid JSON that is not an object', () {
      expectError(ValidationResult.parse('[1, 2, 3]'));
      expectError(ValidationResult.parse('"hello"'));
      expectError(ValidationResult.parse('null'));
    });

    test('each missing field is an error', () {
      for (final key in validJson().keys) {
        final json = validJson()..remove(key);
        expectError(ValidationResult.parse(encode(json)));
      }
    });

    test('each null field is an error', () {
      for (final key in validJson().keys) {
        final json = validJson()..[key] = null;
        expectError(ValidationResult.parse(encode(json)));
      }
    });

    test('wrong types', () {
      expectError(
        ValidationResult.parse(encode(validJson()..['isBreedingSite'] = 'true')),
      );
      expectError(
        ValidationResult.parse(encode(validJson()..['looksFake'] = 0)),
      );
      expectError(
        ValidationResult.parse(encode(validJson()..['confidence'] = '0.9')),
      );
      expectError(
        ValidationResult.parse(encode(validJson()..['reason'] = 42)),
      );
    });

    test('unknown category', () {
      expectError(
        ValidationResult.parse(encode(validJson()..['category'] = 'swamp')),
      );
    });

    test('confidence outside 0..1', () {
      expectError(
        ValidationResult.parse(encode(validJson()..['confidence'] = 1.5)),
      );
      expectError(
        ValidationResult.parse(encode(validJson()..['confidence'] = -0.1)),
      );
    });

    test('empty or blank reason', () {
      expectError(ValidationResult.parse(encode(validJson()..['reason'] = '')));
      expectError(
        ValidationResult.parse(encode(validJson()..['reason'] = '   ')),
      );
    });

    test('breeding site with category none is a contradiction', () {
      final json = validJson()..['category'] = 'none';
      expectError(ValidationResult.parse(encode(json)));
    });
  });

  group('ValidationResult.error', () {
    test('is never a breeding site and shows a retry message', () {
      const r = ValidationResult.error('boom');
      expectError(r);
      expect(r.error, 'boom');
    });
  });

  group('SiteCategory.fromWire', () {
    test('maps known values and rejects others', () {
      expect(SiteCategory.fromWire('stagnant_water'), SiteCategory.stagnantWater);
      expect(SiteCategory.fromWire('blocked_drain'), SiteCategory.blockedDrain);
      expect(SiteCategory.fromWire('Tire'), isNull);
      expect(SiteCategory.fromWire(null), isNull);
      expect(SiteCategory.fromWire(3), isNull);
    });
  });
}
