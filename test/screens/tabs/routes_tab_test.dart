import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trans/config/app_theme.dart';
import 'package:trans/l10n/app_localizations.dart';
import 'package:trans/models/journey.dart';
import 'package:trans/models/station.dart';
import 'package:trans/screens/tabs/routes_tab.dart';

final _pullOrigin = Station(id: 'origin', name: 'Origin', type: 'station');

JourneyStep _pullStep(int index) => JourneyStep(
      type: 'ride',
      line: 'RB$index',
      instruction: 'Ride $index',
      duration: '10 min',
      departureTime: '10:0$index',
      arrivalTime: '10:1$index',
      startStationName: 'Stop $index',
      destinationName: 'Stop ${index + 1}',
    );

Journey _pullJourney({int minute = 0, int steps = 24}) {
  final departure = DateTime(2026, 9, 3, 10).add(Duration(minutes: minute));
  return Journey(
    steps: List.generate(steps, _pullStep),
    departure: departure,
    arrival: departure.add(const Duration(hours: 2)),
    duration: const Duration(hours: 2),
    transferCount: steps - 1,
    totalWaitTime: Duration.zero,
    rawSource: const {'legs': []},
    source: 'test',
  );
}

RouteTab _routeTab({
  required int index,
  Journey? activeJourney,
  List<Journey>? candidates,
}) {
  final destination = Station(
    id: 'destination-$index',
    name: 'Destination $index',
    type: 'station',
  );
  return RouteTab(
    id: 'tab-$index',
    title: 'Destination $index',
    subtitle: '10:00 - 12:00',
    eta: '12:00',
    totalDuration: '2 h',
    destination: destination,
    origin: _pullOrigin,
    steps: activeJourney?.steps ?? const <JourneyStep>[],
    candidates: candidates,
    stack: activeJourney == null ? const <Journey>[] : <Journey>[activeJourney],
    activeJourney: activeJourney,
    searchSettings: RouteSearchSettings(
      when: DateTime(2026, 9, 3, 10),
      isArrival: false,
    ),
  );
}

RouteTab _activeJourneyTab({int index = 0}) =>
    _routeTab(index: index, activeJourney: _pullJourney());

RouteTab _candidatesTab({int index = 0}) => _routeTab(
      index: index,
      candidates: List.generate(
        8,
        (i) => _pullJourney(minute: i * 15, steps: 2),
      ),
    );

Future<RoutesTabState> _pumpRoutesTab(
  WidgetTester tester, {
  Size size = const Size(420, 760),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final key = GlobalKey<RoutesTabState>();
  await tester.pumpWidget(MaterialApp(
    theme: createTheme(const Color(0xFF4F46E5), Brightness.light)
        .copyWith(platform: TargetPlatform.android),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: RoutesTab(
        key: key,
        currentPosition: null,
        onlyNahverkehr: false,
        alwaysWakeMe: false,
        signalLevel: 0,
        onHighAccuracyTrackingChanged: (_) {},
      ),
    ),
  ));
  await tester.pump();
  return key.currentState!;
}

final Finder _tabStripFinder = find.byWidgetPredicate(
  (widget) => widget is ListView && widget.scrollDirection == Axis.horizontal,
);

ScrollableState _tabStripScrollable(WidgetTester tester) => tester.state(
      find.descendant(of: _tabStripFinder, matching: find.byType(Scrollable)),
    );

/// The scrollable behind whichever route view is on screen: the opened journey
/// or the route candidates list.
ScrollController _routeViewScrollController(WidgetTester tester) => tester
    .widget<ListView>(find.descendant(
      of: find.byType(RefreshIndicator),
      matching: find.byType(ListView),
    ))
    .controller!;

/// Presses down on an empty stretch of the fixed tab strip, to the right of the
/// "+" button, so no chip or icon is involved in the gesture.
Future<TestGesture> _startHeaderPull(
  WidgetTester tester, {
  required PointerDeviceKind kind,
}) async {
  final strip = tester.getRect(_tabStripFinder);
  final plusButton = tester.getRect(find.byIcon(Icons.add_circle_outline));
  final x = (plusButton.right + strip.right) / 2;
  expect(x, greaterThan(plusButton.right),
      reason: 'the strip needs empty space to press on');
  return tester.startGesture(Offset(x, strip.center.dy), kind: kind);
}

