import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trans/config/app_theme.dart';
import 'package:trans/models/joint_journey.dart';
import 'package:trans/widgets/togetherness_slider.dart';

const _seed = Color(0xFFEC4899);

Future<double?> _pumpSlider(
  WidgetTester tester, {
  required double value,
  bool german = false,
}) async {
  double? reported;
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.lightTheme(_seed),
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: TogethernessSlider(
          value: value,
          german: german,
          onChanged: (next) => reported = next,
        ),
      ),
    ),
  ));
  return reported;
}

void main() {
  testWidgets('uses the app slider, seeded like every other one',
      (tester) async {
    await _pumpSlider(tester, value: 0.5);

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.activeColor, _seed);
    expect(slider.thumbColor, _seed);
    expect(slider.divisions, TogethernessSlider.divisions);
    expect(slider.value, 0.5);
  });

  testWidgets('names the current stop above the track', (tester) async {
    await _pumpSlider(tester, value: 0.5);
    expect(find.text('Time together: Balanced'), findsOneWidget);

    await _pumpSlider(tester, value: 1);
    expect(find.text('Time together: Together'), findsOneWidget);
  });

  testWidgets('names all three stops', (tester) async {
    await _pumpSlider(tester, value: 0.5);

    expect(find.text('Fast'), findsOneWidget);
    expect(find.text('Balanced'), findsOneWidget);
    expect(find.text('Together'), findsOneWidget);
  });

  testWidgets('tapping a stop label jumps to that stop', (tester) async {
    double? reported;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme(_seed),
      home: Scaffold(
        body: TogethernessSlider(
          value: 0.5,
          german: false,
          onChanged: (next) => reported = next,
        ),
      ),
    ));

    await tester.tap(find.byKey(const ValueKey('togetherness-stop-together')));
    expect(reported, 1);

    await tester.tap(find.byKey(const ValueKey('togetherness-stop-fast')));
    expect(reported, 0);
  });

  testWidgets('dragging the track reports a new position', (tester) async {
    double? reported;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme(_seed),
      home: Scaffold(
        body: TogethernessSlider(
          value: 0,
          german: false,
          onChanged: (next) => reported = next,
        ),
      ),
    ));

    await tester.drag(find.byType(Slider), const Offset(500, 0));
    await tester.pump();

    expect(reported, 1);
  });

  testWidgets('advanced settings can keep only the single balance slider',
      (tester) async {
    double? completed;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme(_seed),
      home: Scaffold(
        body: TogethernessSlider(
          value: 0.5,
          german: false,
          showSummary: false,
          onChanged: (_) {},
          onChangeEnd: (value) => completed = value,
        ),
      ),
    ));

    expect(find.byKey(const ValueKey('togetherness-summary')), findsNothing);
    await tester.drag(find.byType(Slider), const Offset(240, 0));
    await tester.pump();
    expect(completed, isNotNull);
  });

  testWidgets('every step lands on the division grid', (tester) async {
    final reported = <double>[];
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme(_seed),
      home: Scaffold(
        body: TogethernessSlider(
          value: 0,
          german: false,
          onChanged: reported.add,
        ),
      ),
    ));

    await tester.drag(find.byType(Slider), const Offset(120, 0));
    await tester.pump();

    expect(reported, isNotEmpty);
    for (final value in reported) {
      expect(value, inInclusiveRange(0, 1));
      expect(
        (value * TogethernessSlider.divisions) -
            (value * TogethernessSlider.divisions).round(),
        closeTo(0, 0.0001),
      );
    }
  });

  testWidgets('the summary spells out what the setting allows',
      (tester) async {
    await _pumpSlider(tester, value: 0);
    const fast = JointJourneyPreferences.fast();
    expect(
      find.text('At most +${fast.maxExtraTravelMinutes} min per person'),
      findsOneWidget,
    );

    await _pumpSlider(tester, value: 1);
    const together = JointJourneyPreferences.together();
    expect(
      find.text('At most +${together.maxExtraTravelMinutes} min per person'),
      findsOneWidget,
    );
    expect(
      find.text(
          'At most ${together.maxExtraTransfers} extra transfers per person'),
      findsOneWidget,
    );
  });

  testWidgets('translates the stops and the summary into German',
      (tester) async {
    await _pumpSlider(tester, value: 1, german: true);

    expect(find.text('Gemeinsame Zeit: Zusammen'), findsOneWidget);
    expect(find.text('Ausgewogen'), findsOneWidget);
    expect(
        find.textContaining('Höchstens +35 Min. pro Person'), findsOneWidget);
  });
}
