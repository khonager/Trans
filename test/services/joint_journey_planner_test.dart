import 'package:flutter_test/flutter_test.dart';
import 'package:trans/models/joint_journey.dart';
import 'package:trans/models/journey.dart';
import 'package:trans/services/joint_journey_planner.dart';

JourneyStep _step({
  required String type,
  required DateTime start,
  required DateTime end,
  String line = '',
  String? tripId,
  String? startId,
  String? endId,
  double? startLat,
  double? startLng,
  double? endLat,
  double? endLng,
  Duration? walk,
  Duration? wait,
  List<dynamic>? path,
}) {
  String time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  return JourneyStep(
    type: type,
    line: line,
    instruction: type,
    duration: '${end.difference(start).inMinutes} min',
    departureTime: time(start),
    arrivalTime: time(end),
    dateTime: start,
    plannedDeparture: start,
    plannedArrival: end,
    tripId: tripId,
    startStationId: startId,
    destinationStationId: endId,
    startLat: startLat,
    startLng: startLng,
    endLat: endLat,
    endLng: endLng,
    walkDuration: walk,
    waitDuration: wait,
    path: path,
  );
}

Journey _journey({
  required DateTime departure,
  required DateTime arrival,
  required List<JourneyStep> steps,
  int transfers = 0,
}) =>
    Journey(
      steps: steps,
      departure: departure,
      arrival: arrival,
      duration: arrival.difference(departure),
      transferCount: transfers,
      totalWaitTime: Duration.zero,
      rawSource: const {},
      source: 'test',
    );

void main() {
  final day = DateTime(2026, 8, 13);

  test('counts an overlapping ride on the same trip', () {
    final mine = _journey(
      departure: day.add(const Duration(hours: 8)),
      arrival: day.add(const Duration(hours: 9)),
      steps: [
        _step(
          type: 'ride',
          start: day.add(const Duration(hours: 8)),
          end: day.add(const Duration(hours: 9)),
          line: 'RE 1',
          tripId: 'trip-1',
          startId: 'a',
          endId: 'z',
        ),
      ],
    );
    final friend = _journey(
      departure: day.add(const Duration(hours: 8, minutes: 20)),
      arrival: day.add(const Duration(hours: 9)),
      steps: [
        _step(
          type: 'ride',
          start: day.add(const Duration(hours: 8, minutes: 20)),
          end: day.add(const Duration(hours: 9)),
          line: 'RE 1',
          tripId: 'trip-1',
          startId: 'b',
          endId: 'z',
        ),
      ],
    );

    final result = JointJourneyPlanner.rank(
      myJourneys: [mine],
      friendJourneys: [friend],
    );

    expect(result, hasLength(1));
    expect(result.single.sharedRideDuration, const Duration(minutes: 40));
    expect(result.single.sharedDuration, const Duration(minutes: 40));
  });

  test('counts waiting together at the same stop', () {
    final start = day.add(const Duration(hours: 12));
    Journey waiting(DateTime from, DateTime to) => _journey(
          departure: from,
          arrival: to,
          steps: [
            _step(
              type: 'wait',
              start: from,
              end: to,
              startId: 'station-a',
              endId: 'station-a',
              wait: to.difference(from),
            ),
          ],
        );

    final result = JointJourneyPlanner.rank(
      myJourneys: [waiting(start, start.add(const Duration(minutes: 20)))],
      friendJourneys: [
        waiting(
          start.add(const Duration(minutes: 5)),
          start.add(const Duration(minutes: 15)),
        )
      ],
    );

    expect(result.single.sharedWaitDuration, const Duration(minutes: 10));
  });

  test('counts walking together along the same path', () {
    final start = day.add(const Duration(hours: 16));
    Journey walking(List<dynamic> path) => _journey(
          departure: start,
          arrival: start.add(const Duration(minutes: 12)),
          steps: [
            _step(
              type: 'walk',
              start: start,
              end: start.add(const Duration(minutes: 12)),
              startId: 'station-a',
              endId: 'destination',
              startLat: 50.0,
              startLng: 8.0,
              endLat: 50.001,
              endLng: 8.001,
              walk: const Duration(minutes: 12),
              path: path,
            ),
          ],
        );

    final result = JointJourneyPlanner.rank(
      myJourneys: [
        walking(const [
          [50.0, 8.0],
          [50.0005, 8.0005],
          [50.001, 8.001],
        ])
      ],
      friendJourneys: [
        walking(const [
          [50.0, 8.0],
          [50.0005, 8.0005],
          [50.001, 8.001],
        ])
      ],
    );

    expect(result.single.sharedWalkDuration, const Duration(minutes: 12));
  });

  test('rejects a route outside the maximum detour', () {
    Journey route(int minutes, {String trip = 'shared'}) => _journey(
          departure: day,
          arrival: day.add(Duration(minutes: minutes)),
          steps: [
            _step(
              type: 'ride',
              start: day,
              end: day.add(Duration(minutes: minutes)),
              tripId: trip,
              line: '1',
            ),
          ],
        );

    final result = JointJourneyPlanner.rank(
      myJourneys: [route(30, trip: 'solo'), route(60)],
      friendJourneys: [route(60)],
      preferences: const JointJourneyPreferences.fast(),
    );

    expect(result, isEmpty);
  });

  test('prefers substantial shared time for a small arrive-by sacrifice', () {
    final arrival = day.add(const Duration(hours: 9));
    final solo = _journey(
      departure: day.add(const Duration(hours: 8)),
      arrival: arrival,
      steps: [
        _step(
          type: 'ride',
          start: day.add(const Duration(hours: 8)),
          end: arrival,
          tripId: 'solo',
          line: '1',
        ),
      ],
    );
    final shared = _journey(
      departure: day.add(const Duration(hours: 7, minutes: 55)),
      arrival: arrival,
      transfers: 1,
      steps: [
        _step(
          type: 'ride',
          start: day.add(const Duration(hours: 8, minutes: 20)),
          end: arrival,
          tripId: 'shared-trip',
          line: 'RE 1',
        ),
      ],
    );
    final friend = _journey(
      departure: day.add(const Duration(hours: 8, minutes: 20)),
      arrival: arrival,
      steps: [
        _step(
          type: 'ride',
          start: day.add(const Duration(hours: 8, minutes: 20)),
          end: arrival,
          tripId: 'shared-trip',
          line: 'RE 1',
        ),
      ],
    );

    final result = JointJourneyPlanner.rank(
      myJourneys: [solo, shared],
      friendJourneys: [friend],
      isArrival: true,
    );

    expect(result.single.myJourney, same(shared));
    expect(result.single.myExtraMinutes, 5);
    expect(result.single.myExtraTransfers, 1);
    expect(result.single.sharedDuration, const Duration(minutes: 40));
  });
}
