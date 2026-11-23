import 'package:cloud_firestore/cloud_firestore.dart';

import 'geohash.dart' as geohash;
import 'haversine.dart';

/// Collection and field names. These must match `ReportModel.toMap()`
/// (lib/models/report_model.dart); a unit test checks that they do.
const String reportsCollection = 'reports';
const String fieldGeohash = 'geohash';
const String fieldStatus = 'status';
const String fieldCreatedAt = 'createdAt';
const String fieldLastConfirmedAt = 'lastConfirmedAt';
const String fieldLocation = 'location';

/// Only accepted reports can be marked as still present. The Report screen
/// saves an eligible report with status 'valid' (see docs/DATA_MODEL.md).
const String validStatus = 'valid';

/// Precision of the query cells. A precision-6 cell is about 1.2 km x 0.6 km,
/// so the cell plus its 8 neighbours always covers a 50 m radius.
const int queryPrecision = 6;

/// "Still present" rule (from the proposal): a new photo that passes the AI
/// check within [stillPresentRadiusMeters] of a valid report whose last
/// activity (created or last confirmed) is within [stillPresentWindow] updates
/// that report instead of creating a new one.
const Duration stillPresentWindow = Duration(days: 14);
const double stillPresentRadiusMeters = 50;

/// The precision-6 geohash of the point's cell plus its 8 neighbours,
/// de-duplicated (they can repeat near the poles).
List<String> candidatePrefixes(double latitude, double longitude) {
  final cell = geohash.encode(latitude, longitude, queryPrecision);
  return {cell, ...geohash.neighbours(cell)}.toList();
}

/// The time of a report's last activity: the later of `createdAt` and
/// `lastConfirmedAt`, or null if neither is a [Timestamp].
DateTime? lastActivity(Map<String, dynamic> data) {
  final created = data[fieldCreatedAt];
  final confirmed = data[fieldLastConfirmedAt];
  final times = [
    if (created is Timestamp) created.toDate(),
    if (confirmed is Timestamp) confirmed.toDate(),
  ];
  if (times.isEmpty) return null;
  return times.reduce((a, b) => a.isAfter(b) ? a : b);
}

/// Distance in metres from ([latitude], [longitude]) to one report document
/// (raw Firestore data) if it is a still-present match checked at [now], or
/// null if it is not.
///
/// A match is `status == 'valid'`, last activity within [stillPresentWindow],
/// and within [stillPresentRadiusMeters]. A document without a usable
/// `location` or timestamps is never a match: it cannot be shown to be recent
/// and nearby.
double? matchDistance(
  Map<String, dynamic> data,
  double latitude,
  double longitude,
  DateTime now,
) {
  if (data[fieldStatus] != validStatus) return null;

  final last = lastActivity(data);
  if (last == null || !last.isAfter(now.subtract(stillPresentWindow))) {
    return null;
  }

  final location = data[fieldLocation];
  if (location is! GeoPoint) return null;
  final distance = haversineMeters(
    latitude,
    longitude,
    location.latitude,
    location.longitude,
  );
  return distance <= stillPresentRadiusMeters ? distance : null;
}

/// The id of the nearest still-present match among [docs] (id to data), or
/// null if none matches. Pure, so it can be tested without Firestore.
String? nearestMatch(
  Iterable<MapEntry<String, Map<String, dynamic>>> docs,
  double latitude,
  double longitude,
  DateTime now,
) {
  String? bestId;
  double? bestDistance;
  for (final doc in docs) {
    final d = matchDistance(doc.value, latitude, longitude, now);
    if (d != null && (bestDistance == null || d < bestDistance)) {
      bestId = doc.key;
      bestDistance = d;
    }
  }
  return bestId;
}

/// The id of the valid report this point should be marked as "still present"
/// on (the nearest one within 50 m, active in the last 14 days, from any
/// user), or null if this is a new site.
///
/// Runs one range query per candidate cell (in parallel) on `geohash`, then
/// filters on the phone. Reads from the server only: if any query fails
/// (including when offline) this throws, and the check controller shows the
/// retryable error. A failed query is never treated as "new site".
Future<String?> findStillPresentReport(
  double latitude,
  double longitude, {
  FirebaseFirestore? firestore,
  DateTime Function()? now,
}) async {
  final db = firestore ?? FirebaseFirestore.instance;
  final reports = db.collection(reportsCollection);

  final snapshots = await Future.wait(
    candidatePrefixes(latitude, longitude).map(
      (prefix) => reports
          .orderBy(fieldGeohash)
          .startAt([prefix])
          .endAt(['$prefix'])
          .get(const GetOptions(source: Source.server)),
    ),
    eagerError: true,
  );

  return nearestMatch(
    snapshots.expand((s) => s.docs).map((d) => MapEntry(d.id, d.data())),
    latitude,
    longitude,
    (now ?? DateTime.now)(),
  );
}
