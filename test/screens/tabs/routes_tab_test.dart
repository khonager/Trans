import 'package:flutter_test/flutter_test.dart';
import 'package:trans/models/journey.dart';
import 'package:trans/screens/tabs/routes_tab.dart';

void main() {
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
}
