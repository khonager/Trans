/// Provider legs for a route built from several consecutive searches.
/// The first leg of each appended section carries a marker so the timeline
/// can keep its visible boundary after the journey is rebuilt.
const routeExtensionStartKey = 'transRouteExtensionStart';

/// A provider may start an onward itinerary with an access walk before the
/// search time, even though its first vehicle leaves later. Check whether
/// that access can actually be completed after the preceding route arrives.
bool canCatchOnwardJourney({
  required DateTime previousArrival,
  required Map<String, dynamic> onward,
}) {
  final legs = (onward['legs'] as List?)?.whereType<Map>().toList();
  if (legs == null || legs.isEmpty) return false;
  // The planner displays and searches in whole minutes.
  final availableAt = DateTime(
    previousArrival.year,
    previousArrival.month,
    previousArrival.day,
    previousArrival.hour,
    previousArrival.minute,
  );
  final first = legs.first;
  final firstDeparture = DateTime.tryParse(
    (first['departure'] ?? first['plannedDeparture'] ?? '').toString(),
  )?.toLocal();
  if (firstDeparture == null) return false;
  if (!firstDeparture.isBefore(availableAt)) return true;

  var accessDuration = Duration.zero;
  for (final leg in legs) {
    final departure = DateTime.tryParse(
      (leg['departure'] ?? leg['plannedDeparture'] ?? '').toString(),
    )?.toLocal();
    final arrival = DateTime.tryParse(
      (leg['arrival'] ?? leg['plannedArrival'] ?? '').toString(),
    )?.toLocal();
    if (departure == null || arrival == null || arrival.isBefore(departure)) {
      return false;
    }
    if (leg['line'] is Map && (leg['line'] as Map)['name'] != null) {
      return !departure.isBefore(availableAt.add(accessDuration));
    }
    accessDuration += arrival.difference(departure);
  }
  final lastArrival = DateTime.tryParse(
    (legs.last['arrival'] ?? legs.last['plannedArrival'] ?? '').toString(),
  )?.toLocal();
  return lastArrival != null &&
      !lastArrival.isBefore(availableAt.add(accessDuration));
}

Map<String, dynamic> appendJourneyData({
  required Map<String, dynamic> original,
  required Map<String, dynamic> onward,
}) {
  final originalLegs = (original['legs'] as List?) ?? const [];
  final onwardLegs = (onward['legs'] as List?) ?? const [];
  if (originalLegs.isEmpty || onwardLegs.isEmpty) {
    throw ArgumentError('Both routes need legs');
  }
  final firstOnward = Map<String, dynamic>.from(onwardLegs.first as Map);
  firstOnward[routeExtensionStartKey] = true;
  final legs = [
    ...originalLegs,
    firstOnward,
    ...onwardLegs.skip(1),
  ];
  final result = Map<String, dynamic>.from(original)
    ..['legs'] = legs
    ..['arrival'] =
        (legs.last as Map)['arrival'] ?? (legs.last as Map)['plannedArrival'];
  result.remove('duration');
  result.remove('transfers');
  return result;
}
