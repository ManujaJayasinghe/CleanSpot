import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ai_validation_service.dart';

// Debug-only live check of validatePhoto() on the sample photos in
// assets/dev_samples/. Run it with:
//   flutter run --dart-define=AI_LIVE_TEST=true

const _samplesPrefix = 'assets/dev_samples/';
const bool _aiLiveTest = bool.fromEnvironment('AI_LIVE_TEST');

/// Runs validatePhoto() on every .jpg/.jpeg in assets/dev_samples/ and prints
/// each full ValidationResult. Does nothing unless this is a debug build AND
/// the app was started with --dart-define=AI_LIVE_TEST=true.
Future<void> runDevLiveTest() async {
  if (!kDebugMode || !_aiLiveTest) return;
  try {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final paths = manifest
        .listAssets()
        .where((p) => p.startsWith(_samplesPrefix))
        .toList()
      ..sort();

    final photos = paths.where((p) {
      final lower = p.toLowerCase();
      return lower.endsWith('.jpg') || lower.endsWith('.jpeg');
    }).toList();

    if (photos.isEmpty) {
      debugPrint('AI LIVE TEST: no .jpg/.jpeg files in $_samplesPrefix');
      return;
    }

    debugPrint('AI LIVE TEST: ${photos.length} sample(s)');
    final service = AiValidationService();
    for (final path in photos) {
      final data = await rootBundle.load(path);
      final bytes = data.buffer.asUint8List();
      final stopwatch = Stopwatch()..start();
      final r = await service.validatePhoto(bytes);
      stopwatch.stop();
      debugPrint('AI LIVE TEST: $path (${bytes.length} bytes, '
          '${stopwatch.elapsedMilliseconds} ms)');
      debugPrint('  isError:        ${r.isError}'
          '${r.isError ? '  (${r.error})' : ''}');
      debugPrint('  isBreedingSite: ${r.isBreedingSite}');
      debugPrint('  category:       ${r.category.wireValue}');
      debugPrint('  confidence:     ${r.confidence}');
      debugPrint('  looksFake:      ${r.looksFake}');
      debugPrint('  reason:         ${r.reason}');
    }
    debugPrint('AI LIVE TEST: done');
  } catch (e) {
    debugPrint('AI LIVE TEST FAILED: $e');
  }
}