Future<void> _pullBy(
  WidgetTester tester,
  TestGesture gesture,
  double distance,
) async {
  for (var moved = 0.0; moved < distance; moved += 20) {
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Lets the indicator finish its snap animation, which is when
/// [RefreshIndicator] invokes `onRefresh`.
Future<void> _settleIndicator(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  test('saved journey identity survives realtime provider changes', () {
    const savedKey = 'origin::destination::saved-connection';
    final plannedDeparture = DateTime.utc(2026, 9, 3, 10);
    final plannedArrival = DateTime.utc(2026, 9, 3, 11);
    final journey = Journey(
      steps: const [],
      departure: plannedDeparture,
      arrival: plannedArrival,
      duration: const Duration(hours: 1),
      transferCount: 0,
      totalWaitTime: Duration.zero,
      rawSource: const {'legs': []},
      source: 'motis',
      plannedDeparture: plannedDeparture,
      plannedArrival: plannedArrival,
      savedConnectionKey: savedKey,
    );

    final refreshed = journey.copyWith(
      departure: plannedDeparture.add(const Duration(minutes: 12)),
      arrival: plannedArrival.add(const Duration(minutes: 12)),
      rawSource: const {
        'legs': [
          {'tripId': 'provider-now-uses-a-different-id'}
        ],
      },
    );

    expect(
      savedJourneyConnectionKeyFor(
        journey: refreshed,
        from: Station(id: 'origin', name: 'Origin', type: 'station'),
        to: Station(
          id: 'destination',
          name: 'Destination',
          type: 'station',
        ),
      ),
      savedKey,
    );
  });

  test('formats ride line with numeric platform', () {
    final formatted = formatRideLineWithPlatform('RB21', '6');
    expect(formatted, 'RB21 (Gl. 6)');
  });

  test('does not duplicate platform suffix when already present', () {
    final formatted = formatRideLineWithPlatform('RB21 (Pl. 6)', '6');
    expect(formatted, 'RB21 (Gl. 6)');
  });

  test('does not duplicate platform suffix when Gl. suffix already present',
      () {
    final formatted = formatRideLineWithPlatform('RE 50 (Gl. 2)', '2');
    expect(formatted, 'RE 50 (Gl. 2)');
  });

  test('does not use arrival platform as display fallback', () {
    final formatted = formatRideDisplayLine(
      line: 'RE29',
      platform: null,
      arrivalPlatform: '9',
      tripId: null,
      showTrainNumbers: false,
    );
    expect(formatted, 'RE29');
  });

  test('keeps both coupled line numbers but hides both train numbers', () {
    final formatted = formatRideDisplayLine(
      line: 'RB22 (80854) / RB13 (81020)',
      platform: '4b',
      arrivalPlatform: null,
      tripId: 'opaque-trip-id',
      showTrainNumbers: false,
    );
    expect(formatted, 'RB22 / RB13 (4b)');
  });

  group('starting a search', () {
    test('needs both ends of the journey', () {
      expect(
        canStartRouteSearch(
          hasOrigin: false,
          hasDestination: true,
          jointPlanningEnabled: false,
          hasCompanionOrigin: false,
        ),
        isFalse,
      );
      expect(
        canStartRouteSearch(
          hasOrigin: true,
          hasDestination: false,
          jointPlanningEnabled: false,
          hasCompanionOrigin: false,
        ),
        isFalse,
      );
      expect(
        canStartRouteSearch(
          hasOrigin: true,
          hasDestination: true,
          jointPlanningEnabled: false,
          hasCompanionOrigin: false,
        ),
        isTrue,
      );
    });

    test('planning together also needs where the companion starts', () {
      expect(
        canStartRouteSearch(
          hasOrigin: true,
          hasDestination: true,
          jointPlanningEnabled: true,
          hasCompanionOrigin: false,
        ),
        isFalse,
      );
      expect(
        canStartRouteSearch(
          hasOrigin: true,
          hasDestination: true,
          jointPlanningEnabled: true,
          hasCompanionOrigin: true,
        ),
        isTrue,
      );
    });

    test('a companion start alone is not enough', () {
      expect(
        canStartRouteSearch(
          hasOrigin: true,
          hasDestination: false,
          jointPlanningEnabled: true,
          hasCompanionOrigin: true,
        ),
        isFalse,
      );
    });
  });

  group('station identity matching', () {
    test('recognises Hbf and Hauptbahnhof as the same station', () {
      expect(
        sameTransitStationForTesting(
          'provider:arrival:23',
          'Frankfurt (Main) Hbf',
          'provider:departure:15',
          'Frankfurt (Main) Hauptbahnhof',
        ),
        isTrue,
      );
    });

    test('does not merge different stations just because ids differ', () {
      expect(
        sameTransitStationForTesting(
          'station:frankfurt',
          'Frankfurt (Main) Hbf',
          'station:offenbach',
          'Offenbach (Main) Hbf',
        ),
        isFalse,
      );
    });
  });

  test('combines train platform with richer stop label detail', () {
    final combined = combinePlatformAndStopLabel(
      '24',
      'Gleis 24-25',
      stationName: 'München Hbf',
      isRail: true,
    );
    expect(combined, 'Gl. 24');
  });

  group('earlier alternative hints', () {
    JourneyStep ride(String line, DateTime departure, DateTime arrival) {
      return JourneyStep(
        type: 'ride',
        line: line,
        instruction: line,
        duration: '10 min',
        departureTime: '',
        arrivalTime: '',
        dateTime: departure,
        plannedDeparture: departure,
        plannedArrival: arrival,
      );
    }

    JourneyStep walk(DateTime departure) {
      return JourneyStep(
        type: 'walk',
        line: 'Transfer',
        instruction: 'walk',
        duration: '5 min',
        departureTime: '',
        arrivalTime: '',
        isWalking: true,
        dateTime: departure,
      );
    }

    // Far enough ahead that "now" never overtakes the fixture.
    final start = DateTime(2030, 8, 24, 9, 0);
    final steps = <JourneyStep>[
      walk(start),
      ride('21', start.add(const Duration(minutes: 15)),
          start.add(const Duration(minutes: 41))),
      ride('RB75', start.add(const Duration(minutes: 50)),
          start.add(const Duration(minutes: 80))),
      ride('RB33', start.add(const Duration(minutes: 87)),
          start.add(const Duration(minutes: 120))),
    ];

    test('checks the first two rides when a route is opened', () {
      expect(earlierAlternativeScanTargets(steps, start), [1, 2]);
    });

    test('slides forward one ride at a time as rides depart', () {
      expect(
        earlierAlternativeScanTargets(
          steps,
          start.add(const Duration(minutes: 20)),
        ),
        [2, 3],
      );
      expect(
        earlierAlternativeScanTargets(
          steps,
          start.add(const Duration(minutes: 55)),
        ),
        [3],
      );
      expect(
        earlierAlternativeScanTargets(
          steps,
          start.add(const Duration(minutes: 90)),
        ),
        isEmpty,
      );
    });

    test('cannot board before the ride that brings you there arrives', () {
      final state = RoutesTabState();
      // Ride 3 is reached with ride 2, which arrives at start + 80 min.
      expect(
        state.earliestCatchableDeparture(steps, 3),
        start.add(const Duration(minutes: 80)),
      );
    });

    test('accepts an earlier departure that still arrives in time', () {
      expect(
        earlierAlternativeQualifies(
          plannedDeparture: DateTime(2026, 8, 24, 10, 27),
          alternativeDeparture: DateTime(2026, 8, 24, 10, 0),
          alternativeArrival: DateTime(2026, 8, 24, 11, 9),
          earliestCatchable: DateTime(2026, 8, 24, 9, 50),
          latestArrival: DateTime(2026, 8, 24, 11, 9),
        ),
        isTrue,
      );
    });

    test('rejects an alternative that cannot be reached in time', () {
      expect(
        earlierAlternativeQualifies(
          plannedDeparture: DateTime(2026, 8, 24, 10, 27),
          alternativeDeparture: DateTime(2026, 8, 24, 9, 45),
          alternativeArrival: DateTime(2026, 8, 24, 11, 9),
          earliestCatchable: DateTime(2026, 8, 24, 9, 50),
          latestArrival: DateTime(2026, 8, 24, 11, 9),
        ),
        isFalse,
      );
    });

    test('rejects an alternative that arrives later than the current plan', () {
      expect(
        earlierAlternativeQualifies(
          plannedDeparture: DateTime(2026, 8, 24, 10, 27),
          alternativeDeparture: DateTime(2026, 8, 24, 10, 0),
          alternativeArrival: DateTime(2026, 8, 24, 11, 38),
          earliestCatchable: DateTime(2026, 8, 24, 9, 50),
          latestArrival: DateTime(2026, 8, 24, 11, 9),
        ),
        isFalse,
      );
    });

    test('ignores a departure that is barely earlier', () {
      expect(
        earlierAlternativeQualifies(
          plannedDeparture: DateTime(2026, 8, 24, 10, 27),
          alternativeDeparture: DateTime(2026, 8, 24, 10, 26),
          alternativeArrival: DateTime(2026, 8, 24, 11, 9),
          earliestCatchable: DateTime(2026, 8, 24, 9, 50),
          latestArrival: DateTime(2026, 8, 24, 11, 9),
        ),
        isFalse,
      );
    });

    Map<String, dynamic> rawJourney({
      required String walkStart,
      required String rideStart,
      required String arrival,
      String? tripId,
      String line = 'RB21',
    }) {
      return {
        'legs': [
          {'plannedDeparture': walkStart, 'walking': true},
          {
            'plannedDeparture': rideStart,
            'plannedArrival': arrival,
            'line': {'name': line, if (tripId != null) 'tripId': tripId},
          },
        ],
      };
    }

    test('reads the boarding time, not the start of the leading walk', () {
      final journey = rawJourney(
        walkStart: '2030-08-24T11:10:00Z',
        rideStart: '2030-08-24T11:11:00Z',
        arrival: '2030-08-24T11:27:00Z',
      );

      expect(
        alternativeJourneyBoardingLocal(journey),
        DateTime.parse('2030-08-24T11:11:00Z').toLocal(),
      );
      expect(
        alternativeJourneyDisplayDepartureLocal(journey),
        DateTime.parse('2030-08-24T11:10:00Z').toLocal(),
      );
    });

    test('recognises the ride the traveller is already on by trip id', () {
      final journey = rawJourney(
        walkStart: '2030-08-24T11:10:00Z',
        rideStart: '2030-08-24T11:11:00Z',
        arrival: '2030-08-24T11:27:00Z',
        tripId: 'trip-24441',
      );

      expect(
        alternativeIsSameRide(journey, tripId: 'trip-24441'),
        isTrue,
      );
      expect(
        alternativeIsSameRide(journey, tripId: 'trip-24439'),
        isFalse,
      );
    });

    test('a differing trip id still falls back to line and minute', () {
      // MOTIS hands out opaque trip tokens that can differ for the same trip
      // between two responses.
      final journey = rawJourney(
        walkStart: '2030-08-24T11:10:00Z',
        rideStart: '2030-08-24T11:11:00Z',
        arrival: '2030-08-24T11:27:00Z',
        tripId: 'other-token',
        line: 'RB21 (24441)',
      );

      expect(
        alternativeIsSameRide(
          journey,
          tripId: 'trip-24441',
          line: 'RB21',
          departure: DateTime.parse('2030-08-24T11:11:00Z').toLocal(),
        ),
        isTrue,
      );
      expect(
        alternativeIsSameRide(
          journey,
          tripId: 'trip-24441',
          line: 'RB21',
          departure: DateTime.parse('2030-08-24T11:41:00Z').toLocal(),
        ),
        isFalse,
      );
    });

    test('falls back to line and boarding minute without a trip id', () {
      final journey = rawJourney(
        walkStart: '2030-08-24T11:10:00Z',
        rideStart: '2030-08-24T11:11:00Z',
        arrival: '2030-08-24T11:27:00Z',
        line: 'RB21 (24441)',
      );
      final rideDeparture = DateTime.parse('2030-08-24T11:11:00Z').toLocal();

      expect(
        alternativeIsSameRide(journey, line: 'RB21', departure: rideDeparture),
        isTrue,
      );
      // A different departure of the same line stays an alternative.
      expect(
        alternativeIsSameRide(
          journey,
          line: 'RB21',
          departure: rideDeparture.add(const Duration(minutes: 30)),
        ),
        isFalse,
      );
      expect(
        alternativeIsSameRide(journey, line: 'RB10', departure: rideDeparture),
        isFalse,
      );
    });

    test('lists a ride once, keeping the fastest continuation', () {
      final early = rawJourney(
        walkStart: '2030-08-24T12:09:00Z',
        rideStart: '2030-08-24T12:10:00Z',
        arrival: '2030-08-24T13:20:00Z',
        tripId: 'trip-24443',
      );
      final late = rawJourney(
        walkStart: '2030-08-24T12:09:00Z',
        rideStart: '2030-08-24T12:10:00Z',
        arrival: '2030-08-24T13:50:00Z',
        tripId: 'trip-24443',
      );
      final other = rawJourney(
        walkStart: '2030-08-24T12:39:00Z',
        rideStart: '2030-08-24T12:40:00Z',
        arrival: '2030-08-24T13:55:00Z',
        tripId: 'trip-24445',
      );

      final collapsed = collapseAlternativesByRide([late, early, other]);
      expect(collapsed, hasLength(2));
      expect(collapsed.first, same(early));
      expect(collapsed.last, same(other));
    });

    test('separates rides of the same line at different times', () {
      final first = rawJourney(
        walkStart: '2030-08-24T12:09:00Z',
        rideStart: '2030-08-24T12:10:00Z',
        arrival: '2030-08-24T13:20:00Z',
      );
      final second = rawJourney(
        walkStart: '2030-08-24T12:39:00Z',
        rideStart: '2030-08-24T12:40:00Z',
        arrival: '2030-08-24T13:50:00Z',
      );

      expect(collapseAlternativesByRide([first, second]), hasLength(2));
    });

    test('a long stop keys off the departure, not the arrival', () {
      // Same train, standing at the stop: boarding is possible earlier, but
      // both results are keyed on the 05:36 departure.
      final boarding = rawJourney(
        walkStart: '2030-08-24T05:20:00Z',
        rideStart: '2030-08-24T05:36:00Z',
        arrival: '2030-08-24T06:10:00Z',
      );
      final sameTrain = rawJourney(
        walkStart: '2030-08-24T05:25:00Z',
        rideStart: '2030-08-24T05:36:00Z',
        arrival: '2030-08-24T06:30:00Z',
      );

      expect(collapseAlternativesByRide([boarding, sameTrain]), hasLength(1));
    });

    test('keeps at most three earlier departures, the closest ones', () {
      Map<String, dynamic> at(String time, String arrival) => rawJourney(
            walkStart: time,
            rideStart: time,
            arrival: arrival,
            tripId: 'trip-$time',
          );
      final planned = DateTime.parse('2030-08-24T12:00:00Z').toLocal();
      final journeys = [
        at('2030-08-24T10:00:00Z', '2030-08-24T11:00:00Z'),
        at('2030-08-24T10:30:00Z', '2030-08-24T11:30:00Z'),
        at('2030-08-24T11:00:00Z', '2030-08-24T12:00:00Z'),
        at('2030-08-24T11:20:00Z', '2030-08-24T12:20:00Z'),
        at('2030-08-24T11:40:00Z', '2030-08-24T12:40:00Z'),
        at('2030-08-24T12:30:00Z', '2030-08-24T13:30:00Z'),
      ];

      final limited = limitEarlierAlternatives(journeys, reference: planned);
      expect(limited, hasLength(4));
      expect(
        limited.map(alternativeJourneyBoardingLocal),
        [
          DateTime.parse('2030-08-24T11:00:00Z').toLocal(),
          DateTime.parse('2030-08-24T11:20:00Z').toLocal(),
          DateTime.parse('2030-08-24T11:40:00Z').toLocal(),
          DateTime.parse('2030-08-24T12:30:00Z').toLocal(),
        ],
      );
    });

    test('leaves the list alone when there are few earlier departures', () {
      final planned = DateTime.parse('2030-08-24T12:00:00Z').toLocal();
      final journeys = [
        rawJourney(
          walkStart: '2030-08-24T11:40:00Z',
          rideStart: '2030-08-24T11:40:00Z',
          arrival: '2030-08-24T12:40:00Z',
        ),
        rawJourney(
          walkStart: '2030-08-24T12:30:00Z',
          rideStart: '2030-08-24T12:30:00Z',
          arrival: '2030-08-24T13:30:00Z',
        ),
      ];

      expect(
        limitEarlierAlternatives(journeys, reference: planned),
        same(journeys),
      );
    });

    test('keys a raw journey by departure and arrival', () {
      final journey = {
        'legs': [
          {'plannedDeparture': '2026-08-24T07:00:00Z'},
          {'plannedArrival': '2026-08-24T09:09:00Z'},
        ],
      };
      final departure = DateTime.parse('2026-08-24T07:00:00Z').toLocal();
      final arrival = DateTime.parse('2026-08-24T09:09:00Z').toLocal();

      expect(
        alternativeJourneyKey(journey),
        '${departure.millisecondsSinceEpoch}_'
        '${arrival.millisecondsSinceEpoch}',
      );
      expect(alternativeJourneyKey({'legs': []}), isNull);
    });

    test('reads the arrival of a raw journey map', () {
      expect(
        alternativeJourneyArrivalLocal({
          'legs': [
            {'plannedArrival': '2026-08-24T09:00:00Z'},
            {'plannedArrival': '2026-08-24T09:09:00Z'},
          ],
        }),
        DateTime.parse('2026-08-24T09:09:00Z').toLocal(),
      );
      expect(alternativeJourneyArrivalLocal({'legs': []}), isNull);
    });
  });

  group('tab strip selection', () {
    Journey journey({
      required DateTime departure,
      required DateTime arrival,
      int? branchStepIndex,
      Journey? parentJourney,
      String? platform,
    }) {
      return Journey(
        steps: [
          JourneyStep(
            type: 'ride',
            line: 'RB21',
            instruction: 'RB21',
            duration: '16 min',
            departureTime: '',
            arrivalTime: '',
            dateTime: departure,
            plannedDeparture: departure,
            plannedArrival: arrival,
            platform: platform,
          ),
        ],
        departure: departure,
        arrival: arrival,
        duration: arrival.difference(departure),
        transferCount: 0,
        totalWaitTime: Duration.zero,
        rawSource: const {},
        source: 'motis',
        plannedDeparture: departure,
        plannedArrival: arrival,
        parentJourney: parentJourney,
        branchStepIndex: branchStepIndex,
      );
    }

    final departure = DateTime(2030, 8, 24, 13, 28);
    final arrival = DateTime(2030, 8, 24, 14, 24);

    test('recognises the same entry after a realtime refresh', () {
      // Same connection, rebuilt as a new object by the refresh.
      expect(
        isSameJourneyEntryForTesting(
          journey(departure: departure, arrival: arrival),
          journey(departure: departure, arrival: arrival),
        ),
        isTrue,
      );
    });

    test('keeps a branch apart from the journey it came from', () {
      expect(
        isSameJourneyEntryForTesting(
          journey(departure: departure, arrival: arrival),
          journey(departure: departure, arrival: arrival, branchStepIndex: 2),
        ),
        isFalse,
      );
    });

    test('platform enrichment preserves the route branch back link', () {
      final parent = journey(departure: departure, arrival: arrival);
      final branch = journey(
        departure: departure,
        arrival: arrival,
        branchStepIndex: 2,
        parentJourney: parent,
      );
      final enriched = journey(
        departure: departure,
        arrival: arrival,
        platform: '4b',
      );

      final result = preferJourneyWithMorePlatformDetailForTesting(
        branch,
        enriched,
      );

      expect(result.steps.single.platform, '4b');
      expect(result.parentJourney, same(parent));
      expect(result.branchStepIndex, 2);
    });

    test('keeps different connections apart', () {
      expect(
        isSameJourneyEntryForTesting(
          journey(departure: departure, arrival: arrival),
          journey(
            departure: departure,
            arrival: arrival.add(const Duration(minutes: 30)),
          ),
        ),
        isFalse,
      );
    });
  });

  group('branching into an alternative', () {
    Map<String, dynamic> walkLeg(String from, String to) => {
          'departure': from,
          'arrival': to,
          'walking': true,
        };
    Map<String, dynamic> rideLeg(String line, String from, String to) => {
          'departure': from,
          'arrival': to,
          'plannedDeparture': from,
          'plannedArrival': to,
          'line': {'name': line},
        };

    final original = {
      'legs': [
        walkLeg('2030-08-24T11:38:00Z', '2030-08-24T11:41:00Z'),
        rideLeg('RB21', '2030-08-24T11:41:00Z', '2030-08-24T11:57:00Z'),
        walkLeg('2030-08-24T11:57:00Z', '2030-08-24T11:58:00Z'),
        rideLeg('RB10', '2030-08-24T12:02:00Z', '2030-08-24T12:09:00Z'),
        rideLeg('6', '2030-08-24T12:17:00Z', '2030-08-24T12:20:00Z'),
      ],
    };

    test('keeps the trip up to the ride being swapped', () {
      // Leg 3 is the RB10; the walk before it belongs to the alternative.
      expect(journeyPrefixLegCount(original['legs'] as List, 3), 2);
    });

    test('keeps nothing when the first ride is swapped', () {
      expect(journeyPrefixLegCount(original['legs'] as List, 1), 0);
      expect(journeyPrefixLegCount(original['legs'] as List, 0), 0);
    });

    test('splices the alternative onto the part already under way', () {
      final alternative = {
        'legs': [
          walkLeg('2030-08-24T11:57:00Z', '2030-08-24T11:59:00Z'),
          rideLeg('RB10', '2030-08-24T11:32:00Z', '2030-08-24T11:39:00Z'),
        ],
      };

      final spliced = spliceAlternativeIntoJourney(
        original: original,
        alternative: alternative,
        rideLegIndex: 3,
      );
      final legs = spliced['legs'] as List;

      expect(legs, hasLength(4));
      expect((legs[1] as Map)['line']['name'], 'RB21');
      expect((legs[3] as Map)['line']['name'], 'RB10');
      expect(spliced['departure'], '2030-08-24T11:38:00Z');
      expect(spliced['arrival'], '2030-08-24T11:39:00Z');
      expect(spliced.containsKey('duration'), isFalse);
    });

    test('returns the alternative untouched when nothing precedes it', () {
      final alternative = {
        'legs': [
          rideLeg('RB21', '2030-08-24T11:11:00Z', '2030-08-24T11:27:00Z')
        ],
      };

      expect(
        spliceAlternativeIntoJourney(
          original: original,
          alternative: alternative,
          rideLegIndex: 1,
        ),
        same(alternative),
      );
    });

    test('a transfer after the first ride is not treated as initial access',
        () {
      expect(isBeforeFirstJourneyStepForTesting(0), isTrue);
      expect(isBeforeFirstJourneyStepForTesting(1), isFalse);
    });
  });

  test('keeps the feed track when the label names a whole platform area', () {
    final combined = combinePlatformAndStopLabel(
      '11',
      'Gleis1/11',
      stationName: 'Mainz, Hauptbahnhof',
      isRail: true,
    );
    expect(combined, 'Gl. 11');
  });

  test('shows every track of a platform area when no track is known', () {
    final combined = combinePlatformAndStopLabel(
      null,
      'Gleis1/11',
      stationName: 'Mainz, Hauptbahnhof',
      isRail: true,
    );
    expect(combined, 'Gl. 1/11');
  });

  test('recognises a track that is only a combined platform area', () {
    expect(platformLooksLikeTrackArea('11', 'Gleis1/11'), isTrue);
    expect(platformLooksLikeTrackArea('11', 'Gleis 11'), isFalse);
    expect(platformLooksLikeTrackArea('5b', 'Gleis1/11'), isFalse);
    expect(platformLooksLikeTrackArea(null, 'Gleis1/11'), isFalse);
  });

  test('does not duplicate stop label when it only repeats the platform', () {
    final combined = combinePlatformAndStopLabel(
      '7',
      'Bahnsteig Gleis 7',
      stationName: 'Berlin Hbf',
      isRail: true,
    );
    expect(combined, 'Gl. 7');
  });

  test('does not duplicate bus stand labels like Bussteig B', () {
    final combined = combinePlatformAndStopLabel(
      'B',
      'Bussteig B',
      stationName: 'Wiesbaden Hauptbahnhof',
      isRail: false,
    );
    expect(combined, 'Steig B');
  });

  test('prefers cleaned stop label for Platz B instead of B bullet B', () {
    final combined = combinePlatformAndStopLabel(
      'B',
      'Platz B',
      stationName: 'Wiesbaden Luisenplatz',
      isRail: false,
    );
    expect(combined, 'Steig B');
  });

  test('trims opaque suffix from stand label before deduping', () {
    final combined = combinePlatformAndStopLabel(
      'B',
      'Steig B NAUROD',
      stationName: 'Wiesbaden-Naurod Fondetter Straße',
      isRail: false,
    );
    expect(combined, 'Steig B');
  });

  test('suppresses opaque stop codes when a stand number exists', () {
    final combined = combinePlatformAndStopLabel(
      '1',
      'NWaldstraße',
      stationName: 'Wiesbaden-Biebrich Kahle Mühle P+R',
      isRail: false,
    );
    expect(combined, 'Steig 1');
  });

  test('suppresses opaque stop codes even without a platform', () {
    final combined = combinePlatformAndStopLabel(
      null,
      'VBhf SCHRGK',
      stationName: 'Wiesbaden Schiersteiner Straße',
      isRail: false,
    );
    expect(combined, isNull);
  });

  test('hides train number in parentheses but keeps platform', () {
    final formatted = formatRideDisplayLine(
      line: 'RE54 (4616)',
      platform: '2',
      arrivalPlatform: null,
      tripId: '4616',
      showTrainNumbers: false,
    );
    expect(formatted, 'RE54 (Gl. 2)');
  });

  test('hides parenthesized train number even when tripId is missing', () {
    final formatted = formatRideDisplayLine(
      line: 'IC (2055)',
      platform: '7',
      arrivalPlatform: null,
      tripId: null,
      showTrainNumbers: false,
    );
    expect(formatted, 'IC (Gl. 7)');
  });

  test('hides parenthesized numeric segment from middle of line', () {
    final formatted = formatRideDisplayLine(
      line: 'IC (2055) Express',
      platform: null,
      arrivalPlatform: null,
      tripId: null,
      showTrainNumbers: false,
    );
    expect(formatted, 'IC Express');
  });

  test('long press logic shows delete for started routes', () {
    final shouldShow = savedJourneyLongPressShowsDelete(
      isCompleted: false,
      isLegacy: false,
      hasStarted: true,
    );
    expect(shouldShow, isTrue);
  });

  test('saved route label is compact and keeps both stations', () {
    final label = compactSavedRouteLabel(
      'München Hauptbahnhof',
      'Frankfurt am Main Süd',
    );
    expect(label, 'München Hauptba… → Frankfurt am Ma…');
  });

  test('saved route notification id is stable per route key', () {
    const key = 'route-1';
    final first = savedRouteStatusNotificationIdForKey(key);
    final second = savedRouteStatusNotificationIdForKey(key);
    expect(first, second);
    expect(first, greaterThanOrEqualTo(0));
  });

  group('saved route notification health', () {
    Journey journeyWithRides(List<JourneyStep> rides) {
      final departure = rides.first.plannedDeparture!;
      final arrival = rides.last.plannedArrival!;
      return Journey(
        steps: rides,
        departure: departure,
        arrival: arrival,
        duration: arrival.difference(departure),
        transferCount: rides.length - 1,
        totalWaitTime: Duration.zero,
        rawSource: const {},
        source: 'test',
      );
    }

    JourneyStep ride({
      required int departureMinute,
      required int arrivalMinute,
      int departureDelay = 0,
      int arrivalDelay = 0,
      bool cancelled = false,
    }) {
      final base = DateTime.utc(2026, 9, 3, 10);
      return JourneyStep(
        type: 'ride',
        line: 'RE 1',
        instruction: 'Ride',
        duration: '10 min',
        departureTime: '10:${departureMinute.toString().padLeft(2, '0')}',
        arrivalTime: '10:${arrivalMinute.toString().padLeft(2, '0')}',
        plannedDeparture: base.add(Duration(minutes: departureMinute)),
        plannedArrival: base.add(Duration(minutes: arrivalMinute)),
        departureDelay: departureDelay,
        arrivalDelay: arrivalDelay,
        isCancelled: cancelled,
      );
    }

    test('routine changes within a delay only update silently', () {
      expect(
        savedRouteNotificationAction(
          previous: SavedRouteHealthState.delayed,
          current: SavedRouteHealthState.delayed,
          realtimeChanged: true,
        ),
        SavedRouteNotificationAction.silentUpdate,
      );
      expect(
        savedRouteNotificationAction(
          previous: SavedRouteHealthState.delayed,
          current: SavedRouteHealthState.delayed,
          realtimeChanged: false,
        ),
        SavedRouteNotificationAction.none,
      );
    });

    test('starting and recovering from a delay both alert', () {
      expect(
        savedRouteNotificationAction(
          previous: SavedRouteHealthState.normal,
          current: SavedRouteHealthState.delayed,
          realtimeChanged: true,
        ),
        SavedRouteNotificationAction.alert,
      );
      expect(
        savedRouteNotificationAction(
          previous: SavedRouteHealthState.delayed,
          current: SavedRouteHealthState.normal,
          realtimeChanged: true,
        ),
        SavedRouteNotificationAction.alert,
      );
    });

    test('first on-time observation establishes a quiet baseline', () {
      expect(
        savedRouteNotificationAction(
          previous: null,
          current: SavedRouteHealthState.normal,
          realtimeChanged: true,
        ),
        SavedRouteNotificationAction.none,
      );

      final delayed = journeyWithRides([
        ride(
          departureMinute: 0,
          arrivalMinute: 20,
          departureDelay: 4,
        ),
      ]);
      final health = savedRouteHealthForJourney(delayed);
      expect(health.state, SavedRouteHealthState.delayed);
      expect(health.maxDelayMinutes, 4);
    });

    test(
        'three-minute transfer is at risk and a missed transfer is unavailable',
        () {
      final tight = journeyWithRides([
        ride(departureMinute: 0, arrivalMinute: 20, arrivalDelay: 2),
        ride(departureMinute: 25, arrivalMinute: 40),
      ]);
      final missed = journeyWithRides([
        ride(departureMinute: 0, arrivalMinute: 20, arrivalDelay: 5),
        ride(departureMinute: 25, arrivalMinute: 40),
      ]);

      expect(
        savedRouteHealthForJourney(tight).state,
        SavedRouteHealthState.tightConnection,
      );
      expect(
        savedRouteHealthForJourney(tight).shortestTransferMinutes,
        3,
      );
      expect(
        savedRouteHealthForJourney(missed).state,
        SavedRouteHealthState.unavailable,
      );
    });

    test('cancelled route is unavailable', () {
      final cancelled = journeyWithRides([
        ride(departureMinute: 0, arrivalMinute: 20, cancelled: true),
      ]);
      expect(
        savedRouteHealthForJourney(cancelled).state,
        SavedRouteHealthState.unavailable,
      );
    });
  });

  test('alternative journey display departure prefers planned departure', () {
    final departure = alternativeJourneyDisplayDepartureLocal({
      'legs': [
        {
          'plannedDeparture': '2026-05-14T14:16:00Z',
          'departure': '2026-05-14T14:15:00Z',
          'line': {'name': '37'},
        },
      ],
    });

    expect(departure, DateTime.parse('2026-05-14T14:16:00Z').toLocal());
  });

  test('mergeAlternativeJourneys dedupes by display departure and arrival', () {
    final journeys = mergeAlternativeJourneys(const [], [
      {
        'legs': [
          {
            'plannedDeparture': '2026-05-14T14:16:00Z',
            'departure': '2026-05-14T14:15:00Z',
            'line': {'name': '37'},
          },
          {
            'plannedArrival': '2026-05-14T14:53:00Z',
            'arrival': '2026-05-14T14:52:00Z',
          },
        ],
      },
      {
        'legs': [
          {
            'plannedDeparture': '2026-05-14T14:16:00Z',
            'departure': '2026-05-14T14:16:00Z',
            'line': {'name': '37'},
          },
          {
            'plannedArrival': '2026-05-14T14:53:00Z',
            'arrival': '2026-05-14T14:53:00Z',
          },
        ],
      },
    ]);

    expect(journeys, hasLength(1));
  });

  test('refreshed candidates replace stale delays and retain platform detail',
      () {
    final plannedDeparture = DateTime.utc(2026, 8, 11, 10, 27);
    final plannedArrival = DateTime.utc(2026, 8, 11, 10, 39);

    Journey journey({
      required String departureTime,
      required int departureDelay,
      String? platform,
    }) {
      return Journey(
        steps: [
          JourneyStep(
            type: 'ride',
            line: 'X26',
            instruction: 'X26 → Anne-Frank-Straße',
            duration: '12 min',
            departureTime: departureTime,
            arrivalTime: '10:39',
            tripId: 'live-x26',
            startStationName: 'Wiesbaden Hauptbahnhof',
            destinationName: 'Anne-Frank-Straße',
            plannedDeparture: plannedDeparture,
            plannedArrival: plannedArrival,
            departureDelay: departureDelay,
            arrivalDelay: departureDelay,
            platform: platform,
          ),
        ],
        departure: plannedDeparture.add(Duration(minutes: departureDelay)),
        arrival: plannedArrival.add(Duration(minutes: departureDelay)),
        plannedDeparture: plannedDeparture,
        plannedArrival: plannedArrival,
        duration: const Duration(minutes: 12),
        transferCount: 0,
        totalWaitTime: Duration.zero,
        rawSource: const {},
        source: 'motis',
      );
    }

    final stale = journey(
      departureTime: '10:27',
      departureDelay: 0,
      platform: 'D',
    );
    final refreshed = journey(departureTime: '10:33', departureDelay: 6);

    final merged = mergeRefreshedJourneyCandidates([stale], [refreshed]);

    expect(merged, hasLength(1));
    expect(merged.single.steps.single.departureTime, '10:33');
    expect(merged.single.steps.single.departureDelay, 6);
    expect(merged.single.steps.single.platform, 'D');
  });

  test('formats short and long realtime delays clearly', () {
    expect(formatRealtimeDelay(7), '+7 min');
    expect(formatRealtimeDelay(124), '+2h 4min');
    expect(formatRealtimeDelay(-3), '-3 min');
  });

  test('highlights only the changed realtime suffix', () {
    expect(realtimeChangedSuffixStart('10:42', '10:49'), 4);
    expect(realtimeChangedSuffixStart('10:42', '10:50'), 3);
  });

  test('derives a platform change around a stale wait step', () {
    final steps = [
      JourneyStep(
        type: 'ride',
        line: 'RE14',
        instruction: 'RE14',
        duration: '20 min',
        departureTime: '08:30',
        arrivalTime: '08:56',
        destinationStationId: 'saalfeld',
        destinationName: 'Saalfeld (Saale)',
        arrivalPlatform: '6',
      ),
      JourneyStep(
        type: 'wait',
        line: 'Transfer',
        instruction: 'Wait at Saalfeld (Saale)',
        duration: '5 min',
        departureTime: '08:56',
        arrivalTime: '09:00',
      ),
      JourneyStep(
        type: 'ride',
        line: 'RE14',
        instruction: 'RE14',
        duration: '95 min',
        departureTime: '09:00',
        arrivalTime: '10:35',
        startStationId: 'saalfeld',
        startStationName: 'Saalfeld (Saale)',
        platform: '2',
      ),
    ];

    expect(
      transferPlatformChangeForStep(steps, 1),
      (fromPlatform: '6', toPlatform: '2'),
    );
  });

  testWidgets('renders current platforms instead of a stale wait instruction',
      (tester) async {
    final state = await _pumpRoutesTab(tester);
    final departure = DateTime(2030, 9, 3, 8, 30);
    final journey = Journey(
      steps: [
        JourneyStep(
          type: 'ride',
          line: 'RE14',
          instruction: 'RE14 → Saalfeld (Saale)',
          duration: '26 min',
          departureTime: '08:30',
          arrivalTime: '08:56',
          destinationStationId: 'saalfeld',
          destinationName: 'Saalfeld (Saale)',
          arrivalPlatform: '6',
        ),
        JourneyStep(
          type: 'wait',
          line: 'Transfer',
          instruction: 'Wait at Saalfeld (Saale)',
          duration: '5 min',
          departureTime: '08:56',
          arrivalTime: '09:00',
          waitDuration: const Duration(minutes: 5),
        ),
        JourneyStep(
          type: 'ride',
          line: 'RE14',
          instruction: 'RE14 → Bamberg',
          duration: '1h 35min',
          departureTime: '09:00',
          arrivalTime: '10:35',
          startStationId: 'saalfeld',
          startStationName: 'Saalfeld (Saale)',
          platform: '2',
        ),
      ],
      departure: departure,
      arrival: departure.add(const Duration(hours: 2, minutes: 5)),
      duration: const Duration(hours: 2, minutes: 5),
      transferCount: 1,
      totalWaitTime: const Duration(minutes: 5),
      rawSource: const {'legs': []},
      source: 'test',
    );
    state.debugOpenRouteTabs([
      _routeTab(index: 0, activeJourney: journey),
    ]);
    await tester.pump();

    expect(find.text('Switch from Pl. 6 to Pl. 2'), findsOneWidget);
    expect(find.text('Wait at Saalfeld (Saale)'), findsNothing);
  });

  group('pulling down on the fixed tab strip', () {
    testWidgets('a mouse pull refreshes the opened journey in place',
        (tester) async {
      final state = await _pumpRoutesTab(tester);
      state.debugOpenRouteTabs([_activeJourneyTab()]);
      await tester.pump();

      final controller = _routeViewScrollController(tester);
      controller.jumpTo(600);
      await tester.pump();
      expect(controller.offset, 600);

      final gesture = await _startHeaderPull(
        tester,
        kind: PointerDeviceKind.mouse,
      );
      await _pullBy(tester, gesture, 260);

      // The stock circular indicator follows the pull, exactly like the
      // in-list gesture does.
      expect(find.byType(RefreshProgressIndicator), findsOneWidget);

      await gesture.up();
      await _settleIndicator(tester);

      expect(state.debugActiveJourneyRefreshCount, 1);
      expect(controller.offset, 600,
          reason: 'refreshing must not move the journey');
    });

    testWidgets('a touch pull refreshes the opened journey in place',
        (tester) async {
      final state = await _pumpRoutesTab(tester);
      state.debugOpenRouteTabs([_activeJourneyTab()]);
      await tester.pump();

      final controller = _routeViewScrollController(tester);
      controller.jumpTo(600);
      await tester.pump();

      final gesture = await _startHeaderPull(
        tester,
        kind: PointerDeviceKind.touch,
      );
      await _pullBy(tester, gesture, 280);

      expect(find.byType(RefreshProgressIndicator), findsOneWidget);

      await gesture.up();
      await _settleIndicator(tester);

      expect(state.debugActiveJourneyRefreshCount, 1);
      expect(controller.offset, 600);
    });

    testWidgets('a short pull cancels without refreshing', (tester) async {
      final state = await _pumpRoutesTab(tester);
      state.debugOpenRouteTabs([_activeJourneyTab()]);
      await tester.pump();

      final controller = _routeViewScrollController(tester);
      controller.jumpTo(600);
      await tester.pump();

      final gesture = await _startHeaderPull(
        tester,
        kind: PointerDeviceKind.mouse,
      );
      await _pullBy(tester, gesture, 60);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(state.debugActiveJourneyRefreshCount, 0);
      expect(find.byType(RefreshProgressIndicator), findsNothing);
      expect(controller.offset, 600);
    });

    testWidgets('the pull refreshes the route candidates view too',
        (tester) async {
      // The results cards need the wider phone layout the route results view
      // is designed for.
      final state = await _pumpRoutesTab(tester, size: const Size(500, 844));
      state.debugOpenRouteTabs([_candidatesTab()]);
      await tester.pump();

      final controller = _routeViewScrollController(tester);
      controller.jumpTo(300);
      await tester.pump();
      expect(controller.offset, 300);

      final gesture = await _startHeaderPull(
        tester,
        kind: PointerDeviceKind.mouse,
      );
      await _pullBy(tester, gesture, 300);

      expect(find.byType(RefreshProgressIndicator), findsOneWidget);

      await gesture.up();
      await _settleIndicator(tester);

      expect(state.debugRouteResultsRefreshCount, 1);
      expect(controller.offset, 300);
    });

    testWidgets('dragging the journey itself scrolls instead of refreshing',
        (tester) async {
      final state = await _pumpRoutesTab(tester);
      state.debugOpenRouteTabs([_activeJourneyTab()]);
      await tester.pump();

      final controller = _routeViewScrollController(tester);
      controller.jumpTo(600);
      await tester.pump();

      await tester.drag(find.byType(RefreshIndicator), const Offset(0, 240));
      await tester.pumpAndSettle();

      expect(controller.offset, lessThan(600));
      expect(state.debugActiveJourneyRefreshCount, 0);
      expect(find.byType(RefreshProgressIndicator), findsNothing);
    });

    testWidgets('the strip still scrolls sideways', (tester) async {
      final state = await _pumpRoutesTab(tester);
      state.debugOpenRouteTabs(
        List.generate(6, (index) => _activeJourneyTab(index: index)),
        activeId: 'tab-0',
      );
      await tester.pump();

      final strip = _tabStripScrollable(tester);
      expect(strip.position.maxScrollExtent, greaterThan(0));

      await tester.drag(_tabStripFinder, const Offset(-160, 0));
      await tester.pumpAndSettle();

      expect(strip.position.pixels, greaterThan(0));
      expect(state.debugActiveJourneyRefreshCount, 0);
    });

    testWidgets('selecting a chip and closing a tab still work',
        (tester) async {
      final state = await _pumpRoutesTab(tester);
      state.debugOpenRouteTabs(
        List.generate(2, (index) => _activeJourneyTab(index: index)),
        activeId: 'tab-0',
      );
      await tester.pump();

      // Selecting another chip switches the opened route.
      await tester.tap(find.text('Destination 1').first);
      await tester.pumpAndSettle();
      expect(find.text('Destination 1'), findsWidgets);

      // Closing a tab removes its chip.
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();
      expect(find.text('Destination 0'), findsNothing);

      expect(state.debugActiveJourneyRefreshCount, 0);
    });

    testWidgets('the "+" button still opens the search view', (tester) async {
      final state = await _pumpRoutesTab(tester);
      state.debugOpenRouteTabs([_activeJourneyTab()]);
      await tester.pump();
      expect(find.byType(RefreshIndicator), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();

      expect(find.byType(RefreshIndicator), findsNothing);
      expect(state.debugActiveJourneyRefreshCount, 0);
    });
  });
}
