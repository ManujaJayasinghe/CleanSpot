import 'package:clean_spot/features/symptoms/symptoms_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Yes and No fill the card width and are 52 px tall',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: SymptomsScreen()));
    await tester.pump();

    Size optionSize(String label) => tester.getSize(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(AnimatedContainer),
          ),
        );

    final yes = optionSize('Yes');
    final no = optionSize('No');
    expect(yes.height, 52);
    expect(no.height, 52);
    // Full card width (screen 800 minus page and card padding): far wider
    // than the old text-width squish.
    expect(yes.width, greaterThan(250));
    expect(no.width, yes.width);

    // Selecting still works and keeps the size.
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    expect(optionSize('Yes').width, yes.width);
  });
}
