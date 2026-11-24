import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme_proposal.dart';
import 'map_projection.dart';

/// A small read-only OpenStreetMap preview of one captured location, shown in
/// the report form's location card.
///
/// With a location it centres on it (zoom 17), draws a green pin exactly at
/// the centre and a translucent circle for the GPS accuracy. Without one it
/// shows a neutral, washed-out view of Colombo so the card still looks like a
/// map waiting for a location. It never pans, zooms or takes touches, so it
/// can sit inside a scrolling page, and it fades when the location changes.
/// Failed tile loads (offline) leave a plain light green background.
class LocationPreviewMap extends StatelessWidget {
  const LocationPreviewMap({
    super.key,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
    this.height = 170,
  });

  final double? latitude;
  final double? longitude;

  /// GPS accuracy radius in metres, drawn as a translucent circle.
  final double? accuracyMeters;

  final double height;

  static const double locationZoom = 17;
  static const double neutralLatitude = 6.9271;
  static const double neutralLongitude = 79.8612;
  static const double neutralZoom = 11;

  /// The accuracy circle is never smaller than this radius (px), so it stays
  /// visible for very precise fixes.
  static const double minAccuracyRadius = 10;

  /// Upper bound so a very poor fix cannot paint an absurdly large circle.
  static const double maxAccuracyRadius = 400;

  bool get hasLocation => latitude != null && longitude != null;

  @override
  Widget build(BuildContext context) {
    final layerKey = hasLocation
        ? ValueKey('location-$latitude,$longitude')
        : const ValueKey('no-location');

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Semantics(
          label: hasLocation
              ? 'Map showing the captured location'
              : 'Map waiting for a location',
          image: true,
          child: ExcludeSemantics(
            child: IgnorePointer(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    layoutBuilder: (current, previous) => Stack(
                      fit: StackFit.expand,
                      children: [...previous, ?current],
                    ),
                    child: _MapLayer(
                      key: layerKey,
                      latitude: latitude,
                      longitude: longitude,
                      accuracyMeters: accuracyMeters,
                    ),
                  ),
                  const Positioned(right: 6, bottom: 4, child: _Attribution()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tiles, accuracy circle and pin for one location (or the neutral view).
class _MapLayer extends StatelessWidget {
  const _MapLayer({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
  });

  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;

  static const _background = Color(0xFFEDF3ED);

  @override
  Widget build(BuildContext context) {
    final lat = latitude;
    final lng = longitude;
    final hasLocation = lat != null && lng != null;

    final centerLat = hasLocation ? lat : LocationPreviewMap.neutralLatitude;
    final centerLng = hasLocation ? lng : LocationPreviewMap.neutralLongitude;
    final zoom = hasLocation
        ? LocationPreviewMap.locationZoom
        : LocationPreviewMap.neutralZoom;

    return LayoutBuilder(
      builder: (context, constraints) {
        final centerWorld = project(centerLat, centerLng, zoom);
        final accuracy = accuracyMeters;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Plain light green shows through wherever a tile did not load.
            const ColoredBox(color: _background),
            ...buildOsmTiles(
              centerWorld: centerWorld,
              zoom: zoom,
              width: constraints.maxWidth,
              height: constraints.maxHeight,
            ),
            if (!hasLocation)
              ColoredBox(color: Colors.white.withValues(alpha: 0.55))
            else ...[
              if (accuracy != null)
                Center(
                  child: _AccuracyCircle(
                    radius: _radiusPx(accuracy, centerLat, zoom),
                  ),
                ),
              const Center(child: _Pin()),
            ],
          ],
        );
      },
    );
  }

  static double _radiusPx(double meters, double lat, double zoom) {
    final px = meters / metersPerPixel(lat, zoom);
    return math.max(
      LocationPreviewMap.minAccuracyRadius,
      math.min(px, LocationPreviewMap.maxAccuracyRadius),
    );
  }
}

class _AccuracyCircle extends StatelessWidget {
  const _AccuracyCircle({required this.radius});

  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('location-accuracy-circle'),
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary.withValues(alpha: 0.18),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.55),
          width: 1.5,
        ),
      ),
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('location-pin'),
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.primaryDark,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Icon(Icons.location_on, color: Colors.white, size: 20),
    );
  }
}

/// "© OpenStreetMap contributors", required by the OSM tile usage policy.
class _Attribution extends StatelessWidget {
  const _Attribution();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('osm-attribution'),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        '© OpenStreetMap contributors',
        style: TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 9,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}
