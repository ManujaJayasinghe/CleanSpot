import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../models/report_model.dart';

/// Platform channel used to check whether the native Google Maps API key
/// (`android/local.properties` or `ios/Flutter/Secrets.xcconfig`) is set.
const String mapsChannelName = 'com.example.clean_spot/maps';

/// Message shown on map screens when `MAPS_API_KEY` is missing.
const String mapKeyNotSetMessage = 'Map key not set';

/// Setup guidance shown below [mapKeyNotSetMessage].
const String mapKeyNotSetHint =
    'Set MAPS_API_KEY in android/local.properties or ios/Flutter/Secrets.xcconfig.';

/// Returns true when [key] is a non-empty API key and not an unresolved
/// build variable placeholder (`$(...)` or `${...}`).
bool isValidMapsApiKey(String? key) {
  if (key == null) return false;
  final trimmed = key.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed.startsWith(r'$(') || trimmed.startsWith(r'${')) return false;
  return true;
}

/// Checks whether a Google Maps API key is configured for the current build.
///
/// Checks `--dart-define=MAPS_API_KEY` (or [envKey] if supplied) first, then
/// queries the native platform channel ([mapsChannelName]) which reads
/// `MAPS_API_KEY` from `android/local.properties` on Android or
/// `ios/Flutter/Secrets.xcconfig` (`GMSApiKey`) on iOS.
/// Returns `false` instead of throwing if the key or channel is unavailable.
Future<bool> checkMapsApiKeyConfigured({
  MethodChannel? channel,
  String? envKey,
}) async {
  final dartDefineKey = envKey ?? const String.fromEnvironment('MAPS_API_KEY');
  if (isValidMapsApiKey(dartDefineKey)) {
    return true;
  }
  try {
    final activeChannel = channel ?? const MethodChannel(mapsChannelName);
    final response = await activeChannel.invokeMethod<Object?>('hasMapsApiKey');
    if (response is bool) return response;
    if (response is String) return isValidMapsApiKey(response);
    return false;
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return false;
  } catch (_) {
    return false;
  }
}

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
