import 'dart:math' as math;

/// A balanced background fix is enough while far away. Near the target, use
/// its reported accuracy to decide whether a precise fix is needed.
class WakeLocationPolicy {
  static double allowedAccuracy(double triggerDistanceMeters) =>
      math.max(25, math.min(100, triggerDistanceMeters / 2));

  static bool isNearTarget({
    required double distanceMeters,
    required double accuracyMeters,
    required double triggerDistanceMeters,
  }) =>
      distanceMeters - math.min(accuracyMeters, 500) <=
      math.max(1500, triggerDistanceMeters + 750);

  static bool isAccurateEnough({
    required double accuracyMeters,
    required double triggerDistanceMeters,
  }) =>
      accuracyMeters <= allowedAccuracy(triggerDistanceMeters);

  static bool canTrigger({
    required double distanceMeters,
    required double accuracyMeters,
    required double triggerDistanceMeters,
  }) =>
      distanceMeters <= triggerDistanceMeters &&
      (isAccurateEnough(
            accuracyMeters: accuracyMeters,
            triggerDistanceMeters: triggerDistanceMeters,
          ) ||
          distanceMeters + accuracyMeters <= triggerDistanceMeters);
}
