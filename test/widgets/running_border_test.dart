import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trans/widgets/running_border.dart';

/// The outline is painted by a private painter, so it is matched by name.
Iterable<CustomPainter> _outlinePainters(WidgetTester tester) {
  return tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((paint) => paint.foregroundPainter)
      .nonNulls
      .where((painter) => painter.runtimeType.toString().contains('RunningBorder'));
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
}
