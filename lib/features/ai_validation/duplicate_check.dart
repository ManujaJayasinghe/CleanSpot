import 'package:cloud_firestore/cloud_firestore.dart';

import 'geohash.dart' as geohash;
import 'haversine.dart';

/// Collection and field names. These must match `ReportModel.toMap()`
/// (lib/models/report_model.dart); a unit test checks that they do.
const String reportsCollection = 'reports';
const String fieldGeohash = 'geohash';
const String fieldStatus = 'status';
const String fieldCreatedAt = 'createdAt';
const String fieldLocation = 'location';

/// Only approved reports count as duplicates.
const String approvedStatus = 'approved';

/// Precision of the query cells. A precision-6 cell is about 1.2 km x 0.6 km,
/// so the cell plus its 8 neighbours always covers a 20 m radius.
const int queryPrecision = 6;

const Duration duplicateWindow = Duration(days: 7);
const double duplicateRadiusMeters = 20;

/// The precision-6 geohash of the point's cell plus its 8 neighbours,
/// de-duplicated (they can repeat near the poles).
List<String> candidatePrefixes(double latitude, double longitude) {
  final cell = geohash.encode(latitude, longitude, queryPrecision);
  return {cell, ...geohash.neighbours(cell)}.toList();
}

/// Whether one report document (raw Firestore data) is a duplicate of a new
/// report at ([latitude], [longitude]) checked at [now].
///
/// A document missing `createdAt` or `location` (or with the wrong type) is
/// not counted: it cannot be shown to be recent and nearby.
bool matchesDuplicate(
  Map<String, dynamic> data,
  double latitude,
  double longitude,
  DateTime now,
) {
  if (data[fieldStatus] != approvedStatus) return false;

  final createdAt = data[fieldCreatedAt];
  if (createdAt is! Timestamp) return false;
  if (!createdAt.toDate().isAfter(now.subtract(duplicateWindow))) return false;

  final location = data[fieldLocation];
  if (location is! GeoPoint) return false;
  final distance = haversineMeters(
    latitude,
    longitude,
    location.latitude,
    location.longitude,
  );
  return distance <= duplicateRadiusMeters;
}

/// Whether an approved report was created within the last 7 days within
/// 20 m of this point.
///
/// Runs one range query per candidate cell (in parallel) on `geohash`, then
/// filters client-side. Reads from the server only: if any query fails
/// (including when offline) this throws, and the check controller shows the
/// retryable error. A failed query is never treated as "not a duplicate".
Future<bool> isDuplicate(
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

  final checkedAt = (now ?? DateTime.now)();
  return snapshots.any(
    (snap) => snap.docs.any(
      (doc) => matchesDuplicate(doc.data(), latitude, longitude, checkedAt),
    ),
  );
}
