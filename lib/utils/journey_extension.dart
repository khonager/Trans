/// Provider legs for a route built from several consecutive searches.
/// The first leg of each appended section carries a marker so the timeline
/// can keep its visible boundary after the journey is rebuilt.
const routeExtensionStartKey = 'transRouteExtensionStart';

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
