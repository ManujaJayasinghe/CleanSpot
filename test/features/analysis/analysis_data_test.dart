import 'dart:io';

import 'package:clean_spot/features/analysis/analysis_notes.dart';
import 'package:clean_spot/features/analysis/dengue_analysis.dart';
import 'package:clean_spot/features/analysis/dengue_stat.dart';
import 'package:clean_spot/features/analysis/district_centres.dart';
import 'package:clean_spot/features/analysis/waste_period.dart';
import 'package:flutter_test/flutter_test.dart';

/// Checks on the bundled data files themselves (tests run from the project
/// root, so the paths are relative to it).
void main() {
  final stats = parseDengueCsv(
    File('assets/data/dengue_stats.csv').readAsStringSync(),
  );

  group('assets/data/dengue_stats.csv', () {
    test('has the 26 RDHS areas, Kalmunai separate from Ampara', () {
      final names = districtsOf(stats);
      expect(names, hasLength(26));
      expect(names, containsAll(['Kalmunai', 'Ampara', 'Moneragala']));
      expect(names.toSet(), districtCentres.map((c) => c.name).toSet());
    });

    test('has no duplicate (district, year, week)', () {
      final keys = {for (final s in stats) '${s.district}|${s.year}|${s.week}'};
      expect(keys, hasLength(stats.length));
    });

    test('every week has all 26 districts', () {
      final perWeek = <String, int>{};
      for (final s in stats) {
        perWeek.update('${s.year}-${s.week}', (n) => n + 1, ifAbsent: () => 1);
      }
      expect(perWeek.values.toSet(), {26});
    });

    test('is sorted by district, year, week', () {
      for (var i = 1; i < stats.length; i++) {
        final a = stats[i - 1];
        final b = stats[i];
        final order = a.district != b.district
            ? a.district.compareTo(b.district)
            : a.year != b.year
            ? a.year.compareTo(b.year)
            : a.week.compareTo(b.week);
        expect(order, lessThan(0), reason: '$a then $b');
      }
    });
  });

  group('assets/data/waste_periods.csv', () {
    final periods = parseWastePeriodsCsv(
      File('assets/data/waste_periods.csv').readAsStringSync(),
    );

    test('has at least 3 periods, each with a source link', () {
      expect(periods.length, greaterThanOrEqualTo(3));
      for (final p in periods) {
        expect(p.sourceUrl, startsWith('https://'), reason: p.label);
      }
    });

    test('names only districts that exist in the dengue data', () {
      final known = districtsOf(stats).toSet();
      for (final p in periods) {
        expect(known.containsAll(p.districts), isTrue, reason: p.label);
      }
    });
  });

  group('parseWastePeriodsCsv', () {
    const header = 'label,start_date,end_date,districts,source_url\n';

    test('reads quoted labels with commas, all, and several districts', () {
      final p = parseWastePeriodsCsv(
        '$header'
        '"Strike, week one",2025-03-01,2025-03-07,all,https://example.org/a\n'
        'Festival,2025-04-10,2025-04-20,Colombo;Gampaha,https://example.org/b\n',
      );
      expect(p, hasLength(2));
      expect(p[0].label, 'Strike, week one');
      expect(p[0].isAllDistricts, isTrue);
      expect(p[0].appliesTo('Kandy'), isTrue);
      expect(p[1].districts, ['Colombo', 'Gampaha']);
      expect(p[1].appliesTo('Kandy'), isFalse);
    });

    test('contains includes both end days', () {
      final p = parseWastePeriodsCsv(
        '${header}X,2025-03-01,2025-03-07,all,https://example.org/a\n',
      ).single;
      expect(p.contains(DateTime(2025, 3, 1)), isTrue);
      expect(p.contains(DateTime(2025, 3, 7, 23, 59)), isTrue);
      expect(p.contains(DateTime(2025, 2, 28)), isFalse);
      expect(p.contains(DateTime(2025, 3, 8)), isFalse);
    });

    test('rejects a row without a source link', () {
      expect(
        () => parseWastePeriodsCsv('${header}X,2025-03-01,2025-03-07,all,\n'),
        throwsFormatException,
      );
    });

    test('rejects a bad date, a reversed range and a wrong header', () {
      expect(
        () => parseWastePeriodsCsv(
          '${header}X,01/03/2025,2025-03-07,all,https://example.org/a\n',
        ),
        throwsFormatException,
      );
      expect(
        () => parseWastePeriodsCsv(
          '${header}X,2025-03-09,2025-03-07,all,https://example.org/a\n',
        ),
        throwsFormatException,
      );
      expect(() => parseWastePeriodsCsv('a,b,c\n'), throwsFormatException);
    });
  });

  test('every written insight note has a real source link', () {
    expect(writtenInsights, isNotEmpty);
    for (final note in writtenInsights) {
      expect(note.sources, isNotEmpty, reason: note.title);
      for (final s in note.sources) {
        expect(s.url, startsWith('https://'), reason: note.title);
      }
    }
  });

  test('Kalmunai is shown as Kalmunai (Ampara), other names unchanged', () {
    expect(displayDistrictName('Kalmunai'), 'Kalmunai (Ampara)');
    expect(displayDistrictName('Ampara'), 'Ampara');
    expect(displayDistrictName('Colombo'), 'Colombo');
  });
}
