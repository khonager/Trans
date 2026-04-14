import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trans/services/notification_manager.dart';
import 'package:trans/services/wake_alarm_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await WakeAlarmSettings.clearCustomSound();
  });

  tearDown(() async {
    await WakeAlarmSettings.clearCustomSound();
    debugDefaultTargetPlatformOverride = null;
  });

  test('keeps bundled iOS alarm sounds when available', () {
    final details = NotificationManager.buildWakeAlarmIosDetails(
      soundId: WakeAlarmSettings.defaultSoundId,
      soundEnabled: true,
    );

    expect(details.presentSound, isTrue);
    expect(details.sound, 'station_chime.wav');
  });

  test('falls back to the default iOS notification sound for custom audio',
      () async {
    final customSound = await WakeAlarmSettings.addCustomSound(
      id: 'custom_test_sound',
      localFilePath: '/tmp/custom_test_sound.mp3',
      fileName: 'custom_test_sound.mp3',
      label: 'Custom test sound',
    );

    final details = NotificationManager.buildWakeAlarmIosDetails(
      soundId: customSound.id,
      soundEnabled: true,
    );

    expect(details.presentSound, isTrue);
    expect(details.sound, isNull);
  });
}
