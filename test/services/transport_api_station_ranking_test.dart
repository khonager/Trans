import 'package:flutter_test/flutter_test.dart';
import 'package:trans/models/station.dart';
import 'package:trans/services/transport_api.dart';

void main() {
  group('TransportApi.rankStationsForQuery', () {
    test('prefers a main transit hub over an exact city place without location',
        () {
      final ranked = TransportApi.rankStationsForQuery(
        [
          Station(
            id: 'city-place',
            name: 'Wiesbaden',
            type: 'location',
            city: 'Wiesbaden',
            country: 'DE',
          ),
          Station(
            id: 'main-station',
            name: 'Wiesbaden Hauptbahnhof',
            type: 'stop',
            city: 'Wiesbaden',
            country: 'DE',
          ),
          Station(
            id: 'foreign-place',
            name: 'WIESBADEN',
            type: 'location',
            city: 'Amahlathi Local Municipality',
            country: 'ZA',
          ),
        ],
        'wiesbaden',
      );

      expect(ranked.first.id, 'main-station');
      expect(ranked[1].id, 'city-place');
    });

    test(
        'prioritizes nearby airport stops over generic airport POIs and streets',
        () {
      final ranked = TransportApi.rankStationsForQuery(
        [
          Station(
            id: 'generic-airport',
            name: 'Flughafen',
            type: 'location',
            latitude: 51.1243,
            longitude: 13.7653,
            city: 'Dresden',
          ),
          Station(
            id: 'airport-road',
            name: 'Flughafenstrasse',
            type: 'address',
            latitude: 50.0707,
            longitude: 8.6420,
            city: 'Frankfurt am Main',
          ),
          Station(
            id: 'fra-fern',
            name: 'Frankfurt(M) Flughafen Fernbf',
            type: 'stop',
            latitude: 50.0520,
            longitude: 8.5707,
            city: 'Frankfurt am Main',
          ),
        ],
        'Flughafen',
        lat: 50.1109,
        lng: 8.6821,
      );

      expect(ranked.first.id, 'fra-fern');
      expect(ranked.last.id, 'airport-road');
    });

    test('normalizes diacritics in airport-like queries', () {
      final ranked = TransportApi.rankStationsForQuery(
        [
          Station(
            id: 'airportring',
            name: 'Airportring',
            type: 'address',
            latitude: 50.0378,
            longitude: 8.5232,
            city: 'Frankfurt am Main',
          ),
          Station(
            id: 'fra-terminal',
            name: 'Frankfurt Airport Terminal 1',
            type: 'stop',
            latitude: 50.0500,
            longitude: 8.5706,
            city: 'Frankfurt am Main',
          ),
        ],
        'äirport',
        lat: 50.1109,
        lng: 8.6821,
      );

      expect(ranked.first.id, 'fra-terminal');
    });

    test('ignores filler words in nearby airport searches', () {
      final ranked = TransportApi.rankStationsForQuery(
        [
          Station(
            id: 'fra-regional',
            name: 'Frankfurt(M) Flughafen Regionalbf',
            type: 'stop',
            latitude: 50.0519,
            longitude: 8.5718,
            city: 'Frankfurt am Main',
          ),
          Station(
            id: 'generic-airport',
            name: 'Flughafen',
            type: 'location',
            latitude: 52.3913,
            longitude: 13.5161,
            city: 'Schonefeld',
          ),
        ],
        'naher flughafen',
        lat: 50.1109,
        lng: 8.6821,
      );

      expect(ranked.first.id, 'fra-regional');
    });
  });
}
