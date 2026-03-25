import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class WakeAlarmSoundOption {
  const WakeAlarmSoundOption({
    required this.id,
    required this.label,
    this.fileName,
    this.androidResourceName,
  });

  final String id;
  final String label;
  final String? fileName;
  final String? androidResourceName;

  bool get usesPlatformDefault =>
      fileName == null || androidResourceName == null;

  String? get assetPath => fileName == null ? null : 'assets/sounds/$fileName';

  AndroidNotificationSound? get androidSound => androidResourceName == null
      ? null
      : RawResourceAndroidNotificationSound(androidResourceName!);
}

class WakeAlarmSettings {
  static const String soundPreferenceKey = 'wake_alarm_sound';
  static const String defaultSoundId = 'system_default';

  static const List<WakeAlarmSoundOption> soundOptions = [
    WakeAlarmSoundOption(
      id: defaultSoundId,
      label: 'System Default',
    ),
    WakeAlarmSoundOption(
      id: 'station_chime',
      label: 'Station Chime',
      fileName: 'station_chime.wav',
      androidResourceName: 'station_chime',
    ),
    WakeAlarmSoundOption(
      id: 'tram_bell',
      label: 'Tram Bell',
      fileName: 'tram_bell.wav',
      androidResourceName: 'tram_bell',
    ),
    WakeAlarmSoundOption(
      id: 'platform_ping',
      label: 'Platform Ping',
      fileName: 'platform_ping.wav',
      androidResourceName: 'platform_ping',
    ),
    WakeAlarmSoundOption(
      id: 'conductor_whistle',
      label: 'Conductor Whistle',
      fileName: 'conductor_whistle.wav',
      androidResourceName: 'conductor_whistle',
    ),
  ];

  static WakeAlarmSoundOption soundForId(String? id) {
    return soundOptions.firstWhere(
      (option) => option.id == id,
      orElse: () => soundOptions.first,
    );
  }

  static List<WakeAlarmSoundOption> get bundledSoundOptions => soundOptions
      .where((option) => !option.usesPlatformDefault)
      .toList(growable: false);

  static List<int> vibrationPatternForId(String patternName) {
    switch (patternName) {
      case 'heartbeat':
        return [0, 100, 100, 250, 600, 100, 100, 250];
      case 'tick':
        return [0, 30];
      case 'mario':
        return [0, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 200];
      case 'fox':
        return [
          0,
          100,
          100,
          100,
          100,
          100,
          100,
          100,
          150,
          100,
          150,
          100,
          150,
          100,
          400,
        ];
      case 'imperial':
        return [
          0,
          450,
          150,
          450,
          150,
          450,
          150,
          350,
          100,
          150,
          450,
          150,
          350,
          100,
          150,
          450,
        ];
      case 'potter':
        return [
          0,
          150,
          350,
          150,
          100,
          150,
          100,
          150,
          100,
          400,
          300,
          300,
          150,
          400,
        ];
      case 'indy':
        return [
          0,
          150,
          50,
          80,
          50,
          150,
          100,
          500,
          400,
          150,
          50,
          80,
          100,
          600,
        ];
      case 'mission':
        return [
          0,
          250,
          250,
          250,
          250,
          120,
          120,
          120,
          120,
          250,
          250,
          250,
          250,
          120,
          120,
          120,
          120,
        ];
      case 'terminator':
        return [0, 250, 250, 250, 400, 200, 200, 250, 200, 250];
      case 'future':
        return [0, 150, 150, 150, 150, 300, 200, 100, 50, 100, 50, 400];
      case 'eva':
        return [
          0,
          100,
          100,
          100,
          100,
          250,
          100,
          100,
          100,
          100,
          100,
          100,
          250,
          100,
          100,
        ];
      case 'pokemon':
        return [0, 100, 100, 100, 100, 300, 150, 100, 100, 300];
      case 'titan':
        return [0, 200, 150, 200, 150, 250, 250, 400, 400, 600];
      case 'bebop':
        return [0, 150, 400, 150, 400, 150, 400, 150, 600, 1000];
      default:
        return [0, 500];
    }
  }
}
