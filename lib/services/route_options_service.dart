import 'package:trans/models/journey.dart';
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

/// Distinct first vehicles from every loaded journey, including journeys that
/// reach the destination after a transfer. The caller keeps adding results
/// when the traveller loads earlier or later connections.
List<String> availableFirstLines(Iterable<Journey> journeys) {
  final names = <String>{};
  for (final journey in journeys) {
    for (final step in journey.steps) {
      if (step.type != 'ride') continue;
      final name = step.line.trim();
      if (name.isNotEmpty && name != '?') names.add(name);
      break;
    }
  }
  return sortLineNames(names);
}

List<String> sortLineNames(Iterable<String> names) {
  final result = names.toSet().toList();
  result.sort((a, b) {
    final aNumber = int.tryParse(a);
    final bNumber = int.tryParse(b);
    if (aNumber != null && bNumber != null) return aNumber.compareTo(bNumber);
    if (aNumber != null) return -1;
    if (bNumber != null) return 1;
    return a.compareTo(b);
  });
  return result;
}

bool _matchesStation(RideStop stop, Station station, double maxMeters) {
  if (stop.id == station.id) return true;
  final lat = stop.latitude;
  final lon = stop.longitude;
  final stationLat = station.latitude;
  final stationLon = station.longitude;
  if (lat == null || lon == null || stationLat == null || stationLon == null) {
    return false;
  }
  final latMeters = (lat - stationLat) * 111200;
  final lonMeters = (lon - stationLon) * 111200 * 0.7;
  return latMeters * latMeters + lonMeters * lonMeters <= maxMeters * maxMeters;
}

/// Adds direct first lines that a journey planner may omit from its preferred
/// results. Timetable lookup is optional; loaded journeys remain the primary
/// source of the line list when a provider cannot serve trips.
Future<List<String>> discoverDirectFirstLines({
  required Station origin,
  required Station destination,
  required DateTime date,
  Future<List<Map<String, dynamic>>> Function(
    String stopId, {
    DateTime? date,
    int maxResults,
  })? loadDepartures,
  Future<Map<String, dynamic>?> Function(String tripId)? loadTrip,
}) async {
  if (origin.id.isEmpty) return [];
  final departures = await (loadDepartures?.call(
        origin.id,
        date: date,
        maxResults: 1200,
      ) ??
      TransportApi.fetchStopDepartures(
        origin.id,
        date: date,
        maxResults: 1200,
      ));
  departures.sort((a, b) {
    final first = TransportApi.stopDepartureTime(a);
    final second = TransportApi.stopDepartureTime(b);
    if (first == null) return 1;
    if (second == null) return -1;
    return first.compareTo(second);
  });

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
    if ((sampleCounts[key] ?? 0) >= 2) continue;
    sampleCounts[key] = (sampleCounts[key] ?? 0) + 1;
    samples.add(departure);
  }

  final found = <String>{};
  for (var offset = 0; offset < samples.length; offset += 6) {
    final batch = samples.skip(offset).take(6);
    final checked = await Future.wait(batch.map((departure) async {
      final tripId = TransportApi.stopDepartureTripId(departure)!;
      Map<String, dynamic>? journey;
      try {
        journey = await (loadTrip?.call(tripId) ??
            TransportApi.fetchLiveTripJourney(tripId));
      } catch (_) {
        return null;
      }
      final legs = (journey?['legs'] as List?)?.whereType<Map>();
      if (legs == null) return null;
      for (final rawLeg in legs) {
        final stops = rideStopsFromLeg(Map<String, dynamic>.from(rawLeg));
        final originIndex =
            stops.indexWhere((stop) => _matchesStation(stop, origin, 100));
        if (originIndex < 0) continue;
        if (stops.skip(originIndex + 1).any(
              (stop) => _matchesStation(stop, destination, 150),
            )) {
          return (departure['routeShortName'] ??
                  departure['displayName'] ??
                  _map(departure['line'])?['name'])
              .toString();
        }
      }
      return null;
    }));
    found.addAll(checked.whereType<String>());
  }
  return sortLineNames(found);
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
