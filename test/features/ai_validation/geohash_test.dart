import 'dart:math' as math;

import 'package:clean_spot/features/ai_validation/geohash.dart' as geohash;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('encode', () {
    test('matches the published reference value (Wikipedia/geohash.org)', () {
      expect(geohash.encode(57.64911, 10.40744, 11), 'u4pruydqqvj');
    });

    test('shorter precision is a prefix of the longer one', () {
      final full = geohash.encode(57.64911, 10.40744, 11);
      for (var p = 1; p <= 11; p++) {
        expect(geohash.encode(57.64911, 10.40744, p), full.substring(0, p));
      }
    });

    test('Wikipedia example ezs42 contains (42.6, -5.6)', () {
      expect(geohash.encode(42.6, -5.6, 5), 'ezs42');
    });

    test('rejects bad input', () {
      expect(() => geohash.encode(0, 0, 0), throwsArgumentError);
      expect(() => geohash.encode(0, 0, 13), throwsArgumentError);
      expect(() => geohash.encode(91, 0, 5), throwsArgumentError);
      expect(() => geohash.encode(0, 181, 5), throwsArgumentError);
    });
  });

  group('bounds', () {
    test('ezs42 decodes to the published box', () {
      final b = geohash.bounds('ezs42');
      expect(b.minLat, closeTo(42.583, 0.001));
      expect(b.maxLat, closeTo(42.627, 0.001));
      expect(b.minLng, closeTo(-5.625, 0.001));
      expect(b.maxLng, closeTo(-5.581, 0.001));
    });

    test('rejects invalid characters', () {
      expect(() => geohash.bounds('abc'), throwsArgumentError); // 'a' invalid
      expect(() => geohash.bounds(''), throwsArgumentError);
    });
  });

  group('neighbours', () {
    // Published precision-1 grid (north at top):
    //   b c f g u v y z
    //   8 9 d e s t w x
    //   2 3 6 7 k m q r
    //   0 1 4 5 h j n p
    test('neighbours of "s" match the precision-1 grid', () {
      // Order: N, NE, E, SE, S, SW, W, NW.
      expect(geohash.neighbours('s'), ['u', 'v', 't', 'm', 'k', '7', 'e', 'g']);
    });

    test('longitude wraps across the antimeridian', () {
      // "8" is on the west edge of row 2; across the antimeridian its west is "x".
      expect(geohash.neighbours('8')[6], 'x'); // W
      expect(geohash.neighbours('x')[2], '8'); // E
    });

    test('each neighbour is exactly one cell away in its direction', () {
      final cell = geohash.encode(57.64911, 10.40744, 7);
      final b = geohash.bounds(cell);
      const steps = [
        [1, 0],
        [1, 1],
        [0, 1],
        [-1, 1],
        [-1, 0],
        [-1, -1],
        [0, -1],
        [1, -1],
      ];
      final n = geohash.neighbours(cell);
      for (var i = 0; i < 8; i++) {
        final nb = geohash.bounds(n[i]);
        expect(nb.minLat, closeTo(b.minLat + steps[i][0] * b.height, 1e-9));
        expect(nb.minLng, closeTo(b.minLng + steps[i][1] * b.width, 1e-9));
      }
    });

    test('returns 8 distinct same-precision cells away from the poles', () {
      final cell = geohash.encode(6.9271, 79.8612, 6); // Colombo
      final n = geohash.neighbours(cell);
      expect(n, hasLength(8));
      expect(n.toSet(), hasLength(8));
      expect(n, isNot(contains(cell)));
      expect(n.every((h) => h.length == 6), isTrue);
    });

    test('every point within 20 m lands in the cell or a neighbour', () {
      final rnd = math.Random(42);
      for (var i = 0; i < 2000; i++) {
        final lat = -60 + rnd.nextDouble() * 120;
        final lng = -180 + rnd.nextDouble() * 360;
        final cell = geohash.encode(lat, lng, 6);
        final covered = {cell, ...geohash.neighbours(cell)};
        // Offset by up to ~20 m in a random direction.
        final angle = rnd.nextDouble() * 2 * math.pi;
        final dLat = 20 / 111195 * math.sin(angle);
        final dLng =
            20 / (111195 * math.cos(lat * math.pi / 180)) * math.cos(angle);
        var lng2 = lng + dLng;
        if (lng2 > 180) lng2 -= 360;
        if (lng2 < -180) lng2 += 360;
        expect(covered, contains(geohash.encode(lat + dLat, lng2, 6)));
      }
    });
  });
}
