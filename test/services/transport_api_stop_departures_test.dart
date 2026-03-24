import 'package:flutter_test/flutter_test.dart';
import 'package:trans/services/transport_api.dart';

void main() {
  group('TransportApi.decodeStopDeparturesResponse', () {
    test('extracts Transitous stopTimes payloads', () {
      final result = TransportApi.decodeStopDeparturesResponse({
        'stopTimes': [
          {
            'routeShortName': '21',
            'headsign': 'Kirchgasse',
            'place': {
              'scheduledDeparture': '2026-03-24T07:09:00Z',
              'departure': '2026-03-24T07:09:00Z',
            },
          },
        ],
      });

      expect(result, hasLength(1));
      expect(result.first['routeShortName'], '21');
    });

    test('extracts v6 departures payloads', () {
      final result = TransportApi.decodeStopDeparturesResponse({
        'departures': [
          {
            'plannedWhen': '2026-03-24T07:09:00Z',
            'when': '2026-03-24T07:10:00Z',
          },
        ],
      });

      expect(result, hasLength(1));
      expect(result.first['plannedWhen'], '2026-03-24T07:09:00Z');
    });

    test('keeps legacy bare lists working', () {
      final result = TransportApi.decodeStopDeparturesResponse([
        {'routeShortName': 'RB 75'},
      ]);

      expect(result, hasLength(1));
      expect(result.first['routeShortName'], 'RB 75');
    });
  });
}
