/// One row of the dengue data set: cases in one district in one week.
///
/// CSV columns (exactly, in this order): `district,year,week,cases`.
class DengueStat {
  const DengueStat({
    required this.district,
    required this.year,
    required this.week,
    required this.cases,
  });

  final String district;
  final int year;
  final int week;
  final int cases;

  @override
  String toString() => 'DengueStat($district, $year, W$week, $cases)';
}

/// Parses the dengue CSV (`district,year,week,cases` with a header row).
///
/// Blank lines are skipped. A malformed row throws a [FormatException] that
/// names the line, so a bad cell in the spreadsheet is easy to find.
List<DengueStat> parseDengueCsv(String csv) {
  final lines = csv.split(RegExp(r'\r?\n'));
  final stats = <DengueStat>[];
  var sawHeader = false;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;

    final cells = line.split(',').map((c) => c.trim()).toList();

    if (!sawHeader) {
      sawHeader = true;
      final header = cells.map((c) => c.toLowerCase()).toList();
      const expected = ['district', 'year', 'week', 'cases'];
      if (header.length != 4 ||
          [for (var k = 0; k < 4; k++) header[k] == expected[k]]
              .contains(false)) {
        throw const FormatException(
          'Line 1: header must be "district,year,week,cases".',
        );
      }
      continue;
    }

    if (cells.length != 4) {
      throw FormatException('Line ${i + 1}: expected 4 columns, got '
          '${cells.length}.');
    }
    final year = int.tryParse(cells[1]);
    final week = int.tryParse(cells[2]);
    final cases = int.tryParse(cells[3]);
    if (cells[0].isEmpty || year == null || week == null || cases == null) {
      throw FormatException('Line ${i + 1}: "$line" is not valid.');
    }
    if (week < 1 || week > 53 || cases < 0) {
      throw FormatException('Line ${i + 1}: week or cases out of range.');
    }
    stats.add(
      DengueStat(district: cells[0], year: year, week: week, cases: cases),
    );
  }

  if (!sawHeader) throw const FormatException('The CSV is empty.');
  return stats;
}
