import 'package:clean_spot/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The app itself needs Firebase (router, auth), which is not available in unit
// tests, so this smoke test only checks that the shared theme builds and that a
// themed screen renders.
void main() {
  testWidgets('App theme builds and a themed screen renders', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: const Scaffold(body: Center(child: Text('CleanSpot'))),
      ),
    );

    expect(find.text('CleanSpot'), findsOneWidget);
    expect(Theme.of(tester.element(find.text('CleanSpot'))).useMaterial3, isTrue);
  });
}
