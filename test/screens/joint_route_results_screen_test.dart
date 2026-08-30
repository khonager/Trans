import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trans/config/app_theme.dart';
import 'package:trans/models/joint_journey.dart';
import 'package:trans/models/journey.dart';
import 'package:trans/screens/joint_route_results_screen.dart';

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

void main() {
  testWidgets('joint results keep comparison navigation and saturated action',
      (tester) async {
    final start = DateTime(2026, 8, 13, 8, 20);
    final end = DateTime(2026, 8, 13, 9);
    final journey = _journey(start, end);
    final option = JointJourneyOption(
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
      myExtraMinutes: 5,
      friendExtraMinutes: 0,
      myExtraTransfers: 1,
      friendExtraTransfers: 0,
      score: 10,
    );
    var wentBack = false;
    JointJourneyOption? selected;
    const seed = Color(0xFFEC4899);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme(seed),
      home: Scaffold(
        body: JointRouteResultsView(
          friendName: 'Alex',
          destinationName: 'Central',
          options: [option],
          onBack: () => wentBack = true,
          onSelect: (value) => selected = value,
        ),
      ),
    ));

    expect(find.byKey(const ValueKey('joint-results-back')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('joint-results-back')));
    expect(wentBack, isTrue);

    final action = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(action.style?.backgroundColor?.resolve({}), seed);
    await tester.tap(find.byType(FilledButton));
    expect(selected, same(option));
  });
}
