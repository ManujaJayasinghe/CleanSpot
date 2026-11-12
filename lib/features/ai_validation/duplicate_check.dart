/// Whether a report was already submitted at about this spot recently.
///
/// TODO(Step 8): query the reports collection (geohash cell plus neighbours,
/// then filter by 7 days and 20 m). Until then this always returns false, so
/// no photo is ever rejected as a duplicate. A real implementation may throw;
/// the check controller treats that as a failed check, never as "not a
/// duplicate".
Future<bool> isDuplicate(double latitude, double longitude) async => false;
