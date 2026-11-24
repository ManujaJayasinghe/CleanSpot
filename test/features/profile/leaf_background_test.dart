import 'package:clean_spot/features/profile/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('PointsCard is drawn on the shared LeafBackground', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PointsCard(label: 'Your points', points: 55, caption: 'Earn more'),
        ),
      ),
    );

    expect(find.byType(LeafBackground), findsOneWidget);
    expect(find.text('YOUR POINTS'), findsOneWidget);
    expect(find.text('55'), findsOneWidget);
    expect(find.text('Earn more'), findsOneWidget);
    expect(find.byIcon(Icons.eco_outlined), findsOneWidget);

    // Same decoration as before: dark green, 24 px corners, lighter circle.
    final box = tester
        .widget<Container>(
          find.descendant(
            of: find.byType(LeafBackground),
            matching: find.byType(Container),
          ).first,
        )
        .decoration as BoxDecoration;
    expect(box.color, const Color(0xFF145A32));
    expect(box.borderRadius, BorderRadius.circular(24));
    expect(LeafBackground.circleGreen, const Color(0xFF1E7544));
  });

  testWidgets('a compact LeafBackground takes the height of its child',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: LeafBackground(
              borderRadius: BorderRadius.circular(18),
              circleSize: 120,
              circleTop: null,
              circleRight: -34,
              leafSize: 44,
              child: const SizedBox(height: 56),
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(LeafBackground)).height, 56);
    expect(tester.takeException(), isNull);
  });
}
