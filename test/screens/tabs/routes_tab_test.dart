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

  test('combines train platform with richer stop label detail', () {
    final combined = combinePlatformAndStopLabel(
      '24',
      'Gleis 24-25',
      stationName: 'München Hbf',
      isRail: true,
    );
    expect(combined, 'Gl. 24');
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
