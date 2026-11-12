import 'package:clean_spot/features/ai_validation/validation_result.dart';
import 'package:clean_spot/models/report_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> baseDoc() => {
      'reporterId': 'u1',
      'photoUrl': 'https://example.com/p.jpg',
      'location': const GeoPoint(7.29, 80.63),
      'geohash': 'tc2b6w9q1',
      'status': 'approved',
      'confirmationCount': 2,
      'createdAt': Timestamp.fromDate(DateTime(2026, 11, 10)),
      'lastConfirmedAt': Timestamp.fromDate(DateTime(2026, 11, 11)),
    };

void main() {
  group('ReportModel AI fields', () {
    test('old documents without AI fields still parse (fields are null)', () {
      final r = ReportModel.fromMap('r1', baseDoc());
      expect(r.aiCategory, isNull);
      expect(r.aiConfidence, isNull);
      expect(r.aiReason, isNull);
      expect(r.status, 'approved');
    });

    test('AI fields are read from a document', () {
      final doc = baseDoc()
        ..['aiCategory'] = 'tire'
        ..['aiConfidence'] = 0.92
        ..['aiReason'] = 'A tyre is holding rainwater.';
      final r = ReportModel.fromMap('r1', doc);
      expect(r.aiCategory, 'tire');
      expect(r.aiConfidence, 0.92);
      expect(r.aiReason, 'A tyre is holding rainwater.');
    });

    test('an integer aiConfidence (Firestore may store 1) is read as double', () {
      final doc = baseDoc()..['aiConfidence'] = 1;
      expect(ReportModel.fromMap('r1', doc).aiConfidence, 1.0);
    });

    test('toMap omits AI fields when they are null', () {
      final map = ReportModel.fromMap('r1', baseDoc()).toMap();
      expect(map.containsKey('aiCategory'), isFalse);
      expect(map.containsKey('aiConfidence'), isFalse);
      expect(map.containsKey('aiReason'), isFalse);
    });

    test('AI fields round trip through toMap and fromMap', () {
      final original = ReportModel.fromMap(
        'r1',
        baseDoc()
          ..['aiCategory'] = SiteCategory.blockedDrain.wireValue
          ..['aiConfidence'] = 0.81
          ..['aiReason'] = 'A clogged drain with water.',
      );
      final copy = ReportModel.fromMap('r1', original.toMap());
      expect(copy.aiCategory, 'blocked_drain');
      expect(copy.aiConfidence, 0.81);
      expect(copy.aiReason, 'A clogged drain with water.');
    });
  });

  group('SiteCategory.label', () {
    test('every category has a non-empty label', () {
      for (final c in SiteCategory.values) {
        expect(c.label, isNotEmpty, reason: c.wireValue);
      }
      expect(SiteCategory.tire.label, 'Discarded tyre');
    });
  });
}
