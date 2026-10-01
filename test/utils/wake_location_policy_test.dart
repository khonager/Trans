import 'package:flutter_test/flutter_test.dart';
import 'package:trans/utils/wake_location_policy.dart';

void main() {
  test('keeps precise tracking off far from the alarm', () {
    expect(
        WakeLocationPolicy.isNearTarget(
          distanceMeters: 8000,
          accuracyMeters: 100,
          triggerDistanceMeters: 500,
        ),
        isFalse);
  });

  test('uses a shared accurate fix near the alarm', () {
    expect(
        WakeLocationPolicy.isNearTarget(
          distanceMeters: 1200,
          accuracyMeters: 20,
          triggerDistanceMeters: 100,
        ),
        isTrue);
    expect(
        WakeLocationPolicy.isAccurateEnough(
          accuracyMeters: 20,
          triggerDistanceMeters: 100,
        ),
        isTrue);
  });

  test('very uncertain distant fixes do not keep precise tracking on', () {
    expect(
        WakeLocationPolicy.isNearTarget(
          distanceMeters: 5000,
          accuracyMeters: 5000,
          triggerDistanceMeters: 500,
        ),
        isFalse);
  });

  test('waits for a precise fix when the uncertainty spans a small target', () {
    expect(
        WakeLocationPolicy.canTrigger(
          distanceMeters: 30,
          accuracyMeters: 80,
          triggerDistanceMeters: 50,
        ),
        isFalse);
  });

  test('allows a coarse fix wholly inside a wide alarm radius', () {
    expect(
        WakeLocationPolicy.canTrigger(
          distanceMeters: 100,
          accuracyMeters: 80,
          triggerDistanceMeters: 500,
        ),
        isTrue);
  });
}
