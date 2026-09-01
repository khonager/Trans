import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trans/config/app_theme.dart';
import 'package:trans/l10n/app_localizations.dart';
import 'package:trans/models/joint_journey.dart';
import 'package:trans/models/journey.dart';
import 'package:trans/screens/joint_route_results_screen.dart';

const _seed = Color(0xFFEC4899);

Journey _journey(DateTime start, DateTime end) => Journey(
      steps: [
        JourneyStep(
          type: 'ride',
          line: 'RE 1',
          instruction: 'Ride',
          duration: '40 min',
          departureTime: '08:20',
          arrivalTime: '09:00',
          dateTime: start,
          plannedDeparture: start,
          plannedArrival: end,
          tripId: 'shared-trip',
        ),
      ],
      departure: start,
      arrival: end,
      duration: end.difference(start),
      transferCount: 0,
      totalWaitTime: Duration.zero,
      rawSource: const {},
      source: 'test',
    );

JointJourneyOption _option({
  double detourMinutes = 11,
  double gainMinutes = 40,
  Duration baselineShared = Duration.zero,
  int myExtraMinutes = 5,
  int myExtraTransfers = 1,
}) {
  final start = DateTime(2026, 8, 13, 8, 20);
  final end = DateTime(2026, 8, 13, 9);
  final journey = _journey(start, end);
  return JointJourneyOption(
    myJourney: journey,
    friendJourney: journey,
    sharedSegments: [
      SharedJourneySegment(
        mode: SharedJourneyMode.ride,
        start: start,
        end: end,
        label: 'RE 1',
      ),
    ],
    sharedDuration: const Duration(minutes: 40),
    sharedRideDuration: const Duration(minutes: 40),
    sharedWalkDuration: Duration.zero,
    sharedWaitDuration: Duration.zero,
    baselineSharedDuration: baselineShared,
    myExtraMinutes: myExtraMinutes,
    friendExtraMinutes: 0,
    myExtraTransfers: myExtraTransfers,
    friendExtraTransfers: 0,
    detourMinutes: detourMinutes,
    sharedGainMinutes: gainMinutes,
    netTogetherMinutes: gainMinutes - detourMinutes,
  );
}

Future<void> _pumpResults(
  WidgetTester tester, {
  required List<JointJourneyOption> options,
  JointSearchWindow window = const JointSearchWindow(baseTogetherness: 0.5),
  ValueChanged<JointJourneyOption>? onSelect,
  VoidCallback? onBack,
  Future<void> Function(JointJourneyOption)? onShare,
  VoidCallback? onExpand,
  bool isExpanding = false,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.lightTheme(_seed),
    home: Scaffold(
      body: JointRouteResultsView(
        friendName: 'Alex',
        destinationName: 'Central',
        options: options,
        window: window,
        onBack: onBack ?? () {},
        onSelect: onSelect ?? (_) {},
        onShare: onShare,
        onExpand: onExpand,
        isExpanding: isExpanding,
      ),
    ),
  ));
}

