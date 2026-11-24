import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';

/// A time when garbage built up or collection was disrupted, with the source
/// that says so. Loaded from assets/data/waste_periods.csv.
class WastePeriod {
  const WastePeriod({
    required this.label,
    required this.start,
    required this.end,
    required this.districts,
    required this.sourceUrl,
  });

  final String label;

  /// First and last day of the period, both included.
  final DateTime start;
  final DateTime end;

  /// District names as in the dengue CSV; empty means the period applies to
  /// every district ("all" in the CSV).
  final List<String> districts;
  final String sourceUrl;

  bool get isAllDistricts => districts.isEmpty;

  bool appliesTo(String district) =>
      isAllDistricts || districts.contains(district);

  /// True when [day] (ignoring the time of day) is inside the period.
  bool contains(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return !d.isBefore(start) && !d.isAfter(end);
  }
}

/// Periods that cover [day] for [district].
List<WastePeriod> activeWastePeriods(
  List<WastePeriod> periods,
  String district,
  DateTime day,
) => [
  for (final p in periods)
    if (p.appliesTo(district) && p.contains(day)) p,
];

/// Splits one CSV line into cells, honouring "double quoted" cells that may
/// contain commas.
List<String> _splitCsvLine(String line) {
  final cells = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        buffer.write(c);
      }
    } else if (c == '"') {
      inQuotes = true;
    } else if (c == ',') {
      cells.add(buffer.toString().trim());
      buffer.clear();
    } else {
      buffer.write(c);
    }
  }
  cells.add(buffer.toString().trim());
  return cells;
}

DateTime _parseDay(String text, int lineNo) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
  if (m == null) {
    throw FormatException('Line $lineNo: "$text" is not a date (yyyy-mm-dd).');
  }
  return DateTime(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
  );
}

/// Parses waste_periods.csv:
/// `label,start_date,end_date,districts,source_url`.
///
/// `districts` is `all` or district names separated by `;`. A row without a
/// source URL is rejected: an unsourced period must not feed the risk index.
List<WastePeriod> parseWastePeriodsCsv(String csv) {
  final lines = csv.split(RegExp(r'\r?\n'));
  final periods = <WastePeriod>[];
  var sawHeader = false;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;
    final cells = _splitCsvLine(line);

    if (!sawHeader) {
      sawHeader = true;
      const expected = [
        'label',
        'start_date',
        'end_date',
        'districts',
        'source_url',
      ];
      final header = cells.map((c) => c.toLowerCase()).toList();
      if (header.length != 5 ||
          [for (var k = 0; k < 5; k++) header[k] == expected[k]]
              .contains(false)) {
        throw const FormatException(
          'Line 1: header must be '
          '"label,start_date,end_date,districts,source_url".',
        );
      }
      continue;
    }

    if (cells.length != 5) {
      throw FormatException(
        'Line ${i + 1}: expected 5 columns, got ${cells.length}.',
      );
    }
    final start = _parseDay(cells[1], i + 1);
    final end = _parseDay(cells[2], i + 1);
    if (cells[0].isEmpty || end.isBefore(start)) {
      throw FormatException('Line ${i + 1}: empty label or end before start.');
    }
    if (!cells[4].startsWith('http')) {
      throw FormatException('Line ${i + 1}: source_url must be a link.');
    }
    final districts = cells[3].toLowerCase() == 'all'
        ? const <String>[]
        : cells[3]
              .split(';')
              .map((d) => d.trim())
              .where((d) => d.isNotEmpty)
              .toList();
    if (cells[3].isEmpty) {
      throw FormatException('Line ${i + 1}: districts is empty (use "all").');
    }
    periods.add(
      WastePeriod(
        label: cells[0],
        start: start,
        end: end,
        districts: districts,
        sourceUrl: cells[4],
      ),
    );
  }

  if (!sawHeader) throw const FormatException('The CSV is empty.');
  return periods;
}

/// Loads the bundled waste periods. A missing file means no periods; a file
/// that exists but is malformed throws, so a bad row is never silently lost.
class WastePeriodRepository {
  WastePeriodRepository({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static const String asset = 'assets/data/waste_periods.csv';

  final AssetBundle _bundle;

  Future<List<WastePeriod>> load() async {
    final String csv;
    try {
      csv = await _bundle.loadString(asset);
    } on FlutterError {
      return const [];
    }
    return parseWastePeriodsCsv(csv);
  }
}
