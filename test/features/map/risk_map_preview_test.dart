import 'dart:io';

import 'package:clean_spot/features/map/risk_map_preview.dart';
import 'package:clean_spot/features/map/risk_map_view.dart';
import 'package:clean_spot/models/report_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

ReportModel _report(String id) => ReportModel.fromMap(id, {
      'uid': 'u1',
      'location': const GeoPoint(6.9271, 79.8612),
      'geohash': 'tc2b6w9q1',
      'status': 'valid',
      'createdAt': Timestamp.fromDate(DateTime.now()),
    });

/// A Home-like scrolling page with the preview in it, plus a stand-in /map.
Widget _app({required Stream<List<ReportModel>> reports, Key? listKey}) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, _) => Scaffold(
          body: ListView(
            key: listKey,
            padding: const EdgeInsets.all(20),
            children: [
              RiskMapPreview(reports: reports),
              const SizedBox(height: 900),
            ],
          ),
        ),
      ),
      GoRoute(path: '/map', builder: (_, _) => const Text('FULL MAP SCREEN')),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

void main() {
  testWidgets('the preview is a 300 px card with an "Open full map" label',
      (tester) async {
    await tester.pumpWidget(_app(reports: Stream.value([_report('a')])));
    await tester.pump();

    expect(find.text('Open full map'), findsOneWidget);
    expect(tester.getSize(find.byType(RiskMapPreview)).height, 300);
    // Same map widget as the Map tab.
    expect(find.byType(RiskMapView), findsOneWidget);
  });

  testWidgets('tapping the preview opens the full /map screen', (tester) async {
    await tester.pumpWidget(_app(reports: Stream.value([_report('a')])));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('risk-map-preview-tap')));
    await tester.pumpAndSettle();

    expect(find.text('FULL MAP SCREEN'), findsOneWidget);
  });

  testWidgets('the preview has no zoom controls and does not capture drags',
      (tester) async {
    await tester.pumpWidget(_app(reports: Stream.value([_report('a')])));
    await tester.pump();

    // No zoom +/- buttons in the preview.
    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.byIcon(Icons.remove), findsNothing);

    // Dragging on the map scrolls the PAGE instead of panning the map.
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.pixels, 0);
    await tester.drag(
      find.byKey(const ValueKey('risk-map-preview-tap')),
      const Offset(0, -150),
    );
    await tester.pump();
    expect(scrollable.position.pixels, greaterThan(0));
  });

  testWidgets('the full map (interactive) keeps its zoom controls',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RiskMapView(reports: Stream.value([_report('a')])),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.byIcon(Icons.remove), findsOneWidget);
  });

  test('Home layout: header, map, report button, then recent reports', () {
    final home = File('lib/features/home/home_screen.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');

    final tagline = home.indexOf('A small action can protect a whole street.');
    final map = home.indexOf('const RiskMapPreview()');
    final button = home.indexOf("'Report a Breeding Site'");
    final recent = home.indexOf("'Recent reports'");
    final viewAll = home.indexOf("context.push('/profile/reports')");
    expect(tagline, isNot(-1));
    expect(tagline < map && map < button && button < recent, isTrue);
    expect(viewAll, greaterThan(recent));

    for (final removed in [
      'Demo community',
      'points earned',
      'Every report helps your community.',
      'Explore nearby',
      'Use your points',
      'After rain, take a look around',
      'Demo seasonal reminder',
      'InfoNote',
    ]) {
      expect(home.contains(removed), isFalse, reason: removed);
    }
  });

  test('the Profile screen no longer shows the demo-user note', () {
    final profile = File('lib/features/profile/profile_screen.dart')
        .readAsStringSync();
    expect(profile.contains('Fictional demonstration user'), isFalse);
    expect(File('lib/features/profile/dummy_data.dart').existsSync(), isFalse);
  });
}
