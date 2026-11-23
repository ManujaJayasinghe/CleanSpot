import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../models/report_model.dart';

/// Time filter chips on the risk map.
enum MapTimeRange {
  last7Days('Last 7 days', Duration(days: 7)),
  last30Days('Last 30 days', Duration(days: 30)),
  allTime('All time', null);

  const MapTimeRange(this.label, this.window);

  final String label;

  /// How far back to look; null means no limit.
  final Duration? window;
}

/// Heatmap vs. marker view.
enum MapViewMode { heatmap, markers }

/// A report can be drawn only if it has a real position. Reports saved
/// without a location are read as (0, 0) by `ReportModel.fromMap`.
bool isMappable(ReportModel report) {
  final point = report.location;
  return !(point.latitude == 0 && point.longitude == 0);
}

/// Keeps the mappable reports created within [range] of [now].
List<ReportModel> filterReports(
  List<ReportModel> reports,
  MapTimeRange range,
  DateTime now,
) {
  final window = range.window;
  final cutoff = window == null ? null : now.subtract(window);
  return reports
      .where(isMappable)
      .where((r) => cutoff == null || r.createdAt.isAfter(cutoff))
      .toList();
}

/// One heatmap point per report. Heat builds up where reports overlap.
List<WeightedLatLng> heatmapPoints(List<ReportModel> reports) {
  return [
    for (final r in reports)
      WeightedLatLng(LatLng(r.location.latitude, r.location.longitude)),
  ];
}

const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// e.g. `17 Nov 2026`.
String formatReportDate(DateTime date) =>
    '${date.day} ${_months[date.month - 1]} ${date.year}';
