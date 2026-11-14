/// Standard geohash (base32 alphabet "0123456789bcdefghjkmnpqrstuvwxyz"),
/// written here so we do not need a package.
///
/// Reports must store `geohash` produced by [encode] at precision 9 so that
/// the duplicate check's prefix queries can find them.
library;

const String _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

/// Encodes a point as a geohash of [precision] characters (1 to 12).
///
/// Example: `encode(57.64911, 10.40744, 11) == 'u4pruydqqvj'`.
String encode(double latitude, double longitude, int precision) {
  if (precision < 1 || precision > 12) {
    throw ArgumentError.value(precision, 'precision', 'must be 1 to 12');
  }
  if (latitude.isNaN || latitude < -90 || latitude > 90) {
    throw ArgumentError.value(latitude, 'latitude', 'must be -90 to 90');
  }
  if (longitude.isNaN || longitude < -180 || longitude > 180) {
    throw ArgumentError.value(longitude, 'longitude', 'must be -180 to 180');
  }

  var latMin = -90.0, latMax = 90.0;
  var lngMin = -180.0, lngMax = 180.0;
  final out = StringBuffer();
  var bits = 0;
  var bitCount = 0;
  var evenBit = true; // Even bits are longitude, odd bits are latitude.

  while (out.length < precision) {
    if (evenBit) {
      final mid = (lngMin + lngMax) / 2;
      if (longitude >= mid) {
        bits = (bits << 1) | 1;
        lngMin = mid;
      } else {
        bits = bits << 1;
        lngMax = mid;
      }
    } else {
      final mid = (latMin + latMax) / 2;
      if (latitude >= mid) {
        bits = (bits << 1) | 1;
        latMin = mid;
      } else {
        bits = bits << 1;
        latMax = mid;
      }
    }
    evenBit = !evenBit;
    if (++bitCount == 5) {
      out.write(_base32[bits]);
      bits = 0;
      bitCount = 0;
    }
  }
  return out.toString();
}

/// The bounding box of a geohash cell.
class GeohashBounds {
  const GeohashBounds(this.minLat, this.minLng, this.maxLat, this.maxLng);

  final double minLat;
  final double minLng;
  final double maxLat;
  final double maxLng;

  double get centerLat => (minLat + maxLat) / 2;
  double get centerLng => (minLng + maxLng) / 2;
  double get height => maxLat - minLat;
  double get width => maxLng - minLng;
}

/// Decodes [geohash] to its cell's bounding box.
GeohashBounds bounds(String geohash) {
  if (geohash.isEmpty) {
    throw ArgumentError.value(geohash, 'geohash', 'must not be empty');
  }
  var latMin = -90.0, latMax = 90.0;
  var lngMin = -180.0, lngMax = 180.0;
  var evenBit = true;

  for (final char in geohash.toLowerCase().split('')) {
    final value = _base32.indexOf(char);
    if (value < 0) {
      throw ArgumentError.value(
        geohash,
        'geohash',
        'invalid character "$char"',
      );
    }
    for (var bit = 4; bit >= 0; bit--) {
      final isSet = (value >> bit) & 1 == 1;
      if (evenBit) {
        final mid = (lngMin + lngMax) / 2;
        if (isSet) {
          lngMin = mid;
        } else {
          lngMax = mid;
        }
      } else {
        final mid = (latMin + latMax) / 2;
        if (isSet) {
          latMin = mid;
        } else {
          latMax = mid;
        }
      }
      evenBit = !evenBit;
    }
  }
  return GeohashBounds(latMin, lngMin, latMax, lngMax);
}

/// The 8 cells around [geohash], same precision, in the order
/// N, NE, E, SE, S, SW, W, NW.
///
/// Longitude wraps across the antimeridian. At the poles there is no cell
/// further north/south, so those entries repeat the edge row (the list may
/// then contain duplicates or [geohash] itself; callers should de-duplicate).
List<String> neighbours(String geohash) {
  final b = bounds(geohash);
  final precision = geohash.length;
  final lat = b.centerLat;
  final lng = b.centerLng;
  final dLat = b.height;
  final dLng = b.width;

  String at(int rowStep, int colStep) {
    final nLat = (lat + rowStep * dLat).clamp(-90.0, 90.0);
    var nLng = lng + colStep * dLng;
    if (nLng > 180) nLng -= 360;
    if (nLng < -180) nLng += 360;
    return encode(nLat, nLng, precision);
  }

  return [
    at(1, 0), // N
    at(1, 1), // NE
    at(0, 1), // E
    at(-1, 1), // SE
    at(-1, 0), // S
    at(-1, -1), // SW
    at(0, -1), // W
    at(1, -1), // NW
  ];
}
