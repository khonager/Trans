import 'package:flutter_test/flutter_test.dart';
import 'package:trans/services/transport_api.dart';

void main() {
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
}
