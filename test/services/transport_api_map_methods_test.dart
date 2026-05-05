import 'package:flutter_test/flutter_test.dart';
import 'package:trans/models/station.dart';
import 'package:trans/services/transport_api.dart';

void main() {
  final testFrom = Station(
    id: 'de:test:from',
    name: 'From',
    type: 'stop',
    latitude: 50.0,
    longitude: 8.0,
  );
  final testTo = Station(
    id: 'de:test:to',
    name: 'To',
    type: 'stop',
    latitude: 50.1,
    longitude: 8.1,
  );

  void configureDefaultAdvanced({required bool enabled}) {
    TransportApi.configureAdvancedSearchSettings(
      enabledForDevice: enabled,
      minTransferTimeMinutes:
          TransportApi.defaultAdvancedMinTransferTimeMinutes,
      additionalTransferTimeMinutes:
          TransportApi.defaultAdvancedAdditionalTransferTimeMinutes,
      transferTimeFactor: TransportApi.defaultAdvancedTransferTimeFactor,
      preTransitWalkEnabled: true,
      preTransitBikeEnabled: false,
      postTransitWalkEnabled: true,
      postTransitBikeEnabled: false,
      cyclingSpeedKmh: TransportApi.defaultAdvancedCyclingSpeedKmh,
      pedestrianSpeedKmh: TransportApi.defaultAdvancedPedestrianSpeedKmh,
      maxWalkingTimeMinutes: TransportApi.defaultAdvancedMaxWalkingTimeMinutes,
    );
    TransportApi.setBikeToggleEnabledForDevice(false);
  }

  setUp(() => configureDefaultAdvanced(enabled: false));

  // ---------------------------------------------------------------------------
  // buildLiveMapTripsUri – query-parameter serialisation
  // ---------------------------------------------------------------------------
  group('TransportApi.buildLiveMapTripsUri', () {
    test('encodes startTime and endTime as UTC ISO-8601 strings', () {
      // Use a fixed local time that is not already UTC so we can confirm the
      // conversion actually fires (UTC+2 example: 10:00 local → 08:00Z).
      final local = DateTime(2024, 6, 15, 10, 0, 0);
      final uri = TransportApi.buildLiveMapTripsUri(
        min: '0.0,0.0',
        max: '1.0,1.0',
        startTime: local,
        endTime: local.add(const Duration(hours: 1)),
        zoom: 12.0,
      );
      final params = uri.queryParameters;

      expect(params['startTime'], endsWith('Z'),
          reason: 'startTime must end with Z (UTC)');
      expect(params['endTime'], endsWith('Z'),
          reason: 'endTime must end with Z (UTC)');
      expect(params['startTime'], local.toUtc().toIso8601String());
      expect(
        params['endTime'],
        local.add(const Duration(hours: 1)).toUtc().toIso8601String(),
      );
    });

    test('already-UTC DateTime is not double-converted', () {
      final utc = DateTime.utc(2024, 1, 1, 8, 30);
      final uri = TransportApi.buildLiveMapTripsUri(
        min: '0.0,0.0',
        max: '1.0,1.0',
        startTime: utc,
        endTime: utc.add(const Duration(hours: 1)),
        zoom: 10.0,
      );
      expect(uri.queryParameters['startTime'], '2024-01-01T08:30:00.000Z');
    });

    test('encodes zoom with exactly two decimal places', () {
      final uri = TransportApi.buildLiveMapTripsUri(
        min: '0.0,0.0',
        max: '1.0,1.0',
        startTime: DateTime.utc(2024, 1, 1),
        endTime: DateTime.utc(2024, 1, 1, 1),
        zoom: 14.5,
      );
      expect(uri.queryParameters['zoom'], '14.50');
    });

    test('encodes whole-number zoom with two decimal places', () {
      final uri = TransportApi.buildLiveMapTripsUri(
        min: '0.0,0.0',
        max: '1.0,1.0',
        startTime: DateTime.utc(2024, 1, 1),
        endTime: DateTime.utc(2024, 1, 1, 1),
        zoom: 12.0,
      );
      expect(uri.queryParameters['zoom'], '12.00');
    });

    test('rounds zoom to two decimal places', () {
      final uri = TransportApi.buildLiveMapTripsUri(
        min: '0.0,0.0',
        max: '1.0,1.0',
        startTime: DateTime.utc(2024, 1, 1),
        endTime: DateTime.utc(2024, 1, 1, 1),
        zoom: 15.6789,
      );
      expect(uri.queryParameters['zoom'], '15.68');
    });

    test('truncates microseconds from map request times', () {
      final uri = TransportApi.buildLiveMapTripsUri(
        min: '0.0,0.0',
        max: '1.0,1.0',
        startTime: DateTime.utc(2026, 5, 1, 15, 7, 40, 568, 520),
        endTime: DateTime.utc(2026, 5, 1, 16, 27, 40, 723, 466),
        zoom: 15.0,
      );
      final params = uri.queryParameters;

      expect(params['startTime'], '2026-05-01T15:07:40.568Z');
      expect(params['endTime'], '2026-05-01T16:27:40.723Z');
    });

    test('passes min and max verbatim', () {
      final uri = TransportApi.buildLiveMapTripsUri(
        min: '48.0,11.0',
        max: '49.0,12.0',
        startTime: DateTime.utc(2024, 1, 1),
        endTime: DateTime.utc(2024, 1, 1, 1),
        zoom: 10.0,
      );
      expect(uri.queryParameters['min'], '48.0,11.0');
      expect(uri.queryParameters['max'], '49.0,12.0');
    });

    test('targets the correct MOTIS endpoint path', () {
      final uri = TransportApi.buildLiveMapTripsUri(
        min: '0.0,0.0',
        max: '1.0,1.0',
        startTime: DateTime.utc(2024, 1, 1),
        endTime: DateTime.utc(2024, 1, 1, 1),
        zoom: 10.0,
      );
      expect(uri.path, '/api/v5/map/trips');
    });
  });

  // ---------------------------------------------------------------------------
  // buildTripItineraryUri – boolean query-parameter serialisation
  // ---------------------------------------------------------------------------
  group('TransportApi.buildTripItineraryUri', () {
    test('serialises true/false booleans as lowercase strings', () {
      final uri = TransportApi.buildTripItineraryUri(
        'de:trip:123',
        withScheduledSkippedStops: true,
        joinInterlinedLegs: false,
      );
      final params = uri.queryParameters;
      expect(params['withScheduledSkippedStops'], 'true');
      expect(params['joinInterlinedLegs'], 'false');
    });

    test('serialises false/true booleans as lowercase strings', () {
      final uri = TransportApi.buildTripItineraryUri(
        'de:trip:456',
        withScheduledSkippedStops: false,
        joinInterlinedLegs: true,
      );
      final params = uri.queryParameters;
      expect(params['withScheduledSkippedStops'], 'false');
      expect(params['joinInterlinedLegs'], 'true');
    });

    test('defaults both booleans to true', () {
      final uri = TransportApi.buildTripItineraryUri('de:trip:456');
      final params = uri.queryParameters;
      expect(params['withScheduledSkippedStops'], 'true');
      expect(params['joinInterlinedLegs'], 'true');
    });

    test('includes tripId in query parameters', () {
      const tripId = 'de:hvv:trip:abcdef';
      final uri = TransportApi.buildTripItineraryUri(tripId);
      expect(uri.queryParameters['tripId'], tripId);
    });

    test('targets the correct MOTIS endpoint path', () {
      final uri = TransportApi.buildTripItineraryUri('x');
      expect(uri.path, '/api/v5/trip');
    });
  });

  group('TransportApi.buildMotisPlanUri', () {
    test('targets the correct MOTIS plan endpoint path', () {
      final uri = TransportApi.buildMotisPlanUri({
        'fromPlace': '1,2',
        'toPlace': '3,4',
      });
      expect(uri.path, '/api/v5/plan');
    });

    test('supports pre/post transit walk time override parameters', () {
      final uri = TransportApi.buildMotisPlanUri({
        'fromPlace': '1,2',
        'toPlace': '3,4',
        'maxPreTransitTime': '3600',
        'maxPostTransitTime': '3600',
      });
      final params = uri.queryParameters;
      expect(params['maxPreTransitTime'], '3600');
      expect(params['maxPostTransitTime'], '3600');
    });
  });

  group('TransportApi MOTIS advanced search parameters', () {
    test('advanced defaults build the same query as disabled advanced search',
        () {
      final when = DateTime.utc(2026, 5, 4, 10, 30);

      configureDefaultAdvanced(enabled: false);
      final normal = TransportApi.buildMotisJourneySearchParamsForTesting(
        testFrom,
        testTo,
        when: when,
        results: 7,
      );

      configureDefaultAdvanced(enabled: true);
      final advancedDefault =
          TransportApi.buildMotisJourneySearchParamsForTesting(
        testFrom,
        testTo,
        when: when,
        results: 7,
      );

      expect(advancedDefault, normal);
      expect(advancedDefault.containsKey('minTransferTime'), isFalse);
      expect(advancedDefault.containsKey('additionalTransferTime'), isFalse);
      expect(advancedDefault.containsKey('transferTimeFactor'), isFalse);
      expect(advancedDefault.containsKey('preTransitModes'), isFalse);
      expect(advancedDefault.containsKey('postTransitModes'), isFalse);
      expect(advancedDefault['maxPreTransitTime'], '3600');
      expect(advancedDefault['maxPostTransitTime'], '3600');
    });

    test('serialises transfer settings in Transitous minutes, not seconds', () {
      TransportApi.configureAdvancedSearchSettings(
        enabledForDevice: true,
        minTransferTimeMinutes: 4,
        additionalTransferTimeMinutes: 2,
        transferTimeFactor: 1.3,
        preTransitWalkEnabled: true,
        preTransitBikeEnabled: false,
        postTransitWalkEnabled: true,
        postTransitBikeEnabled: false,
        cyclingSpeedKmh: TransportApi.defaultAdvancedCyclingSpeedKmh,
        pedestrianSpeedKmh: TransportApi.defaultAdvancedPedestrianSpeedKmh,
        maxWalkingTimeMinutes:
            TransportApi.defaultAdvancedMaxWalkingTimeMinutes,
      );

      final params = TransportApi.buildMotisJourneySearchParamsForTesting(
        testFrom,
        testTo,
      );

      expect(params['minTransferTime'], '4');
      expect(params['additionalTransferTime'], '2');
      expect(params['transferTimeFactor'], '1.30');
    });

    test('serialises changed first and last mile walking windows in seconds',
        () {
      TransportApi.configureAdvancedSearchSettings(
        enabledForDevice: true,
        minTransferTimeMinutes:
            TransportApi.defaultAdvancedMinTransferTimeMinutes,
        additionalTransferTimeMinutes:
            TransportApi.defaultAdvancedAdditionalTransferTimeMinutes,
        transferTimeFactor: TransportApi.defaultAdvancedTransferTimeFactor,
        preTransitWalkEnabled: true,
        preTransitBikeEnabled: false,
        postTransitWalkEnabled: true,
        postTransitBikeEnabled: false,
        cyclingSpeedKmh: TransportApi.defaultAdvancedCyclingSpeedKmh,
        pedestrianSpeedKmh: TransportApi.defaultAdvancedPedestrianSpeedKmh,
        maxWalkingTimeMinutes: 15,
      );

      final params = TransportApi.buildMotisJourneySearchParamsForTesting(
        testFrom,
        testTo,
      );

      expect(params['maxPreTransitTime'], '900');
      expect(params['maxPostTransitTime'], '900');
    });

    test('uses Transitous BIKE mode token when bike access is active', () {
      TransportApi.configureAdvancedSearchSettings(
        enabledForDevice: true,
        minTransferTimeMinutes:
            TransportApi.defaultAdvancedMinTransferTimeMinutes,
        additionalTransferTimeMinutes:
            TransportApi.defaultAdvancedAdditionalTransferTimeMinutes,
        transferTimeFactor: TransportApi.defaultAdvancedTransferTimeFactor,
        preTransitWalkEnabled: true,
        preTransitBikeEnabled: true,
        postTransitWalkEnabled: true,
        postTransitBikeEnabled: true,
        cyclingSpeedKmh: 18,
        pedestrianSpeedKmh: TransportApi.defaultAdvancedPedestrianSpeedKmh,
        maxWalkingTimeMinutes:
            TransportApi.defaultAdvancedMaxWalkingTimeMinutes,
      );
      TransportApi.setBikeToggleEnabledForDevice(true);

      final params = TransportApi.buildMotisJourneySearchParamsForTesting(
        testFrom,
        testTo,
      );

      expect(params['preTransitModes'], 'WALK,BIKE');
      expect(params['postTransitModes'], 'WALK,BIKE');
      expect(params['preTransitModes'], isNot(contains('BICYCLE')));
      expect(params['cyclingSpeed'], '5.00');
    });
  });

  // ---------------------------------------------------------------------------
  // decodeJsonMap – JSON shape handling
  // ---------------------------------------------------------------------------
  group('TransportApi.decodeJsonMap', () {
    test('returns a Map when JSON is a JSON object', () {
      final result = TransportApi.decodeJsonMap('{"key": "value"}');
      expect(result, isNotNull);
      expect(result, isA<Map<String, dynamic>>());
      expect(result!['key'], 'value');
    });

    test('returns an empty map for an empty JSON object', () {
      final result = TransportApi.decodeJsonMap('{}');
      expect(result, isNotNull);
      expect(result, isEmpty);
    });

    test('returns null when JSON is an array', () {
      expect(TransportApi.decodeJsonMap('[1, 2, 3]'), isNull);
    });

    test('returns null when JSON is a string', () {
      expect(TransportApi.decodeJsonMap('"hello"'), isNull);
    });

    test('returns null when JSON is a number', () {
      expect(TransportApi.decodeJsonMap('42'), isNull);
    });

    test('returns null when JSON is a boolean', () {
      expect(TransportApi.decodeJsonMap('true'), isNull);
    });

    test('returns null when JSON is null', () {
      expect(TransportApi.decodeJsonMap('null'), isNull);
    });
  });

  group('TransportApi.decodeMotisPlanJourneys', () {
    test('returns empty list for valid plan response with no itineraries', () {
      final result = TransportApi.decodeMotisPlanJourneys({
        'requestParameters': {},
        'itineraries': [],
        'previousPageCursor': 'EARLIER|1',
        'nextPageCursor': 'LATER|1',
      });
      expect(result, isEmpty);
    });

    test(
        'keeps valid itineraries when response also contains malformed entries',
        () {
      final result = TransportApi.decodeMotisPlanJourneys({
        'itineraries': [
          {'legs': 'not-a-list'},
          {
            'startTime': '2026-04-21T08:00:00Z',
            'endTime': '2026-04-21T09:00:00Z',
            'legs': [
              {
                'mode': 'WALK',
                'from': {'name': 'A', 'lat': 1.0, 'lon': 2.0},
                'to': {'name': 'B', 'lat': 1.1, 'lon': 2.1},
                'startTime': '2026-04-21T08:00:00Z',
                'endTime': '2026-04-21T08:05:00Z',
              }
            ],
          },
          'bad-itinerary',
        ],
      });

      expect(result.length, 1);
      expect(result.every((journey) => journey['source'] == 'motis'), isTrue);
    });
  });

  group('TransportApi direct journey fallback helpers', () {
    test('builds direct WALK and BIKE fallback parameters', () {
      final from = Station(
        id: 'gps',
        name: 'From',
        type: 'location',
        latitude: 40.007733,
        longitude: 4.1537476,
      );
      final to = Station(
        id: 'gps',
        name: 'To',
        type: 'location',
        latitude: 40.0220224,
        longitude: 4.1787784,
      );

      final params = TransportApi.buildMotisDirectJourneySearchParamsForTesting(
        from,
        to,
        when: DateTime.utc(2026, 5, 5, 6, 12, 17),
      );

      expect(params['fromPlace'], '40.007733,4.1537476');
      expect(params['toPlace'], '40.0220224,4.1787784');
      expect(params['directModes'], 'WALK,BIKE');
      expect(params['maxDirectTime'], '7200');
      expect(params, isNot(contains('transitModes')));
      expect(params, isNot(contains('preTransitModes')));
      expect(params, isNot(contains('postTransitModes')));
      expect(params, isNot(contains('maxPreTransitTime')));
      expect(params, isNot(contains('maxPostTransitTime')));
    });

    test('decodes direct itineraries from the MOTIS direct array', () {
      final result = TransportApi.decodeMotisDirectPlanJourneys({
        'itineraries': [],
        'direct': [
          {
            'duration': 600,
            'startTime': '2026-05-05T06:12:00Z',
            'endTime': '2026-05-05T06:22:00Z',
            'transfers': 0,
            'legs': [
              {
                'mode': 'BIKE',
                'from': {'name': 'START', 'lat': 40.0, 'lon': 4.0},
                'to': {'name': 'END', 'lat': 40.1, 'lon': 4.1},
                'startTime': '2026-05-05T06:12:00Z',
                'endTime': '2026-05-05T06:22:00Z',
                'scheduledStartTime': '2026-05-05T06:12:00Z',
                'scheduledEndTime': '2026-05-05T06:22:00Z',
                'distance': 2500,
              },
            ],
          },
        ],
      });

      expect(result.length, 1);
      expect(result.first['source'], 'motis');
      expect(result.first['direct'], isTrue);
      final legs = result.first['legs'] as List<dynamic>;
      expect(legs.length, 1);
      expect((legs.first as Map<String, dynamic>)['walking'], isTrue);
      expect(legs.first['distance'], 2500);
    });
  });
}
