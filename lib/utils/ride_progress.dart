import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:trans/models/journey.dart';

/// The interval after a stop (0 is boarding) and the fraction toward the next.
class RideProgress {
  final int interval;
  final double fraction;

  const RideProgress(this.interval, this.fraction);
}

/// Projects the GPS fix onto the ride shape, then locates it between stops.
/// Returns null when the fix is too far from the ride to be trustworthy.
RideProgress? rideProgressFor(JourneyStep step, Position position) {
  if (DateTime.now().difference(position.timestamp) >
      const Duration(minutes: 2)) {
    return null;
  }
  if (step.type != 'ride' ||
      step.startLat == null ||
      step.startLng == null ||
      step.endLat == null ||
      step.endLng == null ||
      position.accuracy > 250) {
    return null;
  }

  final stops = <(double, double)>[(step.startLat!, step.startLng!)];
  for (final item in step.stopovers ?? const []) {
    if (item is! Map) continue;
    final location = item['stop']?['location'];
    if (location is! Map) return null;
    final lat = (location['latitude'] as num?)?.toDouble();
    final lng = (location['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    stops.add((lat, lng));
  }
  stops.add((step.endLat!, step.endLng!));

  final shape = <(double, double)>[];
  for (final item in step.path ?? const []) {
    if (item is List && item.length >= 2 && item[0] is num && item[1] is num) {
      shape.add(((item[0] as num).toDouble(), (item[1] as num).toDouble()));
    }
  }
  var points = shape.length >= 2 ? shape : stops;
  if (points.length < 2) return null;

  final latitudeScale = math.cos(position.latitude * math.pi / 180);
  double distance((double, double) a, (double, double) b) {
    final dy = (a.$1 - b.$1) * 111195;
    final dx = (a.$2 - b.$2) * 111195 * latitudeScale;
    return math.sqrt(dx * dx + dy * dy);
  }

  if (shape.length >= 2 &&
      distance(stops.first, points.last) <
          distance(stops.first, points.first)) {
    points = points.reversed.toList();
  }

  (double, double) project(
      (double, double) point, (double, double) start, (double, double) end) {
    final dx = (end.$2 - start.$2) * latitudeScale;
    final dy = end.$1 - start.$1;
    final lengthSquared = dx * dx + dy * dy;
    if (lengthSquared == 0) return (0, distance(point, start));
    final fraction = (((point.$2 - start.$2) * latitudeScale * dx +
                (point.$1 - start.$1) * dy) /
            lengthSquared)
        .clamp(0.0, 1.0);
    final projected = (
      start.$1 + (end.$1 - start.$1) * fraction,
      start.$2 + (end.$2 - start.$2) * fraction
    );
    return (fraction, distance(point, projected));
  }

  final lengths = <double>[0];
  for (var i = 1; i < points.length; i++) {
    lengths.add(lengths.last + distance(points[i - 1], points[i]));
  }
  if (lengths.last == 0) return null;

  double along((double, double) point) {
    var bestDistance = double.infinity;
    var bestAlong = 0.0;
    for (var i = 1; i < points.length; i++) {
      final result = project(point, points[i - 1], points[i]);
      if (result.$2 < bestDistance) {
        bestDistance = result.$2;
        bestAlong = lengths[i - 1] + (lengths[i] - lengths[i - 1]) * result.$1;
      }
    }
    return bestAlong;
  }

  final fix = (position.latitude, position.longitude);
  var nearestDistance = double.infinity;
  for (var i = 1; i < points.length; i++) {
    nearestDistance =
        math.min(nearestDistance, project(fix, points[i - 1], points[i]).$2);
  }
  if (nearestDistance > math.max(150, position.accuracy * 2)) return null;

  // Stop coordinates can be slightly off the supplied shape. Keep their
  // positions ordered, so a loop in the route cannot reverse the stop list.
  final stopDistances = <double>[0];
  for (var i = 1; i < stops.length - 1; i++) {
    stopDistances.add(along(stops[i]).clamp(stopDistances.last, lengths.last));
  }
  stopDistances.add(lengths.last);
  final progress = along(fix);
  for (var i = 0; i < stopDistances.length - 1; i++) {
    if (progress <= stopDistances[i + 1] || i == stopDistances.length - 2) {
      final span = stopDistances[i + 1] - stopDistances[i];
      return RideProgress(
          i,
          span == 0
              ? 1
              : ((progress - stopDistances[i]) / span).clamp(0.0, 1.0));
    }
  }
  return null;
}
