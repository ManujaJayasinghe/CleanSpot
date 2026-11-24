import 'dengue_stat.dart';

/// Cases in one week, summed over the rows for that district.
class WeekPoint {
  const WeekPoint({required this.year, required this.week, required this.cases});

  final int year;
  final int week;
  final int cases;
}

/// A district's total cases for one year.
class DistrictTotal {
  const DistrictTotal({required this.district, required this.cases});

  final String district;
  final int cases;
}

/// A short written takeaway shown on an insight card.
class Insight {
  const Insight({required this.title, required this.body});

  final String title;
  final String body;
}

/// How a district name from the data is shown to people. Kalmunai is its own
/// RDHS in the Epidemiology Unit tables, separate from Ampara; the label only
/// tells readers where it is.
String displayDistrictName(String district) =>
    district == 'Kalmunai' ? 'Kalmunai (Ampara)' : district;

/// Distinct district names, A to Z.
List<String> districtsOf(List<DengueStat> stats) {
  final names = {for (final s in stats) s.district}.toList()..sort();
  return names;
}

/// The most recent year in the data, or null if there is no data.
int? latestYear(List<DengueStat> stats) {
  if (stats.isEmpty) return null;
  return stats.map((s) => s.year).reduce((a, b) => a > b ? a : b);
}

/// Weekly cases for [district], oldest first.
List<WeekPoint> weeklySeries(List<DengueStat> stats, String district) {
  final byWeek = <(int, int), int>{};
  for (final s in stats) {
    if (s.district != district) continue;
    final key = (s.year, s.week);
    byWeek[key] = (byWeek[key] ?? 0) + s.cases;
  }
  final points = [
    for (final e in byWeek.entries)
      WeekPoint(year: e.key.$1, week: e.key.$2, cases: e.value),
  ]..sort((a, b) {
      final byYear = a.year.compareTo(b.year);
      return byYear != 0 ? byYear : a.week.compareTo(b.week);
    });
  return points;
}

/// The [limit] districts with the most cases in [year], highest first.
List<DistrictTotal> topDistricts(
  List<DengueStat> stats,
  int year, {
  int limit = 10,
}) {
  final totals = <String, int>{};
  for (final s in stats) {
    if (s.year != year) continue;
    totals[s.district] = (totals[s.district] ?? 0) + s.cases;
  }
  final list = [
    for (final e in totals.entries)
      DistrictTotal(district: e.key, cases: e.value),
  ]..sort((a, b) {
      final byCases = b.cases.compareTo(a.cases);
      return byCases != 0 ? byCases : a.district.compareTo(b.district);
    });
  return list.take(limit).toList();
}

const List<String> _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Rough calendar month (0-11) for an ISO week number.
int _monthOfWeek(int week) => (((week - 1) * 7) ~/ 30.44).clamp(0, 11);

/// Insight cards worked out from the data for [district].
///
/// These are descriptive only: they say what the numbers show, not why.
List<Insight> buildInsights(List<DengueStat> stats, String district) {
  final series = weeklySeries(stats, district);
  if (series.isEmpty) return const [];
  final name = displayDistrictName(district);

  final insights = <Insight>[];

  // 1. The single worst week.
  final peak = series.reduce((a, b) => a.cases >= b.cases ? a : b);
  insights.add(
    Insight(
      title: 'Worst week on record',
      body: '$name peaked in week ${peak.week} of ${peak.year} with '
          '${peak.cases} cases.',
    ),
  );

  // 2. Busiest time of year, averaged over all years in the data.
  final perMonth = List<int>.filled(12, 0);
  for (final p in series) {
    perMonth[_monthOfWeek(p.week)] += p.cases;
  }
  var busiest = 0;
  for (var m = 1; m < 12; m++) {
    if (perMonth[m] > perMonth[busiest]) busiest = m;
  }
  if (perMonth[busiest] > 0) {
    insights.add(
      Insight(
        title: 'Busiest time of year',
        body: 'Across all years, cases are highest around '
            '${_monthNames[busiest]}. Prevention work before then matters '
            'most.',
      ),
    );
  }

  // 3. This year against the same weeks last year.
  final year = latestYear(stats)!;
  final thisYear = series.where((p) => p.year == year).toList();
  final lastYear = series.where((p) => p.year == year - 1).toList();
  if (thisYear.isNotEmpty && lastYear.isNotEmpty) {
    final maxWeek = thisYear.map((p) => p.week).reduce((a, b) => a > b ? a : b);
    final now = thisYear.fold<int>(0, (sum, p) => sum + p.cases);
    final before = lastYear
        .where((p) => p.week <= maxWeek)
        .fold<int>(0, (sum, p) => sum + p.cases);
    if (before > 0) {
      final change = ((now - before) / before * 100).round();
      final direction = change >= 0 ? 'higher' : 'lower';
      insights.add(
        Insight(
          title: '$year compared with ${year - 1}',
          body: 'Up to week $maxWeek, cases are ${change.abs()}% $direction '
              'than the same weeks of ${year - 1} ($now vs $before).',
        ),
      );
    }
  }

  return insights;
}
