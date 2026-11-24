import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Web Mercator projection and OpenStreetMap tile layout shared by the risk map
/// ([RiskMapView]) and the read-only report location preview
/// ([LocationPreviewMap]), so both draw exactly the same map.

/// Sent with every tile request (required by the OSM tile usage policy).
const String osmUserAgent = 'CleanSpot/1.0 (MAD Project)';

/// Size in pixels of the whole world at [zoom] (256 px tiles).
double worldSize(double zoom) => 256.0 * math.pow(2.0, zoom);

/// Projects [lat]/[lng] to world pixel coordinates at [zoom].
Offset project(double lat, double lng, double zoom) {
  final size = worldSize(zoom);
  final x = (lng + 180.0) / 360.0 * size;
  final sinLat = math.sin(lat * math.pi / 180.0).clamp(-0.9999, 0.9999);
  final y =
      (0.5 - math.log((1.0 + sinLat) / (1.0 - sinLat)) / (4.0 * math.pi)) *
      size;
  return Offset(x, y);
}

/// Inverse of [project].
(double lat, double lng) unproject(Offset world, double zoom) {
  final size = worldSize(zoom);
  final lng = ((world.dx / size) * 360.0 - 180.0).clamp(-180.0, 180.0);
  final n = math.pi - 2.0 * math.pi * (world.dy / size);
  final lat =
      ((180.0 / math.pi) * math.atan(0.5 * (math.exp(n) - math.exp(-n)))).clamp(
        -85.0,
        85.0,
      );
  return (lat, lng);
}

/// Ground distance covered by one screen pixel at [lat] and [zoom].
double metersPerPixel(double lat, double zoom) =>
    40075016.686 * math.cos(lat * math.pi / 180.0) / worldSize(zoom);

/// The OpenStreetMap tiles that cover a [width] x [height] viewport centred on
/// [centerWorld] (a [project]ed point) at [zoom]. Each is a [Positioned] child
/// for a [Stack] the size of the viewport. Tiles that fail to load render
/// nothing, so whatever sits behind the stack shows through.
List<Widget> buildOsmTiles({
  required Offset centerWorld,
  required double zoom,
  required double width,
  required double height,
}) {
  // Integer tile zoom; the tiles are scaled to match the fractional zoom.
  final tileZ = zoom.round().clamp(3, 18);
  final tileScale = math.pow(2.0, zoom - tileZ).toDouble();
  final tileScreenSize = 256.0 * tileScale;
  final maxTileIndex = (1 << tileZ) - 1;

  final minTx = ((centerWorld.dx - width / 2) / tileScreenSize).floor();
  final maxTx = ((centerWorld.dx + width / 2) / tileScreenSize).floor();
  final minTy = ((centerWorld.dy - height / 2) / tileScreenSize).floor();
  final maxTy = ((centerWorld.dy + height / 2) / tileScreenSize).floor();

  final tiles = <Widget>[];
  for (var ty = minTy; ty <= maxTy; ty++) {
    if (ty < 0 || ty > maxTileIndex) continue;
    for (var tx = minTx; tx <= maxTx; tx++) {
      final wrappedTx =
          ((tx % (maxTileIndex + 1)) + (maxTileIndex + 1)) % (maxTileIndex + 1);
      final left = tx * tileScreenSize - centerWorld.dx + width / 2;
      final top = ty * tileScreenSize - centerWorld.dy + height / 2;
      tiles.add(
        Positioned(
          key: ValueKey('tile-$tileZ-$wrappedTx-$ty'),
          left: left,
          top: top,
          width: tileScreenSize + 0.5,
          height: tileScreenSize + 0.5,
          child: Image.network(
            'https://tile.openstreetmap.org/$tileZ/$wrappedTx/$ty.png',
            headers: const {'User-Agent': osmUserAgent},
            fit: BoxFit.fill,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      );
    }
  }
  return tiles;
}
