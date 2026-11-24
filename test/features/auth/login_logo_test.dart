import 'dart:io';

import 'package:clean_spot/features/auth/login_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

// The login screen itself builds a FirestoreService, so it needs Firebase and
// is checked on a device; these tests cover the logo files it relies on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the logo shown on the login screen is bundled and square', () async {
    final data = await rootBundle.load(kCleanSpotLogoAsset);
    final logo = img.decodePng(data.buffer.asUint8List());
    expect(logo, isNotNull);
    expect(logo!.width, logo.height);
    expect(logo.width, greaterThanOrEqualTo(256));
  });

  test('the Android launcher icon resources exist', () {
    const res = 'android/app/src/main/res';
    for (final density in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      expect(File('$res/mipmap-$density/ic_launcher.png').existsSync(), isTrue);
      expect(
        File('$res/mipmap-$density/ic_launcher_foreground.png').existsSync(),
        isTrue,
      );
    }
    expect(File('$res/mipmap-anydpi-v26/ic_launcher.xml').existsSync(), isTrue);
    expect(File('$res/values/colors.xml').existsSync(), isTrue);
  });
}
