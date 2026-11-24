import 'package:clean_spot/features/ai_validation/geohash.dart' as geohash;
import 'package:clean_spot/features/ai_validation/validation_result.dart';
import 'package:clean_spot/models/report_model.dart';
import 'package:clean_spot/services/report_write_plan.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

const _photo = 'QkFTRTY0UEhPVE8='; // any non-empty base64 text

ReportModel report({
  String status = reportStatusValid,
  String uid = 'u1',
  String type = 'blocked_drain',
}) {
  final now = DateTime(2026, 11, 10);
  return ReportModel(
    id: 'r1',
    uid: uid,
    lat: 7.2906,
    lng: 80.6337,
    type: type,
    status: status,
    location: const GeoPoint(7.2906, 80.6337),
    geohash: geohash.encode(7.2906, 80.6337, 9),
    createdAt: now,
    lastConfirmedAt: now,
    aiCategory: type,
    aiConfidence: 0.95,
    aiReason: 'A clogged gutter with water.',
  );
}

void main() {
  test('the points per valid report is one constant, 10', () {
    expect(kPointsPerValidReport, 10);
    expect(reportStatusValid, 'valid');
    expect(reportStatusRejected, 'rejected');
  });

  group('valid report', () {
    final plan = buildReportWritePlan(report(), 'r1', photoBase64: _photo);

    test('writes the report, the photo and the points', () {
      expect(plan.photoData, isNotNull);
      expect(plan.userPointsData, isNotNull);
      expect(plan.pointsAwarded, kPointsPerValidReport);
    });

    test('the photo goes only into the reportPhotos document', () {
      expect(plan.photoData!['photoBase64'], _photo);
      expect(plan.photoData!['reportId'], 'r1');
      expect(plan.photoData!['createdAt'], isA<FieldValue>());

      final data = plan.reportData;
      expect(data.containsKey('imageUrl'), isFalse);
      expect(data.containsKey('photoUrl'), isFalse);
      expect(data.containsKey('photoBase64'), isFalse);
      expect(
        data.values.whereType<String>().any((v) => v.contains(_photo)),
        isFalse,
      );
      expect(data['photoId'], 'r1');
    });

    test('points are incremented on both keys the app reads', () {
      expect(plan.userPointsData!.keys, containsAll(['pointsBalance', 'points']));
      expect(plan.userPointsData!['pointsBalance'], isA<FieldValue>());
      expect(plan.userPointsData!['points'], isA<FieldValue>());
    });

    test('the report document carries status, AI fields, geohash and server time', () {
      final data = plan.reportData;
      expect(data['status'], 'valid');
      expect(data['uid'], 'u1');
      expect(data['type'], 'blocked_drain');
      expect(data['aiCategory'], 'blocked_drain');
      expect(data['aiConfidence'], 0.95);
      expect(data['aiReason'], 'A clogged gutter with water.');
      expect(data['geohash'], geohash.encode(7.2906, 80.6337, 9));
      expect(data['location'], const GeoPoint(7.2906, 80.6337));
      expect(data['createdAt'], isA<FieldValue>());
    });

    test('a custom points value is used', () {
      final p = buildReportWritePlan(
        report(),
        'r1',
        photoBase64: _photo,
        points: 25,
      );
      expect(p.pointsAwarded, 25);
    });

    test('a valid report without its photo is refused', () {
      expect(
        () => buildReportWritePlan(report(), 'r1'),
        throwsArgumentError,
      );
      expect(
        () => buildReportWritePlan(report(), 'r1', photoBase64: ''),
        throwsArgumentError,
      );
    });
  });

  group('rejected report', () {
    // The photo is passed on purpose: it must still not be stored.
    final plan = buildReportWritePlan(
      report(status: reportStatusRejected, type: 'none'),
      'r2',
      photoBase64: _photo,
    );

    test('writes only the reports document: no photo and no points', () {
      expect(plan.photoData, isNull);
      expect(plan.userPointsData, isNull);
      expect(plan.pointsAwarded, 0);
    });

    test('keeps the status, AI fields and geohash', () {
      final data = plan.reportData;
      expect(data['status'], 'rejected');
      expect(data['type'], 'none');
      expect(data['aiCategory'], 'none');
      expect(data['aiConfidence'], 0.95);
      expect(data['aiReason'], 'A clogged gutter with water.');
      expect(data['geohash'], geohash.encode(7.2906, 80.6337, 9));
    });

    test('has no photo data and no photoId pointing at a missing photo', () {
      final data = plan.reportData;
      expect(data['photoId'], '');
      expect(data.containsKey('imageUrl'), isFalse);
      expect(data.containsKey('photoUrl'), isFalse);
      expect(
        data.values.whereType<String>().any((v) => v.contains(_photo)),
        isFalse,
      );
    });

    test('needs no photo', () {
      final p = buildReportWritePlan(
        report(status: reportStatusRejected, type: 'none'),
        'r2',
      );
      expect(p.photoData, isNull);
    });
  });

  group('invalid input', () {
    test('an unknown status is refused', () {
      for (final status in ['pending', 'approved', '']) {
        expect(
          () => buildReportWritePlan(
            report(status: status),
            'r1',
            photoBase64: _photo,
          ),
          throwsArgumentError,
          reason: status,
        );
      }
    });

    test('a missing uid is refused (no points can go to nobody)', () {
      expect(
        () => buildReportWritePlan(report(uid: ''), 'r1', photoBase64: _photo),
        throwsArgumentError,
      );
    });
  });

  test('the type saved for every category is a documented wire value', () {
    for (final c in SiteCategory.values) {
      final isSite = c != SiteCategory.none;
      final plan = buildReportWritePlan(
        report(
          status: isSite ? reportStatusValid : reportStatusRejected,
          type: c.wireValue,
        ),
        'r1',
        photoBase64: isSite ? _photo : null,
      );
      expect(plan.reportData['type'], c.wireValue);
      expect(plan.reportData['aiCategory'], c.wireValue);
    }
  });
}
