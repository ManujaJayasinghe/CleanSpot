import 'package:clean_spot/features/analysis/dengue_analysis.dart';
import 'package:clean_spot/features/analysis/dengue_repository.dart';
import 'package:clean_spot/features/analysis/dengue_stat.dart';
import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// An asset bundle backed by an in-memory map.
class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this.files);

  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    final text = files[key];
    if (text == null) throw FlutterError('Unable to load asset: $key');
    final bytes = Uint8List.fromList(text.codeUnits);
    return ByteData.sublistView(bytes);
  }
}

void main() {
  const csv = 'district,year,week,cases\n'
      'Colombo,2025,1,10\n'
      'Colombo,2025,2,30\n'
      'Colombo,2026,1,20\n'
      'Colombo,2026,2,40\n'
      'Gampaha,2025,1,5\n'
      'Gampaha,2026,1,50\n';

  group('parseDengueCsv', () {
    test('parses rows after the header', () {
      final stats = parseDengueCsv(csv);
      expect(stats, hasLength(6));
      expect(stats.first.district, 'Colombo');
      expect(stats.first.year, 2025);
      expect(stats.first.week, 1);
      expect(stats.first.cases, 10);
    });

    test('handles CRLF line endings and blank lines', () {
      final stats = parseDengueCsv('district,year,week,cases\r\n\r\nGalle,2025,3,7\r\n');
      expect(stats, hasLength(1));
      expect(stats.single.cases, 7);
    });

    test('rejects a wrong header', () {
      expect(
        () => parseDengueCsv('place,year,week,cases\nGalle,2025,3,7\n'),
        throwsFormatException,
      );
    });

    test('rejects a bad row and names its line', () {
      expect(
        () => parseDengueCsv('district,year,week,cases\nGalle,2025,x,7\n'),
        throwsA(
          isA<FormatException>().having((e) => e.message, 'message', contains('Line 2')),
        ),
      );
    });

    test('rejects an empty file', () {
      expect(() => parseDengueCsv(''), throwsFormatException);
    });
  });

  group('analysis helpers', () {
    final stats = parseDengueCsv(csv);

    test('districtsOf is sorted and distinct', () {
      expect(districtsOf(stats), ['Colombo', 'Gampaha']);
    });

    test('latestYear', () {
      expect(latestYear(stats), 2026);
      expect(latestYear(const []), isNull);
    });

    test('weeklySeries is ordered oldest first', () {
      final series = weeklySeries(stats, 'Colombo');
      expect(series.map((p) => p.cases), [10, 30, 20, 40]);
      expect(series.last.year, 2026);
    });

    test('topDistricts ranks by cases in the given year', () {
      final top = topDistricts(stats, 2026);
      expect(top.map((t) => t.district), ['Colombo', 'Gampaha']);
      expect(top.first.cases, 60); // 20 + 40
      expect(top.last.cases, 50);
    });

    test('topDistricts honours the limit', () {
      expect(topDistricts(stats, 2026, limit: 1), hasLength(1));
    });

    test('buildInsights reports the peak week and year-on-year change', () {
      final insights = buildInsights(stats, 'Colombo');
      expect(insights.first.body, contains('week 2 of 2026'));
      final yoy = insights.firstWhere((i) => i.title.startsWith('2026'));
      // 2026 weeks 1-2: 60 vs 2025 weeks 1-2: 40 -> 50% higher.
      expect(yoy.body, contains('50% higher'));
    });

    test('buildInsights is empty for an unknown district', () {
      expect(buildInsights(stats, 'Nowhere'), isEmpty);
    });
  });

  group('DengueRepository', () {
    test('uses the real CSV when present', () async {
      final repo = DengueRepository(
        bundle: _FakeBundle({DengueRepository.realAsset: csv}),
      );
      final data = await repo.load();
      expect(data.isSample, isFalse);
      expect(data.stats, hasLength(6));
    });

    test('falls back to the sample CSV and flags it', () async {
      final repo = DengueRepository(
        bundle: _FakeBundle({DengueRepository.sampleAsset: csv}),
      );
      final data = await repo.load();
      expect(data.isSample, isTrue);
    });

    test('does not hide a malformed real CSV', () async {
      final repo = DengueRepository(
        bundle: _FakeBundle({
          DengueRepository.realAsset: 'district,year,week,cases\nbad row\n',
          DengueRepository.sampleAsset: csv,
        }),
      );
      expect(repo.load(), throwsFormatException);
    });
  });
}
