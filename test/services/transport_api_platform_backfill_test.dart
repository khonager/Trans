import 'package:flutter_test/flutter_test.dart';
import 'package:trans/services/transport_api.dart';

void main() {
  group('TransportApi platform backfill matching', () {
    test('combines line names for portions of the same physical train', () {
      final events = [
        {
          'displayName': 'RB13 (81020)',
          'routeShortName': 'RB13',
          'headsign': 'Leipzig Hbf',
          'tripId': 'rb13-trip',
          'agencyName': 'Erfurter Bahn',
          'mode': 'REGIONAL_RAIL',
          'tripFrom': {'name': 'Hof Hbf'},
          'tripTo': {'name': 'Leipzig Hbf'},
          'place': {
            'scheduledArrival': '2026-08-29T10:56:00Z',
            'scheduledDeparture': '2026-08-29T11:01:00Z',
          },
        },
        {
          'displayName': 'RB22 (80854)',
          'routeShortName': 'RB22',
          'headsign': 'Leipzig Hbf',
          'tripId': 'rb22-trip',
          'agencyName': 'Erfurter Bahn',
          'mode': 'REGIONAL_RAIL',
          'tripFrom': {'name': 'Saalfeld (Saale)'},
          'tripTo': {'name': 'Leipzig Hbf'},
          'place': {
            'scheduledArrival': '2026-08-29T10:56:00Z',
            'scheduledDeparture': '2026-08-29T11:01:00Z',
          },
        },
      ];

      final displayName =
          TransportApi.coupledLineDisplayNameFromStopEventsForTesting(
        events,
        leg: {
          'line': {'name': 'RB13 (81020)', 'tripId': 'rb13-trip'},
          'direction': 'Leipzig Hbf',
        },
        expectedTime: DateTime.parse('2026-08-29T11:01:00Z').toLocal(),
      );

      expect(displayName, 'RB22 (80854) / RB13 (81020)');
    });

    test('does not combine trains going in different directions', () {
      final displayName =
          TransportApi.coupledLineDisplayNameFromStopEventsForTesting(
        [
          {
            'displayName': 'RB13 (81017)',
            'routeShortName': 'RB13',
            'headsign': 'Hof Hbf',
            'tripId': 'rb13-trip',
            'agencyName': 'Erfurter Bahn',
            'mode': 'REGIONAL_RAIL',
            'tripTo': {'name': 'Hof Hbf'},
            'place': {
              'scheduledArrival': '2026-08-29T10:58:00Z',
              'scheduledDeparture': '2026-08-29T11:02:00Z',
            },
          },
          {
            'displayName': 'RB22 (80849)',
            'routeShortName': 'RB22',
            'headsign': 'Saalfeld (Saale)',
            'tripId': 'rb22-trip',
            'agencyName': 'Erfurter Bahn',
            'mode': 'REGIONAL_RAIL',
            'tripTo': {'name': 'Saalfeld (Saale)'},
            'place': {
              'scheduledArrival': '2026-08-29T10:58:00Z',
              'scheduledDeparture': '2026-08-29T11:02:00Z',
            },
          },
        ],
        leg: {
          'line': {'name': 'RB13 (81017)', 'tripId': 'rb13-trip'},
          'direction': 'Hof Hbf',
        },
        expectedTime: DateTime.parse('2026-08-29T11:02:00Z').toLocal(),
      );

      expect(displayName, isNull);
    });

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

    test('prefers related platform event over exact trip without platform', () {
      final details = TransportApi.matchStopEventDetailsForTesting(
        [
          {
            'displayName': 'RE1 (73734)',
            'headsign': 'Brandenburg Hbf',
            'tripId': 'delfi-trip',
            'place': {
              'stopId': 'de-DELFI_de:11000:900003201_G',
              'name': 'S+U Berlin Hauptbahnhof',
            },
            'departure': {'scheduledTime': '2026-05-15T12:24:00Z'},
          },
          {
            'displayName': 'RE1',
            'headsign': 'Brandenburg Hbf',
            'tripId': 'vbb-trip',
            'place': {
              'stopId': 'de-VBB_de:11000:900003201:2:53',
              'name': 'S+U Berlin Hauptbahnhof',
              'track': '14',
              'description': 'Bahnsteig Gleis 14',
            },
            'departure': {'scheduledTime': '2026-05-15T12:24:00Z'},
          },
        ],
        leg: {
          'line': {'name': 'RE1 (73734)', 'tripId': 'delfi-trip'},
          'direction': 'Brandenburg Hbf',
        },
        expectedTime: DateTime.parse('2026-05-15T12:24:00Z').toLocal(),
      );

      expect(details.platform, '14');
      expect(details.stopId, 'de-VBB_de:11000:900003201:2:53');
    });

    test('matches rail platform from exact trip itinerary stop', () {
      final details = TransportApi.matchStopDetailsFromTripItineraryForTesting(
        {
          'legs': [
            {
              'from': {
                'stopId': 'de-DELFI_de:16052:8010125',
                'name': 'Gera Hbf',
                'track': '6b',
              },
              'to': {
                'stopId': 'de-DELFI_de:16051:8010101',
                'name': 'Erfurt Hbf',
                'track': '8',
              },
              'scheduledStartTime': '2026-05-15T17:05:00Z',
              'startTime': '2026-05-15T17:05:00Z',
              'scheduledEndTime': '2026-05-15T18:07:00Z',
              'endTime': '2026-05-15T18:07:00Z',
            },
          ],
        },
        targetPlace: {
          'id': 'de-DELFI_de:16052:8010125',
          'name': 'Gera Hbf',
        },
        expectedTime: DateTime.parse('2026-05-15T17:05:00Z').toLocal(),
      );

      expect(details?.platform, '6b');
      expect(details?.stopId, 'de-DELFI_de:16052:8010125');
    });

    test('prefers timed trip stop when a station appears more than once', () {
      final details = TransportApi.matchStopDetailsFromTripItineraryForTesting(
        {
          'legs': [
            {
              'from': {
                'stopId': 'loop-station',
                'name': 'Loop Hbf',
                'track': '1',
              },
              'to': {
                'stopId': 'loop-station',
                'name': 'Loop Hbf',
                'track': '7',
              },
              'scheduledStartTime': '2026-05-15T08:00:00Z',
              'startTime': '2026-05-15T08:00:00Z',
              'scheduledEndTime': '2026-05-15T09:00:00Z',
              'endTime': '2026-05-15T09:00:00Z',
            },
          ],
        },
        targetPlace: {
          'id': 'loop-station',
          'name': 'Loop Hbf',
        },
        expectedTime: DateTime.parse('2026-05-15T09:00:00Z').toLocal(),
      );

      expect(details?.platform, '7');
    });

    test('matches bahn board platform by rail line and time', () {
      final platform = TransportApi.matchPlatformFromBahnBoardEventsForTesting(
        [
          {
            'zeit': '2026-05-15T18:01:00',
            'gleis': '6b',
            'verkehrmittel': {'mittelText': 'RE12'},
          },
          {
            'zeit': '2026-05-15T18:04:00',
            'gleis': '3b',
            'verkehrmittel': {'mittelText': 'IC 2150'},
          },
        ],
        leg: {
          'mode': 'LONG_DISTANCE',
          'line': {'name': 'IC 2150'},
        },
        expectedTime: DateTime.parse('2026-05-15T18:04:00').toLocal(),
      );

      expect(platform, '3b');
    });

    test('requests and matches underground S-Bahn platforms', () {
      expect(
        TransportApi.bahnBoardTransportModesForTesting,
        contains('SBAHN'),
      );

      final platform = TransportApi.matchPlatformFromBahnBoardEventsForTesting(
        [
          {
            'zeit': '2026-09-03T14:52:00',
            'gleis': '103',
            'richtung': 'Niedernhausen Bahnhof',
            'verkehrmittel': {'mittelText': 'S2'},
          },
        ],
        leg: {
          'mode': 'SUBURBAN',
          'line': {'name': 'S2'},
          'direction': 'Niedernhausen Bahnhof',
        },
        expectedTime: DateTime.parse('2026-09-03T14:52:00').toLocal(),
      );

      expect(platform, '103');
    });

    test('matches bahn board line when Transitous only has train number', () {
      final platform = TransportApi.matchPlatformFromBahnBoardEventsForTesting(
        [
          {
            'zeit': '2026-05-15T22:49:00',
            'gleis': '2',
            'verkehrmittel': {'mittelText': 'ICE 79'},
          },
        ],
        leg: {
          'mode': 'HIGHSPEED_RAIL',
          'line': {'name': '79'},
        },
        expectedTime: DateTime.parse('2026-05-15T22:49:00').toLocal(),
      );

      expect(platform, '2');
    });

    test('ignores bahn board platforms outside the matching time window', () {
      final platform = TransportApi.matchPlatformFromBahnBoardEventsForTesting(
        [
          {
            'zeit': '2026-05-15T18:25:00',
            'gleis': '9',
            'verkehrmittel': {'mittelText': 'IC 2150'},
          },
        ],
        leg: {
          'mode': 'LONG_DISTANCE',
          'line': {'name': 'IC 2150'},
        },
        expectedTime: DateTime.parse('2026-05-15T18:04:00').toLocal(),
      );

      expect(platform, isNull);
    });

    test('platform writeback replaces blank existing values', () {
      final place = <String, dynamic>{
        'platform': null,
        'scheduledPlatform': '',
        'stopLabel': '  ',
        'exactStopId': 'existing-child',
      };

      TransportApi.setIfBlankMapValueForTesting(place, 'platform', '2');
      TransportApi.setIfBlankMapValueForTesting(
        place,
        'scheduledPlatform',
        '2',
      );
      TransportApi.setIfBlankMapValueForTesting(
        place,
        'stopLabel',
        'Gleis 2',
      );
      TransportApi.setIfBlankMapValueForTesting(
        place,
        'exactStopId',
        'new-child',
      );

      expect(place['platform'], '2');
      expect(place['scheduledPlatform'], '2');
      expect(place['stopLabel'], 'Gleis 2');
      expect(place['exactStopId'], 'existing-child');
    });

    test('flags a track that only names a combined platform area', () {
      expect(
        TransportApi.platformLooksLikeTrackAreaForTesting({
          'platform': '11',
          'description': 'Gleis1/11',
        }),
        isTrue,
      );
    });

    test('keeps a track that names a single platform', () {
      expect(
        TransportApi.platformLooksLikeTrackAreaForTesting({
          'platform': '11',
          'description': 'Gleis 11',
        }),
        isFalse,
      );
      expect(
        TransportApi.platformLooksLikeTrackAreaForTesting({
          'platform': '5b',
          'description': 'Gleis1/11',
        }),
        isFalse,
      );
    });

    test('prefers the realtime track of a bahn board entry', () {
      final platform = TransportApi.matchPlatformFromBahnBoardEventsForTesting(
        [
          {
            'zeit': '2026-08-22T10:27:00',
            'gleis': '5',
            'ezGleis': '5b',
            'richtung': 'Idar-Oberstein',
            'verkehrmittel': {'mittelText': 'RB33'},
          },
        ],
        leg: {
          'mode': 'REGIONAL_RAIL',
          'line': {'name': 'RB33'},
          'direction': 'Idar-Oberstein, Bahnhof',
        },
        expectedTime: DateTime.parse('2026-08-22T10:27:00').toLocal(),
      );

      expect(platform, '5b');
    });

    test('strict matching skips the same line in the other direction', () {
      final entries = [
        {
          'zeit': '2026-08-22T10:25:00',
          'gleis': '2',
          'richtung': 'Mainz Hauptbahnhof',
          'verkehrmittel': {'mittelText': 'RB33'},
        },
        {
          'zeit': '2026-08-22T10:27:00',
          'gleis': '5b',
          'richtung': 'Idar-Oberstein',
          'verkehrmittel': {'mittelText': 'RB33'},
        },
      ];
      final leg = {
        'mode': 'REGIONAL_RAIL',
        'line': {'name': 'RB33'},
        'direction': 'Idar-Oberstein, Bahnhof',
      };

      expect(
        TransportApi.matchPlatformFromBahnBoardEventsForTesting(
          entries,
          leg: leg,
          expectedTime: DateTime.parse('2026-08-22T10:27:00').toLocal(),
          strict: true,
          matchDirection: true,
        ),
        '5b',
      );
      expect(
        TransportApi.matchPlatformFromBahnBoardEventsForTesting(
          entries,
          leg: leg,
          expectedTime: DateTime.parse('2026-08-22T10:40:00').toLocal(),
          strict: true,
          matchDirection: true,
        ),
        isNull,
      );
    });
  });
}
