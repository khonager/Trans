import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trans/config/app_theme.dart';
import 'package:trans/widgets/journey_signal_tutorial.dart';

void main() {
  testWidgets('walks through levels and returns the chosen level',
      (tester) async {
    int? selectedLevel;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: false,
          extensions: const [
            TransColors(seed: Color(0xFF4F46E5), brightness: Brightness.light),
          ],
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selectedLevel = await showJourneySignalTutorial(
                  context,
                  initialLevel: 0,
                );
              },
              child: const Text('Open tutorial'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open tutorial'));
    await tester.pumpAndSettle();

    expect(find.text('Ghost'), findsOneWidget);
    expect(find.text('Nothing is shared.'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('On board'), findsOneWidget);
    await tester.tap(find.text('Use level 1'));
    await tester.pumpAndSettle();

    expect(selectedLevel, 1);
  });
}
