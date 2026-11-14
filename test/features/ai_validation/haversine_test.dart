import 'package:clean_spot/features/ai_validation/haversine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('same point is 0 m', () {
    expect(haversineMeters(6.9271, 79.8612, 6.9271, 79.8612), 0);
  });

  test('one degree of latitude is about 111.2 km', () {
    expect(haversineMeters(0, 0, 1, 0), closeTo(111195, 5));
  });

  test('London to Paris is about 343.5 km', () {
    expect(
      haversineMeters(51.5074, -0.1278, 48.8566, 2.3522),
      closeTo(343500, 1000),
    );
  });

  test('symmetric', () {
    expect(
      haversineMeters(6.9, 79.8, 7.0, 80.0),
      closeTo(haversineMeters(7.0, 80.0, 6.9, 79.8), 1e-6),
    );
  });

  test('small distances near 20 m are accurate', () {
    // 0.00018 degrees of latitude is about 20.0 m.
    expect(
      haversineMeters(6.9271, 79.8612, 6.92728, 79.8612),
      closeTo(20.0, 0.1),
    );
  });
}
