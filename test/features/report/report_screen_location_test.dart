import 'package:clean_spot/features/map/location_preview_map.dart';
import 'package:clean_spot/features/report/report_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: ReportScreen()));
    await tester.pump();
  }

  testWidgets('the location card shows a real map preview and no painted map', (
    tester,
  ) async {
    await pumpAt(tester, const Size(412, 915));

    expect(find.byType(LocationPreviewMap), findsOneWidget);
    expect(find.text('Location not added yet'), findsOneWidget);
    // No location yet: a neutral map without a pin.
    expect(find.byKey(const ValueKey('location-pin')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'no overflow on a short (640 px high) phone and the page still scrolls',
    (tester) async {
      // Width 412: the test font (Ahem) is wider than real text and overflows the
      // untouched 'Site photo' header row below ~380 px; the real 360 px width is
      // checked on a device.
      await pumpAt(tester, const Size(412, 640));
      expect(tester.takeException(), isNull);

      final scrollable = find.byType(Scrollable).first;
      final before = tester.state<ScrollableState>(scrollable).position.pixels;
      // Start the drag on the map preview itself: it must not swallow it.
      await tester.drag(
        find.byType(LocationPreviewMap),
        const Offset(0, -120),
        warnIfMissed: false,
      );
      await tester.pump(const Duration(milliseconds: 500));
      final after = tester.state<ScrollableState>(scrollable).position.pixels;

      expect(after, greaterThan(before));
      expect(tester.takeException(), isNull);
    },
  );
}
