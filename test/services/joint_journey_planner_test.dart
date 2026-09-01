import 'package:flutter_test/flutter_test.dart';
import 'package:trans/models/joint_journey.dart';
import 'package:trans/models/journey.dart';
import 'package:trans/services/joint_journey_planner.dart';

JourneyStep _step({
  required String type,
  required DateTime start,
  required DateTime end,
  String line = '',
  String? tripId,
  String? startId,
  String? endId,
  double? startLat,
  double? startLng,
  double? endLat,
  double? endLng,
  Duration? walk,
  Duration? wait,
  List<dynamic>? path,
}) {
  String time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  return JourneyStep(
    type: type,
    line: line,
    instruction: type,
    duration: '${end.difference(start).inMinutes} min',
    departureTime: time(start),
    arrivalTime: time(end),
    dateTime: start,
    plannedDeparture: start,
    plannedArrival: end,
    tripId: tripId,
    startStationId: startId,
    destinationStationId: endId,
    startLat: startLat,
    startLng: startLng,
    endLat: endLat,
    endLng: endLng,
    walkDuration: walk,
    waitDuration: wait,
    path: path,
  );
}

Journey _journey({
  required DateTime departure,
  required DateTime arrival,
  required List<JourneyStep> steps,
  int transfers = 0,
}) =>
    Journey(
      steps: steps,
      departure: departure,
      arrival: arrival,
      duration: arrival.difference(departure),
      transferCount: transfers,
      totalWaitTime: Duration.zero,
      rawSource: const {},
      source: 'test',
    );

