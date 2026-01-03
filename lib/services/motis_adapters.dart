// lib/services/motis_adapters.dart
// Adapters to convert MOTIS API responses to existing app formats

import '../models/station.dart';

/// Converts MOTIS geocode Match → Station
/// MOTIS format: { type: "STOP"|"ADDRESS"|"PLACE", name, id, lat, lon, areas }
Station stationFromMotisMatch(Map<String, dynamic> match) {
  String type = 'station';
  final motisType = match['type'] as String?;
  if (motisType == 'ADDRESS') type = 'address';
  if (motisType == 'PLACE') type = 'location';

  return Station(
    id: match['id']?.toString() ?? '',
    name: match['name'] ?? 'Unknown',
    type: type,
    latitude: (match['lat'] as num?)?.toDouble(),
    longitude: (match['lon'] as num?)?.toDouble(),
  );
}

/// Converts MOTIS Place → location map for journey legs
Map<String, dynamic> _placeToLocation(Map<String, dynamic> place) {
  return {
    'id': place['stopId'] ?? '',
    'name': place['name'] ?? '',
    'type': place['vertexType'] == 'TRANSIT' ? 'stop' : 'location',
    'location': {
      'latitude': place['lat'],
      'longitude': place['lon'],
    },
    // Pass through track/platform info if present
    if (place['track'] != null) 'platform': place['track'],
    if (place['scheduledTrack'] != null) 'scheduledPlatform': place['scheduledTrack'],
  };
}

/// Extracts line/product info from MOTIS leg
Map<String, dynamic> _extractLineInfo(Map<String, dynamic> leg) {
  final mode = leg['mode'] as String? ?? 'WALK';
  
  return {
    'name': leg['displayName'] ?? leg['routeShortName'] ?? mode,
    'productName': _modeToProduct(mode),
    'mode': mode,
    'product': {
      'type': _modeToProduct(mode),
      'name': leg['routeLongName'] ?? leg['routeShortName'],
      'short': leg['routeShortName'],
      'color': {
        if (leg['routeColor'] != null) 'bg': '#${leg['routeColor']}',
        if (leg['routeTextColor'] != null) 'fg': '#${leg['routeTextColor']}',
      },
    },
    if (leg['tripId'] != null) 'tripId': leg['tripId'],
    if (leg['agencyName'] != null) 'operator': {'name': leg['agencyName']},
  };
}

/// Maps MOTIS mode to v6.db product type
String _modeToProduct(String mode) {
  switch (mode) {
    case 'HIGHSPEED_RAIL':
      return 'nationalExpress';
    case 'LONG_DISTANCE':
    case 'NIGHT_RAIL':
      return 'national';
    case 'REGIONAL_FAST_RAIL':
    case 'REGIONAL_RAIL':
      return 'regional';
    case 'SUBURBAN':
      return 'suburban';
    case 'SUBWAY':
      return 'subway';
    case 'TRAM':
      return 'tram';
    case 'BUS':
      return 'bus';
    case 'COACH':
      return 'bus';
    case 'FERRY':
      return 'ferry';
    case 'WALK':
      return 'walking';
    default:
      return mode.toLowerCase();
  }
}

/// Converts stopovers from MOTIS intermediateStops format
List<Map<String, dynamic>> _convertIntermediateStops(List<dynamic>? stops) {
  if (stops == null) return [];
  
  return stops.map((stop) {
    final s = stop as Map<String, dynamic>;
    return {
      'stop': _placeToLocation(s),
      'arrival': s['arrival'],
      'departure': s['departure'],
      'plannedArrival': s['scheduledArrival'],
      'plannedDeparture': s['scheduledDeparture'],
      'arrivalDelay': _calculateDelay(s['scheduledArrival'], s['arrival']),
      'departureDelay': _calculateDelay(s['scheduledDeparture'], s['departure']),
      if (s['cancelled'] == true) 'cancelled': true,
      if (s['track'] != null) 'platform': s['track'],
    };
  }).toList();
}

/// Calculate delay in seconds from scheduled vs actual times
int? _calculateDelay(String? scheduled, String? actual) {
  if (scheduled == null || actual == null) return null;
  try {
    final scheduledTime = DateTime.parse(scheduled);
    final actualTime = DateTime.parse(actual);
    return actualTime.difference(scheduledTime).inSeconds;
  } catch (e) {
    return null;
  }
}

/// Converts MOTIS Leg → v6.db leg format expected by UI
Map<String, dynamic> legFromMotisLeg(Map<String, dynamic> leg) {
  final mode = leg['mode'] as String? ?? 'WALK';
  final isWalking = mode == 'WALK' || mode == 'BIKE' || mode == 'CAR';
  
  return {
    'origin': _placeToLocation(leg['from']),
    'destination': _placeToLocation(leg['to']),
    'departure': leg['startTime'],
    'arrival': leg['endTime'],
    'plannedDeparture': leg['scheduledStartTime'],
    'plannedArrival': leg['scheduledEndTime'],
    'departureDelay': _calculateDelay(leg['scheduledStartTime'], leg['startTime']),
    'arrivalDelay': _calculateDelay(leg['scheduledEndTime'], leg['endTime']),
    'reachable': true,
    if (leg['cancelled'] == true) 'cancelled': true,
    
    // Walking legs
    if (isWalking) 'walking': true,
    if (isWalking && leg['distance'] != null) 'distance': leg['distance'],
    
    // Transit legs
    if (!isWalking) 'line': _extractLineInfo(leg),
    if (!isWalking) 'direction': leg['headsign'],
    
    // Stopovers / intermediate stops
    if (leg['intermediateStops'] != null) 
      'stopovers': _convertIntermediateStops(leg['intermediateStops']),
    
    // Polyline - MOTIS uses Google polyline format
    if (leg['legGeometry'] != null) 'polyline': {
      'points': leg['legGeometry']['points'],
      'precision': leg['legGeometry']['precision'] ?? 6,
    },
  };
}

/// Converts MOTIS Itinerary → Journey format expected by UI
/// This is the main entry point for journey conversion
Map<String, dynamic> journeyFromMotisItinerary(Map<String, dynamic> itinerary) {
  final legs = (itinerary['legs'] as List?) ?? [];
  
  return {
    'type': 'journey',
    'legs': legs.map((leg) => legFromMotisLeg(leg as Map<String, dynamic>)).toList(),
    
    // Journey-level timing
    'departure': itinerary['startTime'],
    'arrival': itinerary['endTime'],
    
    // Duration in seconds
    if (itinerary['duration'] != null) 'duration': itinerary['duration'],
    
    // Transfer count
    if (itinerary['transfers'] != null) 'transfers': itinerary['transfers'],
  };
}
