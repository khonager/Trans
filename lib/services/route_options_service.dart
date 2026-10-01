import 'package:trans/models/station.dart';
import 'package:trans/services/transport_api.dart';

DateTime? _time(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString())?.toLocal();

Map<String, dynamic>? _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;

double? _number(Object? value) => value is num ? value.toDouble() : null;

class RideStop {
  final String id;
  final String name;
  final DateTime arrival;
  final double? latitude;
  final double? longitude;

  const RideStop({
    required this.id,
    required this.name,
    required this.arrival,
    this.latitude,
    this.longitude,
  });

  Station get station => Station(
        id: id,
        name: name,
        type: 'station',
        latitude: latitude,
        longitude: longitude,
      );
}

RideStop? _rideStop(Map<String, dynamic>? place, DateTime? arrival) {
  if (place == null || arrival == null) return null;
  final id = place['id']?.toString() ?? '';
  if (id.isEmpty) return null;
  final location = _map(place['location']);
  return RideStop(
    id: id,
    name: place['name']?.toString() ?? id,
    arrival: arrival,
    latitude: _number(location?['latitude'] ?? place['latitude']),
    longitude: _number(location?['longitude'] ?? place['longitude']),
  );
}

/// Ordered stops on a single vehicle, including its final stop.
List<RideStop> rideStopsFromLeg(Map<String, dynamic> leg) {
  final stops = <RideStop>[];
  final origin = _rideStop(
    _map(leg['origin']),
    _time(leg['departure'] ?? leg['plannedDeparture']),
  );
  if (origin != null) stops.add(origin);
  for (final raw in (leg['stopovers'] as List?) ?? const []) {
    final stopover = _map(raw);
    final stop = _rideStop(
      _map(stopover?['stop']),
      _time(stopover?['arrival'] ??
          stopover?['plannedArrival'] ??
          stopover?['departure'] ??
          stopover?['plannedDeparture']),
    );
    if (stop != null && (stops.isEmpty || stops.last.id != stop.id)) {
      stops.add(stop);
    }
  }
  final destination = _rideStop(
    _map(leg['destination']),
    _time(leg['arrival'] ?? leg['plannedArrival']),
  );
  if (destination != null &&
      (stops.isEmpty || stops.last.id != destination.id)) {
    stops.add(destination);
  }
  return stops;
}

/// Parent stop ids differ between providers, so coordinates also identify
/// platforms belonging to the same destination stop area.
bool stopReachesDestination(RideStop stop, Station destination) {
  if (stop.id == destination.id) return true;
  final lat = stop.latitude;
  final lon = stop.longitude;
  final destLat = destination.latitude;
  final destLon = destination.longitude;
  if (lat == null || lon == null || destLat == null || destLon == null) {
    return false;
  }
  final latMeters = (lat - destLat) * 111200;
  final lonMeters = (lon - destLon) * 111200 * 0.7;
  return latMeters * latMeters + lonMeters * lonMeters <= 150 * 150;
}

bool _stopMatchesOrigin(RideStop stop, Station origin) {
  if (stop.id == origin.id) return true;
  final lat = stop.latitude;
  final lon = stop.longitude;
  final originLat = origin.latitude;
  final originLon = origin.longitude;
  if (lat == null || lon == null || originLat == null || originLon == null) {
    return false;
  }
  final latMeters = (lat - originLat) * 111200;
  final lonMeters = (lon - originLon) * 111200 * 0.7;
  return latMeters * latMeters + lonMeters * lonMeters <= 100 * 100;
}

