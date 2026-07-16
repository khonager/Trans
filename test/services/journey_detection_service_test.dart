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
        MapEntry('a', _journey(departure: departure, latitude: 50, line: '7')),
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
        MapEntry('a', _journey(departure: departure, latitude: 50, line: '7')),
        MapEntry('b', _journey(departure: departure, latitude: 50, line: '8')),
      ],
      now: departure.add(const Duration(minutes: 2)),
      latitude: 50.001,
      longitude: 8,
    );
    expect(JourneyDetectionService.isConfident(ranked), isFalse);
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
