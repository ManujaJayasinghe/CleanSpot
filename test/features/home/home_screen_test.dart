import 'package:clean_spot/features/home/home_screen.dart';
import 'package:clean_spot/features/map/risk_map_preview.dart';
import 'package:clean_spot/features/profile/current_user.dart';
import 'package:clean_spot/models/report_model.dart';
import 'package:clean_spot/models/user_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const double _navBarHeight = 80;

ReportModel _report(String id) => ReportModel.fromMap(id, {
      'uid': 'u1',
      'location': const GeoPoint(6.9271, 79.8612),
      'geohash': 'tc2b6w9q1',
      'status': 'valid',
      'type': 'tire',
      'createdAt': Timestamp.fromDate(DateTime(2026, 11, 20, 10, 30)),
    });

/// Home inside a shell with a bottom navigation bar, like the real app.
Widget _app() {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, _) => Scaffold(
          body: HomeScreen(
            user: const CurrentUser(name: 'Manuja Jayasinghe', email: 'm@x.lk'),
            pointsStream: Stream.value(
              UserModel(
                uid: 'u1',
                displayName: 'Manuja',
                pointsBalance: 55,
                createdAt: DateTime(2026, 11, 1),
              ),
            ),
            mapReports: Stream.value([_report('a')]),
            recentReports: Stream.value([_report('a')]),
          ),
          bottomNavigationBar: SizedBox(
            height: _navBarHeight,
            child: NavigationBar(
              destinations: const [
                NavigationDestination(icon: Icon(Icons.map), label: 'Map'),
                NavigationDestination(icon: Icon(Icons.person), label: 'Me'),
              ],
            ),
          ),
        ),
      ),
      GoRoute(path: '/report', builder: (_, _) => const Text('REPORT SCREEN')),
      GoRoute(path: '/map', builder: (_, _) => const Text('MAP SCREEN')),
      GoRoute(
        path: '/profile/reports',
        builder: (_, _) => const Text('MY REPORTS SCREEN'),
      ),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

Future<void> _pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

double _top(WidgetTester t, Finder f) => t.getTopLeft(f).dy;
double _bottom(WidgetTester t, Finder f) => t.getBottomLeft(f).dy;

void main() {
  final points = find.byKey(const ValueKey('home-points-card'));
  final map = find.byType(RiskMapPreview);
  final reportButton = find.byKey(const ValueKey('home-report-button'));
  final recentTitle = find.text('Recent reports');
  final latest = find.byType(LatestReportCard);

  testWidgets('tall phone: points, map, report button, recent reports in order, '
      'map fills the space, recent reports sit above the nav bar',
      (tester) async {
    await _pumpAt(tester, const Size(412, 915));

    expect(find.text('Hello, Manuja'), findsOneWidget);
    expect(find.text('A small action can protect a whole street.'),
        findsOneWidget);
    expect(find.text('AVAILABLE POINTS'), findsOneWidget);
    expect(find.text('55'), findsOneWidget);
    expect(find.text('Report a Breeding Site'), findsOneWidget);

    // Order, top to bottom.
    expect(_top(tester, points) < _top(tester, map), isTrue);
    expect(_bottom(tester, points) <= _top(tester, map), isTrue);
    expect(_bottom(tester, map) <= _top(tester, reportButton), isTrue);
    expect(_bottom(tester, reportButton) <= _top(tester, recentTitle), isTrue);
    expect(_top(tester, recentTitle) < _top(tester, latest), isTrue);

    // Compact points card and 56 px button.
    final pointsHeight = tester.getSize(points).height;
    expect(pointsHeight, inInclusiveRange(64, 90));
    expect(tester.getSize(reportButton).height, 56);

    // The map is taller than the old 300 px and far above its minimum.
    expect(tester.getSize(map).height, greaterThan(300));

    // Recent reports end just above the navigation bar (14 px page padding).
    final bodyBottom = 915.0 - _navBarHeight;
    final gap = bodyBottom - _bottom(tester, latest);
    expect(gap, inInclusiveRange(12, 16));

    // The page fits: nothing to scroll.
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.maxScrollExtent, 0);

    expect(tester.takeException(), isNull);
  });

  testWidgets('short phone: no overflow, the map keeps its minimum height and '
      'the page scrolls', (tester) async {
    await _pumpAt(tester, const Size(360, 640));

    expect(tester.takeException(), isNull);
    expect(tester.getSize(map).height, HomeScreen.minMapHeight);

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.maxScrollExtent, greaterThan(0));

    // Scrolling to the bottom brings Recent reports into view.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
    await tester.pump();
    expect(_bottom(tester, latest), lessThanOrEqualTo(640.0 - _navBarHeight));
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text on a tall phone still lays out without overflow',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pumpAt(tester, const Size(412, 915));

    expect(tester.takeException(), isNull);
    expect(tester.getSize(map).height,
        greaterThanOrEqualTo(HomeScreen.minMapHeight));
  });

  testWidgets('the Report button works over the decoration', (tester) async {
    await _pumpAt(tester, const Size(412, 915));

    // Tap the left edge of the button, far from its label and icon.
    final topLeft = tester.getTopLeft(reportButton);
    await tester.tapAt(topLeft + const Offset(12, 28));
    await tester.pumpAndSettle();
    expect(find.text('REPORT SCREEN'), findsOneWidget);
  });

  testWidgets('View all opens the reports list and back returns to Home',
      (tester) async {
    await _pumpAt(tester, const Size(412, 915));

    await tester.tap(find.text('View all'));
    await tester.pumpAndSettle();
    expect(find.text('MY REPORTS SCREEN'), findsOneWidget);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('Hello, Manuja'), findsOneWidget);
  });
}
