import 'package:clean_spot/features/map/location_preview_map.dart';
import 'package:clean_spot/features/map/map_projection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _pin = ValueKey('location-pin');
const _circle = ValueKey('location-accuracy-circle');

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('LocationPreviewMap', () {
    testWidgets('with coordinates it shows the pin and the accuracy circle', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const LocationPreviewMap(
            latitude: 6.9271,
            longitude: 79.8612,
            accuracyMeters: 20,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(_pin), findsOneWidget);
      expect(find.byKey(_circle), findsOneWidget);
      expect(find.byIcon(Icons.location_on), findsOneWidget);
    });

    testWidgets('the pin sits exactly at the centre of the map', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const LocationPreviewMap(
            latitude: 6.9271,
            longitude: 79.8612,
            accuracyMeters: 20,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final map = tester.getRect(find.byType(LocationPreviewMap));
      expect(tester.getCenter(find.byKey(_pin)), map.center);
      expect(tester.getCenter(find.byKey(_circle)), map.center);
    });

    testWidgets('without coordinates it shows no pin and no circle', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const LocationPreviewMap()));
      await tester.pumpAndSettle();

      expect(find.byKey(_pin), findsNothing);
      expect(find.byKey(_circle), findsNothing);
      expect(find.byIcon(Icons.location_on), findsNothing);
      // Still a map: attribution is there and tiles are laid out.
      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
      expect(find.byType(Image), findsWidgets);
    });

    testWidgets('has the default height of 170 and a custom height', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const LocationPreviewMap()));
      expect(tester.getSize(find.byType(LocationPreviewMap)).height, 170);

      await tester.pumpWidget(_host(const LocationPreviewMap(height: 120)));
      expect(tester.getSize(find.byType(LocationPreviewMap)).height, 120);
    });

    testWidgets('accuracy circle radius follows metres per pixel', (
      tester,
    ) async {
      const lat = 6.9271;
      await tester.pumpWidget(
        _host(
          const LocationPreviewMap(
            latitude: lat,
            longitude: 79.8612,
            accuracyMeters: 30,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final expected =
          30 / metersPerPixel(lat, LocationPreviewMap.locationZoom);
      expect(
        tester.getSize(find.byKey(_circle)).width,
        closeTo(expected * 2, 0.5),
      );
    });

    testWidgets('a very small accuracy still draws at least a 10 px circle', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const LocationPreviewMap(
            latitude: 6.9271,
            longitude: 79.8612,
            accuracyMeters: 0.5,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byKey(_circle)).width, 20);
    });

    testWidgets('shows the OpenStreetMap attribution bottom right', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const LocationPreviewMap(latitude: 6.9271, longitude: 79.8612)),
      );
      await tester.pumpAndSettle();

      final map = tester.getRect(find.byType(LocationPreviewMap));
      final attribution = tester.getRect(
        find.byKey(const ValueKey('osm-attribution')),
      );
      expect(attribution.right, closeTo(map.right - 6, 0.01));
      expect(attribution.bottom, closeTo(map.bottom - 4, 0.01));
      // No accuracy given: no circle, pin still drawn.
      expect(find.byKey(_circle), findsNothing);
      expect(find.byKey(_pin), findsOneWidget);
    });

    testWidgets('fades to the new location when the coordinates change', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const LocationPreviewMap()));
      await tester.pumpAndSettle();
      expect(find.byKey(_pin), findsNothing);

      await tester.pumpWidget(
        _host(
          const LocationPreviewMap(
            latitude: 6.9271,
            longitude: 79.8612,
            accuracyMeters: 12,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      // Mid-fade the old and new layers overlap.
      expect(find.byType(FadeTransition), findsAtLeastNWidgets(2));
      expect(find.byKey(_pin), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byKey(_pin), findsOneWidget);
    });

    testWidgets('is clipped to rounded top corners only', (tester) async {
      await tester.pumpWidget(_host(const LocationPreviewMap()));
      final clip = tester.widget<ClipRRect>(find.byType(ClipRRect).first);
      expect(
        clip.borderRadius,
        const BorderRadius.vertical(top: Radius.circular(20)),
      );
    });

    testWidgets('is read-only: a drag on it scrolls the page instead', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              controller: controller,
              children: const [
                LocationPreviewMap(
                  latitude: 6.9271,
                  longitude: 79.8612,
                  accuracyMeters: 20,
                ),
                SizedBox(height: 1500),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final before = tester.getCenter(find.byKey(_pin));
      await tester.drag(
        find.byType(LocationPreviewMap),
        const Offset(0, -80),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      // The page scrolled; the pin did not move inside the map.
      expect(controller.offset, greaterThan(0));
      expect(tester.getCenter(find.byKey(_pin)).dx, closeTo(before.dx, 0.01));
    });
  });

  group('map_projection', () {
    test('project and unproject round-trip', () {
      final world = project(6.9271, 79.8612, 17);
      final (lat, lng) = unproject(world, 17);
      expect(lat, closeTo(6.9271, 1e-6));
      expect(lng, closeTo(79.8612, 1e-6));
    });

    test('metersPerPixel matches the known value at the equator', () {
      expect(metersPerPixel(0, 0), closeTo(156543.03, 0.01));
      expect(metersPerPixel(0, 1), closeTo(156543.03 / 2, 0.01));
      expect(metersPerPixel(60, 10), closeTo(metersPerPixel(0, 10) / 2, 0.01));
    });
  });
}
