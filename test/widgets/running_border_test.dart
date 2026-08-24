import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trans/widgets/running_border.dart';

/// The outline is painted by a private painter, so it is matched by name.
Iterable<CustomPainter> _outlinePainters(WidgetTester tester) {
  return tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((paint) => paint.foregroundPainter)
      .nonNulls
      .where((painter) =>
          painter.runtimeType.toString().contains('RunningBorder'));
}

void main() {
  testWidgets('renders the child untouched while inactive', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: RunningBorder(
          active: false,
          color: Colors.purple,
          child: Text('Alt'),
        ),
      ),
    );

    expect(find.text('Alt'), findsOneWidget);
    expect(_outlinePainters(tester), isEmpty);
  });

  testWidgets('paints a moving outline while active', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: RunningBorder(
            color: Colors.purple,
            child: SizedBox(width: 80, height: 32, child: Text('Alt')),
          ),
        ),
      ),
    );

    expect(find.text('Alt'), findsOneWidget);
    expect(_outlinePainters(tester), isNotEmpty);

    // The animation keeps running without settling.
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('stops circling when it is switched off', (tester) async {
    Widget build({required bool active}) => MaterialApp(
          home: Center(
            child: RunningBorder(
              active: active,
              color: Colors.purple,
              child: const SizedBox(width: 80, height: 32, child: Text('Alt')),
            ),
          ),
        );

    await tester.pumpWidget(build(active: true));
    expect(_outlinePainters(tester), isNotEmpty);

    await tester.pumpWidget(build(active: false));
    expect(_outlinePainters(tester), isEmpty);
    expect(tester.hasRunningAnimations, isFalse);
  });
}
