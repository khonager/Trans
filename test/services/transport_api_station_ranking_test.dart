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

    test('prefers exact city stop over same-region hubs for hbf queries', () {
      final ranked = TransportApi.rankStationsForQuery(
        [
          Station(
            id: 'neuss-hbf',
            name: 'Neuss Hauptbahnhof',
            type: 'stop',
            city: 'Neuss',
            region: 'Regierungsbezirk Dusseldorf',
            country: 'DE',
            searchImportance: 0.11,
          ),
          Station(
            id: 'duesseldorf-hbf',
            name: 'Dusseldorf Hbf',
            type: 'stop',
            city: 'Dusseldorf',
            region: 'Nordrhein-Westfalen',
            country: 'DE',
            searchImportance: 0.39,
          ),
          Station(
            id: 'wuppertal-hbf',
            name: 'Wuppertal Hauptbahnhof',
            type: 'stop',
            city: 'Wuppertal',
            region: 'Regierungsbezirk Dusseldorf',
            country: 'DE',
            searchImportance: 0.08,
          ),
        ],
        'Dusseldorf Hbf',
        lat: 51.2290,
        lng: 6.7820,
      );

      expect(ranked.first.id, 'duesseldorf-hbf');
    });

    test('prefers main airport rail stations over terminal-specific stops', () {
      final ranked = TransportApi.rankStationsForQuery(
        [
          Station(
            id: 'terminal-p36',
            name: 'Frankfurt Airport (P36 Terminal 1)',
            type: 'stop',
            city: 'Frankfurt am Main',
            country: 'DE',
            searchImportance: 0.01,
          ),
          Station(
            id: 'airport-center',
            name: 'Frankfurt Airport Center',
            type: 'location',
            city: 'Frankfurt am Main',
            country: 'DE',
            searchImportance: 0.02,
          ),
          Station(
            id: 'fra-fern',
            name: 'Frankfurt(M) Flughafen Fernbf',
            type: 'stop',
            city: 'Frankfurt am Main',
            country: 'DE',
            searchImportance: 0.14,
          ),
        ],
        'Frankfurt Airport',
        lat: 50.1109,
        lng: 8.6821,
      );

      expect(ranked.first.id, 'fra-fern');
      expect(
        ranked.indexWhere((station) => station.id == 'terminal-p36'),
        greaterThan(ranked.indexWhere((station) => station.id == 'fra-fern')),
      );
    });

    test(
        'keeps farther duplicate place accessible when query names another city',
        () {
      final ranked = TransportApi.rankStationsForQuery(
        [
          Station(
            id: 'wiesbaden-luisenplatz',
            name: 'Luisenplatz',
            type: 'stop',
            city: 'Wiesbaden',
            country: 'DE',
            latitude: 50.0791,
            longitude: 8.2397,
          ),
          Station(
            id: 'darmstadt-luisenplatz',
            name: 'Darmstadt Luisenplatz',
            type: 'stop',
            city: 'Darmstadt',
            country: 'DE',
            latitude: 49.8729,
            longitude: 8.6506,
          ),
          Station(
            id: 'darmstadt-fountain',
            name: 'Luisenplatz-Brunnen',
            type: 'location',
            city: 'Darmstadt',
            country: 'DE',
            latitude: 49.8724,
            longitude: 8.6513,
          ),
        ],
        'Luisenplatz Wiesbaden',
        lat: 49.8729,
        lng: 8.6506,
      );

      expect(ranked.first.id, 'wiesbaden-luisenplatz');
    });

    test('prefers actual hauptbahnhof over einkaufsbahnhof poi for hbf query',
        () {
      final ranked = TransportApi.rankStationsForQuery(
        [
          Station(
            id: 'einkaufsbahnhof',
            name: 'Einkaufsbahnhof Wiesbaden Hbf',
            type: 'location',
            city: 'Wiesbaden',
            country: 'DE',
            category: 'shop_other_16',
            searchScore: -23.5,
          ),
          Station(
            id: 'wiesbaden-hbf',
            name: 'Wiesbaden Hauptbahnhof',
            type: 'stop',
            city: 'Wiesbaden',
            country: 'DE',
            searchScore: -30.9,
            searchImportance: 0.075,
          ),
        ],
        'wiesbaden hbf',
      );

      expect(ranked.first.id, 'wiesbaden-hbf');
    });

    test('generally prefers transit stops over similarly named places', () {
      final ranked = TransportApi.rankStationsForQuery(
        [
          Station(
            id: 'poi',
            name: 'Wiesbaden Hauptbahnhof',
            type: 'location',
            city: 'Wiesbaden',
            country: 'DE',
            searchScore: -26.5,
          ),
          Station(
            id: 'stop',
            name: 'Wiesbaden Hauptbahnhof',
            type: 'stop',
            city: 'Wiesbaden',
            country: 'DE',
            searchScore: -30.9,
            searchImportance: 0.075,
          ),
        ],
        'wiesbaden hauptbahnhof',
      );

      expect(ranked.first.id, 'stop');
    });
  });
}
