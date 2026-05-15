import 'package:flutter_test/flutter_test.dart';
import 'package:trans/screens/tabs/routes_tab.dart';

void main() {
  test('formats ride line with numeric platform', () {
    final formatted = formatRideLineWithPlatform('RB21', '6');
    expect(formatted, 'RB21 (Gl. 6)');
  });

  test('does not duplicate platform suffix when already present', () {
    final formatted = formatRideLineWithPlatform('RB21 (Pl. 6)', '6');
    expect(formatted, 'RB21 (Pl. 6)');
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
    );
    expect(combined, '24 • Gleis 24-25');
  });

  test('does not duplicate stop label when it only repeats the platform', () {
    final combined = combinePlatformAndStopLabel(
      '7',
      'Bahnsteig Gleis 7',
      stationName: 'Berlin Hbf',
    );
    expect(combined, '7');
  });

  test('does not duplicate bus stand labels like Bussteig B', () {
    final combined = combinePlatformAndStopLabel(
      'B',
      'Bussteig B',
      stationName: 'Wiesbaden Hauptbahnhof',
    );
    expect(combined, 'Bussteig B');
  });

  test('prefers cleaned stop label for Platz B instead of B bullet B', () {
    final combined = combinePlatformAndStopLabel(
      'B',
      'Platz B',
      stationName: 'Wiesbaden Luisenplatz',
    );
    expect(combined, 'Platz B');
  });

  test('trims opaque suffix from stand label before deduping', () {
    final combined = combinePlatformAndStopLabel(
      'B',
      'Steig B NAUROD',
      stationName: 'Wiesbaden-Naurod Fondetter Straße',
    );
    expect(combined, 'Steig B');
  });

  test('suppresses opaque stop codes when a stand number exists', () {
    final combined = combinePlatformAndStopLabel(
      '1',
      'NWaldstraße',
      stationName: 'Wiesbaden-Biebrich Kahle Mühle P+R',
    );
    expect(combined, '1');
  });

  test('suppresses opaque stop codes even without a platform', () {
    final combined = combinePlatformAndStopLabel(
      null,
      'VBhf SCHRGK',
      stationName: 'Wiesbaden Schiersteiner Straße',
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
}
