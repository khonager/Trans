import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:trans/models/journey.dart';
import 'package:trans/utils/ride_progress.dart';

void main() {
  final step = JourneyStep(
    type: 'ride',
    line: '1',
    instruction: 'Ride',
    duration: '10 min',
    departureTime: '10:00',
    arrivalTime: '10:10',
    startLat: 52,
    startLng: 13,
    endLat: 52,
    endLng: 13.02,
    stopovers: [
      {
        'stop': {
          'location': {'latitude': 52, 'longitude': 13.01}
        }
      },
    ],
    path: [
      [52, 13],
      [52, 13.005],
      [52, 13.01],
      [52, 13.015],
      [52, 13.02]
    ],
  );

  Position fix(double longitude,
          {double latitude = 52, double accuracy = 5, DateTime? timestamp}) =>
      Position(
        latitude: latitude,
        longitude: longitude,
        timestamp: timestamp ?? DateTime.now(),
        accuracy: accuracy,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );

  test('places the dot between the correct adjacent stops', () {
    final first = rideProgressFor(step, fix(13.005))!;
    expect(first.interval, 0);
    expect(first.fraction, closeTo(0.5, 0.01));

    final second = rideProgressFor(step, fix(13.015))!;
    expect(second.interval, 1);
    expect(second.fraction, closeTo(0.5, 0.01));
  });

  test('does not show progress for an unrelated or inaccurate fix', () {
    expect(rideProgressFor(step, fix(14)), isNull);
    expect(rideProgressFor(step, fix(13.005, accuracy: 300)), isNull);
  });

  test('does not show a stale location as live progress', () {
    final stale = Position(
      latitude: 52,
      longitude: 13.005,
      timestamp: DateTime.now().subtract(const Duration(minutes: 3)),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
    expect(rideProgressFor(step, stale), isNull);
  });

  test('handles a shape supplied from destination to boarding', () {
    final reversed = step.copyWith(path: step.path!.reversed.toList());
    final progress = rideProgressFor(reversed, fix(13.015))!;
    expect(progress.interval, 1);
    expect(progress.fraction, closeTo(0.5, 0.01));
  });

  test('moves from a confirmed fix using stop times between GPS checks', () {
    final now = DateTime.now();
    final stopTime =
        DateTime(now.year, now.month, now.day, now.hour, now.minute);
    final start = stopTime.subtract(const Duration(minutes: 1));
    final end = stopTime.add(const Duration(minutes: 1));
    final timed = step.copyWith(
      dateTime: start,
      arrivalTime: '${end.hour.toString().padLeft(2, '0')}:'
          '${end.minute.toString().padLeft(2, '0')}',
      stopovers: [
        {
          'stop': {
            'location': {'latitude': 52, 'longitude': 13.01}
          },
          'arrival': stopTime.toIso8601String(),
        },
      ],
    );
    final confirmed = fix(13.01, timestamp: stopTime);
    final estimated = estimatedRideProgressFor(
        timed, confirmed, stopTime.add(const Duration(seconds: 30)))!;
    expect(estimated.interval, 1);
    expect(estimated.fraction, closeTo(0.5, 0.01));
    expect(estimatedRideProgressFor(timed, null, stopTime), isNull);
  });
}
