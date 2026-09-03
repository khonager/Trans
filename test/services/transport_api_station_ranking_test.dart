import 'package:flutter_test/flutter_test.dart';
import 'package:trans/models/station.dart';
import 'package:trans/services/transport_api.dart';

void main() {
  group('TransportApi.shouldSupplementSparseStationResults', () {
    test('supplements sparse station-like short queries', () {
      expect(
        TransportApi.shouldSupplementSparseStationResults(
          'hbf',
          currentCount: 10,
          requestedLimit: 60,
          hasLocationBias: true,
        ),
        isTrue,
      );
    });

    test('does not supplement when station-like results already fill batch',
        () {
      expect(
        TransportApi.shouldSupplementSparseStationResults(
          'hbf',
          currentCount: 20,
          requestedLimit: 20,
          hasLocationBias: true,
        ),
        isFalse,
      );
    });

    test('does not supplement specific longer non-station queries', () {
      expect(
        TransportApi.shouldSupplementSparseStationResults(
          'frankfurt airport terminal 1',
          currentCount: 8,
          requestedLimit: 60,
          hasLocationBias: true,
        ),
        isFalse,
      );
    });

    test('does not supplement when there is no location bias to remove', () {
      expect(
        TransportApi.shouldSupplementSparseStationResults(
          'hbf',
          currentCount: 6,
          requestedLimit: 60,
          hasLocationBias: false,
        ),
        isFalse,
      );
    });
  });

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

    test('keeps an exact address ahead of city-named street stops', () {
      // Real api.transitous.org/api/v1/geocode payload for the query below,
      // which the prefilled "from" field produces from a reverse-geocoded
      // current location. Transitous ranks the address first; the app used to
      // sort it last behind nine near-tied "Wiesbaden <X>-Straße" bus stops.
      Station stop(String name, double lat, double lng, double score,
              double importance) =>
          Station(
            id: name,
            name: name,
            type: 'stop',
            latitude: lat,
            longitude: lng,
            city: 'Wiesbaden',
            region: 'Hessen',
            country: 'DE',
            searchScore: score,
            searchImportance: importance,
          );

      final ranked = TransportApi.rankStationsForQuery(
        [
          Station(
            id: 'helgolander-address',
            name: 'Helgoländer Straße',
            type: 'address',
            latitude: 50.0660486,
            longitude: 8.2058587,
            city: 'Wiesbaden',
            region: 'Hessen',
            country: 'DE',
            searchScore: -42.95,
          ),
          stop('Wiesbaden Berliner Straße', 50.072205, 8.256731, -30.55,
              0.000143),
          stop('Wiesbaden Carl-von-Linde-Straße', 50.076176, 8.208654, -30.55,
              0.000105),
          stop('Wiesbaden Wilhelm-Hauff-Straße', 50.069366, 8.232805, -30.55,
              0.00000079),
          stop('Wiesbaden Hans-Bredow-Straße', 50.076977, 8.258082, -30.05,
              0.0000092),
          stop('Wiesbaden-Biebrich Faaker Straße', 50.055847, 8.224544, -30.05,
              0.0000284),
          stop('Wiesbaden A.-Schlüter-Straße', 50.064552, 8.265466, -29.80,
              0.0000282),
          stop('Wiesbaden-Dotzheim Juister Straße', 50.062110, 8.209416, -29.80,
              0.0000414),
          stop('Wiesbaden Gustav-Mahler-Straße', 50.087326, 8.256986, -29.55,
              0.0000304),
          stop('Wiesbaden Klarenthaler Straße', 50.078125, 8.227440, -29.55,
              0.000125),
        ],
        'Helgoländer Straße Wiesbaden Hessen',
        lat: 50.0660486,
        lng: 8.2058587,
      );

      expect(ranked.first.id, 'helgolander-address');
    });

    test('tolerates a single slipped keystroke in the city name', () {
      // "wiesbden" misses the 'a'. Transitous still ranks the address first;
      // without typo tolerance the token matched nothing here, so far-away
      // stops carrying the street name outscored it.
      final ranked = TransportApi.rankStationsForQuery(
        [
          Station(
            id: 'gifhorn-stop',
            name: 'Gifhorn, Helgoländer Straße',
            type: 'stop',
            latitude: 52.4875,
            longitude: 10.5501,
            city: 'Gifhorn',
            region: 'Niedersachsen',
            country: 'DE',
            searchScore: -20.35,
            searchImportance: 0.0000062,
          ),
          Station(
            id: 'syke-stop',
            name: 'Ristedt(Syke) Helgoländer Straße',
            type: 'stop',
            latitude: 52.9163,
            longitude: 8.8221,
            city: 'Syke',
            region: 'Niedersachsen',
            country: 'DE',
            searchScore: -19.35,
            searchImportance: 0.0000017,
          ),
          Station(
            id: 'helgolander-address',
            name: 'Helgoländer Straße',
            type: 'address',
            latitude: 50.0660486,
            longitude: 8.2058587,
            city: 'Wiesbaden',
            region: 'Hessen',
            country: 'DE',
            searchScore: -24.50,
          ),
        ],
        'Helgoländer Straße wiesbden',
      );

      expect(ranked.first.id, 'helgolander-address');
    });

    test('tolerates two slipped keystrokes in a long city name', () {
      // "wiesbdne" is two edits from "wiesbaden" (a dropped letter plus a
      // transposition), and the query carries no usable location. Transitous
      // still ranks the address first, by a margin of 0.15.
      final ranked = TransportApi.rankStationsForQuery(
        [
          Station(
            id: 'gifhorn-stop',
            name: 'Gifhorn, Helgoländer Straße',
            type: 'stop',
            latitude: 52.465546,
            longitude: 10.569263,
            city: 'Gifhorn',
            region: 'Niedersachsen',
            country: 'DE',
            searchScore: -19.35,
            searchImportance: 0.0000062,
          ),
          Station(
            id: 'syke-stop',
            name: 'Ristedt(Syke) Helgoländer Straße',
            type: 'stop',
            latitude: 52.94754,
            longitude: 8.75603,
            city: 'Syke',
            region: 'Niedersachsen',
            country: 'DE',
            searchScore: -18.35,
            searchImportance: 0.0000017,
          ),
          Station(
            id: 'helgolander-address',
            name: 'Helgoländer Straße',
            type: 'address',
            latitude: 50.0660486,
            longitude: 8.2058587,
            city: 'Wiesbaden',
            region: 'Hessen',
            country: 'DE',
            searchScore: -19.50,
          ),
        ],
        'helgölander straße wiesbdne',
      );

      expect(ranked.first.id, 'helgolander-address');
    });

    test('keeps the edit budget tight for mid-length tokens', () {
      // "kasel" is two edits from "kassel", but at five characters the budget
      // is one, so the unrelated exact match must stay ahead.
      final ranked = TransportApi.rankStationsForQuery(
        [
          Station(
            id: 'exact-city',
            name: 'Kasel Bahnhof',
            type: 'stop',
            city: 'Kasel',
            country: 'DE',
            searchScore: -20.0,
          ),
          Station(
            id: 'two-edits-away',
            name: 'Kassel Hauptbahnhof',
            type: 'stop',
            city: 'Kassel',
            country: 'DE',
            searchScore: -20.0,
          ),
        ],
        'kasel',
      );

      expect(ranked.first.id, 'exact-city');
    });

    test('does not treat short tokens as typos of each other', () {
      final ranked = TransportApi.rankStationsForQuery(
        [
          Station(
            id: 'mainz-hbf',
            name: 'Mainz Hbf',
            type: 'stop',
            city: 'Mainz',
            country: 'DE',
            searchScore: -30.9,
            searchImportance: 0.075,
          ),
          Station(
            id: 'unrelated-main',
            name: 'Main Tower',
            type: 'location',
            city: 'Frankfurt am Main',
            country: 'DE',
            searchScore: -30.9,
          ),
        ],
        'mainz',
      );

      expect(ranked.first.id, 'mainz-hbf');
    });
  });
}
