import 'package:clean_spot/features/map/map_filters.dart';
import 'package:clean_spot/models/report_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 17, 12);

  ReportModel report(
    String id, {
    required Duration age,
    GeoPoint location = const GeoPoint(6.9271, 79.8612),
  }) {
    return ReportModel(
      id: id,
      uid: 'u',
      lat: location.latitude,
      lng: location.longitude,
      status: 'valid',
      location: location,
      createdAt: now.subtract(age),
      lastConfirmedAt: now.subtract(age),
    );
  }

  final reports = [
    report('today', age: const Duration(hours: 3)),
    report('twoWeeks', age: const Duration(days: 14)),
    report('twoMonths', age: const Duration(days: 60)),
  ];

  List<String> ids(List<ReportModel> list) => list.map((r) => r.id).toList();

  group('filterReports', () {
    test('last 7 days keeps only recent reports', () {
      final out = filterReports(reports, MapTimeRange.last7Days, now);
      expect(ids(out), ['today']);
    });

    test('last 30 days keeps reports up to a month old', () {
      final out = filterReports(reports, MapTimeRange.last30Days, now);
      expect(ids(out), ['today', 'twoWeeks']);
    });

    test('all time keeps everything', () {
      final out = filterReports(reports, MapTimeRange.allTime, now);
      expect(ids(out), ['today', 'twoWeeks', 'twoMonths']);
    });

    test('drops reports without a real location', () {
      final out = filterReports(
        [report('noLoc', age: Duration.zero, location: const GeoPoint(0, 0))],
        MapTimeRange.allTime,
        now,
      );
      expect(out, isEmpty);
    });
  });

  test('heatmapPoints gives one point per report at its position', () {
    final points = heatmapPoints(reports);
    expect(points, hasLength(3));
    expect(points.first.point.latitude, 6.9271);
    expect(points.first.point.longitude, 79.8612);
  });

  test('formatReportDate', () {
    expect(formatReportDate(DateTime(2026, 11, 7)), '7 Nov 2026');
  });
}
