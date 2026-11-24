import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The photo collection must only ever be READ for ONE report on screen
/// (FirestoreService.getReportPhoto), written when a report is saved, and
/// deleted when a report is cleared. Lists, the map and the duplicate check
/// must read `reports` only.
///
/// This scans the source so a future change that reads `reportPhotos` from a
/// list or query is caught.
String _code(String source) => source
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// The text of one FirestoreService method, from its signature to the closing
/// brace at two-space indentation.
String _method(String service, String signature) {
  final start = service.indexOf(signature);
  expect(start, isNot(-1), reason: 'method not found: $signature');
  final end = service.indexOf('\n  }\n', start);
  return service.substring(start, end == -1 ? service.length : end);
}

void main() {
  final libFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  final service = File('lib/services/firestore_service.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  test('only FirestoreService touches the reportPhotos collection', () {
    final offenders = <String>[];
    for (final f in libFiles) {
      final path = f.path.replaceAll('\\', '/');
      if (path.endsWith('lib/services/firestore_service.dart')) continue;
      final code = _code(f.readAsStringSync());
      if (code.contains("'reportPhotos'") ||
          code.contains('"reportPhotos"') ||
          code.contains('_reportPhotosRef')) {
        offenders.add(path);
      }
    }
    expect(offenders, isEmpty);
  });

  test('list, map and other queries never read reportPhotos', () {
    for (final signature in [
      'Stream<List<ReportModel>> watchUserReports',
      'Stream<List<ReportModel>> watchValidReports',
      'Stream<List<CouponModel>> watchAvailableCoupons',
      'Stream<List<RedemptionModel>> watchUserRedemptions',
      'Stream<List<UserModel>> watchAllUsers',
      'Stream<UserModel?> watchUser',
    ]) {
      final body = _code(_method(service, signature));
      expect(body.contains('reportPhotos'), isFalse, reason: signature);
      expect(body.contains('_reportPhotosRef'), isFalse, reason: signature);
    }

    final duplicates = File('lib/features/ai_validation/duplicate_check.dart')
        .readAsStringSync();
    expect(_code(duplicates).contains('reportPhotos'), isFalse);
  });

  test('inside FirestoreService only the save, photo load and clear use it', () {
    final code = _code(service);
    final uses = RegExp(r'_reportPhotosRef').allMatches(code).length;
    // the getter, the batch write in submitReport, the read in
    // _loadReportPhoto, and the delete in markReportCleared
    expect(uses, 4);

    expect(_code(_method(service, 'Future<String> submitReport')).contains('_reportPhotosRef'), isTrue);
    expect(_code(_method(service, 'Future<Uint8List?> _loadReportPhoto')).contains('_reportPhotosRef'), isTrue);
    expect(_code(_method(service, 'Future<void> markReportCleared')).contains('_reportPhotosRef'), isTrue);
  });
}
