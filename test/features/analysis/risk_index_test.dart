import 'package:clean_spot/features/analysis/dengue_stat.dart';
import 'package:clean_spot/features/analysis/district_centres.dart';
import 'package:clean_spot/features/analysis/risk_constants.dart';
import 'package:clean_spot/features/analysis/risk_index.dart';
import 'package:clean_spot/features/analysis/waste_period.dart';
import 'package:flutter_test/flutter_test.dart';

DengueStat row(String district, int year, int week, int cases) =>
    DengueStat(district: district, year: year, week: week, cases: cases);

void main() {
  group('isoWeek', () {
    test('mid-year date', () {
      expect(isoWeek(DateTime(2026, 11, 24)), 48);
    });

    test('days around New Year belong to the right ISO year', () {
      expect(isoWeek(DateTime(2025, 12, 29)), 1); // Monday, week 1 of 2026
      expect(isoWeek(DateTime(2026, 1, 1)), 1);
      expect(isoWeek(DateTime(2024, 12, 30)), 1); // week 1 of 2025
      expect(isoWeek(DateTime(2021, 1, 3)), 53); // last day of 2020's week 53
      expect(isoWeek(DateTime(2025, 12, 28)), 52);
    });

    test('ignores the time of day', () {
      expect(isoWeek(DateTime(2026, 11, 24, 23, 59)), 48);
    });
  });

  group('weekDistance', () {
    test('plain and wrapped distances', () {
      expect(weekDistance(10, 12), 2);
      expect(weekDistance(12, 10), 2);
      expect(weekDistance(48, 48), 0);
      expect(weekDistance(52, 1), 1);
      expect(weekDistance(1, 52), 1);
      expect(weekDistance(51, 2), 3);
    });

    test('week 53 counts as week 52', () {
      expect(weekDistance(53, 52), 0);
      expect(weekDistance(53, 1), 1);
    });
  });

  group('seasonalLevel and districtNormal', () {
    final stats = [
      row('Colombo', 2024, 47, 10),
      row('Colombo', 2024, 48, 20),
      row('Colombo', 2024, 49, 30),
      row('Colombo', 2025, 48, 40),
      row('Colombo', 2025, 20, 100), // far from week 48
      row('Gampaha', 2024, 48, 999), // other district
    ];

    test('averages the same week +/- 1 over all years', () {
      // (10 + 20 + 30 + 40) / 4
      expect(seasonalLevel(stats, 'Colombo', 48), 25);
    });

    test('the window is a parameter', () {
      expect(seasonalLevel(stats, 'Colombo', 48, window: 0), 30);
    });

    test('the window wraps around the new year', () {
      final wrap = [
        row('Colombo', 2024, 52, 10),
        row('Colombo', 2025, 1, 30),
        row('Colombo', 2025, 3, 500),
      ];
      expect(seasonalLevel(wrap, 'Colombo', 1), 20); // weeks 52 and 1, not 3
    });

    test('null when the district has no rows in those weeks', () {
      expect(seasonalLevel(stats, 'Colombo', 30), isNull);
      expect(seasonalLevel(stats, 'Kandy', 48), isNull);
    });

    test('normal is the average of every week of the district', () {
      // (10 + 20 + 30 + 40 + 100) / 5
      expect(districtNormal(stats, 'Colombo'), 40);
      expect(districtNormal(stats, 'Kandy'), isNull);
    });
  });

  group('score and levels', () {
    test('score divides by the normal and is 0 when the normal is 0', () {
      expect(seasonalScore(30, 20), 1.5);
      expect(seasonalScore(0, 0), 0);
      expect(seasonalScore(5, 0), 0);
    });

    test(
      'thresholds: below low is Low, up to high is Medium, above is High',
      () {
        expect(levelForScore(seasonalLowBelow - 0.01), RiskLevel.low);
        expect(levelForScore(seasonalLowBelow), RiskLevel.medium);
        expect(levelForScore(1.0), RiskLevel.medium);
        expect(levelForScore(seasonalHighAbove), RiskLevel.medium);
        expect(levelForScore(seasonalHighAbove + 0.01), RiskLevel.high);
        expect(levelForScore(0), RiskLevel.low);
      },
    );

    test('bumpLevel goes up and stops at High', () {
      expect(bumpLevel(RiskLevel.low, 1), RiskLevel.medium);
      expect(bumpLevel(RiskLevel.medium, 1), RiskLevel.high);
      expect(bumpLevel(RiskLevel.high, 1), RiskLevel.high);
      expect(bumpLevel(RiskLevel.low, 2), RiskLevel.high);
      expect(bumpLevel(RiskLevel.low, 0), RiskLevel.low);
    });
  });

  group('live reports', () {
    test('the district centres cover the 26 RDHS rows once each', () {
      final names = districtCentres.map((c) => c.name).toList();
      expect(names.toSet(), hasLength(26));
      expect(names, contains('Kalmunai'));
    });

    test('nearestDistrict picks the closest centre', () {
      expect(nearestDistrict(6.93, 79.85), 'Colombo');
      expect(nearestDistrict(9.66, 80.02), 'Jaffna');
      expect(nearestDistrict(7.41, 81.82), 'Kalmunai');
      expect(nearestDistrict(7.29, 81.67), 'Ampara');
    });

    test('countLiveReports counts only the last 14 days, per district', () {
      final now = DateTime(2026, 11, 24, 12);
      LiveReport at(double lat, double lng, DateTime t) =>
          LiveReport(lat: lat, lng: lng, createdAt: t);
      final counts = countLiveReports([
        at(6.93, 79.85, now.subtract(const Duration(days: 1))),
        at(6.94, 79.86, now.subtract(const Duration(days: 14))), // edge: in
        at(6.95, 79.87, now.subtract(const Duration(days: 15))), // too old
        at(9.66, 80.02, now.subtract(const Duration(hours: 2))),
        at(6.93, 79.85, now.add(const Duration(days: 1))), // future: out
      ], now);
      expect(counts, {'Colombo': 2, 'Jaffna': 1});
    });
  });

  group('reasonLine', () {
    test('matches the wording on the screen', () {
      expect(
        reasonLine(score: 1.6, wastePeriods: const [], liveReports: 3),
        'Usually 1.6× higher this time of year · 3 live reports',
      );
      expect(
        reasonLine(score: 0.5, wastePeriods: const [], liveReports: 1),
        'Usually 0.5× the normal level this time of year · 1 live report',
      );
      expect(
        reasonLine(score: 1.02, wastePeriods: const [], liveReports: 0),
        'Usually about the normal level this time of year · 0 live reports',
      );
    });

    test('leaves out the live count when reports are unavailable', () {
      expect(
        reasonLine(score: 1.6, wastePeriods: const [], liveReports: null),
        'Usually 1.6× higher this time of year',
      );
    });

    test('says when there is no historical data', () {
      expect(
        reasonLine(score: null, wastePeriods: const [], liveReports: null),
        'No historical data for this time of year',
      );
    });

    test('names a high-waste period', () {
      final p = WastePeriod(
        label: 'Collection halted',
        start: DateTime(2026, 11, 1),
        end: DateTime(2026, 11, 30),
        districts: const [],
        sourceUrl: 'https://example.org/x',
      );
      expect(
        reasonLine(score: 1.6, wastePeriods: [p], liveReports: 0),
        'Usually 1.6× higher this time of year · '
        'High-waste period: Collection halted · 0 live reports',
      );
    });
  });

  group('computeDistrictRisk', () {
    final today = DateTime(2026, 11, 24); // ISO week 48
    // Colombo: week 48 average 30 over a normal of 15 -> score 2.0 (High).
    // Kandy: week 48 average 4 over a normal of 8 -> score 0.5 (Low).
    // Galle: week 48 average 10 over a normal of 10 -> score 1.0 (Medium).
    final stats = [
      row('Colombo', 2024, 48, 30),
      row('Colombo', 2024, 10, 0),
      row('Kandy', 2024, 48, 4),
      row('Kandy', 2024, 10, 12),
      row('Galle', 2024, 48, 10),
      row('Galle', 2024, 10, 10),
    ];
    final wastePeriod = WastePeriod(
      label: 'Strike',
      start: DateTime(2026, 11, 20),
      end: DateTime(2026, 11, 28),
      districts: const ['Kandy'],
      sourceUrl: 'https://example.org/strike',
    );

    DistrictRisk risk(
      String district, {
      List<WastePeriod> periods = const [],
      Map<String, int>? live,
    }) => computeDistrictRisk(
      stats: stats,
      district: district,
      today: today,
      periods: periods,
      liveReportCounts: live,
    );

    test('base level comes from the seasonal score', () {
      expect(risk('Colombo').score, 2.0);
      expect(risk('Colombo').level, RiskLevel.high);
      expect(risk('Kandy').score, 0.5);
      expect(risk('Kandy').level, RiskLevel.low);
      expect(risk('Galle').score, 1.0);
      expect(risk('Galle').level, RiskLevel.medium);
    });

    test('a sourced waste period for the district adds one level', () {
      expect(risk('Kandy', periods: [wastePeriod]).level, RiskLevel.medium);
      expect(risk('Kandy', periods: [wastePeriod]).wastePeriods, hasLength(1));
    });

    test('a waste period for another district changes nothing', () {
      expect(risk('Galle', periods: [wastePeriod]).level, RiskLevel.medium);
    });

    test('live reports bump only when ABOVE the threshold', () {
      final at = liveReportsBumpAbove;
      expect(risk('Galle', live: {'Galle': at}).level, RiskLevel.medium);
      expect(risk('Galle', live: {'Galle': at + 1}).level, RiskLevel.high);
      expect(risk('Galle', live: const {}).level, RiskLevel.medium);
      expect(risk('Galle', live: const {}).liveReports, 0);
    });

    test('unavailable live reports add no bump', () {
      final r = risk('Galle');
      expect(r.liveReports, isNull);
      expect(r.level, RiskLevel.medium);
    });

    test('both bumps stack but stop at High', () {
      final r = risk('Kandy', periods: [wastePeriod], live: {'Kandy': 5});
      expect(r.level, RiskLevel.high);
      expect(risk('Colombo', live: {'Colombo': 9}).level, RiskLevel.high);
    });

    test('a district without data is Low with its own reason', () {
      final r = risk('Jaffna');
      expect(r.score, isNull);
      expect(r.level, RiskLevel.low);
      expect(r.reason, contains('No historical data'));
    });

    test('a district that never had a case is Low, not a division by zero', () {
      final zeros = [row('Mannar', 2024, 48, 0), row('Mannar', 2024, 10, 0)];
      final r = computeDistrictRisk(
        stats: zeros,
        district: 'Mannar',
        today: today,
      );
      expect(r.score, 0);
      expect(r.level, RiskLevel.low);
    });
  });

  test('computeRisks lists every district, highest level first', () {
    final stats = [
      row('Colombo', 2024, 48, 30),
      row('Colombo', 2024, 10, 0),
      row('Kandy', 2024, 48, 4),
      row('Kandy', 2024, 10, 12),
    ];
    final risks = computeRisks(stats: stats, today: DateTime(2026, 11, 24));
    expect(risks.map((r) => r.district), ['Colombo', 'Kandy']);
    expect(risks.map((r) => r.level), [RiskLevel.high, RiskLevel.low]);
  });
}
