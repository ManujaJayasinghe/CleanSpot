import 'package:clean_spot/features/ai_validation/duplicate_check.dart';
import 'package:clean_spot/features/ai_validation/geohash.dart' as geohash;
import 'package:clean_spot/models/report_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const lat = 6.9271;
  const lng = 79.8612;
  final now = DateTime(2026, 11, 13, 12);

  Map<String, dynamic> report({
    String status = 'approved',
    Object? createdAt,
    Object? location,
  }) => {
    'status': status,
    'createdAt':
        createdAt ?? Timestamp.fromDate(now.subtract(const Duration(days: 1))),
    'location': location ?? const GeoPoint(lat, lng),
  };

  test('field names match ReportModel.toMap()', () {
    final map = ReportModel(
      id: 'x',
      reporterId: 'u',
      photoUrl: '',
      location: const GeoPoint(0, 0),
      geohash: 's00000000',
      status: 'approved',
      confirmationCount: 0,
      createdAt: now,
      lastConfirmedAt: now,
    ).toMap();
    for (final f in [
      fieldGeohash,
      fieldStatus,
      fieldCreatedAt,
      fieldLocation,
    ]) {
      expect(map.containsKey(f), isTrue, reason: f);
    }
    expect(map[fieldStatus], approvedStatus);
  });

  group('candidatePrefixes', () {
    test('cell plus 8 neighbours, precision 6', () {
      final prefixes = candidatePrefixes(lat, lng);
      expect(prefixes, hasLength(9));
      expect(prefixes.first, geohash.encode(lat, lng, 6));
      expect(prefixes.every((p) => p.length == 6), isTrue);
    });

    test('a precision-9 geohash 15 m away starts with one of the prefixes', () {
      final stored = geohash.encode(lat + 0.000135, lng, 9); // ~15 m north
      expect(candidatePrefixes(lat, lng).any(stored.startsWith), isTrue);
    });
  });

  group('matchesDuplicate', () {
    test('approved, recent, same spot -> duplicate', () {
      expect(matchesDuplicate(report(), lat, lng, now), isTrue);
    });

    test('pending or rejected -> not a duplicate', () {
      expect(
        matchesDuplicate(report(status: 'pending'), lat, lng, now),
        isFalse,
      );
      expect(
        matchesDuplicate(report(status: 'rejected'), lat, lng, now),
        isFalse,
      );
    });

    test('older than 7 days -> not a duplicate', () {
      final old = Timestamp.fromDate(
        now.subtract(const Duration(days: 7, seconds: 1)),
      );
      expect(matchesDuplicate(report(createdAt: old), lat, lng, now), isFalse);
    });

    test('just inside 7 days -> duplicate', () {
      final recent = Timestamp.fromDate(
        now.subtract(const Duration(days: 6, hours: 23)),
      );
      expect(
        matchesDuplicate(report(createdAt: recent), lat, lng, now),
        isTrue,
      );
    });

    test('about 19 m away -> duplicate; about 21 m away -> not', () {
      // 1 m of latitude is about 1 / 111195 degrees.
      final near = GeoPoint(lat + 19 / 111195, lng);
      final far = GeoPoint(lat + 21 / 111195, lng);
      expect(matchesDuplicate(report(location: near), lat, lng, now), isTrue);
      expect(matchesDuplicate(report(location: far), lat, lng, now), isFalse);
    });

    test('missing or wrongly typed fields -> not counted', () {
      expect(
        matchesDuplicate(
          {'status': 'approved', 'location': const GeoPoint(lat, lng)},
          lat,
          lng,
          now,
        ),
        isFalse,
      );
      expect(
        matchesDuplicate(
          {'status': 'approved', 'createdAt': Timestamp.fromDate(now)},
          lat,
          lng,
          now,
        ),
        isFalse,
      );
      expect(
        matchesDuplicate(report(createdAt: 'yesterday'), lat, lng, now),
        isFalse,
      );
    });
  });
}