void main() {
  testWidgets('joint results keep comparison navigation and saturated action',
      (tester) async {
    final option = _option();
    var wentBack = false;
    JointJourneyOption? selected;

    await _pumpResults(
      tester,
      options: [option],
      onBack: () => wentBack = true,
      onSelect: (value) => selected = value,
    );

    expect(find.byKey(const ValueKey('joint-results-back')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('joint-results-back')));
    expect(wentBack, isTrue);

    final action = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(action.style?.backgroundColor?.resolve({}), _seed);
    await tester.tap(find.byType(FilledButton));
    expect(selected, same(option));
  });

  testWidgets('states what an option adds and what it costs', (tester) async {
    await _pumpResults(tester, options: [_option()]);

    expect(find.text('+40 min together for +11 min of travel'),
        findsOneWidget);
    expect(find.text('0.3 min of travel per minute together'), findsOneWidget);
    expect(find.text('40 min together'), findsOneWidget);
  });

  testWidgets('calls out an option that costs nothing', (tester) async {
    await _pumpResults(
      tester,
      options: [
        _option(detourMinutes: 0, gainMinutes: 12, myExtraMinutes: 0,
            myExtraTransfers: 0)
      ],
    );

    expect(find.text('+12 min together at no cost'), findsOneWidget);
    expect(find.textContaining('per minute together'), findsNothing);
    expect(find.text('no detour'), findsNWidgets(2));
  });

  testWidgets('separates time the pair would share anyway', (tester) async {
    await _pumpResults(
      tester,
      options: [
        _option(gainMinutes: 25, baselineShared: const Duration(minutes: 15)),
      ],
    );

    expect(
      find.text('You would already travel 15 min of that together anyway.'),
      findsOneWidget,
    );
  });

  testWidgets('names the setting the results were ranked with',
      (tester) async {
    await _pumpResults(
      tester,
      options: [_option()],
      window: const JointSearchWindow(baseTogetherness: 1),
    );

    expect(find.text('with Alex · Together'), findsOneWidget);
  });

  testWidgets('offers sharing only when there is a friend to share with',
      (tester) async {
    await _pumpResults(tester, options: [_option()]);
    expect(find.text('Send to Alex'), findsNothing);

    JointJourneyOption? shared;
    await _pumpResults(
      tester,
      options: [_option()],
      onShare: (option) async => shared = option,
    );
    await tester.tap(find.text('Send to Alex'));
    await tester.pumpAndSettle();

    expect(shared, isNotNull);
    expect(find.text('Plan sent to Alex.'), findsOneWidget);
  });

  testWidgets('reports a failed share without losing the results',
      (tester) async {
    await _pumpResults(
      tester,
      options: [_option()],
      onShare: (_) async => throw StateError('offline'),
    );

    await tester.tap(find.text('Send to Alex'));
    await tester.pumpAndSettle();

    expect(find.text('The plan could not be sent.'), findsOneWidget);
    expect(find.byKey(const ValueKey('joint-route-results-list')),
        findsOneWidget);
  });

  testWidgets('empty results point at the slider when it can still move',
      (tester) async {
    await _pumpResults(
      tester,
      options: const [],
      window: const JointSearchWindow(baseTogetherness: 0),
    );

    expect(find.text('No worthwhile shared route found'), findsOneWidget);
    expect(
      find.text('Move the slider towards “Together” to allow bigger detours.'),
      findsOneWidget,
    );
  });

  testWidgets('empty results stop suggesting the slider at the last stop',
      (tester) async {
    await _pumpResults(
      tester,
      options: const [],
      window: const JointSearchWindow(baseTogetherness: 1),
    );

    expect(
      find.text('Move the slider towards “Together” to allow bigger detours.'),
      findsNothing,
    );
  });

  group('looking further', () {
    testWidgets('offers one more step below the results', (tester) async {
      var presses = 0;
      await _pumpResults(
        tester,
        options: [_option()],
        onExpand: () => presses++,
      );

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('joint-expand-button')),
        200,
      );
      await tester.tap(find.byKey(const ValueKey('joint-expand-button')));
      expect(presses, 1);
    });

    testWidgets('offers the same step when nothing was found',
        (tester) async {
      var presses = 0;
      await _pumpResults(
        tester,
        options: const [],
        onExpand: () => presses++,
      );

      await tester.tap(find.byKey(const ValueKey('joint-expand-button')));
      expect(presses, 1);
    });

    testWidgets('shows progress and blocks a second press while running',
        (tester) async {
      var presses = 0;
      await _pumpResults(
        tester,
        options: const [],
        isExpanding: true,
        onExpand: () => presses++,
      );

      expect(find.text('Looking further…'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('joint-expand-button')),
        warnIfMissed: false,
      );
      expect(presses, 0);
    });

    testWidgets('says when there is nothing left to widen into',
        (tester) async {
      await _pumpResults(tester, options: [_option()]);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('joint-expand-exhausted')),
        200,
      );
      expect(
        find.text('There is no more time together to find around this time.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('joint-expand-button')), findsNothing);
    });

    testWidgets('marks results that needed a wider search', (tester) async {
      await _pumpResults(
        tester,
        options: [_option()],
        window: const JointSearchWindow(baseTogetherness: 0.5, budgetSteps: 1),
      );

      expect(find.textContaining('· widened'), findsOneWidget);
    });
  });

  testWidgets('German results describe the trade in German', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme(_seed),
      locale: const Locale('de'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: JointRouteResultsView(
          friendName: 'Alex',
          destinationName: 'Central',
          options: [_option()],
          onSelect: (_) {},
        ),
      ),
    ));

    expect(find.text('+40 Min. zusammen für +11 Min. Reisezeit'),
        findsOneWidget);
    expect(find.text('40 Min. zusammen'), findsOneWidget);
  });
}
