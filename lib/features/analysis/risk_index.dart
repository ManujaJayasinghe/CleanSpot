import 'dart:math' as math;

import 'dengue_stat.dart';
import 'district_centres.dart';
import 'risk_constants.dart';
import 'waste_period.dart';

/// Low, Medium or High. The index order is the severity order.
enum RiskLevel {
  low('Low'),
  medium('Medium'),
  high('High');

  const RiskLevel(this.label);

  final String label;
}

/// A valid CleanSpot report reduced to what the index needs.
class LiveReport {
  const LiveReport({
    required this.lat,
    required this.lng,
    required this.createdAt,
  });

  final double lat;
  final double lng;
  final DateTime createdAt;
}

/// The seasonal risk of one district for one day, with the numbers behind it.
class DistrictRisk {
  const DistrictRisk({
    required this.district,
    required this.level,
    required this.seasonalLevel,
    required this.districtNormal,
    required this.score,
    required this.wastePeriods,
    required this.liveReports,
    required this.reason,
  });

  final String district;

  /// Final level after the waste-period and live-report bumps.
  final RiskLevel level;

  /// Average cases in this district for this week +/- the window, over all
  /// years in the data. Null when the district has no data for those weeks.
  final double? seasonalLevel;

  /// Average weekly cases of the district over every week in the data.
  final double? districtNormal;

  /// [seasonalLevel] / [districtNormal]; null when there is no data.
  final double? score;

  /// Sourced high-waste periods that cover the day for this district.
  final List<WastePeriod> wastePeriods;

  /// Valid reports in the last [liveReportWindowDays] days; null when the
  /// live reports could not be loaded.
  final int? liveReports;

  /// One line: why the district has this level.
  final String reason;
}

// ------------------------------------------------------------------- dates

/// ISO 8601 week number (1-53) of [date]. Weeks start on Monday and week 1 is
/// the week that holds the year's first Thursday.
int isoWeek(DateTime date) {
  final day = DateTime.utc(date.year, date.month, date.day);
  // The Thursday of this week decides which year the week belongs to.
  final thursday = day.add(Duration(days: 4 - day.weekday));
  final firstDay = DateTime.utc(thursday.year, 1, 1);
  return (thursday.difference(firstDay).inDays ~/ 7) + 1;
}

/// How many weeks apart [a] and [b] are, wrapping around the year so that
/// week 52 and week 1 are one week apart. Week 53 counts as week 52.
int weekDistance(int a, int b) {
  final x = a > seasonalWeeksPerYear ? seasonalWeeksPerYear : a;
  final y = b > seasonalWeeksPerYear ? seasonalWeeksPerYear : b;
  final d = (x - y).abs() % seasonalWeeksPerYear;
  return math.min(d, seasonalWeeksPerYear - d);
}

// --------------------------------------------------------------- the index

/// Average cases for [district] in weeks within [window] of [week], over all
/// years in [stats]. Null when there is no such row.
double? seasonalLevel(
  List<DengueStat> stats,
  String district,
  int week, {
  int window = seasonalWeekWindow,
}) {
  var sum = 0;
  var count = 0;
  for (final s in stats) {
    if (s.district != district) continue;
    if (weekDistance(s.week, week) > window) continue;
    sum += s.cases;
    count++;
  }
  return count == 0 ? null : sum / count;
}

/// Average weekly cases of [district] over every week in [stats]. Null when
/// the district has no rows.
double? districtNormal(List<DengueStat> stats, String district) {
  var sum = 0;
  var count = 0;
  for (final s in stats) {
    if (s.district != district) continue;
    sum += s.cases;
    count++;
  }
  return count == 0 ? null : sum / count;
}

/// Seasonal level divided by the district normal. A normal of 0 means the
/// district never had a case, so the season cannot be above normal: the score
/// is 0 instead of a division by zero.
double seasonalScore(double seasonal, double normal) =>
    normal <= 0 ? 0 : seasonal / normal;

/// Below [seasonalLowBelow] is Low, up to and including [seasonalHighAbove]
/// is Medium, above it is High.
RiskLevel levelForScore(double score) {
  if (score < seasonalLowBelow) return RiskLevel.low;
  if (score > seasonalHighAbove) return RiskLevel.high;
  return RiskLevel.medium;
}

/// [level] raised by [steps] levels, never above High.
RiskLevel bumpLevel(RiskLevel level, int steps) {
  final index = math.min(level.index + steps, RiskLevel.values.length - 1);
  return RiskLevel.values[index];
}

// -------------------------------------------------------- live reports

double _radians(double degrees) => degrees * math.pi / 180;