void main() {
  final day = DateTime(2026, 8, 13);

  test('counts an overlapping ride on the same trip', () {
    final mine = _journey(
      departure: day.add(const Duration(hours: 8)),
      arrival: day.add(const Duration(hours: 9)),
      steps: [
        _step(
          type: 'ride',
          start: day.add(const Duration(hours: 8)),
          end: day.add(const Duration(hours: 9)),
          line: 'RE 1',
          tripId: 'trip-1',
          startId: 'a',
          endId: 'z',
        ),
      ],
    );
    final friend = _journey(
      departure: day.add(const Duration(hours: 8, minutes: 20)),
      arrival: day.add(const Duration(hours: 9)),
      steps: [
        _step(
          type: 'ride',
          start: day.add(const Duration(hours: 8, minutes: 20)),
          end: day.add(const Duration(hours: 9)),
          line: 'RE 1',
          tripId: 'trip-1',
          startId: 'b',
          endId: 'z',
        ),
      ],
    );

    final result = JointJourneyPlanner.rank(
      myJourneys: [mine],
      friendJourneys: [friend],
    );

    expect(result, hasLength(1));
    expect(result.single.sharedRideDuration, const Duration(minutes: 40));
    expect(result.single.sharedDuration, const Duration(minutes: 40));
  });

  test('counts waiting together at the same stop', () {
    final start = day.add(const Duration(hours: 12));
    Journey waiting(DateTime from, DateTime to) => _journey(
          departure: from,
          arrival: to,
          steps: [
            _step(
              type: 'wait',
              start: from,
              end: to,
              startId: 'station-a',
              endId: 'station-a',
              wait: to.difference(from),
            ),
          ],
        );

    final result = JointJourneyPlanner.rank(
      myJourneys: [waiting(start, start.add(const Duration(minutes: 20)))],
      friendJourneys: [
        waiting(
          start.add(const Duration(minutes: 5)),
          start.add(const Duration(minutes: 15)),
        )
      ],
    );

    expect(result.single.sharedWaitDuration, const Duration(minutes: 10));
  });

  test('counts walking together along the same path', () {
    final start = day.add(const Duration(hours: 16));
    Journey walking(List<dynamic> path) => _journey(
          departure: start,
          arrival: start.add(const Duration(minutes: 12)),
          steps: [
            _step(
              type: 'walk',
              start: start,
              end: start.add(const Duration(minutes: 12)),
              startId: 'station-a',
              endId: 'destination',
              startLat: 50.0,
              startLng: 8.0,
              endLat: 50.001,
              endLng: 8.001,
              walk: const Duration(minutes: 12),
              path: path,
            ),
          ],
        );

    final result = JointJourneyPlanner.rank(
      myJourneys: [
        walking(const [
          [50.0, 8.0],
          [50.0005, 8.0005],
          [50.001, 8.001],
        ])
      ],
      friendJourneys: [
        walking(const [
          [50.0, 8.0],
          [50.0005, 8.0005],
          [50.001, 8.001],
        ])
      ],
    );

    expect(result.single.sharedWalkDuration, const Duration(minutes: 12));
  });

  test('rejects a route outside the maximum detour', () {
    Journey route(int minutes, {String trip = 'shared'}) => _journey(
          departure: day,
          arrival: day.add(Duration(minutes: minutes)),
          steps: [
            _step(
              type: 'ride',
              start: day,
              end: day.add(Duration(minutes: minutes)),
              tripId: trip,
              line: '1',
            ),
          ],
        );

    final result = JointJourneyPlanner.rank(
      myJourneys: [route(30, trip: 'solo'), route(60)],
      friendJourneys: [route(60)],
      preferences: const JointJourneyPreferences.fast(),
    );

    expect(result, isEmpty);
  });

  test('prefers substantial shared time for a small arrive-by sacrifice', () {
    final arrival = day.add(const Duration(hours: 9));
    final solo = _journey(
      departure: day.add(const Duration(hours: 8)),
      arrival: arrival,
      steps: [
        _step(
          type: 'ride',
          start: day.add(const Duration(hours: 8)),
          end: arrival,
          tripId: 'solo',
          line: '1',
        ),
      ],
    );
    final shared = _journey(
      departure: day.add(const Duration(hours: 7, minutes: 55)),
      arrival: arrival,
      transfers: 1,
      steps: [
        _step(
          type: 'ride',
          start: day.add(const Duration(hours: 8, minutes: 20)),
          end: arrival,
          tripId: 'shared-trip',
          line: 'RE 1',
        ),
      ],
    );
    final friend = _journey(
      departure: day.add(const Duration(hours: 8, minutes: 20)),
      arrival: arrival,
      steps: [
        _step(
          type: 'ride',
          start: day.add(const Duration(hours: 8, minutes: 20)),
          end: arrival,
          tripId: 'shared-trip',
          line: 'RE 1',
        ),
      ],
    );

    final result = JointJourneyPlanner.rank(
      myJourneys: [solo, shared],
      friendJourneys: [friend],
      isArrival: true,
    );

    expect(result.single.myJourney, same(shared));
    expect(result.single.myExtraMinutes, 5);
    expect(result.single.myExtraTransfers, 1);
    expect(result.single.sharedDuration, const Duration(minutes: 40));
  });

  group('looking further', () {
    Journey ride(String trip, DateTime start, DateTime end) => _journey(
          departure: start,
          arrival: end,
          steps: [
            _step(
              type: 'ride',
              start: start,
              end: end,
              tripId: trip,
              line: trip,
            ),
          ],
        );

    Journey best() => ride(
          'best',
          day.add(const Duration(hours: 8)),
          day.add(const Duration(hours: 8, minutes: 40)),
        );
    Journey longerTogether() => ride(
          'longer',
          day.add(const Duration(hours: 8)),
          day.add(const Duration(hours: 9)),
        );

    test('stays at the chosen setting when it already finds something', () {
      final outcome = JointJourneyPlanner.rankProgressively(
        myJourneys: [best()],
        friendJourneys: [best()],
        window: const JointSearchWindow(baseTogetherness: 0),
      );

      expect(outcome.options, hasLength(1));
      expect(outcome.window.isWidened, isFalse);
      expect(outcome.needsMoreDepartures, isFalse);
    });

    test('widens on its own when the chosen setting finds nothing', () {
      // Only a costly pairing exists, so Fast alone would show an empty list.
      final outcome = JointJourneyPlanner.rankProgressively(
        myJourneys: [
          ride('my-solo', day.add(const Duration(hours: 8)),
              day.add(const Duration(hours: 8, minutes: 40))),
          longerTogether(),
        ],
        friendJourneys: [
          ride('friend-solo', day.add(const Duration(hours: 8)),
              day.add(const Duration(hours: 8, minutes: 40))),
          longerTogether(),
        ],
        window: const JointSearchWindow(baseTogetherness: 0),
      );

      expect(outcome.options, isNotEmpty);
      expect(outcome.window.isWidened, isTrue);
      expect(outcome.needsMoreDepartures, isFalse);
    });

    test('a further look surfaces more time together', () {
      final myJourneys = [best(), longerTogether()];
      final friendJourneys = [best(), longerTogether()];
      const start = JointSearchWindow(baseTogetherness: 0);

      final first = JointJourneyPlanner.rankProgressively(
        myJourneys: myJourneys,
        friendJourneys: friendJourneys,
        window: start,
      );
      expect(first.options.first.sharedDuration, const Duration(minutes: 40));

      final second = JointJourneyPlanner.rankProgressively(
        myJourneys: myJourneys,
        friendJourneys: friendJourneys,
        window: first.window,
        previousOptions: first.options,
      );

      expect(second.window.togetherness,
          greaterThan(first.window.togetherness));
      expect(second.options.length, greaterThan(first.options.length));
      expect(
        second.options
            .map((option) => option.sharedDuration)
            .reduce((a, b) => a > b ? a : b),
        const Duration(minutes: 60),
      );
      expect(second.needsMoreDepartures, isFalse);
    });

    test('asks for more departures once the budget cannot help', () {
      final myJourneys = [best()];
      final friendJourneys = [best()];
      final first = JointJourneyPlanner.rankProgressively(
        myJourneys: myJourneys,
        friendJourneys: friendJourneys,
        window: const JointSearchWindow(baseTogetherness: 0),
      );

      final second = JointJourneyPlanner.rankProgressively(
        myJourneys: myJourneys,
        friendJourneys: friendJourneys,
        window: first.window,
        previousOptions: first.options,
      );

      expect(second.needsMoreDepartures, isTrue);
      expect(second.window.canWidenBudget, isFalse);
      // The option that was already shown is kept, not dropped.
      expect(second.options, hasLength(1));
    });

    test('reports immediately when the budget is already at together', () {
      final outcome = JointJourneyPlanner.rankProgressively(
        myJourneys: [best()],
        friendJourneys: [best()],
        window: const JointSearchWindow(baseTogetherness: 1),
        previousOptions: JointJourneyPlanner.rank(
          myJourneys: [best()],
          friendJourneys: [best()],
          preferences: const JointJourneyPreferences.together(),
        ),
      );

      expect(outcome.needsMoreDepartures, isTrue);
      expect(outcome.window.budgetSteps, 0);
    });
  });

  group('value against travelling alone', () {
    // Both would take the same 08:00 tram anyway; the later one is only worth
    // it if the extra time together beats the extra travel time.
    Journey ride(String trip, DateTime start, DateTime end) => _journey(
          departure: start,
          arrival: end,
          steps: [
            _step(
              type: 'ride',
              start: start,
              end: end,
              tripId: trip,
              line: trip,
            ),
          ],
        );

    Journey best() => ride(
          'best',
          day.add(const Duration(hours: 8)),
          day.add(const Duration(hours: 8, minutes: 40)),
        );
    Journey later() => ride(
          'later',
          day.add(const Duration(hours: 8)),
          day.add(const Duration(hours: 9)),
        );

    test('keeps the pairing that costs nothing', () {
      final result = JointJourneyPlanner.rank(
        myJourneys: [best(), later()],
        friendJourneys: [best(), later()],
      );

      final free = result.single;
      expect(free.isFree, isTrue);
      expect(free.detourMinutes, 0);
      expect(free.sharedDuration, const Duration(minutes: 40));
      expect(free.baselineSharedDuration, const Duration(minutes: 40));
      // Nothing is gained over simply travelling alone at the same time.
      expect(free.sharedGainMinutes, 0);
    });

    test('does not charge a detour for time the pair would share anyway', () {
      final result = JointJourneyPlanner.rank(
        myJourneys: [best(), later()],
        friendJourneys: [best(), later()],
        preferences: const JointJourneyPreferences.together(),
      );

      // 20 extra minutes together, bought with 20 extra travel minutes each.
      final stretched = result.first;
      expect(stretched.sharedDuration, const Duration(minutes: 60));
      expect(stretched.sharedGainMinutes, 20);
      expect(stretched.detourMinutes, 40);
      expect(result, hasLength(2));
    });

    test('a costly option only survives when the slider allows it', () {
      List<JointJourneyOption> rankWith(JointJourneyPreferences preferences) =>
          JointJourneyPlanner.rank(
            myJourneys: [best(), later()],
            friendJourneys: [best(), later()],
            preferences: preferences,
          );

      expect(
        rankWith(const JointJourneyPreferences.fast())
            .where((option) => option.detourMinutes > 0),
        isEmpty,
      );
      expect(
        rankWith(const JointJourneyPreferences.together())
            .where((option) => option.detourMinutes > 0),
        isNotEmpty,
      );
    });

    test('the slider decides between a cheap and a generous option', () {
      final mySolo = ride(
        'my-solo',
        day.add(const Duration(hours: 8)),
        day.add(const Duration(hours: 8, minutes: 40)),
      );
      final friendSolo = ride(
        'friend-solo',
        day.add(const Duration(hours: 8)),
        day.add(const Duration(hours: 8, minutes: 40)),
      );
      // +5 min each for 45 shared minutes.
      Journey cheap() => ride(
            'cheap',
            day.add(const Duration(hours: 8)),
            day.add(const Duration(hours: 8, minutes: 45)),
          );
      // +20 min each for 60 shared minutes.
      Journey generous() => ride(
            'generous',
            day.add(const Duration(hours: 8)),
            day.add(const Duration(hours: 9)),
          );

      final balanced = JointJourneyPlanner.rank(
        myJourneys: [mySolo, cheap(), generous()],
        friendJourneys: [friendSolo, cheap(), generous()],
      );
      expect(balanced.first.sharedDuration, const Duration(minutes: 45));

      final together = JointJourneyPlanner.rank(
        myJourneys: [mySolo, cheap(), generous()],
        friendJourneys: [friendSolo, cheap(), generous()],
        preferences: const JointJourneyPreferences.together(),
      );
      expect(together.first.sharedDuration, const Duration(minutes: 60));
    });

    test('prefers sharing the detour over one person carrying it', () {
      final mySolo = ride(
        'my-solo',
        day.add(const Duration(hours: 8)),
        day.add(const Duration(hours: 8, minutes: 40)),
      );
      // Both pay 10 minutes for 40 minutes together.
      Journey evenRide() => ride(
            'even',
            day.add(const Duration(hours: 8)),
            day.add(const Duration(hours: 8, minutes: 50)),
          );
      // The friend pays nothing and rides straight to the destination, while
      // the same 40 shared minutes cost me 20 extra minutes of walking.
      final friendLopsided = ride(
        'lopsided',
        day.add(const Duration(hours: 8)),
        day.add(const Duration(hours: 8, minutes: 40)),
      );
      final myLopsided = _journey(
        departure: day.add(const Duration(hours: 8)),
        arrival: day.add(const Duration(hours: 9)),
        steps: [
          _step(
            type: 'ride',
            start: day.add(const Duration(hours: 8)),
            end: day.add(const Duration(hours: 8, minutes: 40)),
            tripId: 'lopsided',
            line: 'lopsided',
          ),
          _step(
            type: 'walk',
            start: day.add(const Duration(hours: 8, minutes: 40)),
            end: day.add(const Duration(hours: 9)),
            startId: 'transfer-stop',
            endId: 'destination',
            walk: const Duration(minutes: 20),
          ),
        ],
      );

      final result = JointJourneyPlanner.rank(
        myJourneys: [mySolo, evenRide(), myLopsided],
        friendJourneys: [evenRide(), friendLopsided],
      );

      expect(result, hasLength(2));
      expect(result.first.myExtraMinutes, 10);
      expect(result.first.friendExtraMinutes, 10);
      expect(result.first.sharedDuration, const Duration(minutes: 50));
    });
  });
}
