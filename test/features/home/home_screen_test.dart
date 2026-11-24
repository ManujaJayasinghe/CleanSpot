import 'package:clean_spot/app/theme_proposal.dart';
import 'package:clean_spot/features/ai_validation/validation_result.dart';
import 'package:clean_spot/features/home/home_screen.dart';
import 'package:clean_spot/features/map/risk_map_preview.dart';
import 'package:clean_spot/features/profile/current_user.dart';
import 'package:clean_spot/features/profile/widgets/widgets.dart';
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
  final frame = find.byKey(const ValueKey('home-points-map-card'));
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

    // Compact points header and 56 px button.
    final pointsHeight = tester.getSize(points).height;
    expect(pointsHeight, inInclusiveRange(64, 90));
    expect(tester.getSize(reportButton).height, 56);

    // The map is taller than the old 300 px and far above its minimum.
    expect(tester.getSize(map).height, greaterThan(300));

    // Recent reports end 12 px above the navigation bar.
    final bodyBottom = 915.0 - _navBarHeight;
    final gap = bodyBottom - _bottom(tester, latest);
    expect(gap, closeTo(12, 0.5));

    // The page fits: nothing to scroll.
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.maxScrollExtent, 0);

    expect(tester.takeException(), isNull);
  });

  testWidgets('points and map share one green LeafBackground frame',
      (tester) async {
    await _pumpAt(tester, const Size(412, 915));

    // Exactly one leaf card on Home: the frame. The button has none.
    expect(find.byType(LeafBackground), findsOneWidget);
    expect(
      find.descendant(of: frame, matching: find.byType(RiskMapPreview)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: frame, matching: find.text('AVAILABLE POINTS')),
      findsOneWidget,
    );
    expect(find.descendant(of: frame, matching: reportButton), findsNothing);

    final frameBox = tester
        .widget<Container>(
          find.descendant(of: frame, matching: find.byType(Container)).first,
        )
        .decoration as BoxDecoration;
    expect(frameBox.color, const Color(0xFF145A32));
    expect(frameBox.borderRadius, BorderRadius.circular(24));

    // The frame runs from the top of the points row to the bottom of the map.
    expect(_top(tester, frame), closeTo(_top(tester, points), 0.5));
    // The map is inset 8 px on the left, right and bottom.
    final f = tester.getRect(frame);
    final m = tester.getRect(map);
    expect(m.left - f.left, 8);
    expect(f.right - m.right, 8);
    expect(f.bottom - m.bottom, 8);
    // Below the header, flush with it.
    expect(m.top, greaterThanOrEqualTo(tester.getRect(points).bottom - 0.5));

    // The map has its own 16 px corners and no border of its own.
    final mapBox = tester
        .widget<Container>(
          find.descendant(of: map, matching: find.byType(Container)).first,
        )
        .decoration as BoxDecoration;
    expect(mapBox.borderRadius, BorderRadius.circular(16));
    expect(mapBox.border, isNull);

    expect(tester.takeException(), isNull);
  });

  testWidgets('the Report button is a solid AppColors.primary fill with no '
      'leaf or circle', (tester) async {
    await _pumpAt(tester, const Size(412, 915));

    final material = tester.widget<Material>(
      find.ancestor(of: reportButton, matching: find.byType(Material)).first,
    );
    expect(material.color, AppColors.primary);
    expect(material.borderRadius, BorderRadius.circular(18));
    expect(tester.getSize(reportButton).height, 56);
    expect(tester.getSize(reportButton).width, 412 - 40);

    // The only leaf icon on Home is the one in the frame.
    expect(find.byIcon(Icons.eco_outlined), findsOneWidget);
    expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);
    expect(find.text('Report a Breeding Site'), findsOneWidget);
  });

  testWidgets('Recent reports is compact and keeps its content',
      (tester) async {
    await _pumpAt(tester, const Size(412, 915));

    final title = tester.widget<Text>(recentTitle);
    expect(title.style!.fontSize, 17);
    expect(
      tester.widget<Text>(find.text('View all')).style!.fontSize,
      13,
    );

    // Latest report: title, status chip, coordinates and date.
    expect(find.text(SiteCategory.labelFor('tire')), findsOneWidget);
    expect(find.text('valid'), findsOneWidget);
    expect(find.textContaining('6.9271° N'), findsOneWidget);
    expect(find.textContaining('Nov 20, 2026'), findsOneWidget);
    // Compact chip.
    expect(tester.getSize(find.byType(StatusChip)).height, lessThan(24));
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
