import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';

import 'dengue_stat.dart';

/// The dengue rows plus whether they are the built-in placeholder sample.
class DengueData {
  const DengueData({required this.stats, required this.isSample});

  final List<DengueStat> stats;

  /// True when the real CSV has not been added yet and the synthetic sample
  /// is shown instead. The screen must say so.
  final bool isSample;
}

/// Loads dengue statistics from bundled CSV assets.
///
/// Drop the cleaned CSV from Anushka at [realAsset] (columns
/// `district,year,week,cases`) and it is used automatically. Until then the
/// synthetic [sampleAsset] is used so the screen still works.
class DengueRepository {
  DengueRepository({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static const String realAsset = 'assets/data/dengue_stats.csv';
  static const String sampleAsset = 'assets/data/dengue_stats_sample.csv';

  final AssetBundle _bundle;

  Future<DengueData> load() async {
    String csv;
    var isSample = false;
    try {
      csv = await _bundle.loadString(realAsset);
    } on FlutterError {
      // No real CSV bundled yet: fall back to the sample. A real CSV that
      // exists but is malformed is NOT hidden; parseDengueCsv throws below.
      csv = await _bundle.loadString(sampleAsset);
      isSample = true;
    }
    return DengueData(stats: parseDengueCsv(csv), isSample: isSample);
  }
}
