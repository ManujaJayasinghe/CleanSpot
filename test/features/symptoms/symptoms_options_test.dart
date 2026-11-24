import 'package:clean_spot/features/symptoms/symptoms_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  _hoverTests();

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

void _hoverTests() {
  const lightGreen = Color(0xFFE6F4EA); // theme AppColors.primaryLight
  const green = Color(0xFF248A50); // theme AppColors.primary
  const darkGreen = Color(0xFF1B5E3B); // theme AppColors.primaryDark

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: SymptomsScreen()));
    await tester.pump();
  }

  Finder box(String label) => find.ancestor(
        of: find.text(label),
        matching: find.byType(AnimatedContainer),
      );

  BoxDecoration decoration(WidgetTester tester, String label) =>
      tester.widget<AnimatedContainer>(box(label)).decoration! as BoxDecoration;

  Color textColor(WidgetTester tester, String label) =>
      tester.widget<Text>(find.text(label)).style!.color!;

  testWidgets('answer boxes are round (16) and white by default', (tester) async {
    await open(tester);

    final d = decoration(tester, 'Yes');
    expect(d.borderRadius, BorderRadius.circular(16));
    expect(d.color, Colors.white);
    expect(tester.getSize(box('Yes')).height, 52);
  });

  testWidgets('hovering turns the box green and leaving resets it',
      (tester) async {
    await open(tester);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    await mouse.moveTo(tester.getCenter(box('Yes')));
    await tester.pump(const Duration(milliseconds: 200));
    var d = decoration(tester, 'Yes');
    expect(d.color, lightGreen);
    expect((d.border! as Border).top.color, green);
    expect(textColor(tester, 'Yes'), darkGreen);
    // The other box is untouched.
    expect(decoration(tester, 'No').color, Colors.white);

    await mouse.moveTo(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 200));
    d = decoration(tester, 'Yes');
    expect(d.color, Colors.white);
  });

  testWidgets('pressing (touch) turns the box green while held',
      (tester) async {
    await open(tester);

    final touch = await tester.startGesture(tester.getCenter(box('No')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(decoration(tester, 'No').color, lightGreen);

    await touch.cancel();
    await tester.pump(const Duration(milliseconds: 200));
    expect(decoration(tester, 'No').color, Colors.white);
  });

  testWidgets('keyboard focus turns the box green', (tester) async {
    await open(tester);

    // Tab moves focus to the first focusable control; find which box got it.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump(const Duration(milliseconds: 200));

    final greenBoxes = [
      for (final label in ['Yes', 'No'])
        if (decoration(tester, label).color == lightGreen) label,
    ];
    expect(greenBoxes, isNotEmpty);
  });

  testWidgets('the selected answer is green with a 1.5 px border',
      (tester) async {
    await open(tester);

    await tester.tap(find.text('Yes'));
    // Move the (mouse-less) pointer away so only the selection is green.
    await tester.pumpAndSettle();

    final yes = decoration(tester, 'Yes');
    expect(yes.color, lightGreen);
    final side = (yes.border! as Border).top;
    expect(side.color, green);
    expect(side.width, 1.5);
    expect(textColor(tester, 'Yes'), darkGreen);

    // Not the old black border, and the other answer stays plain.
    expect(side.color, isNot(Colors.black));
    expect(decoration(tester, 'No').color, Colors.white);
  });
}