/// Keep the exact vehicle, but make its boarding point match the route the
/// rider opened. A trip endpoint may be many stops before that point.
Map<String, dynamic>? rideLegFromBoardingStop(
  Map<String, dynamic> leg,
  String boardingStopId,
) {
  final stops = rideStopsFromLeg(leg);
  if (stops.isEmpty) return null;
  if (stops.first.id == boardingStopId) return leg;
  final rawStopovers = (leg['stopovers'] as List?) ?? const [];
  for (var i = 0; i < rawStopovers.length; i++) {
    final stopover = _map(rawStopovers[i]);
    final stop = _map(stopover?['stop']);
    if (stop?['id']?.toString() != boardingStopId) continue;
    final departure = stopover?['departure'] ??
        stopover?['plannedDeparture'] ??
        stopover?['arrival'];
    if (departure == null) return null;
    return Map<String, dynamic>.from(leg)
      ..['origin'] = stop
      ..['departure'] = departure
      ..['plannedDeparture'] = stopover?['plannedDeparture'] ?? departure
      ..['stopovers'] = rawStopovers.skip(i + 1).toList()
      ..remove('polyline')
      ..remove('decodedPath');
  }
  return null;
}

class DirectLineOption {
  final String line;
  final String direction;
  final DateTime departure;
  final DateTime arrival;

  const DirectLineOption({
    required this.line,
    required this.direction,
    required this.departure,
    required this.arrival,
  });
}

/// Enumerates departures independently of the journey planner's preferred
/// itineraries, then checks each sampled vehicle's actual stop sequence.
Future<List<DirectLineOption>> findDirectLines({
  required Station origin,
  required Station destination,
  required DateTime start,
  Duration window = const Duration(hours: 2),
  Future<List<Map<String, dynamic>>> Function(
    String stationId, {
    required DateTime start,
    required DateTime end,
  })? loadDepartures,
  Future<Map<String, dynamic>?> Function(String tripId)? loadTrip,
}) async {
  if (origin.id.isEmpty) return [];
  final departures = await (loadDepartures?.call(
        origin.id,
        start: start,
        end: start.add(window),
      ) ??
      TransportApi.fetchStopDeparturesWindow(
        origin.id,
        start: start,
        end: start.add(window),
      ));
  departures.sort((a, b) {
    final first = TransportApi.stopDepartureTime(a);
    final second = TransportApi.stopDepartureTime(b);
    if (first == null) return 1;
    if (second == null) return -1;
    return first.compareTo(second);
  });

  // Three vehicles per line and headsign cover common short turns and branch
  // patterns without fetching every high-frequency departure at a busy stop.
  final samples = <Map<String, dynamic>>[];
  final sampleCounts = <String, int>{};
  for (final departure in departures) {
    final line = (departure['routeShortName'] ??
            departure['displayName'] ??
            _map(departure['line'])?['name'])
        ?.toString()
        .trim();
    final tripId = TransportApi.stopDepartureTripId(departure);
    if (line == null || line.isEmpty || tripId == null) continue;
    final direction = (departure['headsign'] ??
            departure['direction'] ??
            _map(departure['tripTo'])?['name'] ??
            '')
        .toString();
    final key = '$line|$direction';
    if ((sampleCounts[key] ?? 0) >= 3) continue;
    sampleCounts[key] = (sampleCounts[key] ?? 0) + 1;
    samples.add(departure);
  }

  final options = <String, DirectLineOption>{};
  for (var offset = 0; offset < samples.length; offset += 6) {
    final batch = samples.skip(offset).take(6);
    final found = await Future.wait(batch.map((departure) async {
      final tripId = TransportApi.stopDepartureTripId(departure)!;
      Map<String, dynamic>? journey;
      try {
        journey = await (loadTrip?.call(tripId) ??
            TransportApi.fetchLiveTripJourney(tripId));
      } catch (_) {
        return null;
      }
      final legs = (journey?['legs'] as List?)?.whereType<Map>().toList();
      if (legs == null || legs.isEmpty) return null;
      final departureTime = TransportApi.stopDepartureTime(departure);
      if (departureTime == null) return null;
      final line = (departure['routeShortName'] ??
              departure['displayName'] ??
              _map(departure['line'])?['name'])
          .toString();
      final direction = (departure['headsign'] ??
              departure['direction'] ??
              _map(departure['tripTo'])?['name'] ??
              '')
          .toString();
      for (final rawLeg in legs) {
        final leg = Map<String, dynamic>.from(rawLeg);
        final stops = rideStopsFromLeg(leg);
        final originIndex =
            stops.indexWhere((stop) => _stopMatchesOrigin(stop, origin));
        if (originIndex < 0) continue;
        for (final stop in stops.skip(originIndex + 1)) {
          if (!stopReachesDestination(stop, destination)) continue;
          return DirectLineOption(
            line: line,
            direction: direction,
            departure: departureTime,
            arrival: stop.arrival,
          );
        }
      }
      return null;
    }));
    for (final option in found.whereType<DirectLineOption>()) {
      final current = options[option.line];
      if (current == null || option.departure.isBefore(current.departure)) {
        options[option.line] = option;
      }
    }
  }
  return options.values.toList()
    ..sort((a, b) => a.departure.compareTo(b.departure));
}

