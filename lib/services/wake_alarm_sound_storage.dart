import 'wake_alarm_settings.dart';
import 'wake_alarm_sound_storage_stub.dart'
    if (dart.library.io) 'wake_alarm_sound_storage_io.dart' as impl;

Future<void> ensureDarwinWakeAlarmSounds(List<WakeAlarmSoundOption> sounds) {
  return impl.ensureDarwinWakeAlarmSounds(sounds);
}
