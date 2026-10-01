import 'package:flutter_test/flutter_test.dart';
import 'package:trans/models/station.dart';
import 'package:trans/services/route_options_service.dart';

final _origin = Station(id: 'origin', name: 'Origin');
final _destination = Station(id: 'destination', name: 'Destination');

String _at(int minute) =>
    DateTime.utc(2026, 10, 1, 10, minute).toIso8601String();

Map<String, dynamic> _leg({
  String origin = 'origin',
  String destination = 'destination',
  int departure = 0,
  int arrival = 20,
  String line = '27',
  String tripId = 'trip-27',
  List<Map<String, dynamic>> stopovers = const [],
}) =>
    {
      'origin': {'id': origin, 'name': origin},
      'destination': {'id': destination, 'name': destination},
      'departure': _at(departure),
      'arrival': _at(arrival),
      'line': {'name': line, 'tripId': tripId},
      'stopovers': stopovers,
    };

void main() {
  test('trims a full trip to the stop where the rider boarded', () {
    final full = _leg(
      origin: 'earlier',
      stopovers: [
        {
          'stop': {'id': 'origin', 'name': 'Origin'},
          'departure': _at(5),
        },
        {
          'stop': {'id': 'later', 'name': 'Later'},
          'arrival': _at(12),
        },
      ],
    );

    final trimmed = rideLegFromBoardingStop(full, 'origin')!;
    expect(trimmed['origin']['id'], 'origin');
    expect(trimmed['departure'], _at(5));
    expect(rideStopsFromLeg(trimmed).map((stop) => stop.id),
        ['origin', 'later', 'destination']);
  });

  test('finds direct lines from departures even when a planner omits them',
      () async {
    final departures = [
      {
        'routeShortName': '27',
        'headsign': 'Destination',
        'tripId': 'trip-27',
        'place': {'scheduledDeparture': _at(0)},
      },
      {
        'routeShortName': '18',
        'headsign': 'Destination',
        'tripId': 'trip-18',
        'place': {'scheduledDeparture': _at(4)},
      },
      {
        'routeShortName': '4',
        'headsign': 'Elsewhere',
        'tripId': 'wrong-way',
        'place': {'scheduledDeparture': _at(6)},
      },
    ];
    final trips = {
      'trip-27': {
        'legs': [_leg()]
      },
      'trip-18': {
        'legs': [_leg(line: '18', tripId: 'trip-18', departure: 4)]
      },
      'wrong-way': {
        'legs': [_leg(destination: 'elsewhere', line: '4')]
      },
    };

    final lines = await findDirectLines(
      origin: _origin,
      destination: _destination,
      start: DateTime.utc(2026, 10, 1, 10),
      loadDepartures: (id, {required start, required end}) async => departures,
      loadTrip: (id) async => trips[id],
    );

    expect(lines.map((line) => line.line), ['27', '18']);
  });

  test('on-board search uses future stops and rejects the current bus',
      () async {
    final stops = [
      RideStop(
          id: 'origin', name: 'Origin', arrival: DateTime.utc(2026, 10, 1, 10)),
      RideStop(
          id: 'middle',
          name: 'Middle',
          arrival: DateTime.utc(2026, 10, 1, 10, 10)),
      RideStop(
          id: 'later',
          name: 'Later',
          arrival: DateTime.utc(2026, 10, 1, 10, 15)),
    ];
    final queried = <String>[];
    final earliestTimes = <DateTime>[];
    final options = await findOnBoardOptions(
      stops: stops,
      nextStopIndex: 1,
      destination: _destination,
      currentTripId: 'current',
      currentLine: '27',
      nahverkehrOnly: true,
      searchFromStop: (from, to, earliest) async {
        queried.add(from.id);
        earliestTimes.add(earliest);
        return [
          {
            'legs': [
              _leg(
                origin: from.id,
                departure: 8,
                arrival: 19,
                line: '4',
                tripId: 'already-left',
              ),
            ],
          },
          {
            'legs': [
              _leg(
                origin: from.id,
                departure: from.id == 'middle' ? 12 : 17,
                arrival: 30,
                tripId: 'current',
              ),
            ],
          },
          {
            'legs': [
              _leg(
                origin: from.id,
                departure: from.id == 'middle' ? 13 : 18,
                arrival: 25,
                line: '18',
                tripId: 'other',
              ),
            ],
          },
        ];
      },
    );

    expect(queried, ['middle', 'later']);
    expect(earliestTimes.first, DateTime.utc(2026, 10, 1, 10, 12));
    expect(options, hasLength(2));
    expect(
        options.every((option) =>
            (option.onwardJourney['legs'][0]['line']['tripId']) == 'other'),
        isTrue);
  });
}
