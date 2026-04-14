import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

class ForegroundHaptics {
  static const MethodChannel _channel =
      MethodChannel('de.khonager.trans/ios_haptics');

  static Future<void> vibratePattern(
    List<int> pattern, {
    int? intensity,
  }) async {
    if (kIsWeb || pattern.isEmpty) return;

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _channel.invokeMethod<void>('vibratePattern', {
        'pattern': pattern,
      });
      return;
    }

    if (!await Vibration.hasVibrator()) return;

    if (await Vibration.hasAmplitudeControl() && intensity != null) {
      final intensities = List<int>.generate(
        pattern.length,
        (i) => i.isEven ? 0 : intensity,
      );
      await Vibration.vibrate(pattern: pattern, intensities: intensities);
      return;
    }

    await Vibration.vibrate(pattern: pattern);
  }

  static Future<bool> hasVibrator() async {
    if (kIsWeb) return false;
    if (defaultTargetPlatform == TargetPlatform.iOS) return true;
    return await Vibration.hasVibrator();
  }
}
