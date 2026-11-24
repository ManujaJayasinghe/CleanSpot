import 'package:clean_spot/features/analysis/analysis_screen.dart';
import 'package:clean_spot/features/analysis/dengue_stat.dart';
import 'package:clean_spot/features/analysis/risk_index.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serves the real files under assets/ straight from disk, so the screen tests
/// do not depend on the platform asset channel.
class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final file = File(key);
    if (!file.existsSync()) throw FlutterError('Unable to load asset: $key');
    return ByteData.sublistView(file.readAsBytesSync());
  }
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  Stream<List<LiveReport>>? reports,
}) async {
  tester.view.physicalSize = const Size(900, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: AnalysisScreen(
        liveReports: reports ?? Stream.value(const <LiveReport>[]),
        clock: () => DateTime(2026, 11, 24),
        bundle: _DiskBundle(),
      ),
    ),
  );
  // Asset loading runs in real time, outside the test's fake clock: wait
  // (up to 10 s) until the screen has swapped its spinner for the content.
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    if (find.text('Seasonal dengue risk').evaluate().isNotEmpty) break;
  }
  await tester.pump(const Duration(seconds: 2)); // chart animations
}

void main() {
  testWidgets('shows real data, the risk index, charts and sourced insights', (
    tester,
  ) async {
    await _pumpScreen(tester);

    expect(find.text('Dengue Analysis'), findsOneWidget);
    expect(find.text('Weekly dengue cases'), findsOneWidget);
    expect(find.textContaining('Top 10 districts in'), findsOneWidget);
    expect(find.text('Insights for Colombo'), findsOneWidget);

    // Real data: no sample warning, and the data status note is shown.
    expect(find.textContaining('Sample data only'), findsNothing);
    expect(
      find.textContaining('Historical data: Epidemiology Unit WER, 2024 –'),
      findsOneWidget,
    );

    // Risk index for today (2026-11-24 is ISO week 48).
    expect(find.text('Seasonal dengue risk'), findsOneWidget);
    expect(find.text('Today · week 48 of 2026'), findsOneWidget);
    expect(find.text('How the risk index works'), findsOneWidget);
    expect(find.textContaining('this time of year'), findsWidgets);
    expect(find.textContaining('0 live reports'), findsWidgets);

    // The insight notes show their source links, not "Source pending".
    expect(find.textContaining('Source pending'), findsNothing);
    expect(
      find.textContaining('https://wwwnc.cdc.gov/eid/article/26/4/19-0435'),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('live reports in a district show in its reason line', (
    tester,
  ) async {
    final now = DateTime(2026, 11, 24);
    // Three valid reports in the last two weeks near Colombo.
    final reports = Stream.value([
      for (var i = 0; i < 3; i++)
        LiveReport(
          lat: 6.93,
          lng: 79.85,
          createdAt: now.subtract(Duration(days: i + 1)),
        ),
    ]);
    await _pumpScreen(tester, reports: reports);

    expect(find.textContaining('3 live reports'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('says so when live reports are not available', (tester) async {
    await _pumpScreen(tester, reports: const Stream.empty());

    expect(
      find.textContaining('Live CleanSpot reports are not available'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  test('dataStatusText says which years and weeks the data covers', () {
    final stats = [
      const DengueStat(district: 'Colombo', year: 2024, week: 1, cases: 1),
      const DengueStat(district: 'Colombo', year: 2025, week: 52, cases: 1),
    ];
    expect(
      dataStatusText(stats, DateTime(2026, 11, 24)),
      'Historical data: Epidemiology Unit WER, 2024 – 2025 '
      '(latest: 2025 week 52). 2026 reports not yet available.',
    );
    // Once the data reaches the current year the "not yet available" part goes.
    final withNow = [
      ...stats,
      const DengueStat(district: 'Colombo', year: 2026, week: 30, cases: 1),
    ];
    expect(
      dataStatusText(withNow, DateTime(2026, 11, 24)),
      'Historical data: Epidemiology Unit WER, 2024 – 2026 '
      '(latest: 2026 week 30).',
    );
  });
}
