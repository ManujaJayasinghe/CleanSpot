import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';

import 'dengue_stat.dart';

/// The dengue rows plus whether they are the built-in placeholder sample.
class DengueData {
  const DengueData({required this.stats, required this.isSample});

  final List<DengueStat> stats;

  /// True when the real CSV is missing and the synthetic fallback is shown
  /// instead. The screen must say so.
  final bool isSample;
}

/// Loads dengue statistics from bundled CSV assets.
///
/// The real Epidemiology Unit data is [realAsset] (columns
/// `district,year,week,cases`, made by tool/extract_dengue.py). The synthetic
/// [sampleAsset] is only a fallback for when that file is missing, so the
/// screen still opens; it is not real statistics and the screen says so.
class DengueRepository {
  DengueRepository({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static const String realAsset = 'assets/data/dengue_stats.csv';
  static const String sampleAsset =
      'assets/data/dengue_stats_sample_fallback.csv';

  final AssetBundle _bundle;

  Future<DengueData> load() async {
    String csv;
    var isSample = false;
    try {
      csv = await _bundle.loadString(realAsset);
    } on FlutterError {
      // No real CSV bundled: fall back to the synthetic sample. A real CSV that
      // exists but is malformed is NOT hidden; parseDengueCsv throws below.
      csv = await _bundle.loadString(sampleAsset);
      isSample = true;
    }
    return DengueData(stats: parseDengueCsv(csv), isSample: isSample);
  }
}
