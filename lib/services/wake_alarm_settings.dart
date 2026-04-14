import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WakeAlarmSoundOption {
  const WakeAlarmSoundOption({
    required this.id,
    required this.label,
    this.playSound = true,
    this.fileName,
    this.androidResourceName,
    this.localFilePath,
  });

  final String id;
  final String label;
  final bool playSound;
  final String? fileName;
  final String? androidResourceName;
  final String? localFilePath;

  bool get isBundledSound =>
      playSound && fileName != null && androidResourceName != null;

  bool get isCustomSound => playSound && localFilePath != null;

  String? get assetPath => fileName == null ? null : 'assets/sounds/$fileName';

  AndroidNotificationSound? get androidSound {
    if (androidResourceName != null) {
      return RawResourceAndroidNotificationSound(androidResourceName!);
    }
    if (localFilePath != null) {
      return UriAndroidNotificationSound(Uri.file(localFilePath!).toString());
    }
    return null;
  }
}

class WakeAlarmSettings {
  static const String soundPreferenceKey = 'wake_alarm_sound';
  static const String customSoundsPreferenceKey = 'wake_alarm_custom_sounds';
  static const String customSoundPathPreferenceKey = 'wake_alarm_custom_path';
  static const String customSoundLabelPreferenceKey = 'wake_alarm_custom_label';
  static const String customSoundFileNamePreferenceKey =
      'wake_alarm_custom_file_name';
  static const String wakeSoundEnabledPreferenceKey =
      'wake_alarm_sound_enabled';
  static const String wakeVibrationEnabledPreferenceKey =
      'wake_alarm_vibration_enabled';
  static const String leaveSoundEnabledPreferenceKey =
      'leave_alarm_sound_enabled';
  static const String leaveVibrationEnabledPreferenceKey =
      'leave_alarm_vibration_enabled';
  static const String defaultSoundId = 'station_chime';
  static const String silentSoundId = 'silent';

  static const List<WakeAlarmSoundOption> _bundledSoundOptions = [
    WakeAlarmSoundOption(
      id: silentSoundId,
      label: 'None',
      playSound: false,
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

  static List<WakeAlarmSoundOption> _customSoundOptions =
      <WakeAlarmSoundOption>[];

  static List<WakeAlarmSoundOption> get soundOptions {
    final options = <WakeAlarmSoundOption>[
      ..._bundledSoundOptions,
      ..._customSoundOptions,
    ];
    return List.unmodifiable(options);
  }

  static WakeAlarmSoundOption soundForId(String? id) {
    return soundOptions.firstWhere(
      (option) => option.id == id,
      orElse: () => soundOptions.firstWhere(
        (option) => option.id == defaultSoundId,
      ),
    );
  }

  static String soundIdForPreference(String? id) {
    return soundForId(id).id;
  }

  static List<WakeAlarmSoundOption> get bundledSoundOptions => soundOptions
      .where((option) => option.isBundledSound)
      .toList(growable: false);

  static bool get hasCustomSound => _customSoundOptions.isNotEmpty;

  static List<WakeAlarmSoundOption> get customSoundOptions =>
      List.unmodifiable(_customSoundOptions);

  static bool isCustomSoundId(String? id) =>
      id != null && _customSoundOptions.any((option) => option.id == id);

  static Future<void> loadPersistedCustomSound() async {
    final prefs = await SharedPreferences.getInstance();
    final encodedOptions = prefs.getStringList(customSoundsPreferenceKey);
    if (encodedOptions != null && encodedOptions.isNotEmpty) {
      _customSoundOptions = encodedOptions
          .map(_decodeCustomSoundOption)
          .whereType<WakeAlarmSoundOption>()
          .toList(growable: true);
      return;
    }

    final path = prefs.getString(customSoundPathPreferenceKey);
    final label = prefs.getString(customSoundLabelPreferenceKey);
    final fileName = prefs.getString(customSoundFileNamePreferenceKey);

    if (path == null || path.isEmpty || fileName == null || fileName.isEmpty) {
      _customSoundOptions = <WakeAlarmSoundOption>[];
      return;
    }

    _customSoundOptions = <WakeAlarmSoundOption>[
      WakeAlarmSoundOption(
        id: 'custom_${DateTime.now().microsecondsSinceEpoch}',
        label: label?.isNotEmpty == true ? label! : 'Custom audio',
        fileName: fileName,
        localFilePath: path,
      ),
    ];
    await _persistCustomSoundOptions();
  }

  static Future<WakeAlarmSoundOption> addCustomSound({
    required String id,
    required String localFilePath,
    required String fileName,
    required String label,
  }) async {
    final option = WakeAlarmSoundOption(
      id: id,
      label: label,
      fileName: fileName,
      localFilePath: localFilePath,
    );
    _customSoundOptions = [
      ..._customSoundOptions.where((existing) => existing.id != id),
      option,
    ];
    await _persistCustomSoundOptions();
    return option;
  }

  static Future<void> removeCustomSound(String id) async {
    _customSoundOptions =
        _customSoundOptions.where((option) => option.id != id).toList();
    await _persistCustomSoundOptions();
  }

  static Future<void> clearCustomSound() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(customSoundsPreferenceKey);
    await prefs.remove(customSoundPathPreferenceKey);
    await prefs.remove(customSoundFileNamePreferenceKey);
    await prefs.remove(customSoundLabelPreferenceKey);
    _customSoundOptions = <WakeAlarmSoundOption>[];
  }

  static WakeAlarmSoundOption? _decodeCustomSoundOption(String encoded) {
    try {
      final map = jsonDecode(encoded) as Map<String, dynamic>;
      final id = map['id']?.toString();
      final label = map['label']?.toString();
      final fileName = map['fileName']?.toString();
      final localFilePath = map['localFilePath']?.toString();
      if (id == null ||
          label == null ||
          fileName == null ||
          localFilePath == null ||
          id.isEmpty ||
          label.isEmpty ||
          fileName.isEmpty ||
          localFilePath.isEmpty) {
        return null;
      }
      return WakeAlarmSoundOption(
        id: id,
        label: label,
        fileName: fileName,
        localFilePath: localFilePath,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _persistCustomSoundOptions() async {
    final prefs = await SharedPreferences.getInstance();
    final encodedOptions = _customSoundOptions
        .map(
          (option) => jsonEncode({
            'id': option.id,
            'label': option.label,
            'fileName': option.fileName,
            'localFilePath': option.localFilePath,
          }),
        )
        .toList(growable: false);
    await prefs.setStringList(customSoundsPreferenceKey, encodedOptions);
    await prefs.remove(customSoundPathPreferenceKey);
    await prefs.remove(customSoundFileNamePreferenceKey);
    await prefs.remove(customSoundLabelPreferenceKey);
  }

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
