import 'package:clean_spot/features/analysis/analysis_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows both charts and insights from the bundled sample data',
      (tester) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: AnalysisScreen()));
    // Asset loading runs in real time, outside the test's fake clock.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2)); // chart animations

    expect(find.text('Dengue Analysis'), findsOneWidget);
    expect(find.text('Weekly dengue cases'), findsOneWidget);
    expect(find.textContaining('Top 10 districts in'), findsOneWidget);
    expect(find.text('Insights for Colombo'), findsOneWidget);
    expect(find.textContaining('Sample data only'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