/// Straight-line distance in kilometres between two points.
double distanceKm(double lat1, double lng1, double lat2, double lng2) {
  const earthKm = 6371.0;
  final dLat = _radians(lat2 - lat1);
  final dLng = _radians(lng2 - lng1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(_radians(lat1)) *
          math.cos(_radians(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * earthKm * math.asin(math.sqrt(a));
}

/// The district whose centre is nearest to the point.
///
/// This is an APPROXIMATION (see district_centres.dart): it does not use real
/// district boundaries.
String nearestDistrict(
  double lat,
  double lng, {
  List<DistrictCentre> centres = districtCentres,
}) {
  var best = centres.first;
  var bestKm = double.infinity;
  for (final c in centres) {
    final km = distanceKm(lat, lng, c.lat, c.lng);
    if (km < bestKm) {
      bestKm = km;
      best = c;
    }
  }
  return best.name;
}

/// Reports per district created in the last [days] days up to [now]. A report
/// dated in the future (a wrong phone clock) is not counted.
Map<String, int> countLiveReports(
  Iterable<LiveReport> reports,
  DateTime now, {
  int days = liveReportWindowDays,
  List<DistrictCentre> centres = districtCentres,
}) {
  final since = now.subtract(Duration(days: days));
  final counts = <String, int>{};
  for (final r in reports) {
    if (r.createdAt.isBefore(since) || r.createdAt.isAfter(now)) continue;
    final d = nearestDistrict(r.lat, r.lng, centres: centres);
    counts[d] = (counts[d] ?? 0) + 1;
  }
  return counts;
}

// ------------------------------------------------------------------- reason

String _times(double value) => value.toStringAsFixed(1);

String _seasonalPhrase(double? score) {
  if (score == null) return 'No historical data for this time of year';
  if ((score - 1).abs() <= nearNormalBand) {
    return 'Usually about the normal level this time of year';
  }
  if (score > 1) {
    return 'Usually ${_times(score)}× higher this time of year';
  }
  return 'Usually ${_times(score)}× the normal level this time of year';
}

/// The one-line reason shown next to a district's level.
String reasonLine({
  required double? score,
  required List<WastePeriod> wastePeriods,
  required int? liveReports,
}) {
  final parts = <String>[_seasonalPhrase(score)];
  if (wastePeriods.isNotEmpty) {
    parts.add('High-waste period: ${wastePeriods.first.label}');
  }
  if (liveReports != null) {
    parts.add('$liveReports live ${liveReports == 1 ? 'report' : 'reports'}');
  }
  return parts.join(' · ');
}

// -------------------------------------------------------------------- all

/// The seasonal risk of one [district] on [today].
///
/// 1. Seasonal score for today's ISO week (see [seasonalScore]) gives the
///    base level.
/// 2. +[wastePeriodBump] level if [today] is in a sourced high-waste period
///    for the district.
/// 3. +[liveReportBump] level if the district has more than
///    [liveReportsBumpAbove] valid reports in the window.
///
/// [liveReportCounts] is null when the live reports are not available; that
/// adds no bump and the reason line leaves the count out.
DistrictRisk computeDistrictRisk({
  required List<DengueStat> stats,
  required String district,
  required DateTime today,
  List<WastePeriod> periods = const [],
  Map<String, int>? liveReportCounts,
}) {
  final week = isoWeek(today);
  final seasonal = seasonalLevel(stats, district, week);
  final normal = districtNormal(stats, district);
  final score = (seasonal == null || normal == null)
      ? null
      : seasonalScore(seasonal, normal);

  var level = score == null ? RiskLevel.low : levelForScore(score);
  final active = activeWastePeriods(periods, district, today);
  if (active.isNotEmpty) level = bumpLevel(level, wastePeriodBump);

  final live = liveReportCounts == null
      ? null
      : (liveReportCounts[district] ?? 0);
  if (live != null && live > liveReportsBumpAbove) {
    level = bumpLevel(level, liveReportBump);
  }

  return DistrictRisk(
    district: district,
    level: level,
    seasonalLevel: seasonal,
    districtNormal: normal,
    score: score,
    wastePeriods: active,
    liveReports: live,
    reason: reasonLine(score: score, wastePeriods: active, liveReports: live),
  );
}

/// The risk of every district in [stats] on [today], highest level first and
/// then highest score, then A to Z.
List<DistrictRisk> computeRisks({
  required List<DengueStat> stats,
  required DateTime today,
  List<WastePeriod> periods = const [],
  Map<String, int>? liveReportCounts,
}) {
  final names = {for (final s in stats) s.district}.toList()..sort();
  final risks = [
    for (final d in names)
      computeDistrictRisk(
        stats: stats,
        district: d,
        today: today,
        periods: periods,
        liveReportCounts: liveReportCounts,
      ),
  ];
  risks.sort((a, b) {
    final byLevel = b.level.index.compareTo(a.level.index);
    if (byLevel != 0) return byLevel;
    final byScore = (b.score ?? -1).compareTo(a.score ?? -1);
    return byScore != 0 ? byScore : a.district.compareTo(b.district);
  });
  return risks;
}
