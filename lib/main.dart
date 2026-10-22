import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'features/ai_validation/dev_live_test.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _activateAppCheck();
  // Debug-only AI photo check on assets/dev_samples/. Runs only with:
  //   flutter run --dart-define=AI_LIVE_TEST=true
  if (kDebugMode && _aiLiveTest) {
    runDevLiveTest();
  }
  runApp(const MyApp());
}

const bool _aiLiveTest = bool.fromEnvironment('AI_LIVE_TEST');

/// App Check is required for Firebase AI Logic (Gemini) requests.
/// Debug builds use the debug provider: the debug token is printed to the
/// device log on first run and must be registered in the Firebase console
/// (App Check > Apps > Manage debug tokens). No token is stored in code.
Future<void> _activateAppCheck() async {
  try {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
      providerApple: kDebugMode
          ? const AppleDebugProvider()
          : const AppleAppAttestWithDeviceCheckFallbackProvider(),
    );
  } catch (e) {
    // The app still starts; AI calls will simply fail and be treated as
    // "not eligible".
    debugPrint('App Check activation failed: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'CleanSpot',
      theme: buildTheme(),
      routerConfig: router,
    );
  }
}
