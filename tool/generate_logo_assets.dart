// Builds the CleanSpot logo assets from the master artwork.
//
//   dart run tool/generate_logo_assets.dart path/to/screen.png
//
// Writes:
//   assets/images/cleanspot_logo.png           in-app logo (login screen)
//   android/.../mipmap-*/ic_launcher.png       legacy launcher icons
//   android/.../mipmap-*/ic_launcher_foreground.png   adaptive icon layer
//   android/.../mipmap-anydpi-v26/ic_launcher.xml     adaptive icon
//   android/.../values/colors.xml              adaptive icon background colour
import 'dart:io';

import 'package:image/image.dart' as img;

const _androidRes = 'android/app/src/main/res';

// Launcher icon size in px per density (48 dp) and adaptive layer size
// (108 dp).
const _densities = <String, ({int icon, int layer})>{
  'mdpi': (icon: 48, layer: 108),
  'hdpi': (icon: 72, layer: 162),
  'xhdpi': (icon: 96, layer: 216),
  'xxhdpi': (icon: 144, layer: 324),
  'xxxhdpi': (icon: 192, layer: 432),
};

/// Share of the adaptive layer the artwork covers. Large enough that every
/// launcher mask (circle, squircle, ...) only ever shows artwork, small
/// enough that the shield stays inside the 72 dp safe zone.
const _layerArtShare = 0.83;

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/generate_logo_assets.dart <logo.png>');
    exit(64);
  }
  final source = img.decodePng(File(args.first).readAsBytesSync());
  if (source == null) {
    stderr.writeln('Could not read ${args.first} as a PNG.');
    exit(65);
  }
  final art = source.hasAlpha ? source : source.convert(numChannels: 4);

  img.Image resize(img.Image from, int size) => img.copyResize(
    from,
    width: size,
    height: size,
    interpolation: img.Interpolation.cubic,
  );

  void writePng(String path, img.Image image) {
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(img.encodePng(image));
    stdout.writeln('wrote $path');
  }

  writePng('assets/images/cleanspot_logo.png', resize(art, 512));

  for (final entry in _densities.entries) {
    final dir = '$_androidRes/mipmap-${entry.key}';
    writePng('$dir/ic_launcher.png', resize(art, entry.value.icon));

    final layer = img.Image(
      width: entry.value.layer,
      height: entry.value.layer,
      numChannels: 4,
    );
    final artSize = (entry.value.layer * _layerArtShare).round();
    final offset = (entry.value.layer - artSize) ~/ 2;
    img.compositeImage(layer, resize(art, artSize), dstX: offset, dstY: offset);
    writePng('$dir/ic_launcher_foreground.png', layer);
  }

  // Adaptive icon background: the artwork's own mint, sampled by the left edge.
  final p = art.getPixel(60, art.height ~/ 2);
  final hex = [p.r, p.g, p.b]
      .map((c) => c.toInt().toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
  File('$_androidRes/values/colors.xml')
    ..createSync(recursive: true)
    ..writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#$hex</color>
</resources>
''');
  File('$_androidRes/mipmap-anydpi-v26/ic_launcher.xml')
    ..createSync(recursive: true)
    ..writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
''');
  stdout.writeln('adaptive icon background: #$hex');
  stdout.writeln(
    'corner alpha: ${art.getPixel(0, 0).a} (0 = transparent rounded corners)',
  );
}
