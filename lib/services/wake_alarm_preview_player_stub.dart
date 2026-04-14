import 'wake_alarm_settings.dart';

class WakeAlarmPreviewPlayer {
  static Future<bool> play(WakeAlarmSoundOption sound) async {
    return !sound.playSound;
  }

  static Future<void> stop() async {}
}
