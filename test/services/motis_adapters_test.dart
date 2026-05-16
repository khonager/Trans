import 'package:flutter_test/flutter_test.dart';
import 'package:trans/services/motis_adapters.dart';

void main() {
  group('motis adapters platform mapping', () {
    test('uses scheduledTrack as fallback platform when track is missing', () {
      final leg = legFromMotisLeg({
        'mode': 'REGIONAL_RAIL',
        'displayName': 'RE 1',
        'from': {
          'stopId': 'from-stop',
          'name': 'From',
          'vertexType': 'TRANSIT',
          'lat': 50.0,
          'lon': 8.0,
          'scheduledTrack': '7',
        },
        'to': {
          'stopId': 'to-stop',
          'name': 'To',
          'vertexType': 'TRANSIT',
          'lat': 51.0,
          'lon': 9.0,
          'scheduledTrack': '9',
        },
        'startTime': '2026-03-22T08:00:00Z',
        'endTime': '2026-03-22T09:00:00Z',
      });

      expect(leg['origin']?['platform'], '7');
      expect(leg['destination']?['platform'], '9');
    });

    test(
        'uses scheduledTrack for intermediate stops when realtime track is missing',
        () {
      final leg = legFromMotisLeg({
        'mode': 'REGIONAL_RAIL',
        'displayName': 'RE 1',
        'from': {
          'stopId': 'from-stop',
          'name': 'From',
          'vertexType': 'TRANSIT',
          'lat': 50.0,
          'lon': 8.0,
        },
        'to': {
          'stopId': 'to-stop',
          'name': 'To',
          'vertexType': 'TRANSIT',
          'lat': 51.0,
          'lon': 9.0,
        },
        'startTime': '2026-03-22T08:00:00Z',
        'endTime': '2026-03-22T09:00:00Z',
        'intermediateStops': [
          {
            'stopId': 'mid-stop',
            'name': 'Mid',
            'vertexType': 'TRANSIT',
            'lat': 50.5,
            'lon': 8.5,
            'scheduledTrack': '4',
            'scheduledArrival': '2026-03-22T08:30:00Z',
            'arrival': '2026-03-22T08:31:00Z',
          }
        ],
      });

      final stopovers = leg['stopovers'] as List<dynamic>;
      final stop = stopovers.first as Map<String, dynamic>;
      expect(stop['platform'], '4');
      expect(stop['stop']?['platform'], '4');
    });

    test(
        'journey conversion skips non-map legs and tolerates missing endpoints',
        () {
      final journey = journeyFromMotisItinerary({
        'startTime': '2026-04-21T08:00:00Z',
        'endTime': '2026-04-21T09:00:00Z',
        'legs': [
          'invalid-leg',
          {
            'mode': 'WALK',
            'startTime': '2026-04-21T08:00:00Z',
            'endTime': '2026-04-21T08:10:00Z',
          }
        ],
      });

      final legs = journey['legs'] as List<dynamic>;
      expect(legs.length, 1);
      expect((legs.first as Map<String, dynamic>)['origin'], isNotNull);
      expect((legs.first)['destination'], isNotNull);
    });

    test('preserves BIKE mode on direct non-transit legs', () {
      final leg = legFromMotisLeg({
        'mode': 'BIKE',
        'from': {'name': 'Start', 'lat': 40.0, 'lon': 4.0},
        'to': {'name': 'End', 'lat': 40.1, 'lon': 4.1},
        'startTime': '2026-05-05T06:12:00Z',
        'endTime': '2026-05-05T06:22:00Z',
        'distance': 2500,
      });

      expect(leg['mode'], 'BIKE');
      expect(leg['walking'], isTrue);
      expect(leg, isNot(contains('line')));
    });
  });
}