class OnBoardOption {
  final RideStop alight;
  final Map<String, dynamic> onwardJourney;
  final DateTime arrival;
  final int transfers;

  const OnBoardOption({
    required this.alight,
    required this.onwardJourney,
    required this.arrival,
    required this.transfers,
  });
}

/// Searches only after the rider can physically leave the selected vehicle.
Future<List<OnBoardOption>> findOnBoardOptions({
  required List<RideStop> stops,
  required int nextStopIndex,
  required Station destination,
  required String? currentTripId,
  required String currentLine,
  required bool nahverkehrOnly,
  void Function(List<OnBoardOption>)? onProgress,
  bool Function()? shouldContinue,
  Future<List<Map<String, dynamic>>> Function(
    Station from,
    Station to,
    DateTime earliest,
  )? searchFromStop,
}) async {
  final options = <OnBoardOption>[];
  final candidates = stops.skip(nextStopIndex).toList();
  for (var offset = 0; offset < candidates.length; offset += 4) {
    if (shouldContinue?.call() == false) break;
    final batch = candidates.skip(offset).take(4);
    final results = await Future.wait(batch.map((stop) async {
      try {
        final earliest = stop.arrival.add(const Duration(minutes: 2));
        final journeys = await (searchFromStop?.call(
              stop.station,
              destination,
              earliest,
            ) ??
            TransportApi.searchJourneys(
              stop.station,
              destination,
              when: earliest,
              results: 7,
              nahverkehrOnly: nahverkehrOnly,
              enrichPlatforms: false,
              enrichCoupledLines: false,
              shouldContinue: shouldContinue,
            ));
        for (final journey in journeys) {
          final legs = (journey['legs'] as List?)?.whereType<Map>().toList();
          if (legs == null || legs.isEmpty) continue;
          final first = Map<String, dynamic>.from(legs.first);
          final start = _time(first['departure'] ?? first['plannedDeparture']);
          if (start == null || start.isBefore(stop.arrival)) continue;
          final firstRide = legs.firstWhere(
            (leg) => leg['line'] != null,
            orElse: () => const {},
          );
          final ride = Map<String, dynamic>.from(firstRide);
          final line = _map(ride['line']);
          final tripId = (ride['tripId'] ?? line?['tripId'])?.toString();
          if (currentTripId != null && tripId == currentTripId) continue;
          final rideDeparture =
              _time(ride['departure'] ?? ride['plannedDeparture']);
          if (line?['name']?.toString().trim().toUpperCase() ==
                  currentLine.trim().toUpperCase() &&
              rideDeparture != null &&
              rideDeparture.difference(stop.arrival).abs() <=
                  const Duration(minutes: 1)) {
            continue;
          }
          final last = Map<String, dynamic>.from(legs.last);
          final arrival = _time(last['arrival'] ?? last['plannedArrival']);
          if (arrival == null) continue;
          return OnBoardOption(
            alight: stop,
            onwardJourney: journey,
            arrival: arrival,
            transfers: legs.where((leg) => leg['line'] != null).length,
          );
        }
      } catch (_) {
        // A single stop with no routing data must not hide the other stops.
      }
      return null;
    }));
    options.addAll(results.whereType<OnBoardOption>());
    options.sort((a, b) => a.arrival.compareTo(b.arrival));
    onProgress?.call(List<OnBoardOption>.from(options));
  }
  return options;
}
