import 'package:flutter_test/flutter_test.dart';
import 'package:trans/models/journey.dart';
import 'package:trans/models/journey_sharing.dart';
import 'package:trans/services/journey_detection_service.dart';

Journey _journey({
  required DateTime departure,
  required double latitude,
  required String line,
}) {
  final arrival = departure.add(const Duration(minutes: 20));
  return Journey(
    steps: [
      JourneyStep(
        type: 'ride',
        line: line,
        instruction: '',
        duration: '20 min',
        departureTime: '10:00',
        arrivalTime: '10:20',
        startLat: latitude,
        startLng: 8.0,
        endLat: latitude + 0.02,
        endLng: 8.0,
        startStationName: 'Start',
        destinationName: 'End',
        dateTime: departure,
        plannedArrival: arrival,
      ),
    ],
    departure: departure,
    arrival: arrival,
    duration: const Duration(minutes: 20),
    transferCount: 0,
    totalWaitTime: Duration.zero,
    rawSource: const {},
    source: 'test',
  );
}

JourneyDetectionCandidate _candidate(
  String key,
  Journey journey, {
  JourneyDetectionSource source = JourneyDetectionSource.searchResult,
  String destinationName = 'End',
  String? tabId,
}) =>
    JourneyDetectionCandidate(
      key: key,
      journey: journey,
      source: source,
      destinationName: destinationName,
      tabId: tabId,
    );

void main() {
  test('Signal levels clamp and friend overrides replace the global level', () {
    expect(JourneySignalLevel.clamp(-1), 0);
    expect(JourneySignalLevel.clamp(99), 8);
    const settings = JourneySharingSettings(
      globalLevel: 1,
      friendOverrides: {'trusted': 7, 'hidden': 0},
    );
    expect(settings.effectiveLevelFor('normal'), 1);
    expect(settings.effectiveLevelFor('trusted'), 7);
    expect(settings.effectiveLevelFor('hidden'), 0);
    expect(settings.needsAlwaysLocation, isTrue);
  });

  test('detector accepts a clear nearby candidate', () {
    final departure = DateTime(2026, 7, 16, 10);
    final ranked = JourneyDetectionService.rankCandidates(
      candidates: [
        _candidate(
          'a',
          _journey(departure: departure, latitude: 50, line: '7'),
          source: JourneyDetectionSource.selected,
        ),
      ],
      now: departure.add(const Duration(minutes: 2)),
      latitude: 50.001,
      longitude: 8,
    );
    expect(JourneyDetectionService.isConfident(ranked), isTrue);
    expect(ranked.first.currentRide?.line, '7');
  });

  test('detector waits when two candidates are indistinguishable', () {
    final departure = DateTime(2026, 7, 16, 10);
    final ranked = JourneyDetectionService.rankCandidates(
      candidates: [
        _candidate('a', _journey(departure: departure, latitude: 50, line: '7'),
            source: JourneyDetectionSource.selected),
        _candidate('b', _journey(departure: departure, latitude: 50, line: '8'),
            source: JourneyDetectionSource.selected),
      ],
      now: departure.add(const Duration(minutes: 2)),
      latitude: 50.001,
      longitude: 8,
    );
    expect(JourneyDetectionService.isConfident(ranked), isFalse);
  });

  group('what the user actually takes', () {
    final departure = DateTime(2026, 7, 16, 10);

    List<JourneyDetectionMatch> rankAt({
      required List<JourneyDetectionCandidate> candidates,
    }) =>
        JourneyDetectionService.rankCandidates(
          candidates: candidates,
          now: departure.add(const Duration(minutes: 2)),
          latitude: 50.001,
          longitude: 8,
        );

    test('the journey the user opened beats an equally close alternative', () {
      final ranked = rankAt(candidates: [
        _candidate(
          'result',
          _journey(departure: departure, latitude: 50, line: '8'),
        ),
        _candidate(
          'selected',
          _journey(departure: departure, latitude: 50, line: '7'),
          source: JourneyDetectionSource.selected,
        ),
      ]);

      expect(ranked.first.key, 'selected');
      expect(JourneyDetectionService.isConfident(ranked), isTrue);
    });

    test('a saved connection outranks a plain search result', () {
      final ranked = rankAt(candidates: [
        _candidate(
          'result',
          _journey(departure: departure, latitude: 50, line: '8'),
        ),
        _candidate(
          'saved',
          _journey(departure: departure, latitude: 50, line: '7'),
          source: JourneyDetectionSource.saved,
        ),
      ]);

      expect(ranked.first.source, JourneyDetectionSource.saved);
    });

    test('the same evidence is weighted by where the journey came from', () {
      final journey = _journey(departure: departure, latitude: 50, line: '7');
      final selected = rankAt(candidates: [
        _candidate('a', journey, source: JourneyDetectionSource.selected),
      ]).single;
      final result = rankAt(candidates: [_candidate('a', journey)]).single;

      expect(selected.evidence, closeTo(result.evidence, 0.0001));
      expect(selected.score, greaterThan(result.score));
    });

    test('a match carries the destination without needing its tab', () {
      final ranked = rankAt(candidates: [
        _candidate(
          'saved',
          _journey(departure: departure, latitude: 50, line: '7'),
          source: JourneyDetectionSource.saved,
          destinationName: 'Offenbach Marktplatz',
        ),
      ]);

      expect(ranked.single.destinationName, 'Offenbach Marktplatz');
      expect(ranked.single.tabId, isNull);
    });
  });

  test('itinerary excludes walking coordinates', () {
    final departure = DateTime(2026, 7, 16, 10);
    final journey = _journey(departure: departure, latitude: 50, line: '7');
    final itinerary = JourneyDetectionService.sanitizedItinerary(journey);
    expect(itinerary, hasLength(1));
    expect(itinerary.single, isNot(contains('latitude')));
    expect(itinerary.single['line'], '7');
  });
}
