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
  _extraTests();
  clearedTests();
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

// ---------------------------------------------------------------------------
// Photo is not stored in reports docs; type / aiCategory are wire values.
// ---------------------------------------------------------------------------
void _extraTests() {
  group('ReportModel: photo is never written to the reports document', () {
    test('toMap has no imageUrl or photoUrl, even if the model holds one', () {
      final r = ReportModel(
        id: 'r1',
        uid: 'u1',
        imageUrl: 'data:image/jpeg;base64,AAAA',
        lat: 7.29,
        lng: 80.63,
        status: 'valid',
        location: const GeoPoint(7.29, 80.63),
        createdAt: DateTime(2026, 11, 10),
        lastConfirmedAt: DateTime(2026, 11, 10),
      );
      final map = r.toMap();
      expect(map.containsKey('imageUrl'), isFalse);
      expect(map.containsKey('photoUrl'), isFalse);
      expect(
        map.values.whereType<String>().any((v) => v.contains('base64')),
        isFalse,
      );
    });

    test('old documents that still hold the photo parse (imageUrl readable)', () {
      final withImageUrl = ReportModel.fromMap(
        'r1',
        baseDoc()..['imageUrl'] = 'data:image/jpeg;base64,AAAA',
      );
      expect(withImageUrl.imageUrl, 'data:image/jpeg;base64,AAAA');

      final withPhotoUrl = ReportModel.fromMap(
        'r2',
        baseDoc()..['photoUrl'] = 'data:image/jpeg;base64,BBBB',
      );
      expect(withPhotoUrl.imageUrl, 'data:image/jpeg;base64,BBBB');
    });

    test('a document with no photo fields parses with an empty imageUrl', () {
      final doc = baseDoc()..remove('photoUrl');
      expect(ReportModel.fromMap('r1', doc).imageUrl, '');
    });
  });

  group('ReportModel: type and aiCategory use wire values', () {
    ReportModel parse({Object? type, Object? aiCategory}) => ReportModel.fromMap(
          'r1',
          baseDoc()
            ..['type'] = type
            ..['aiCategory'] = aiCategory,
        );

    test('wire values are read unchanged', () {
      for (final c in SiteCategory.values) {
        final r = parse(type: c.wireValue, aiCategory: c.wireValue);
        expect(r.type, c.wireValue);
        expect(r.aiCategory, c.wireValue);
      }
    });

    test('old enum names are converted to wire values', () {
      final r = parse(type: 'blockedDrain', aiCategory: 'stagnantWater');
      expect(r.type, 'blocked_drain');
      expect(r.aiCategory, 'stagnant_water');
      // Names that are identical in both forms.
      expect(parse(type: 'tire', aiCategory: 'container').type, 'tire');
      expect(parse(type: 'other', aiCategory: 'none').aiCategory, 'none');
    });

    test('old display labels are converted too', () {
      expect(parse(type: 'Tyres').type, 'tire');
      expect(parse(type: 'Blocked Drain').type, 'blocked_drain');
      expect(parse(type: 'Stagnant Water').type, 'stagnant_water');
      expect(parse(type: 'Containers').type, 'container');
      expect(parse(type: 'Other').type, 'other');
    });

    test('missing type defaults to other; missing aiCategory stays null', () {
      final r = parse();
      expect(r.type, 'other');
      expect(r.aiCategory, isNull);
    });

    test('toMap writes the wire values, not the enum names', () {
      final r = ReportModel(
        id: 'r1',
        uid: 'u1',
        lat: 7.29,
        lng: 80.63,
        type: SiteCategory.blockedDrain.wireValue,
        status: 'valid',
        location: const GeoPoint(7.29, 80.63),
        createdAt: DateTime(2026, 11, 10),
        lastConfirmedAt: DateTime(2026, 11, 10),
        aiCategory: SiteCategory.stagnantWater.wireValue,
      );
      final map = r.toMap();
      expect(map['type'], 'blocked_drain');
      expect(map['aiCategory'], 'stagnant_water');
    });

    test('a value read from an old document is written back as a wire value', () {
      final map = parse(type: 'blockedDrain', aiCategory: 'blockedDrain').toMap();
      expect(map['type'], 'blocked_drain');
      expect(map['aiCategory'], 'blocked_drain');
    });
  });

  group('SiteCategory.normalizeStored / labelFor', () {
    test('normalizeStored', () {
      expect(SiteCategory.normalizeStored(null), isNull);
      expect(SiteCategory.normalizeStored('blocked_drain'), 'blocked_drain');
      expect(SiteCategory.normalizeStored('blockedDrain'), 'blocked_drain');
      expect(SiteCategory.normalizeStored('somethingNew'), 'somethingNew');
    });

    test('labelFor shows a friendly name for every stored form', () {
      expect(SiteCategory.labelFor('blocked_drain'), 'Blocked drain');
      expect(SiteCategory.labelFor('blockedDrain'), 'Blocked drain');
      expect(SiteCategory.labelFor('Tyres'), 'Discarded tyre');
      expect(SiteCategory.labelFor(null), 'Other');
      expect(SiteCategory.labelFor(''), 'Other');
      expect(SiteCategory.labelFor('unknown thing'), 'unknown thing');
    });
  });
}

// ---------------------------------------------------------------------------
// 'cleared' reports: who cleared them and when.
// ---------------------------------------------------------------------------
void clearedTests() {
  group('ReportModel cleared fields', () {
    test('old documents have no clearedBy or clearedAt', () {
      final r = ReportModel.fromMap('r1', baseDoc());
      expect(r.clearedBy, isNull);
      expect(r.clearedAt, isNull);
    });

    test('a cleared document is read with who and when', () {
      final r = ReportModel.fromMap(
        'r1',
        baseDoc()
          ..['status'] = 'cleared'
          ..['clearedBy'] = 'officer1'
          ..['clearedAt'] = Timestamp.fromDate(DateTime(2026, 11, 25, 9)),
      );
      expect(r.status, 'cleared');
      expect(r.clearedBy, 'officer1');
      expect(r.clearedAt, DateTime(2026, 11, 25, 9));
    });

    test('toMap omits the cleared fields unless set', () {
      final plain = ReportModel.fromMap('r1', baseDoc()).toMap();
      expect(plain.containsKey('clearedBy'), isFalse);
      expect(plain.containsKey('clearedAt'), isFalse);
    });

    test('cleared fields round trip', () {
      final original = ReportModel.fromMap(
        'r1',
        baseDoc()
          ..['status'] = 'cleared'
          ..['clearedBy'] = 'officer1'
          ..['clearedAt'] = Timestamp.fromDate(DateTime(2026, 11, 25, 9)),
      );
      final copy = ReportModel.fromMap('r1', original.toMap());
      expect(copy.clearedBy, 'officer1');
      expect(copy.clearedAt, DateTime(2026, 11, 25, 9));
      expect(copy.status, 'cleared');
    });
  });
}
