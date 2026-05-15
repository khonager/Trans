import 'package:flutter_test/flutter_test.dart';
import 'package:trans/services/transport_api.dart';

void main() {
  group('TransportApi platform backfill matching', () {
    test('prefers exact trip id platform match', () {
      final platform = TransportApi.matchPlatformFromStopEventsForTesting(
        [
          {
            'displayName': 'RE1',
            'headsign': 'Brandenburg Hbf',
            'tripId': 'other-trip',
            'place': {'track': '7'},
            'departure': {'scheduledTime': '2026-05-15T12:24:00Z'},
          },
          {
            'displayName': 'RE1',
            'headsign': 'Brandenburg Hbf',
            'tripId': 'trip-123',
            'place': {'track': '14'},
            'departure': {'scheduledTime': '2026-05-15T12:24:00Z'},
          },
        ],
        leg: {
          'line': {'name': 'RE1', 'tripId': 'trip-123'},
          'direction': 'Brandenburg Hbf',
        },
        expectedTime: DateTime.parse('2026-05-15T12:24:00Z').toLocal(),
      );

      expect(platform, '14');
    });

    test('falls back to same line and headsign near expected time', () {
      final platform = TransportApi.matchPlatformFromStopEventsForTesting(
        [
          {
            'displayName': 'RE3',
            'headsign': 'Schwedt, Bahnhof',
            'tripId': 'vbb-trip',
            'place': {'track': '6'},
            'departure': {'scheduledTime': '2026-05-15T12:23:00Z'},
          },
          {
            'displayName': 'RE3',
            'headsign': 'Different Destination',
            'tripId': 'wrong-headsign',
            'place': {'track': '9'},
            'departure': {'scheduledTime': '2026-05-15T12:23:00Z'},
          },
        ],
        leg: {
          'line': {'name': 'RE3', 'tripId': 'delfi-trip'},
          'direction': 'Schwedt, Bahnhof',
        },
        expectedTime: DateTime.parse('2026-05-15T12:23:00Z').toLocal(),
      );

      expect(platform, '6');
    });

    test('ignores distant same-line events', () {
      final platform = TransportApi.matchPlatformFromStopEventsForTesting(
        [
          {
            'displayName': 'ICE 601',
            'headsign': 'München Hbf',
            'tripId': 'other-trip',
            'place': {'track': '8'},
            'departure': {'scheduledTime': '2026-05-15T13:58:00Z'},
          },
        ],
        leg: {
          'line': {'name': 'ICE 601', 'tripId': 'trip-601'},
          'direction': 'München Hbf',
        },
        expectedTime: DateTime.parse('2026-05-15T13:45:00Z').toLocal(),
      );

      expect(platform, isNull);
    });

    test('returns stop label and exact child stop id for bay-style stops', () {
      final details = TransportApi.matchStopEventDetailsForTesting(
        [
          {
            'displayName': 'M10',
            'headsign': 'U Turmstr.',
            'tripId': 'trip-m10',
            'place': {
              'stopId': 'de-VBB_de:11000:900003201::2',
              'parentId': 'de-VBB_de:11000:900003201',
              'name': 'S+U Berlin Hauptbahnhof',
              'description':
                  'Tramsteig Invalidenstr. ht. Friedrich-L.-U. Pos. 4',
            },
            'departure': {'scheduledTime': '2026-05-15T12:45:00Z'},
          },
        ],
        leg: {
          'line': {'name': 'M10', 'tripId': 'trip-m10'},
          'direction': 'U Turmstr.',
        },
        expectedTime: DateTime.parse('2026-05-15T12:45:00Z').toLocal(),
      );

      expect(details.platform, isNull);
      expect(
        details.stopLabel,
        'Tramsteig Invalidenstr. ht. Friedrich-L.-U. Pos. 4',
      );
      expect(details.stopId, 'de-VBB_de:11000:900003201::2');
      expect(details.parentId, 'de-VBB_de:11000:900003201');
    });
  });
}
