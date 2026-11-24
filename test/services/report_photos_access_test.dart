import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The photo collection must only ever be read for ONE report on screen
/// (FirestoreService.getReportPhoto) and written when a report is saved.
/// Lists, the map and the duplicate check must read `reports` only.
///
/// This scans the source so a future change that reads `reportPhotos` from a
/// list or query is caught.
String _code(String source) => source
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  final libFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

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

  test('list, map and duplicate queries never read reportPhotos', () {
    final service = File('lib/services/firestore_service.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    final queries = service.substring(
      service.indexOf('Stream<List<ReportModel>> watchUserReports'),
    );
    expect(_code(queries).contains('reportPhotos'), isFalse);
    expect(_code(queries).contains('_reportPhotosRef'), isFalse);

    final duplicates = File('lib/features/ai_validation/duplicate_check.dart')
        .readAsStringSync();
    expect(_code(duplicates).contains('reportPhotos'), isFalse);
  });

  test('inside FirestoreService only submitReport and the photo loader use it', () {
    final service = File('lib/services/firestore_service.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    final code = _code(service);
    final uses = RegExp(r'_reportPhotosRef').allMatches(code).length;
    // the getter, the batch write in submitReport, the read in _loadReportPhoto
    expect(uses, 3);
  });
}
