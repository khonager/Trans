import 'package:flutter_test/flutter_test.dart';
import 'package:trans/services/transport_api.dart';

void main() {
  group('TransportApi.mergeResults', () {
    test('returns empty list when both inputs are empty', () {
      final result = TransportApi.mergeResults([], []);
      expect(result, isEmpty);
    });

    test('returns MOTIS results when v6 is empty', () {
      final motis = [
        {'departure': '2023-01-01T10:00:00Z', 'id': 'm1'}
      ];
      final result = TransportApi.mergeResults(motis, []);
      expect(result, equals(motis));
    });

    test('returns v6 results when MOTIS is empty', () {
      final v6 = [
        {'departure': '2023-01-01T10:00:00Z', 'id': 'v1'}
      ];
      final result = TransportApi.mergeResults([], v6);
      expect(result, equals(v6));
    });

    test('deduplicates identical journeys (prefers MOTIS)', () {
      final keyTime = '2023-01-01T10:00:00Z';
      final keyArr = '2023-01-01T11:00:00Z';

      final motisJourney = {
        'departure': keyTime,
        'arrival': keyArr,
        'legs': [
          {
            'line': {'name': 'Bus 21'}
          }
        ],
        'source': 'motis'
      };

      final v6Journey = {
        'departure': keyTime,
        'arrival': keyArr,
        'legs': [
          {
            'line': {'name': 'Bus 21'}
          }
        ],
        'source': 'v6'
      };

      final result = TransportApi.mergeResults([motisJourney], [v6Journey]);

      expect(result.length, 1);
      expect(result.first['source'], 'motis');
    });

    test('merges distinct journeys', () {
      final motisJourney = {
        'departure': '2023-01-01T10:00:00Z',
        'arrival': '2023-01-01T11:00:00Z',
        'legs': [
          {
            'line': {'name': 'Bus 21'}
          }
        ],
        'source': 'motis'
      };

      final v6Journey = {
        'departure': '2023-01-01T10:15:00Z', // Different time
        'arrival': '2023-01-01T11:15:00Z',
        'legs': [
          {
            'line': {'name': 'Bus 22'}
          }
        ],
        'source': 'v6'
      };

      final result = TransportApi.mergeResults([motisJourney], [v6Journey]);

      expect(result.length, 2);
    });

    test('merges journeys with same time but different first line', () {
      final time = '2023-01-01T10:00:00Z';
      final arr = '2023-01-01T11:00:00Z';

      final motisJourney = {
        'departure': time,
        'arrival': arr,
        'legs': [
          {
            'line': {'name': 'Bus 21'}
          }
        ],
        'source': 'motis'
      };

      final v6Journey = {
        'departure': time,
        'arrival': arr,
        'legs': [
          {
            'line': {'name': 'Tram 11'}
          }
        ], // Different line
        'source': 'v6'
      };

      final result = TransportApi.mergeResults([motisJourney], [v6Journey]);

      expect(result.length, 2);
    });

    test('sorts results by departure time', () {
      final j1 = {'departure': '2023-01-01T10:00:00Z', 'legs': []};
      final j2 = {'departure': '2023-01-01T09:00:00Z', 'legs': []};
      final j3 = {'departure': '2023-01-01T11:00:00Z', 'legs': []};

      final result = TransportApi.mergeResults([j1], [j2, j3]);

      expect(result[0], equals(j2));
      expect(result[1], equals(j1));
      expect(result[2], equals(j3));
    });
  });
}
