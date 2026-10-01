import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trans/l10n/app_localizations.dart';
import 'package:trans/models/journey.dart';
import 'package:trans/models/station.dart';
import 'package:trans/widgets/route_options.dart';

Journey _journey(String line, {String? transferLine}) {
  final start = DateTime.utc(2026, 10, 1, 10);
  return Journey(
    steps: [
      JourneyStep(
        type: 'ride',
        line: line,
        instruction: '',
        duration: '10 min',
        departureTime: '10:00',
        arrivalTime: '10:10',
      ),
      if (transferLine != null)
        JourneyStep(
          type: 'ride',
          line: transferLine,
          instruction: '',
          duration: '10 min',
          departureTime: '10:15',
          arrivalTime: '10:25',
        ),
    ],
    departure: start,
    arrival: start.add(const Duration(minutes: 25)),
    duration: const Duration(minutes: 25),
    transferCount: transferLine == null ? 0 : 1,
    totalWaitTime: Duration.zero,
    rawSource: const {},
    source: 'test',
  );
}

void main() {
  testWidgets('line list grows with loaded routes and persists for the pair',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final origin = Station(id: 'origin', name: 'Origin');
    final destination = Station(id: 'destination', name: 'Destination');

    Future<void> show(List<Journey> candidates) async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: KnownLinesPanel(
            origin: origin,
            destination: destination,
            candidates: candidates,
            sampleDate: DateTime.utc(2026, 10, 1),
            discoverLines: (
                    {required origin,
                    required destination,
                    required date}) async =>
                [],
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    await show([_journey('27')]);
    await tester.tap(find.text('Lines you can take'));
    await tester.pumpAndSettle();
    expect(find.text('27'), findsOneWidget);

    await show([_journey('27'), _journey('18', transferLine: '45')]);
    expect(find.text('18'), findsOneWidget);
    expect(find.text('27'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await show([]);
    await tester.tap(find.text('Lines you can take'));
    await tester.pumpAndSettle();
    expect(find.text('18'), findsOneWidget);
    expect(find.text('27'), findsOneWidget);
  });

  testWidgets('timetable failure leaves known lines visible', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: KnownLinesPanel(
          origin: Station(id: 'failure-origin', name: 'Origin'),
          destination: Station(id: 'failure-destination', name: 'Destination'),
          candidates: [_journey('18', transferLine: '45')],
          sampleDate: DateTime.utc(2026, 10, 1),
          discoverLines: (
              {required origin, required destination, required date}) async {
            throw StateError('provider unavailable');
          },
        ),
      ),
    ));
    await tester.tap(find.text('Lines you can take'));
    await tester.pumpAndSettle();

    expect(find.text('18'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });
}
