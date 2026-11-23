import 'package:clean_spot/features/ai_validation/duplicate_check.dart';
import 'package:clean_spot/features/ai_validation/geohash.dart' as geohash;
import 'package:clean_spot/models/report_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const lat = 6.9271;
  const lng = 79.8612;
  final now = DateTime(2026, 11, 13, 12);

  /// About [metres] north of the test point (1 m of latitude ~ 1/111195 deg).
  GeoPoint north(double metres) => GeoPoint(lat + metres / 111195, lng);

  Timestamp daysAgo(num days) => Timestamp.fromDate(
    now.subtract(Duration(minutes: (days * 24 * 60).round())),
  );

  Map<String, dynamic> report({
    String status = 'valid',
    Object? createdAt,
    Object? lastConfirmedAt,
    Object? location,
  }) => {
    'status': status,
    'createdAt': createdAt ?? daysAgo(1),
    'lastConfirmedAt': ?lastConfirmedAt,
    'location': location ?? const GeoPoint(lat, lng),
  };

  double? distance(Map<String, dynamic> data) =>
      matchDistance(data, lat, lng, now);

  test('the rule is 50 m and 14 days', () {
    expect(stillPresentRadiusMeters, 50);
    expect(stillPresentWindow, const Duration(days: 14));
  });

  test('field names match ReportModel.toMap()', () {
    final map = ReportModel(
      id: 'x',
      uid: 'u',
      lat: 0,
      lng: 0,
      location: const GeoPoint(0, 0),
      geohash: 's00000000',
      status: 'valid',
      createdAt: now,
      lastConfirmedAt: now,
    ).toMap();
    for (final f in [
      fieldGeohash,
      fieldStatus,
      fieldCreatedAt,
      fieldLastConfirmedAt,
      fieldLocation,
    ]) {
      expect(map.containsKey(f), isTrue, reason: f);
    }
    expect(map[fieldStatus], validStatus);
  });

  group('candidatePrefixes', () {
    test('cell plus 8 neighbours, precision 6', () {
      final prefixes = candidatePrefixes(lat, lng);
      expect(prefixes, hasLength(9));
      expect(prefixes.first, geohash.encode(lat, lng, 6));
      expect(prefixes.every((p) => p.length == 6), isTrue);
    });

    test('a precision-9 geohash 45 m away starts with one of the prefixes', () {
      final p = north(45);
      final stored = geohash.encode(p.latitude, p.longitude, 9);
      expect(candidatePrefixes(lat, lng).any(stored.startsWith), isTrue);
    });
  });

  group('matchDistance', () {
    test('valid, recent, same spot -> match at ~0 m', () {
      expect(distance(report()), closeTo(0, 0.01));
    });

    test('pending, rejected, cleared or old "approved" -> no match', () {
      for (final status in ['pending', 'rejected', 'cleared', 'approved']) {
        expect(distance(report(status: status)), isNull, reason: status);
      }
    });

    test('about 49 m away -> match; about 51 m away -> no match', () {
      expect(distance(report(location: north(49))), closeTo(49, 0.5));
      expect(distance(report(location: north(51))), isNull);
    });

    test('created 13.9 days ago -> match; 14 days ago or more -> no match', () {
      expect(distance(report(createdAt: daysAgo(13.9))), isNotNull);
      expect(distance(report(createdAt: daysAgo(14))), isNull);
      expect(distance(report(createdAt: daysAgo(20))), isNull);
    });

    test('an old report confirmed recently still matches', () {
      final data = report(createdAt: daysAgo(30), lastConfirmedAt: daysAgo(2));
      expect(distance(data), isNotNull);
    });

    test('an old report confirmed long ago does not match', () {
      final data = report(createdAt: daysAgo(30), lastConfirmedAt: daysAgo(15));
      expect(distance(data), isNull);
    });

    test('missing or wrongly typed fields -> no match', () {
      expect(
        distance({'status': 'valid', 'location': const GeoPoint(lat, lng)}),
        isNull,
      );
      expect(
        distance({'status': 'valid', 'createdAt': Timestamp.fromDate(now)}),
        isNull,
      );
      expect(distance(report(createdAt: 'yesterday')), isNull);
      expect(distance(report(location: 'here')), isNull);
    });
  });

  group('lastActivity', () {
    test('the later of createdAt and lastConfirmedAt', () {
      final created = daysAgo(10);
      final confirmed = daysAgo(3);
      expect(
        lastActivity(report(createdAt: created, lastConfirmedAt: confirmed)),
        confirmed.toDate(),
      );
      // A lastConfirmedAt older than createdAt (phone clock) is ignored.
      expect(
        lastActivity(report(createdAt: confirmed, lastConfirmedAt: created)),
        confirmed.toDate(),
      );
    });

    test('null without usable timestamps', () {
      expect(lastActivity({'createdAt': 'x'}), isNull);
      expect(lastActivity({}), isNull);
    });
  });

  group('nearestMatch', () {
    test('null when nothing matches (a new site)', () {
      final docs = {
        'far': report(location: north(80)),
        'old': report(createdAt: daysAgo(20)),
        'rejected': report(status: 'rejected'),
      };
      expect(nearestMatch(docs.entries, lat, lng, now), isNull);
    });

    test('picks the nearest of several matches, from any user', () {
      final docs = {
        'a': report(location: north(40))..['uid'] = 'user-a',
        'b': report(location: north(10))..['uid'] = 'user-b',
        'c': report(location: north(30))..['uid'] = 'user-c',
      };
      expect(nearestMatch(docs.entries, lat, lng, now), 'b');
    });

    test('a non-matching nearer report is skipped', () {
      final docs = {
        'cleared': report(status: 'cleared', location: north(1)),
        'valid': report(location: north(25)),
      };
      expect(nearestMatch(docs.entries, lat, lng, now), 'valid');
    });
  });
}
