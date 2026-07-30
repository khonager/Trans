import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import '../../services/notification_manager.dart';
import '../../services/foreground_haptics.dart';
import '../../services/color_claim_service.dart';
import '../../services/supabase_service.dart';
import '../../services/community_safety_service.dart';
import '../../services/wake_alarm_custom_sound_service.dart';
import '../../services/wake_alarm_settings.dart';
import '../../services/history_manager.dart';
import '../../config/app_theme.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../services/transport_api.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/app_error.dart';
import '../../models/journey_sharing.dart';
import '../changelog_screen.dart';
import '../../widgets/privacy_level_tutorial.dart';

@visibleForTesting
String deleteAccountErrorMessage(
  Object error, {
  required String invalidPasswordMessage,
  required String fallbackMessage,
}) {
  final lower = error.toString().toLowerCase();
  if (lower.contains('invalid login credentials') ||
      lower.contains('invalid credentials')) {
    return invalidPasswordMessage;
  }
  return fallbackMessage;
}

class SettingsTab extends StatefulWidget {
  final bool isDarkMode;
  final Function(bool) onThemeChanged;
  final bool useSystemTheme;
  final Function(bool) onSystemSyncChanged;
  final bool onlyNahverkehr;
  final Function(bool) onNahverkehrChanged;
  final int signalLevel;
  final Future<void> Function(int) onSignalLevelChanged;
  final Future<void> Function(Color) onColorChanged;
  final Color currentColor;
  final bool showTrainNumbers;
  final Function(bool) onShowTrainNumbersChanged;
  final bool alwaysWakeMe;
  final Function(bool) onAlwaysWakeMeChanged;
  final Locale? locale;
  final Function(Locale) onLocaleChanged;

  const SettingsTab({
    super.key,
    required this.isDarkMode,
    required this.onThemeChanged,
    required this.useSystemTheme,
    required this.onSystemSyncChanged,
    required this.onlyNahverkehr,
    required this.onNahverkehrChanged,
    required this.signalLevel,
    required this.onSignalLevelChanged,
    required this.onColorChanged,
    required this.currentColor,
    required this.showTrainNumbers,
    required this.onShowTrainNumbersChanged,
    required this.alwaysWakeMe,
    required this.onAlwaysWakeMeChanged,
    required this.locale,
    required this.onLocaleChanged,
  });

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  static const String _pickCustomSoundValue = '__pick_custom_sound__';
  static const int _hiddenManualAlarmNotificationId = 9002;
  static const int _advancedUnlockHoldSeconds = 7;
  static const int _advancedUnlockCountdownStartSeconds = 3;
  static const int _defaultAdvancedMinTransferTimeMinutes =
      TransportApi.defaultAdvancedMinTransferTimeMinutes;
  static const int _defaultAdvancedAdditionalTransferTimeMinutes =
      TransportApi.defaultAdvancedAdditionalTransferTimeMinutes;
  static const double _defaultAdvancedTransferTimeFactor =
      TransportApi.defaultAdvancedTransferTimeFactor;
  static const double _defaultAdvancedPedestrianSpeedKmh =
      TransportApi.defaultAdvancedPedestrianSpeedKmh;
  static const int _defaultAdvancedMaxWalkingTimeMinutes =
      TransportApi.defaultAdvancedMaxWalkingTimeMinutes;
  static const double _defaultAdvancedCyclingSpeedKmh =
      TransportApi.defaultAdvancedCyclingSpeedKmh;
  static const List<int> _hiddenManualTimerSecondOptions = [
    5,
    10,
    15,
    30,
    45,
    60,
    90,
    120,
    180,
    300,
  ];
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();

  bool _isLoginMode = true;

  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _myLocation;
  StreamSubscription? _locationSub;

  String _version = "";
  bool _isDevBuild = const bool.fromEnvironment('IS_DEV', defaultValue: false);
  bool _isUnstableBuild =
      const bool.fromEnvironment('IS_UNSTABLE', defaultValue: false);
  Timer? _hiddenManualAlarmTimer;
  DateTime? _hiddenManualAlarmTarget;
  bool _obscureAuthPassword = true;
  bool _isAuthSubmitting = false;
  int? _pendingThemeColorArgb;

  String _vibrationPattern = 'standard';
  int _vibrationIntensity = 128;
  String _wakeAlarmSound = WakeAlarmSettings.defaultSoundId;
  bool _wakeAlarmSoundEnabled = true;
  bool _wakeAlarmVibrationEnabled = true;
  bool _leaveAlarmSoundEnabled = true;
  bool _leaveAlarmVibrationEnabled = true;
  bool _isWakeAlarmPreviewPlaying = false;
  int _stopsBeforeAlarm = 1;
  Set<String> _enabledApiSources =
      Set<String>.from(TransportApi.defaultEnabledSources);
  String _alarmTriggerThreshold = '5%'; // NEW: '5%', '10%', or '500m'
  bool _advancedSettingsEnabledForDevice = false;
  int _advancedMinTransferTimeMinutes = _defaultAdvancedMinTransferTimeMinutes;
  int _advancedAdditionalTransferTimeMinutes =
      _defaultAdvancedAdditionalTransferTimeMinutes;
  double _advancedTransferTimeFactor = _defaultAdvancedTransferTimeFactor;
  bool _advancedPreTransitWalkEnabled = true;
  bool _advancedPreTransitBikeEnabled = false;
  bool _advancedPostTransitWalkEnabled = true;
  bool _advancedPostTransitBikeEnabled = false;
  double _advancedPedestrianSpeedKmh = _defaultAdvancedPedestrianSpeedKmh;
  int _advancedMaxWalkingTimeMinutes = _defaultAdvancedMaxWalkingTimeMinutes;
  double _advancedCyclingSpeedKmh = _defaultAdvancedCyclingSpeedKmh;
  Timer? _advancedUnlockTimer;
  Timer? _advancedCountdownTimer;
  DateTime? _advancedUnlockPressStart;
  int? _advancedUnlockCountdownSecondsLeft;
  bool _suppressNextChangelogTap = false;
  // Removed _alwaysWakeMe internal state

  @override
  void dispose() {
    _hiddenManualAlarmTimer?.cancel();
    _advancedUnlockTimer?.cancel();
    _advancedCountdownTimer?.cancel();
    _locationSub?.cancel();
    SupabaseService.settingsRefreshNotifier
        .removeListener(_handleSettingsRefresh);
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _usernameCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    SupabaseService.settingsRefreshNotifier.addListener(_handleSettingsRefresh);
    _loadProfile();
    _loadSettings();
    _loadVersion();
    _subscribeToLocation();
  }

  void _handleSettingsRefresh() {
    unawaited(_loadProfile());
    unawaited(_loadSettings());
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    final appNameLower = info.appName.toLowerCase();
    final isUnstablePackage = info.packageName.endsWith('.unstable');
    final isUnstableLabel = appNameLower.contains('unstable');
    final isDevPackage = info.packageName.endsWith('.dev');
    final isDevLabel = appNameLower.contains('dev');
    final detectedUnstableBuild = isUnstablePackage || isUnstableLabel;
    final detectedDevBuild =
        (isDevPackage || isDevLabel) && !detectedUnstableBuild;
    final unstableBuild = _isUnstableBuild || detectedUnstableBuild;
    if (mounted) {
      setState(() {
        _version = unstableBuild ? "" : info.version;
        _isUnstableBuild = unstableBuild;
        // Auto-enable DEV badge for dev flavor builds while keeping
        // IS_DEV as an optional manual override.
        _isDevBuild = _isDevBuild || detectedDevBuild;
      });
    }
  }

  void _subscribeToLocation() {
    _locationSub?.cancel();
    // Listen to changes, but fetch freshness from REST to be safe/consistent with FriendsTab
    _locationSub = SupabaseService.streamMyLocation().listen((_) async {
      final loc = await SupabaseService.getMyLocation();
      if (mounted) setState(() => _myLocation = loc);
    });
  }

  Future<void> _loadProfile() async {
    final profile = await SupabaseService.getCurrentProfile();
    // Location handled by stream now, but initial fetch is good to prevent flicker if stream is slow
    final location = await SupabaseService.getMyLocation();
    if (mounted) {
      setState(() {
        _profile = profile;
        _myLocation = location;
      });
    }
  }

  Future<void> _loadSettings() async {
    await WakeAlarmSettings.loadPersistedCustomSound();
    final prefs = await SharedPreferences.getInstance();
    final enabledApiSources = TransportApi.enabledSourcesFromPreferences(prefs);
    if (mounted) {
      setState(() {
        _vibrationPattern = prefs.getString('vibration_pattern') ?? 'standard';
        _vibrationIntensity = prefs.getInt('vibration_intensity') ?? 128;
        _wakeAlarmSound = WakeAlarmSettings.soundIdForPreference(
          prefs.getString(WakeAlarmSettings.soundPreferenceKey),
        );
        _wakeAlarmSoundEnabled =
            prefs.getBool(WakeAlarmSettings.wakeSoundEnabledPreferenceKey) ??
                true;
        _wakeAlarmVibrationEnabled = prefs
                .getBool(WakeAlarmSettings.wakeVibrationEnabledPreferenceKey) ??
            true;
        _leaveAlarmSoundEnabled =
            prefs.getBool(WakeAlarmSettings.leaveSoundEnabledPreferenceKey) ??
                true;
        _leaveAlarmVibrationEnabled = prefs.getBool(
                WakeAlarmSettings.leaveVibrationEnabledPreferenceKey) ??
            true;
        _stopsBeforeAlarm = prefs.getInt('alarm_stops_before') ?? 1;
        _enabledApiSources = enabledApiSources;
        _alarmTriggerThreshold =
            prefs.getString('alarm_trigger_threshold') ?? '5%';
        _advancedSettingsEnabledForDevice = prefs.getBool(
              TransportApi.advancedSettingsEnabledPreferenceKey,
            ) ??
            false;
        final hasLegacyTransferComfort = prefs.containsKey(
          TransportApi.advancedTransferComfortPreferenceKey,
        );
        final legacyTransferComfort = hasLegacyTransferComfort
            ? (prefs.getDouble(
                      TransportApi.advancedTransferComfortPreferenceKey,
                    ) ??
                    0.5)
                .clamp(0.0, 1.0)
            : null;
        final hasLegacyBikePreference = prefs.containsKey(
          TransportApi.advancedBikePreferenceKey,
        );
        final legacyBikePreference = hasLegacyBikePreference
            ? (prefs.getDouble(
                      TransportApi.advancedBikePreferenceKey,
                    ) ??
                    0.0)
                .clamp(0.0, 1.0)
            : null;
        _advancedMinTransferTimeMinutes = prefs.getInt(
                TransportApi.advancedMinTransferTimeMinutesPreferenceKey) ??
            (legacyTransferComfort != null
                ? (2 + (legacyTransferComfort * 5)).round()
                : _defaultAdvancedMinTransferTimeMinutes);
        _advancedAdditionalTransferTimeMinutes = prefs.getInt(
              TransportApi.advancedAdditionalTransferTimeMinutesPreferenceKey,
            ) ??
            (legacyTransferComfort != null
                ? (legacyTransferComfort * 4).round()
                : _defaultAdvancedAdditionalTransferTimeMinutes);
        _advancedTransferTimeFactor = ((prefs.getDouble(
                              TransportApi
                                  .advancedTransferTimeFactorPreferenceKey,
                            ) ??
                            (legacyTransferComfort != null
                                ? (0.8 + legacyTransferComfort)
                                : _defaultAdvancedTransferTimeFactor))
                        .clamp(0.7, 2.5) *
                    10)
                .round() /
            10;
        _advancedPreTransitWalkEnabled = prefs.getBool(
              TransportApi.advancedPreTransitWalkEnabledPreferenceKey,
            ) ??
            true;
        _advancedPreTransitBikeEnabled = prefs.getBool(
              TransportApi.advancedPreTransitBikeEnabledPreferenceKey,
            ) ??
            (legacyBikePreference != null && legacyBikePreference > 0.01);
        _advancedPostTransitWalkEnabled = prefs.getBool(
              TransportApi.advancedPostTransitWalkEnabledPreferenceKey,
            ) ??
            true;
        _advancedPostTransitBikeEnabled = prefs.getBool(
              TransportApi.advancedPostTransitBikeEnabledPreferenceKey,
            ) ??
            (legacyBikePreference != null && legacyBikePreference > 0.01);
        _advancedPedestrianSpeedKmh = (prefs.getDouble(
                  TransportApi.advancedPedestrianSpeedKmhPreferenceKey,
                ) ??
                _defaultAdvancedPedestrianSpeedKmh)
            .clamp(2.0, 10.0);
        _advancedMaxWalkingTimeMinutes = prefs.getInt(
              TransportApi.advancedMaxWalkingTimeMinutesPreferenceKey,
            ) ??
            _defaultAdvancedMaxWalkingTimeMinutes;
        _advancedCyclingSpeedKmh = ((prefs.getDouble(
                      TransportApi.advancedCyclingSpeedKmhPreferenceKey,
                    ) ??
                    (legacyBikePreference != null
                        ? ((3.2 + (legacyBikePreference * 2.4)) * 3.6)
                        : _defaultAdvancedCyclingSpeedKmh))
                .clamp(8.0, 30.0))
            .roundToDouble();
        TransportApi.configureEnabledSources(_enabledApiSources);
        TransportApi.configureAdvancedSearchSettings(
          enabledForDevice: _advancedSettingsEnabledForDevice,
          minTransferTimeMinutes: _advancedMinTransferTimeMinutes,
          additionalTransferTimeMinutes: _advancedAdditionalTransferTimeMinutes,
          transferTimeFactor: _advancedTransferTimeFactor,
          preTransitWalkEnabled: _advancedPreTransitWalkEnabled,
          preTransitBikeEnabled: _advancedPreTransitBikeEnabled,
          postTransitWalkEnabled: _advancedPostTransitWalkEnabled,
          postTransitBikeEnabled: _advancedPostTransitBikeEnabled,
          pedestrianSpeedKmh: _advancedPedestrianSpeedKmh,
          maxWalkingTimeMinutes: _advancedMaxWalkingTimeMinutes,
          cyclingSpeedKmh: _advancedCyclingSpeedKmh,
        );
      });
    }
  }

  Future<void> _persistVibrationSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vibration_pattern', _vibrationPattern);
    await prefs.setInt('vibration_intensity', _vibrationIntensity);
    await SupabaseService.updateSettings({
      'vibration_pattern': _vibrationPattern,
      'vibration_intensity': _vibrationIntensity,
    });
    await NotificationManager.updateWakeAlarmChannel(
      WakeAlarmSettings.vibrationPatternForId(_vibrationPattern),
      soundId: _wakeAlarmSound,
      soundEnabled: _wakeAlarmSoundEnabled,
      vibrationEnabled: _wakeAlarmVibrationEnabled,
    );
    await NotificationManager.updateLeaveAlarmChannel(
      WakeAlarmSettings.vibrationPatternForId(_vibrationPattern),
      soundId: _wakeAlarmSound,
      soundEnabled: _leaveAlarmSoundEnabled,
      vibrationEnabled: _leaveAlarmVibrationEnabled,
    );
  }

  Future<void> _persistWakeAlarmSoundSetting() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        WakeAlarmSettings.soundPreferenceKey, _wakeAlarmSound);
    await SupabaseService.updateSettings({
      WakeAlarmSettings.soundPreferenceKey: _wakeAlarmSound,
    });
    await NotificationManager.prepareAlarmSounds();
    await NotificationManager.updateWakeAlarmChannel(
      WakeAlarmSettings.vibrationPatternForId(_vibrationPattern),
      soundId: _wakeAlarmSound,
      soundEnabled: _wakeAlarmSoundEnabled,
      vibrationEnabled: _wakeAlarmVibrationEnabled,
    );
    await NotificationManager.updateLeaveAlarmChannel(
      WakeAlarmSettings.vibrationPatternForId(_vibrationPattern),
      soundId: _wakeAlarmSound,
      soundEnabled: _leaveAlarmSoundEnabled,
      vibrationEnabled: _leaveAlarmVibrationEnabled,
    );
  }

  Future<void> _selectWakeAlarmSound(String value) async {
    if (value == _pickCustomSoundValue) {
      await _pickCustomWakeAlarmSound();
      return;
    }

    if (_isWakeAlarmPreviewPlaying) {
      await NotificationManager.stopWakeAlarmPreview();
      if (mounted) {
        setState(() => _isWakeAlarmPreviewPlaying = false);
      }
    }

    setState(() => _wakeAlarmSound = value);
    await _persistWakeAlarmSoundSetting();
  }

  Future<void> _pickCustomWakeAlarmSound() async {
    try {
      final sound = await WakeAlarmCustomSoundService.pickAndImport();
      if (sound == null || !mounted) return;

      setState(() => _wakeAlarmSound = sound.id);
      await _persistWakeAlarmSoundSetting();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Custom alarm sound set to "${sound.label}". Tap the trash icon in the picker to remove it.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_customSoundImportErrorMessage(error))),
      );
    }
  }

  Future<void> _removeCustomWakeAlarmSound(WakeAlarmSoundOption sound) async {
    if (!sound.isCustomSound) return;

    try {
      await WakeAlarmCustomSoundService.deleteCustomSound(sound);
      if (!mounted) return;

      final wasSelected = _wakeAlarmSound == sound.id;
      if (wasSelected) {
        setState(() => _wakeAlarmSound = WakeAlarmSettings.defaultSoundId);
        await _persistWakeAlarmSoundSetting();
      } else {
        setState(() {});
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Custom alarm sound removed.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove the custom sound: $error')),
      );
    }
  }

  String _customSoundImportErrorMessage(Object error) {
    if (error is StateError) {
      return 'Could not import that audio file: ${error.message}';
    }
    return 'Could not import that audio file.';
  }

  Future<void> _persistAlarmDeliverySettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(WakeAlarmSettings.wakeSoundEnabledPreferenceKey,
        _wakeAlarmSoundEnabled);
    await prefs.setBool(WakeAlarmSettings.wakeVibrationEnabledPreferenceKey,
        _wakeAlarmVibrationEnabled);
    await prefs.setBool(WakeAlarmSettings.leaveSoundEnabledPreferenceKey,
        _leaveAlarmSoundEnabled);
    await prefs.setBool(WakeAlarmSettings.leaveVibrationEnabledPreferenceKey,
        _leaveAlarmVibrationEnabled);
    await SupabaseService.updateSettings({
      WakeAlarmSettings.wakeSoundEnabledPreferenceKey: _wakeAlarmSoundEnabled,
      WakeAlarmSettings.wakeVibrationEnabledPreferenceKey:
          _wakeAlarmVibrationEnabled,
      WakeAlarmSettings.leaveSoundEnabledPreferenceKey: _leaveAlarmSoundEnabled,
      WakeAlarmSettings.leaveVibrationEnabledPreferenceKey:
          _leaveAlarmVibrationEnabled,
    });
    await NotificationManager.updateWakeAlarmChannel(
      WakeAlarmSettings.vibrationPatternForId(_vibrationPattern),
      soundId: _wakeAlarmSound,
      soundEnabled: _wakeAlarmSoundEnabled,
      vibrationEnabled: _wakeAlarmVibrationEnabled,
    );
    await NotificationManager.updateLeaveAlarmChannel(
      WakeAlarmSettings.vibrationPatternForId(_vibrationPattern),
      soundId: _wakeAlarmSound,
      soundEnabled: _leaveAlarmSoundEnabled,
      vibrationEnabled: _leaveAlarmVibrationEnabled,
    );
  }

  Future<void> _saveAlarmSettings(int stops) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('alarm_stops_before', stops);
    setState(() {
      _stopsBeforeAlarm = stops;
    });
    await SupabaseService.updateSettings({'alarm_stops_before': stops});
  }

  Future<void> _saveAlarmThreshold(String threshold) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('alarm_trigger_threshold', threshold);
    setState(() {
      _alarmTriggerThreshold = threshold;
    });
    await SupabaseService.updateSettings(
        {'alarm_trigger_threshold': threshold});
  }

  Future<void> _saveEnabledApiSources(Set<String> sources) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = Set<String>.from(sources);
    if (!normalized.contains(TransportApi.sourceTransitous)) {
      normalized.remove(TransportApi.sourceSyntheticTransitous);
    }
    if (normalized.isEmpty) {
      normalized.addAll(TransportApi.defaultEnabledSources);
    }
    await prefs.setStringList(
      TransportApi.enabledApiSourcesPreferenceKey,
      normalized.toList()..sort(),
    );
    setState(() {
      _enabledApiSources = normalized;
    });
    TransportApi.configureEnabledSources(normalized);
  }

  Future<void> _toggleApiSource(String source, bool enabled) async {
    final updated = Set<String>.from(_enabledApiSources);
    if (enabled) {
      updated.add(source);
      if (source == TransportApi.sourceSyntheticTransitous) {
        updated.add(TransportApi.sourceTransitous);
      }
    } else {
      updated.remove(source);
      if (source == TransportApi.sourceTransitous) {
        updated.remove(TransportApi.sourceSyntheticTransitous);
      }
    }
    await _saveEnabledApiSources(updated);
  }

  String _selectedApiSourcesSummary(AppLocalizations l10n) {
    final labels = <String>[];
    if (_enabledApiSources.contains(TransportApi.sourceTransitous)) {
      labels.add('Transitous');
    }
    if (_enabledApiSources.contains(TransportApi.sourceSyntheticTransitous)) {
      labels.add(_syntheticTransitousLabel(l10n));
    }
    if (_enabledApiSources.contains(TransportApi.sourceDbV6)) {
      labels.add(l10n.dbV6);
    }
    if (labels.isEmpty) {
      labels.add('Transitous');
    }
    return labels.join(' + ');
  }

  String _syntheticTransitousLabel(AppLocalizations l10n) =>
      l10n.localeName.startsWith('de')
          ? 'Synthetisches Transitous'
          : 'Synthetic Transitous';

  String _syntheticTransitousDescription(AppLocalizations l10n) =>
      l10n.localeName.startsWith('de')
          ? 'Erweitert Transitous um zusätzliche synthetische Verbindungen'
          : 'Adds extra synthetic Transitous connections';

  bool _canDisableTransitous() =>
      _enabledApiSources.contains(TransportApi.sourceDbV6);

  bool _canDisableDbV6() =>
      _enabledApiSources.contains(TransportApi.sourceTransitous);

  Future<void> _persistAdvancedSearchPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      TransportApi.advancedMinTransferTimeMinutesPreferenceKey,
      _advancedMinTransferTimeMinutes,
    );
    await prefs.setInt(
      TransportApi.advancedAdditionalTransferTimeMinutesPreferenceKey,
      _advancedAdditionalTransferTimeMinutes,
    );
    await prefs.setDouble(
      TransportApi.advancedTransferTimeFactorPreferenceKey,
      _advancedTransferTimeFactor,
    );
    await prefs.setBool(
      TransportApi.advancedPreTransitWalkEnabledPreferenceKey,
      _advancedPreTransitWalkEnabled,
    );
    await prefs.setBool(
      TransportApi.advancedPreTransitBikeEnabledPreferenceKey,
      _advancedPreTransitBikeEnabled,
    );
    await prefs.setBool(
      TransportApi.advancedPostTransitWalkEnabledPreferenceKey,
      _advancedPostTransitWalkEnabled,
    );
    await prefs.setBool(
      TransportApi.advancedPostTransitBikeEnabledPreferenceKey,
      _advancedPostTransitBikeEnabled,
    );
    await prefs.setDouble(
      TransportApi.advancedCyclingSpeedKmhPreferenceKey,
      _advancedCyclingSpeedKmh,
    );
    await prefs.setDouble(
      TransportApi.advancedPedestrianSpeedKmhPreferenceKey,
      _advancedPedestrianSpeedKmh,
    );
    await prefs.setInt(
      TransportApi.advancedMaxWalkingTimeMinutesPreferenceKey,
      _advancedMaxWalkingTimeMinutes,
    );
    if (!_advancedPreTransitBikeEnabled && !_advancedPostTransitBikeEnabled) {
      await prefs.setBool(TransportApi.advancedBikeTogglePreferenceKey, false);
      TransportApi.setBikeToggleEnabledForDevice(false);
    }

    TransportApi.configureAdvancedSearchSettings(
      enabledForDevice: _advancedSettingsEnabledForDevice,
      minTransferTimeMinutes: _advancedMinTransferTimeMinutes,
      additionalTransferTimeMinutes: _advancedAdditionalTransferTimeMinutes,
      transferTimeFactor: _advancedTransferTimeFactor,
      preTransitWalkEnabled: _advancedPreTransitWalkEnabled,
      preTransitBikeEnabled: _advancedPreTransitBikeEnabled,
      postTransitWalkEnabled: _advancedPostTransitWalkEnabled,
      postTransitBikeEnabled: _advancedPostTransitBikeEnabled,
      pedestrianSpeedKmh: _advancedPedestrianSpeedKmh,
      maxWalkingTimeMinutes: _advancedMaxWalkingTimeMinutes,
      cyclingSpeedKmh: _advancedCyclingSpeedKmh,
    );

    if (SupabaseService.currentUser != null) {
      await SupabaseService.updateSettings({
        TransportApi.advancedMinTransferTimeMinutesPreferenceKey:
            _advancedMinTransferTimeMinutes,
        TransportApi.advancedAdditionalTransferTimeMinutesPreferenceKey:
            _advancedAdditionalTransferTimeMinutes,
        TransportApi.advancedTransferTimeFactorPreferenceKey:
            _advancedTransferTimeFactor,
        TransportApi.advancedPreTransitWalkEnabledPreferenceKey:
            _advancedPreTransitWalkEnabled,
        TransportApi.advancedPreTransitBikeEnabledPreferenceKey:
            _advancedPreTransitBikeEnabled,
        TransportApi.advancedPostTransitWalkEnabledPreferenceKey:
            _advancedPostTransitWalkEnabled,
        TransportApi.advancedPostTransitBikeEnabledPreferenceKey:
            _advancedPostTransitBikeEnabled,
        TransportApi.advancedPedestrianSpeedKmhPreferenceKey:
            _advancedPedestrianSpeedKmh,
        TransportApi.advancedMaxWalkingTimeMinutesPreferenceKey:
            _advancedMaxWalkingTimeMinutes,
        TransportApi.advancedCyclingSpeedKmhPreferenceKey:
            _advancedCyclingSpeedKmh,
      });
    }
  }

  Future<void> _unlockAdvancedSettingsForDevice() async {
    await _setAdvancedSettingsEnabledForDevice(true);
    if (!mounted) return;
    _suppressNextChangelogTap = true;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          Localizations.localeOf(context).languageCode == 'de'
              ? 'Erweiterte Sucheinstellungen sind jetzt auf diesem Gerät aktiviert.'
              : 'Advanced search settings are now enabled on this device.',
        ),
      ),
    );
  }

  Future<void> _setAdvancedSettingsEnabledForDevice(bool enabled) async {
    if (!enabled) {
      _cancelAdvancedUnlockHold();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      TransportApi.advancedSettingsEnabledPreferenceKey,
      enabled,
    );
    if (!mounted) return;

    setState(() {
      _advancedSettingsEnabledForDevice = enabled;
      _advancedUnlockCountdownSecondsLeft = null;
    });

    TransportApi.configureAdvancedSearchSettings(
      enabledForDevice: enabled,
      minTransferTimeMinutes: _advancedMinTransferTimeMinutes,
      additionalTransferTimeMinutes: _advancedAdditionalTransferTimeMinutes,
      transferTimeFactor: _advancedTransferTimeFactor,
      preTransitWalkEnabled: _advancedPreTransitWalkEnabled,
      preTransitBikeEnabled: _advancedPreTransitBikeEnabled,
      postTransitWalkEnabled: _advancedPostTransitWalkEnabled,
      postTransitBikeEnabled: _advancedPostTransitBikeEnabled,
      pedestrianSpeedKmh: _advancedPedestrianSpeedKmh,
      maxWalkingTimeMinutes: _advancedMaxWalkingTimeMinutes,
      cyclingSpeedKmh: _advancedCyclingSpeedKmh,
    );
    SupabaseService.settingsRefreshNotifier.value++;
  }

  void _cancelAdvancedUnlockHold() {
    _advancedUnlockTimer?.cancel();
    _advancedUnlockTimer = null;
    _advancedCountdownTimer?.cancel();
    _advancedCountdownTimer = null;
    _advancedUnlockPressStart = null;
    if (_advancedUnlockCountdownSecondsLeft != null && mounted) {
      setState(() => _advancedUnlockCountdownSecondsLeft = null);
    }
  }

  void _startAdvancedUnlockHold() {
    if (_advancedSettingsEnabledForDevice) return;
    _cancelAdvancedUnlockHold();
    final startedAt = DateTime.now();
    _advancedUnlockPressStart = startedAt;

    _advancedUnlockTimer = Timer(
      const Duration(seconds: _advancedUnlockHoldSeconds),
      () async {
        if (!mounted || _advancedUnlockPressStart != startedAt) return;
        _cancelAdvancedUnlockHold();
        await _unlockAdvancedSettingsForDevice();
      },
    );

    _advancedCountdownTimer = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) {
      if (!mounted || _advancedUnlockPressStart != startedAt) {
        timer.cancel();
        return;
      }

      final elapsedSeconds = DateTime.now().difference(startedAt).inSeconds;
      if (elapsedSeconds >= _advancedUnlockCountdownStartSeconds) {
        final secondsLeft =
            (_advancedUnlockHoldSeconds - elapsedSeconds).clamp(0, 99);
        if (_advancedUnlockCountdownSecondsLeft != secondsLeft) {
          setState(() => _advancedUnlockCountdownSecondsLeft = secondsLeft);
        }
      }
    });
  }

  String _modeLabel(String mode, bool isGerman) {
    switch (mode) {
      case 'WALK':
        return isGerman ? 'Zu Fuß' : 'Walk';
      case 'BICYCLE':
        return isGerman ? 'Fahrrad' : 'Bicycle';
      default:
        return mode;
    }
  }

  Widget _buildTransferImpactPreview(bool isGerman, TransColors colors) {
    final min = _advancedMinTransferTimeMinutes;
    final add = _advancedAdditionalTransferTimeMinutes;
    final factor = _advancedTransferTimeFactor;

    final previewRoutes = <Map<String, dynamic>>[
      {
        'label': isGerman ? 'Route A: Sehr schnell' : 'Route A: Very fast',
        'duration': 29,
        'transfers': 2,
        'transferMinutes': 6, // 2 x 3 min
      },
      {
        'label': isGerman ? 'Route B: Ausgewogen' : 'Route B: Balanced',
        'duration': 33,
        'transfers': 1,
        'transferMinutes': 6, // 1 x 6 min
      },
      {
        'label': isGerman ? 'Route C: Komfort' : 'Route C: Comfort',
        'duration': 39,
        'transfers': 0,
        'transferMinutes': 0,
      },
    ];

    for (final route in previewRoutes) {
      final transfers = route['transfers'] as int;
      final transferMinutes = route['transferMinutes'] as int;
      final minPerTransfer =
          transfers == 0 ? transferMinutes : (transferMinutes / transfers);
      final filtered = transfers > 0 && minPerTransfer < min;
      final effectiveTransferMinutes = transferMinutes + (transfers * add);
      final transferPenalty = effectiveTransferMinutes * factor;
      final totalCost = (route['duration'] as int) + transferPenalty;
      route['filtered'] = filtered;
      route['effectiveTransferMinutes'] = effectiveTransferMinutes;
      route['transferPenalty'] = transferPenalty;
      route['totalCost'] = totalCost;
      route['minPerTransfer'] = minPerTransfer;
    }

    final allowedRoutes = previewRoutes
        .where((route) => route['filtered'] == false)
        .toList(growable: false);
    double? bestAllowedCost;
    if (allowedRoutes.isNotEmpty) {
      bestAllowedCost = allowedRoutes
          .map((route) => (route['totalCost'] as num).toDouble())
          .reduce((a, b) => a < b ? a : b);
    }

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.cardBg.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isGerman ? 'Live-Beispielwirkung' : 'Live example impact',
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isGerman
                ? 'Bewertung: Fahrzeit + ((Umstiegsminuten + Anzahl Umstiege × Zusatz) × Faktor)'
                : 'Score: trip time + ((transfer minutes + number of transfers × additional) × factor)',
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
          const SizedBox(height: 10),
          ...previewRoutes.map((route) {
            final filtered = route['filtered'] as bool;
            final transferPenalty =
                (route['transferPenalty'] as num).toDouble();
            final totalCost = (route['totalCost'] as num).toDouble();
            final transferMinutes = route['transferMinutes'] as int;
            final effectiveTransferMinutes =
                route['effectiveTransferMinutes'] as int;
            final transfers = route['transfers'] as int;
            final minPerTransfer = (route['minPerTransfer'] as num).toDouble();
            final duration = route['duration'] as int;
            final isPreferred = !filtered &&
                bestAllowedCost != null &&
                (totalCost - bestAllowedCost).abs() < 0.0001;

            Color badgeBg;
            Color badgeFg;
            String badgeLabel;
            if (filtered) {
              badgeBg = Colors.red.withValues(alpha: 0.15);
              badgeFg = Colors.red;
              badgeLabel = isGerman ? 'Herausgefiltert' : 'Filtered out';
            } else if (isPreferred) {
              badgeBg = colors.effectiveSeed.withValues(alpha: 0.15);
              badgeFg = colors.effectiveSeed;
              badgeLabel = isGerman ? 'Bevorzugt' : 'Preferred';
            } else {
              badgeBg = Colors.green.withValues(alpha: 0.15);
              badgeFg = Colors.green.shade700;
              badgeLabel = isGerman ? 'Erlaubt' : 'Allowed';
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.cardBg.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: filtered
                      ? Colors.red.withValues(alpha: 0.35)
                      : colors.divider,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.alt_route,
                          size: 18, color: colors.textPrimary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          route['label'] as String,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: badgeBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          badgeLabel,
                          style: TextStyle(
                            color: badgeFg,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isGerman
                        ? 'Fahrzeit: $duration min • Umstiege: $transfers • Summe Umstiegsminuten: $transferMinutes'
                        : 'Trip time: $duration min • Transfers: $transfers • Total transfer minutes: $transferMinutes',
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                  Text(
                    isGerman
                        ? 'Transfer-Penalty: ($transferMinutes + $transfers × $add) × ${factor.toStringAsFixed(1)} = ${transferPenalty.toStringAsFixed(1)}'
                        : 'Transfer penalty: ($transferMinutes + $transfers × $add) × ${factor.toStringAsFixed(1)} = ${transferPenalty.toStringAsFixed(1)}',
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                  Text(
                    isGerman
                        ? 'Effektive Umstiegsminuten: $effectiveTransferMinutes'
                        : 'Effective transfer minutes: $effectiveTransferMinutes',
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                  Text(
                    isGerman
                        ? 'Gesamtwert: $duration + ${transferPenalty.toStringAsFixed(1)} = ${totalCost.toStringAsFixed(1)} (niedriger ist besser)'
                        : 'Total score: $duration + ${transferPenalty.toStringAsFixed(1)} = ${totalCost.toStringAsFixed(1)} (lower is better)',
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                  if (filtered)
                    Text(
                      isGerman
                          ? 'Grund: Ø Umstiegszeit ${minPerTransfer.toStringAsFixed(1)} min < Minimum $min min'
                          : 'Reason: avg transfer time ${minPerTransfer.toStringAsFixed(1)} min < minimum $min min',
                      style:
                          TextStyle(fontSize: 12, color: Colors.red.shade300),
                    ),
                ],
              ),
            );
          }),
          Text(
            isGerman
                ? 'Die Vorschau zeigt nur den Einfluss auf Transfer-Bewertung/Filterung. Echtzeit- und Linien-Daten können die finale Reihenfolge zusätzlich ändern.'
                : 'This preview only shows transfer filter/scoring impact. Real-time and line data can still change final ordering.',
            style: TextStyle(fontSize: 11, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }

  Future<void> _testVibration() async {
    if (kIsWeb) return;
    if (!await ForegroundHaptics.hasVibrator()) return;

    final pattern = WakeAlarmSettings.vibrationPatternForId(_vibrationPattern);
    await ForegroundHaptics.vibratePattern(
      pattern,
      intensity: _vibrationIntensity,
    );
  }

  Future<void> _testAlarmVibration({required bool enabled}) async {
    if (kIsWeb || !enabled) return;
    if (!await ForegroundHaptics.hasVibrator()) return;

    final pattern = WakeAlarmSettings.vibrationPatternForId(_vibrationPattern);
    await ForegroundHaptics.vibratePattern(
      pattern,
      intensity: _vibrationIntensity,
    );
  }

  Future<void> _previewWakeAlarmSound() async {
    if (kIsWeb) return;
    final l10n = AppLocalizations.of(context)!;
    try {
      if (_isWakeAlarmPreviewPlaying) {
        await NotificationManager.stopWakeAlarmPreview();
        if (!mounted) return;
        setState(() => _isWakeAlarmPreviewPlaying = false);
        return;
      }

      await NotificationManager.previewWakeAlarm(
        title: l10n.wakeAlarmPreviewTitle,
        body: l10n.wakeAlarmPreviewBody,
        soundId: _wakeAlarmSound,
        vibrationPattern: WakeAlarmSettings.vibrationPatternForId(
          _vibrationPattern,
        ),
      );
      if (!mounted) return;
      setState(() => _isWakeAlarmPreviewPlaying = true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isWakeAlarmPreviewPlaying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_wakeAlarmPreviewErrorMessage(error))),
      );
    }
  }

  String _wakeAlarmPreviewErrorMessage(Object error) {
    if (error is PlatformException) {
      final message = error.message;
      if (message != null && message.isNotEmpty) {
        return 'Could not play the alarm preview: $message';
      }
    }

    if (error is StateError) {
      return error.message;
    }

    return 'Could not play the alarm preview. Check your output volume and audio route.';
  }

  bool get _showPreviewTooltip {
    if (kIsWeb) return true;

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return false;
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return true;
    }
  }

  Future<void> _triggerHiddenManualLeaveTimer() async {
    if (!mounted) return;

    try {
      await NotificationManager.previewWakeAlarm(
        title: 'Manual leave timer',
        body: 'Hidden timer finished.',
        soundId: _wakeAlarmSoundEnabled
            ? _wakeAlarmSound
            : WakeAlarmSettings.silentSoundId,
        vibrationPattern: WakeAlarmSettings.vibrationPatternForId(
          _vibrationPattern,
        ),
      );
      await _testAlarmVibration(enabled: _wakeAlarmVibrationEnabled);
      _hiddenManualAlarmTarget = null;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Manual leave timer fired.')),
      );
    } catch (error) {
      _hiddenManualAlarmTarget = null;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _wakeAlarmPreviewErrorMessage(error),
          ),
        ),
      );
    }
  }

  Future<void> _cancelHiddenManualLeaveTimer() async {
    _hiddenManualAlarmTimer?.cancel();
    _hiddenManualAlarmTimer = null;
    await NotificationManager.cancelNotification(
      id: _hiddenManualAlarmNotificationId,
    );
    _hiddenManualAlarmTarget = null;
  }

  Future<void> _scheduleHiddenManualLeaveTimer(DateTime target) async {
    await _cancelHiddenManualLeaveTimer();
    final now = DateTime.now();
    final delay = target.difference(now);
    final safeDelay = delay.isNegative ? Duration.zero : delay;
    _hiddenManualAlarmTarget = target;

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await NotificationManager.requestPermissions();
      await NotificationManager.scheduleNotification(
        id: _hiddenManualAlarmNotificationId,
        title: 'Manual leave timer',
        body: 'Hidden timer finished.',
        scheduledAt: target,
        details: NotificationDetails(
          iOS: NotificationManager.buildWakeAlarmIosDetails(
            soundId: _wakeAlarmSound,
            soundEnabled: _wakeAlarmSoundEnabled,
          ),
        ),
      );

      // Keep lightweight local state while the app remains active. The real
      // notification is handled by iOS, so this timer only clears stale UI.
      _hiddenManualAlarmTimer = Timer(safeDelay, () {
        _hiddenManualAlarmTimer = null;
        _hiddenManualAlarmTarget = null;
      });
      return;
    }

    _hiddenManualAlarmTimer = Timer(safeDelay, () {
      unawaited(_triggerHiddenManualLeaveTimer());
    });
  }

  Future<void> _showHiddenManualTimerDialog() async {
    if (kIsWeb || !mounted) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final materialLocalizations = MaterialLocalizations.of(context);
    final alwaysUse24HourFormat = MediaQuery.alwaysUse24HourFormatOf(context);

    if (_hiddenManualAlarmTarget case final target?
        when !target.isAfter(DateTime.now())) {
      _hiddenManualAlarmTimer?.cancel();
      _hiddenManualAlarmTimer = null;
      _hiddenManualAlarmTarget = null;
    }

    final now = DateTime.now();
    var useCountdown = true;
    var countdownSeconds = 10;
    TimeOfDay selectedTime = TimeOfDay.fromDateTime(
      now.add(const Duration(minutes: 1)),
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> pickTime() async {
              final picked = await showTimePicker(
                context: context,
                initialTime: selectedTime,
              );
              if (picked == null) return;
              setDialogState(() => selectedTime = picked);
            }

            final selectedLabel = useCountdown
                ? 'Countdown: ${countdownSeconds}s'
                : 'At ${selectedTime.format(context)}';

            return AlertDialog(
              title: const Text('Hidden timer'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment<bool>(
                        value: true,
                        label: Text('Countdown'),
                        icon: Icon(Icons.timer_outlined),
                      ),
                      ButtonSegment<bool>(
                        value: false,
                        label: Text('Alarm time'),
                        icon: Icon(Icons.schedule),
                      ),
                    ],
                    selected: {useCountdown},
                    onSelectionChanged: (selection) {
                      setDialogState(
                        () => useCountdown = selection.first,
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  if (useCountdown)
                    DropdownButton<int>(
                      value: countdownSeconds,
                      isExpanded: true,
                      items: _hiddenManualTimerSecondOptions
                          .map(
                            (seconds) => DropdownMenuItem<int>(
                              value: seconds,
                              child: Text('$seconds seconds'),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => countdownSeconds = value);
                      },
                    ),
                  if (!useCountdown)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Time'),
                      subtitle: Text(selectedTime.format(context)),
                      trailing: const Icon(Icons.schedule),
                      onTap: pickTime,
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Will fire: $selectedLabel',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                if (_hiddenManualAlarmTarget != null)
                  TextButton(
                    onPressed: () async {
                      final navigator = Navigator.of(dialogContext);
                      await _cancelHiddenManualLeaveTimer();
                      navigator.pop(false);
                      if (!mounted) return;
                      scaffoldMessenger.showSnackBar(
                        const SnackBar(
                            content: Text('Hidden timer cancelled.')),
                      );
                    },
                    child: const Text('Clear'),
                  ),
                FilledButton(
                  onPressed: () async {
                    final navigator = Navigator.of(dialogContext);
                    final now = DateTime.now();
                    final target = useCountdown
                        ? now.add(Duration(seconds: countdownSeconds))
                        : DateTime(
                            now.year,
                            now.month,
                            now.day,
                            selectedTime.hour,
                            selectedTime.minute,
                          ).isAfter(now)
                            ? DateTime(
                                now.year,
                                now.month,
                                now.day,
                                selectedTime.hour,
                                selectedTime.minute,
                              )
                            : DateTime(
                                now.year,
                                now.month,
                                now.day + 1,
                                selectedTime.hour,
                                selectedTime.minute,
                              );
                    await _scheduleHiddenManualLeaveTimer(target);
                    navigator.pop(true);
                  },
                  child: const Text('Start'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true || !mounted || _hiddenManualAlarmTarget == null) {
      return;
    }

    final target = _hiddenManualAlarmTarget!;
    final modeLabel = target.difference(DateTime.now()).inHours < 24
        ? 'Hidden timer set for ${materialLocalizations.formatTimeOfDay(TimeOfDay.fromDateTime(target), alwaysUse24HourFormat: alwaysUse24HourFormat)}'
        : 'Hidden timer scheduled';
    scaffoldMessenger.showSnackBar(
      SnackBar(content: Text(modeLabel)),
    );
  }

  void _pickAvatar() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      builder: (ctx) {
        return SizedBox(
          height: 350,
          child: EmojiPicker(
            onEmojiSelected: (category, emoji) async {
              Navigator.pop(ctx);
              await SupabaseService.updateAvatarEmoji(emoji.emoji);
              _loadProfile();
            },
            config: Config(
              height: 300,
              checkPlatformCompatibility: true,
              emojiViewConfig: EmojiViewConfig(
                backgroundColor: Theme.of(context).cardColor,
                columns: 7,
                emojiSizeMax: 32,
              ),
              viewOrderConfig: const ViewOrderConfig(),
            ),
          ),
        );
      },
    );
  }

  Future<void> _clearHistory() async {
    final colors = TransColors.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.cardBg,
        title: Text(AppLocalizations.of(context)!.clearHistory,
            style: TextStyle(color: colors.textPrimary)),
        content: Text(AppLocalizations.of(context)!.confirmClearHistory,
            style: TextStyle(color: colors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(AppLocalizations.of(context)!.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(AppLocalizations.of(context)!.delete,
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed == true) {
      await SearchHistoryManager.clearHistory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)!.searchHistoryCleared)));
      }
    }
  }

  void _showBlockedUsers() {
    final colors = TransColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.cardBg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => FutureBuilder<List<Map<String, dynamic>>>(
        future: SupabaseService.getBlockedUsers(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final users = snapshot.data ?? [];
          return Container(
            padding: const EdgeInsets.all(20),
            height: 400,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppLocalizations.of(context)!.blockedUsers,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary)),
                const SizedBox(height: 16),
                if (users.isEmpty)
                  Expanded(
                      child: Center(
                          child: Text(
                              AppLocalizations.of(context)!.noBlockedUsers,
                              style: TextStyle(color: colors.textSecondary)))),
                if (users.isNotEmpty)
                  Expanded(
                    child: ListView.separated(
                      itemCount: users.length,
                      separatorBuilder: (_, __) =>
                          Divider(color: colors.divider),
                      itemBuilder: (ctx, idx) {
                        final u = users[idx];
                        return ListTile(
                          leading: CircleAvatar(
                              backgroundImage: u['avatar_url'] != null
                                  ? NetworkImage(u['avatar_url'])
                                  : null,
                              child: u['avatar_url'] == null
                                  ? const Icon(Icons.person)
                                  : null),
                          title: Text(u['username'] ?? "Unknown",
                              style: TextStyle(color: colors.textPrimary)),
                          trailing: TextButton(
                            onPressed: () async {
                              await SupabaseService.unblockUser(u['id']);
                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(AppLocalizations.of(
                                                context)!
                                            .unblockedUser(u['username']))));
                              }
                            },
                            child: Text(AppLocalizations.of(context)!.unblock),
                          ),
                        );
                      },
                    ),
                  )
              ],
            ),
          );
        },
      ),
    );
  }

  void _showDeleteAccountDialog() {
    final passwordCtrl = TextEditingController();
    bool isLoading = false;
    String? errorMsg;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: TransColors.of(context).cardBg,
          title: Text(AppLocalizations.of(context)!.deleteAccount,
              style: TextStyle(color: TransColors.of(context).textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(AppLocalizations.of(context)!.deleteAccountWarning,
                  style: TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              Text(AppLocalizations.of(context)!.enterPasswordToConfirm,
                  style:
                      TextStyle(color: TransColors.of(context).textSecondary)),
              const SizedBox(height: 8),
              TextField(
                controller: passwordCtrl,
                obscureText: true,
                style: TextStyle(color: TransColors.of(context).textPrimary),
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.password,
                  errorText: errorMsg,
                  border: const OutlineInputBorder(),
                  labelStyle:
                      TextStyle(color: TransColors.of(context).textSecondary),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(context)!.cancel),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: isLoading
                  ? null
                  : () async {
                      final l10n = AppLocalizations.of(context)!;
                      if (passwordCtrl.text.isEmpty) {
                        setState(() {
                          errorMsg = l10n.fillRequiredFields;
                        });
                        unawaited(
                          AppError.showReportableSnackBar(
                            context,
                            message: l10n.fillRequiredFields,
                            source: 'delete account validation',
                          ),
                        );
                        return;
                      }
                      setState(() {
                        isLoading = true;
                        errorMsg = null;
                      });
                      try {
                        await SupabaseService.reauthenticate(passwordCtrl.text);
                        await SupabaseService.deleteAccount();
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          if (mounted) {
                            final isGerman =
                                Localizations.localeOf(context).languageCode ==
                                    'de';
                            _showMessage(isGerman
                                ? 'Konto dauerhaft gelöscht.'
                                : 'Account permanently deleted.');
                            setState(() {});
                          }
                        }
                      } catch (e, st) {
                        if (!ctx.mounted) return;
                        final userMessage = deleteAccountErrorMessage(
                          e,
                          invalidPasswordMessage:
                              l10n.incorrectPasswordOrRpcMissing,
                          fallbackMessage: l10n.serviceBusyPleaseTryAgain,
                        );
                        setState(() {
                          errorMsg = userMessage;
                          isLoading = false;
                        });
                        unawaited(
                          AppError.showReportableSnackBar(
                            ctx,
                            message: userMessage,
                            source: 'delete account',
                            error: e,
                            stackTrace: st,
                          ),
                        );
                      }
                    },
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(AppLocalizations.of(context)!.deleteForever,
                      style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showUsernameDialog() async {
    final colors = TransColors.of(context);
    final l10n = AppLocalizations.of(context)!;
    final ctrl =
        TextEditingController(text: (_profile?['username'] ?? '').toString());
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: colors.cardBg,
          title: Text(AppLocalizations.of(context)!.changeUsername,
              style: TextStyle(color: colors.textPrimary)),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            textInputAction: TextInputAction.done,
            style: TextStyle(color: colors.textPrimary),
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context)!.username,
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(context)!.cancel),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final username = ctrl.text.trim();
                      if (username.isEmpty) {
                        _showMessage(
                          l10n.fillRequiredFields,
                          reportable: true,
                          source: 'update username validation',
                        );
                        return;
                      }

                      setState(() => isSaving = true);
                      try {
                        await SupabaseService.updateUsername(username);
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        await _loadProfile();
                        _showMessage(l10n.usernameUpdated);
                      } catch (e, st) {
                        if (!ctx.mounted) return;
                        setState(() => isSaving = false);
                        AppError.showSnackBar(
                          ctx,
                          error: e,
                          stackTrace: st,
                          source: 'update username',
                        );
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(AppLocalizations.of(context)!.save),
            ),
          ],
        ),
      ),
    );

    ctrl.dispose();
  }

  Future<void> _showEmailDialog(String currentEmail) async {
    final colors = TransColors.of(context);
    final ctrl = TextEditingController(text: currentEmail);
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: colors.cardBg,
          title: Text(AppLocalizations.of(context)!.changeEmail,
              style: TextStyle(color: colors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context)!.emailChangeHint,
                style: TextStyle(color: colors.textSecondary),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                style: TextStyle(color: colors.textPrimary),
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.emailSettings,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(context)!.cancel),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final email = ctrl.text.trim();
                      if (!_looksLikeEmail(email)) {
                        _showMessage(
                          AppLocalizations.of(context)!.enterValidEmail,
                          reportable: true,
                          source: 'update email validation',
                        );
                        return;
                      }
                      if (email == currentEmail) {
                        Navigator.pop(ctx);
                        return;
                      }

                      setState(() => isSaving = true);
                      try {
                        await SupabaseService.updateEmail(email);
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        _showMessage(
                            AppLocalizations.of(context)!.emailUpdateSent);
                      } catch (e, st) {
                        if (!ctx.mounted) return;
                        setState(() => isSaving = false);
                        AppError.showSnackBar(
                          ctx,
                          error: e,
                          stackTrace: st,
                          source: 'update email',
                        );
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(AppLocalizations.of(context)!.save),
            ),
          ],
        ),
      ),
    );

    ctrl.dispose();
  }

  Future<void> _showChangePasswordDialog() async {
    final colors = TransColors.of(context);
    final newPasswordCtrl = TextEditingController();
    final confirmPasswordCtrl = TextEditingController();
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: colors.cardBg,
          title: Text(AppLocalizations.of(context)!.changePassword,
              style: TextStyle(color: colors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppLocalizations.of(context)!.passwordChangeHint,
                style: TextStyle(color: colors.textSecondary),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newPasswordCtrl,
                autofocus: true,
                obscureText: true,
                style: TextStyle(color: colors.textPrimary),
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.newPasswordOpt,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmPasswordCtrl,
                obscureText: true,
                style: TextStyle(color: colors.textPrimary),
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.confirmPassword,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(context)!.cancel),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final password = newPasswordCtrl.text.trim();
                      final confirm = confirmPasswordCtrl.text.trim();
                      if (password.isEmpty || confirm.isEmpty) {
                        _showMessage(
                          AppLocalizations.of(context)!.fillRequiredFields,
                          reportable: true,
                          source: 'update password validation',
                        );
                        return;
                      }
                      if (password != confirm) {
                        _showMessage(
                          AppLocalizations.of(context)!.passwordsDoNotMatch,
                          reportable: true,
                          source: 'update password validation',
                        );
                        return;
                      }

                      setState(() => isSaving = true);
                      try {
                        await SupabaseService.updatePassword(password);
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        _showMessage(
                            AppLocalizations.of(context)!.passwordUpdated);
                      } catch (e, st) {
                        if (!ctx.mounted) return;
                        setState(() => isSaving = false);
                        AppError.showSnackBar(
                          ctx,
                          error: e,
                          stackTrace: st,
                          source: 'update password',
                        );
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(AppLocalizations.of(context)!.save),
            ),
          ],
        ),
      ),
    );

    newPasswordCtrl.dispose();
    confirmPasswordCtrl.dispose();
  }

  Future<void> _submitAuth() async {
    if (_isAuthSubmitting) return;

    final l10n = AppLocalizations.of(context)!;
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final username = _usernameCtrl.text.trim();

    if (email.isEmpty) {
      _showMessage(
        _requiredFieldMessage(l10n.emailSettings),
        reportable: true,
        source: 'auth validation',
      );
      return;
    }
    if (!_looksLikeEmail(email)) {
      _showMessage(
        l10n.enterValidEmail,
        reportable: true,
        source: 'auth validation',
      );
      return;
    }
    if (password.isEmpty) {
      _showMessage(
        _requiredFieldMessage(l10n.password),
        reportable: true,
        source: 'auth validation',
      );
      return;
    }
    if (!_isLoginMode && username.isEmpty) {
      _showMessage(
        _requiredFieldMessage(l10n.usernameSignUp),
        reportable: true,
        source: 'auth validation',
      );
      return;
    }

    if (mounted) {
      setState(() => _isAuthSubmitting = true);
    } else {
      _isAuthSubmitting = true;
    }

    bool shouldRefreshApp = false;
    try {
      if (_isLoginMode) {
        await SupabaseService.signIn(email, password);
      } else {
        // If the email already exists and password is correct, just log in.
        try {
          await SupabaseService.signIn(email, password);
          if (!mounted) return;
          final isGerman = Localizations.localeOf(context).languageCode == 'de';
          _showMessage(isGerman
              ? 'Dieses Konto existiert bereits. Du wurdest angemeldet.'
              : 'This account already exists. You are now logged in.');
          setState(() => _isLoginMode = true);
        } catch (signInError) {
          if (!_isInvalidCredentialError(signInError)) rethrow;

          final created =
              await SupabaseService.signUp(email, password, username);
          if (!created) {
            if (!mounted) return;
            await _showExistingAccountDialog(email);
            return;
          }
          if (!mounted) return;
          final isGerman = Localizations.localeOf(context).languageCode == 'de';
          _showMessage(isGerman
              ? 'Konto erstellt. Bitte bestätige deine E-Mail.'
              : 'Account created. Please confirm your email.');
        }
      }
      _passwordCtrl.clear();
      shouldRefreshApp = SupabaseService.currentUser != null;
      if (!shouldRefreshApp) {
        await _loadProfile();
      }
      if (mounted) setState(() {});
    } catch (e, st) {
      if (!mounted) return;
      AppError.showSnackBar(
        context,
        error: e,
        stackTrace: st,
        source: _isLoginMode ? 'sign in' : 'sign up',
      );
    } finally {
      if (mounted) {
        setState(() => _isAuthSubmitting = false);
      } else {
        _isAuthSubmitting = false;
      }
    }

    if (shouldRefreshApp) {
      SupabaseService.requestAppRefresh();
    }
  }

  bool _looksLikeEmail(String value) {
    return value.contains('@') && value.contains('.');
  }

  bool get _supportsOAuthSignIn {
    if (kIsWeb) return true;

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => true,
      TargetPlatform.iOS => true,
      TargetPlatform.linux => true,
      TargetPlatform.macOS => true,
      _ => false,
    };
  }

  String get _orLabel {
    final isGerman = Localizations.localeOf(context).languageCode == 'de';
    return isGerman ? 'oder' : 'or';
  }

  String get _continueInBrowserMessage {
    final isGerman = Localizations.localeOf(context).languageCode == 'de';
    return isGerman
        ? 'Fahre im Browser fort, um die Anmeldung abzuschließen.'
        : 'Continue in your browser to finish signing in.';
  }

  bool get _supportsAppleSignIn {
    return _supportsOAuthSignIn;
  }

  Future<void> _startGoogleSignIn() async {
    await _startOAuthSignIn(
      action: SupabaseService.signInWithGoogle,
      source: 'sign in with google',
    );
  }

  Future<void> _startAppleSignIn() async {
    await _startOAuthSignIn(
      action: SupabaseService.signInWithApple,
      source: 'sign in with apple',
    );
  }

  Future<void> _startPortfolioSignIn() async {
    await _startOAuthSignIn(
      action: SupabaseService.signInWithPortfolio,
      source: 'sign in with portfolio',
    );
  }

  Future<void> _startOAuthSignIn({
    required Future<void> Function() action,
    required String source,
  }) async {
    if (_isAuthSubmitting) return;

    if (mounted) {
      setState(() => _isAuthSubmitting = true);
    } else {
      _isAuthSubmitting = true;
    }

    try {
      await action();
      if (!mounted) return;
      _showMessage(_continueInBrowserMessage);
    } catch (e, st) {
      if (!mounted) return;
      AppError.showSnackBar(
        context,
        error: e,
        stackTrace: st,
        source: source,
      );
    } finally {
      if (mounted) {
        setState(() => _isAuthSubmitting = false);
      } else {
        _isAuthSubmitting = false;
      }
    }
  }

  String _requiredFieldMessage(String fieldName) {
    final isGerman = Localizations.localeOf(context).languageCode == 'de';
    return isGerman
        ? '$fieldName ist erforderlich.'
        : '$fieldName is required.';
  }

  bool _isInvalidCredentialError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('invalid login credentials') ||
        msg.contains('invalid credentials');
  }

  Future<void> _showExistingAccountDialog(String email) async {
    final isGerman = Localizations.localeOf(context).languageCode == 'de';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            isGerman ? 'Konto existiert bereits' : 'Account already exists'),
        content: Text(isGerman
            ? 'Diese E-Mail wird bereits verwendet. Wenn das Passwort falsch ist, kannst du eine Zurücksetzen-E-Mail senden.'
            : 'This email is already in use. If the password is wrong, you can send a reset email.'),
        actions: [
          TextButton(
            onPressed: () {
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (mounted) setState(() => _isLoginMode = true);
            },
            child: Text(isGerman ? 'Zum Login' : 'Go to login'),
          ),
          ElevatedButton(
            onPressed: () async {
              await SupabaseService.resetPassword(email);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (!mounted) return;
              _showMessage(
                  AppLocalizations.of(context)!.passwordResetEmailSent);
              setState(() => _isLoginMode = true);
            },
            child: Text(isGerman ? 'Passwort zurücksetzen' : 'Reset password'),
          ),
        ],
      ),
    );
  }

  void _showMessage(
    String message, {
    bool reportable = false,
    String source = 'settings',
  }) {
    if (!mounted) return;
    if (reportable) {
      unawaited(
        AppError.showReportableSnackBar(
          context,
          message: message,
          source: source,
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String? _linkedPortfolioUid() {
    final settings = _profile?['settings'];
    if (settings is! Map) return null;

    final linkedApps = settings['linked_apps'];
    if (linkedApps is! Map) return null;

    final portfolio = linkedApps['portfolio'];
    if (portfolio is! Map) return null;

    final uid = portfolio['uid'];
    if (uid == null) return null;
    final normalized = uid.toString().trim();
    return normalized.isEmpty ? null : normalized;
  }

  Future<void> _copyTransLinkToken() async {
    final session = SupabaseService.client.auth.currentSession;
    final token = session?.accessToken;

    if (token == null || token.isEmpty) {
      final isGerman = Localizations.localeOf(context).languageCode == 'de';
      _showMessage(
        isGerman
            ? 'Du musst angemeldet sein, um ein Link-Token zu kopieren.'
            : 'You must be signed in to copy a link token.',
        reportable: true,
        source: 'copy trans link token',
      );
      return;
    }

    await Clipboard.setData(ClipboardData(text: token));

    if (!mounted) return;
    final isGerman = Localizations.localeOf(context).languageCode == 'de';
    _showMessage(
      isGerman
          ? 'Trans-Link-Token kopiert. Jetzt im Portfolio unter Konto > Verbundene Apps einfügen.'
          : 'Trans link token copied. Paste it in Portfolio > Account > Connected Apps.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = SupabaseService.currentUser;
    final colors = TransColors.of(context);
    final primaryColor = Theme.of(context).primaryColor;
    final isGerman = Localizations.localeOf(context).languageCode == 'de';
    final wakeAlarmLabel = isGerman ? 'Weckalarm' : 'Wake Alarm';
    final leaveReminderLabel =
        isGerman ? 'Abfahrts-Erinnerung' : 'Leave Reminder';
    final soundEnabledLabel = isGerman ? 'Ton aktiviert' : 'Sound enabled';
    final vibrationEnabledLabel =
        isGerman ? 'Vibration aktiviert' : 'Vibration enabled';

    // FIX: Dynamic Padding
    final topPadding = MediaQuery.of(context).padding.top + 10;

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: ListView(
            padding: const EdgeInsets.only(top: 16.0, bottom: 150.0),
            children: [
              SizedBox(height: topPadding),
              // Header Restored
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      Theme.of(context).brightness == Brightness.dark
                          ? 'lib/assets/logo_light.png'
                          : 'lib/assets/logo_dark.png',
                      height: 48,
                      width: 48,
                      errorBuilder: (c, e, s) => Icon(Icons.directions_transit,
                          size: 48, color: primaryColor),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(AppLocalizations.of(context)!.appName,
                      style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary)),
                  // DEV badge - only shows on dev builds
                  if (_isDevBuild && !_isUnstableBuild) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text("DEV",
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                    ),
                  ],
                  if (_isUnstableBuild) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.shade700,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text("UNSTABLE",
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                    ),
                  ],
                  const Spacer(),
                  // Version Display & Link
                  if (!_isUnstableBuild && _version.isNotEmpty)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (_) => _startAdvancedUnlockHold(),
                      onTapUp: (_) => _cancelAdvancedUnlockHold(),
                      onTapCancel: _cancelAdvancedUnlockHold,
                      child: InkWell(
                        onTap: () {
                          if (_suppressNextChangelogTap) {
                            _suppressNextChangelogTap = false;
                            return;
                          }
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    ChangelogScreen(currentVersion: _version)),
                          );
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Text("v$_version",
                              style: TextStyle(
                                  color: colors.textSecondary
                                      .withValues(alpha: 0.7),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14)),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 30),

              if (user != null) ...[
                Text(AppLocalizations.of(context)!.privacy,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: colors.settingsHeader)),
                const SizedBox(height: 8),
                _buildSection(context, [
                  ListTile(
                    leading: Icon(
                      widget.signalLevel == 0
                          ? Icons.visibility_off
                          : Icons.cell_tower,
                      color: widget.signalLevel == 0
                          ? colors.textSecondary
                          : colors.settingsHeader,
                    ),
                    title: Text(
                      AppLocalizations.of(context)!.journeySignal,
                      style: TextStyle(color: colors.textPrimary),
                    ),
                    subtitle: Text(
                      '${AppLocalizations.of(context)!.signalLevel(widget.signalLevel)} · '
                      '${JourneySignalLevel.title(widget.signalLevel, languageCode: Localizations.localeOf(context).languageCode)}\n'
                      '${JourneySignalLevel.description(widget.signalLevel, languageCode: Localizations.localeOf(context).languageCode)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                    trailing: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: widget.signalLevel,
                        dropdownColor: colors.cardBg,
                        items: List.generate(
                          JourneySignalLevel.maximum + 1,
                          (level) => DropdownMenuItem<int>(
                            value: level,
                            child: Text(
                              '$level · ${JourneySignalLevel.title(level, languageCode: Localizations.localeOf(context).languageCode)}',
                              style: TextStyle(color: colors.textPrimary),
                            ),
                          ),
                        ),
                        onChanged: (level) async {
                          if (level == null) return;
                          await widget.onSignalLevelChanged(level);
                          await _loadProfile();
                        },
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(
                      Icons.help_outline_rounded,
                      color: colors.settingsHeader,
                    ),
                    title: Text(
                      Localizations.localeOf(context).languageCode == 'de'
                          ? 'Stufen erklärt'
                          : 'Explain the levels',
                      style: TextStyle(color: colors.textPrimary),
                    ),
                    subtitle: Text(
                      Localizations.localeOf(context).languageCode == 'de'
                          ? 'Sieh dir an, was Freunde bei jeder Stufe sehen.'
                          : 'See what friends can see at every level.',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: colors.textSecondary,
                    ),
                    onTap: () async {
                      final level = await showJourneySignalTutorial(
                        context,
                        initialLevel: widget.signalLevel,
                      );
                      if (level == null || !mounted) return;
                      await widget.onSignalLevelChanged(level);
                      await _loadProfile();
                    },
                  ),
                ]),
                const SizedBox(height: 20),
              ],

              _buildSection(context, [
                ListTile(
                  title: Text(AppLocalizations.of(context)!.darkMode,
                      style: TextStyle(color: colors.textPrimary)),
                  subtitle: widget.useSystemTheme
                      ? Text(AppLocalizations.of(context)!.syncedWithSystem,
                          style: TextStyle(
                              fontSize: 12, color: colors.textSecondary))
                      : null,
                  trailing: Switch(
                    value: widget.isDarkMode,
                    thumbColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return widget.useSystemTheme
                            ? Colors.grey
                            : primaryColor;
                      }
                      return null;
                    }),
                    onChanged: widget.useSystemTheme
                        ? (val) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(AppLocalizations.of(context)!
                                    .systemSyncActive)));
                          }
                        : widget.onThemeChanged,
                  ),
                  onLongPress: () {
                    bool newState = !widget.useSystemTheme;
                    widget.onSystemSyncChanged(newState);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(newState
                            ? AppLocalizations.of(context)!.systemSyncEnabled
                            : AppLocalizations.of(context)!
                                .manualModeEnabled)));
                  },
                ),
                SwitchListTile(
                    title: Text(
                        AppLocalizations.of(context)!.deutschlandTicketMode,
                        style: TextStyle(color: colors.textPrimary)),
                    subtitle: Text(
                        AppLocalizations.of(context)!.onlyLocalTransport,
                        style: TextStyle(
                            fontSize: 12, color: colors.textSecondary)),
                    value: widget.onlyNahverkehr,
                    thumbColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return primaryColor;
                      }
                      return null;
                    }),
                    onChanged: widget.onNahverkehrChanged),
              ]),

              const SizedBox(height: 20),
              Text(AppLocalizations.of(context)!.appearance,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: colors.settingsHeader)),
              const SizedBox(height: 8),
              _buildSection(context, [
                ListTile(
                  title: Text(AppLocalizations.of(context)!.themeColor,
                      style: TextStyle(color: colors.textPrimary)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: (() {
                            final portfolioColor = _portfolioReservedColor();
                            final transCustomColor =
                                _transCustomSlotColor(portfolioColor);
                            return [
                              ...appThemeColors.map((c) => _colorCircle(c)),
                              _colorSeparator(),
                              if (portfolioColor != null)
                                _portfolioColorCircle(portfolioColor),
                              if (transCustomColor != null)
                                _customColorCircle(transCustomColor)
                              else
                                _customColorButton(),
                            ];
                          })(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        Localizations.localeOf(context).languageCode == 'de'
                            ? 'Tippe auf eine Farbe, den Portfolio-Slot oder auf +, um sie zu ändern. Aktuell: ${ColorClaimService.normalizeColor(widget.currentColor)}'
                            : 'Tap a color, the portfolio slot, or + to change it. Current: ${ColorClaimService.normalizeColor(widget.currentColor)}',
                        style: TextStyle(
                            fontSize: 12, color: colors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Divider(color: colors.divider), // Separator
                SwitchListTile(
                  title: Text(AppLocalizations.of(context)!.showTrainNumbers,
                      style: TextStyle(color: colors.textPrimary)),
                  subtitle: Text(AppLocalizations.of(context)!.displayTripIds,
                      style:
                          TextStyle(fontSize: 12, color: colors.textSecondary)),
                  value: widget.showTrainNumbers,
                  thumbColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return primaryColor;
                    }
                    return null;
                  }),
                  onChanged: widget.onShowTrainNumbersChanged,
                ),
                Divider(color: colors.divider),
                ListTile(
                  title: Text(AppLocalizations.of(context)!.language,
                      style: TextStyle(color: colors.textPrimary)),
                  trailing: DropdownButton<String>(
                    value: widget.locale?.languageCode ?? 'en',
                    dropdownColor: colors.cardBg,
                    underline: const SizedBox(),
                    items: [
                      DropdownMenuItem(
                          value: 'en',
                          child: Text(AppLocalizations.of(context)!.english)),
                      DropdownMenuItem(
                          value: 'de',
                          child: Text(AppLocalizations.of(context)!.german)),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        widget.onLocaleChanged(Locale(val));
                      }
                    },
                  ),
                ),
              ]),

              const SizedBox(height: 20),
              Text(AppLocalizations.of(context)!.notificationsAndHaptics,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: colors.settingsHeader)),
              const SizedBox(height: 8),
              _buildSection(context, [
                ListTile(
                    title: Text(AppLocalizations.of(context)!.alarmTrigger,
                        style: TextStyle(color: colors.textPrimary)),
                    subtitle: Text(
                        _stopsBeforeAlarm == 0
                            ? AppLocalizations.of(context)!.alertAtDestination
                            : AppLocalizations.of(context)!
                                .alertStopsBefore(_stopsBeforeAlarm.toString()),
                        style: TextStyle(
                            fontSize: 12, color: colors.textSecondary)),
                    trailing: DropdownButton<int>(
                        value: _stopsBeforeAlarm,
                        dropdownColor: colors.cardBg,
                        underline: const SizedBox(),
                        items: [
                          DropdownMenuItem(
                              value: 0,
                              child:
                                  Text(AppLocalizations.of(context)!.atDest)),
                          DropdownMenuItem(
                              value: 1,
                              child:
                                  Text(AppLocalizations.of(context)!.oneStop)),
                          DropdownMenuItem(
                              value: 2,
                              child:
                                  Text(AppLocalizations.of(context)!.twoStops)),
                          DropdownMenuItem(
                              value: 3,
                              child: Text(
                                  AppLocalizations.of(context)!.threeStops)),
                        ],
                        onChanged: (val) => _saveAlarmSettings(val!))),
                Divider(color: colors.divider),
                ListTile(
                    title: Text(AppLocalizations.of(context)!.triggerThreshold,
                        style: TextStyle(color: colors.textPrimary)),
                    subtitle: Text(
                        AppLocalizations.of(context)!.notifyAtThreshold(
                            _alarmTriggerThreshold,
                            (_alarmTriggerThreshold.contains('%'))
                                ? AppLocalizations.of(context)!.ofLegCovered
                                : AppLocalizations.of(context)!.fromTarget),
                        style: TextStyle(
                            fontSize: 12, color: colors.textSecondary)),
                    trailing: DropdownButton<String>(
                        value: _alarmTriggerThreshold,
                        dropdownColor: colors.cardBg,
                        underline: const SizedBox(),
                        items: [
                          DropdownMenuItem(
                              value: '5%',
                              child: Text(AppLocalizations.of(context)!
                                  .fivePercentRemaining)),
                          DropdownMenuItem(
                              value: '10%',
                              child: Text(AppLocalizations.of(context)!
                                  .tenPercentRemaining)),
                          DropdownMenuItem(
                              value: '500m',
                              child: Text(
                                  AppLocalizations.of(context)!.fixed500m)),
                        ],
                        onChanged: (val) => _saveAlarmThreshold(val!))),
                Divider(color: colors.divider),
                ListTile(
                  title: Builder(
                    builder: (context) {
                      final alarmSoundTitle = InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: kIsWeb ? null : _previewWakeAlarmSound,
                        onLongPress:
                            kIsWeb ? null : _showHiddenManualTimerDialog,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            AppLocalizations.of(context)!.alarmSound,
                            style: TextStyle(color: colors.textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      );

                      if (kIsWeb || !_showPreviewTooltip) {
                        return alarmSoundTitle;
                      }

                      return Tooltip(
                        message: AppLocalizations.of(context)!.previewSound,
                        child: alarmSoundTitle,
                      );
                    },
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      WakeAlarmSettings.soundForId(_wakeAlarmSound).label,
                      style:
                          TextStyle(fontSize: 12, color: colors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  trailing: DropdownButton<String>(
                    value: _wakeAlarmSound,
                    dropdownColor: colors.cardBg,
                    underline: const SizedBox(),
                    isDense: true,
                    selectedItemBuilder: (context) => [
                      ...WakeAlarmSettings.soundOptions.map(
                        (option) => SizedBox(
                          width: 120,
                          child: Text(
                            option.label,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ),
                      if (!kIsWeb)
                        const SizedBox(
                          width: 120,
                          child: Text(
                            'Add custom audio...',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                    ],
                    items: [
                      ...WakeAlarmSettings.soundOptions.map(
                        (option) => DropdownMenuItem(
                          value: option.id,
                          child: SizedBox(
                            width: 170,
                            child: option.isCustomSound
                                ? Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          option.label,
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      ),
                                      GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () async {
                                          Navigator.of(context).pop();
                                          await _removeCustomWakeAlarmSound(
                                            option,
                                          );
                                        },
                                        child: Padding(
                                          padding:
                                              const EdgeInsets.only(left: 8),
                                          child: Icon(
                                            Icons.delete_outline,
                                            size: 18,
                                            color: colors.textSecondary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : Text(
                                    option.label,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                          ),
                        ),
                      ),
                      if (!kIsWeb)
                        const DropdownMenuItem(
                          value: _pickCustomSoundValue,
                          child: Text('Add custom audio...'),
                        ),
                    ],
                    onChanged: (val) async {
                      if (val == null) return;
                      await _selectWakeAlarmSound(val);
                      if (!mounted) return;
                      setState(() => _isWakeAlarmPreviewPlaying = false);
                    },
                  ),
                ),
                Divider(color: colors.divider),
                ListTile(
                    title: Text(AppLocalizations.of(context)!.alarmPattern,
                        style: TextStyle(color: colors.textPrimary)),
                    trailing: DropdownButton<String>(
                        value: _vibrationPattern,
                        dropdownColor: colors.cardBg,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(
                              value: 'standard', child: Text("Standard")),
                          DropdownMenuItem(
                              value: 'heartbeat', child: Text("Heartbeat")),
                          DropdownMenuItem(value: 'tick', child: Text("Tick")),
                          DropdownMenuItem(
                              value: 'mario', child: Text("Mario")),
                          DropdownMenuItem(
                              value: 'fox', child: Text("20th Century")),
                          DropdownMenuItem(
                              value: 'imperial', child: Text("Imperial March")),
                          DropdownMenuItem(
                              value: 'potter', child: Text("Harry Potter")),
                          DropdownMenuItem(
                              value: 'indy', child: Text("Indiana Jones")),
                          DropdownMenuItem(
                              value: 'mission',
                              child: Text("Mission Impossible")),
                          DropdownMenuItem(
                              value: 'terminator', child: Text("Terminator")),
                          DropdownMenuItem(
                              value: 'future', child: Text("Back to Future")),
                          DropdownMenuItem(
                              value: 'eva', child: Text("Evangelion")),
                          DropdownMenuItem(
                              value: 'pokemon', child: Text("Pokémon")),
                          DropdownMenuItem(
                              value: 'titan', child: Text("Attack on Titan")),
                          DropdownMenuItem(
                              value: 'bebop', child: Text("Cowboy Bebop")),
                        ],
                        onChanged: (val) async {
                          if (val == null) return;
                          setState(() => _vibrationPattern = val);
                          await _persistVibrationSettings();
                          _testVibration();
                        })),
                if (defaultTargetPlatform != TargetPlatform.iOS)
                  ListTile(
                      title: Text(
                          AppLocalizations.of(context)!.vibrationIntensity,
                          style: TextStyle(color: colors.textPrimary)),
                      subtitle: Slider(
                          value: _vibrationIntensity.toDouble(),
                          min: 1,
                          max: 255,
                          activeColor: colors.effectiveSeed,
                          thumbColor: colors.effectiveSeed,
                          onChanged: (val) {
                            setState(() => _vibrationIntensity = val.toInt());
                          },
                          onChangeEnd: (val) {
                            _persistVibrationSettings();
                            _testVibration();
                          })),
                Divider(color: colors.divider),
                ListTile(
                  title: Text(wakeAlarmLabel,
                      style: TextStyle(
                          color: colors.textSecondary,
                          fontWeight: FontWeight.w600)),
                ),
                SwitchListTile(
                  title: Text(soundEnabledLabel,
                      style: TextStyle(color: colors.textPrimary)),
                  value: _wakeAlarmSoundEnabled,
                  thumbColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return primaryColor;
                    }
                    return null;
                  }),
                  onChanged: (val) async {
                    setState(() => _wakeAlarmSoundEnabled = val);
                    await _persistAlarmDeliverySettings();
                  },
                ),
                Divider(color: colors.divider),
                SwitchListTile(
                  title: Text(vibrationEnabledLabel,
                      style: TextStyle(color: colors.textPrimary)),
                  value: _wakeAlarmVibrationEnabled,
                  thumbColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return primaryColor;
                    }
                    return null;
                  }),
                  onChanged: (val) async {
                    setState(() => _wakeAlarmVibrationEnabled = val);
                    await _persistAlarmDeliverySettings();
                  },
                ),
                Divider(color: colors.divider),
                SwitchListTile(
                  title: Text(AppLocalizations.of(context)!.alwaysWakeMe,
                      style: TextStyle(color: colors.textPrimary)),
                  subtitle: Text(
                      AppLocalizations.of(context)!.turnOnAlarmDefault,
                      style:
                          TextStyle(fontSize: 12, color: colors.textSecondary)),
                  value: widget.alwaysWakeMe,
                  thumbColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return primaryColor;
                    }
                    return null;
                  }),
                  onChanged: widget.onAlwaysWakeMeChanged,
                ),
                Divider(color: colors.divider),
                ListTile(
                  title: Text(leaveReminderLabel,
                      style: TextStyle(
                          color: colors.textSecondary,
                          fontWeight: FontWeight.w600)),
                ),
                SwitchListTile(
                  title: Text(soundEnabledLabel,
                      style: TextStyle(color: colors.textPrimary)),
                  value: _leaveAlarmSoundEnabled,
                  thumbColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return primaryColor;
                    }
                    return null;
                  }),
                  onChanged: (val) async {
                    setState(() => _leaveAlarmSoundEnabled = val);
                    await _persistAlarmDeliverySettings();
                  },
                ),
                Divider(color: colors.divider),
                SwitchListTile(
                  title: Text(vibrationEnabledLabel,
                      style: TextStyle(color: colors.textPrimary)),
                  value: _leaveAlarmVibrationEnabled,
                  thumbColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return primaryColor;
                    }
                    return null;
                  }),
                  onChanged: (val) async {
                    setState(() => _leaveAlarmVibrationEnabled = val);
                    await _persistAlarmDeliverySettings();
                  },
                ),
              ]),

              const SizedBox(height: 20),
              Text(AppLocalizations.of(context)!.dataAndPrivacy,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: colors.settingsHeader)),
              const SizedBox(height: 8),
              _buildSection(context, [
                ListTile(
                    leading: Icon(Icons.gavel_outlined,
                        color: colors.settingsHeader),
                    title: Text(
                        isGerman
                            ? 'Nutzungsbedingungen & Community-Regeln'
                            : 'Terms of Use & Community Rules',
                        style: TextStyle(color: colors.textPrimary)),
                    subtitle: Text(
                        isGerman
                            ? 'Keine Toleranz für anstößige Inhalte oder missbräuchliche Nutzer.'
                            : 'No tolerance for objectionable content or abusive users.',
                        style: TextStyle(
                            fontSize: 12, color: colors.textSecondary)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () =>
                        CommunitySafetyService.showCommunityTerms(context)),
                Divider(height: 1, color: colors.divider),
                ListTile(
                    leading: Icon(Icons.block, color: colors.iconBlock),
                    title: Text(AppLocalizations.of(context)!.blockedUsers,
                        style: TextStyle(color: colors.textPrimary)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: _showBlockedUsers),
                Divider(height: 1, color: colors.divider),
                ListTile(
                    leading:
                        Icon(Icons.delete_outline, color: colors.iconDelete),
                    title: Text(
                        AppLocalizations.of(context)!.clearSearchHistory,
                        style: TextStyle(color: Colors.red)),
                    onTap: _clearHistory),
              ]),

              const SizedBox(height: 20),
              Text(AppLocalizations.of(context)!.dataSourceAdvanced,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: colors.settingsHeader)),
              const SizedBox(height: 8),
              _buildSection(context, [
                ListTile(
                  title: Text(AppLocalizations.of(context)!.transportApi,
                      style: TextStyle(color: colors.textPrimary)),
                  subtitle: Text(
                      AppLocalizations.of(context)!.selectedApiMode(
                        _selectedApiSourcesSummary(
                            AppLocalizations.of(context)!),
                      ),
                      style:
                          TextStyle(fontSize: 12, color: colors.textSecondary)),
                )
              ]),
              const SizedBox(height: 8),
              _buildSection(context, [
                CheckboxListTile(
                  value: _enabledApiSources
                      .contains(TransportApi.sourceTransitous),
                  activeColor: Colors.blue,
                  controlAffinity: ListTileControlAffinity.trailing,
                  title: Text(
                    'Transitous',
                    style: TextStyle(color: colors.textPrimary),
                  ),
                  subtitle: Text(
                    AppLocalizations.of(context)!.transitousOpenSource,
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                  secondary:
                      const Icon(Icons.circle, color: Colors.blue, size: 14),
                  onChanged: _enabledApiSources.contains(
                            TransportApi.sourceTransitous,
                          ) &&
                          !_canDisableTransitous()
                      ? null
                      : (value) => _toggleApiSource(
                            TransportApi.sourceTransitous,
                            value ?? false,
                          ),
                ),
                Divider(height: 1, color: colors.divider),
                CheckboxListTile(
                  value: _enabledApiSources.contains(
                    TransportApi.sourceSyntheticTransitous,
                  ),
                  activeColor: Colors.green,
                  controlAffinity: ListTileControlAffinity.trailing,
                  title: Text(
                    _syntheticTransitousLabel(AppLocalizations.of(context)!),
                    style: TextStyle(color: colors.textPrimary),
                  ),
                  subtitle: Text(
                    _syntheticTransitousDescription(
                        AppLocalizations.of(context)!),
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                  secondary:
                      const Icon(Icons.circle, color: Colors.green, size: 14),
                  onChanged:
                      _enabledApiSources.contains(TransportApi.sourceTransitous)
                          ? (value) => _toggleApiSource(
                                TransportApi.sourceSyntheticTransitous,
                                value ?? false,
                              )
                          : null,
                ),
                Divider(height: 1, color: colors.divider),
                CheckboxListTile(
                  value: _enabledApiSources.contains(TransportApi.sourceDbV6),
                  activeColor: Colors.red,
                  controlAffinity: ListTileControlAffinity.trailing,
                  title: Text(
                    AppLocalizations.of(context)!.dbV6,
                    style: TextStyle(color: colors.textPrimary),
                  ),
                  subtitle: Text(
                    AppLocalizations.of(context)!.deutscheBahnLegacy,
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                  secondary:
                      const Icon(Icons.circle, color: Colors.red, size: 14),
                  onChanged:
                      _enabledApiSources.contains(TransportApi.sourceDbV6) &&
                              !_canDisableDbV6()
                          ? null
                          : (value) => _toggleApiSource(
                                TransportApi.sourceDbV6,
                                value ?? false,
                              ),
                ),
              ]),
              if (_isUnstableBuild) ...[
                const SizedBox(height: 20),
                _buildSection(context, [
                  SwitchListTile(
                    value: _advancedSettingsEnabledForDevice,
                    activeThumbColor: colors.effectiveSeed,
                    title: Text(
                      isGerman
                          ? 'Erweiterte Sucheinstellungen'
                          : 'Advanced search settings',
                      style: TextStyle(color: colors.textPrimary),
                    ),
                    subtitle: Text(
                      isGerman
                          ? 'Erweiterte Suche ein- oder ausschalten'
                          : 'Turn advanced search on or off',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                    onChanged: _setAdvancedSettingsEnabledForDevice,
                  ),
                ]),
              ],
              if (_advancedSettingsEnabledForDevice) ...[
                const SizedBox(height: 20),
                Text(
                  isGerman
                      ? 'Erweiterte Suche (Gerät)'
                      : 'Advanced Search (Device)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: colors.settingsHeader,
                  ),
                ),
                const SizedBox(height: 8),
                _buildSection(context, [
                  ListTile(
                    title: Text(
                      isGerman
                          ? 'Minimale Umstiegszeit'
                          : 'Minimum transfer time',
                      style: TextStyle(color: colors.textPrimary),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isGerman
                              ? 'Unter diesem Wert werden Verbindungen mit zu knappem Umstieg verworfen. Aktuell: $_advancedMinTransferTimeMinutes min.'
                              : 'Connections requiring less than this change time are filtered out. Current: $_advancedMinTransferTimeMinutes min.',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Slider(
                                value:
                                    _advancedMinTransferTimeMinutes.toDouble(),
                                min: 0,
                                max: 20,
                                divisions: 20,
                                activeColor: colors.effectiveSeed,
                                thumbColor: colors.effectiveSeed,
                                onChanged: (value) {
                                  setState(
                                    () => _advancedMinTransferTimeMinutes =
                                        value.round(),
                                  );
                                },
                                onChangeEnd: (_) async {
                                  await _persistAdvancedSearchPreferences();
                                },
                              ),
                            ),
                            IconButton(
                              tooltip: isGerman
                                  ? 'Auf Standard zurücksetzen'
                                  : 'Reset to default',
                              icon: Icon(Icons.refresh,
                                  color: colors.textSecondary),
                              onPressed: _advancedMinTransferTimeMinutes ==
                                      _defaultAdvancedMinTransferTimeMinutes
                                  ? null
                                  : () async {
                                      setState(() {
                                        _advancedMinTransferTimeMinutes =
                                            _defaultAdvancedMinTransferTimeMinutes;
                                      });
                                      await _persistAdvancedSearchPreferences();
                                    },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Divider(color: colors.divider),
                  ListTile(
                    title: Text(
                      isGerman
                          ? 'Zusätzliche Umstiegszeit'
                          : 'Additional transfer time',
                      style: TextStyle(color: colors.textPrimary),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isGerman
                              ? 'Fügt jedem Umstieg pauschal Extra-Puffer hinzu. Höher = sicherer, aber oft langsamer. Aktuell: $_advancedAdditionalTransferTimeMinutes min.'
                              : 'Adds fixed extra buffer to every transfer. Higher = safer, but often slower. Current: $_advancedAdditionalTransferTimeMinutes min.',
                          style: TextStyle(
                              fontSize: 12, color: colors.textSecondary),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Slider(
                                value: _advancedAdditionalTransferTimeMinutes
                                    .toDouble(),
                                min: 0,
                                max: 15,
                                divisions: 15,
                                activeColor: colors.effectiveSeed,
                                thumbColor: colors.effectiveSeed,
                                onChanged: (value) {
                                  setState(
                                    () =>
                                        _advancedAdditionalTransferTimeMinutes =
                                            value.round(),
                                  );
                                },
                                onChangeEnd: (_) async {
                                  await _persistAdvancedSearchPreferences();
                                },
                              ),
                            ),
                            IconButton(
                              tooltip: isGerman
                                  ? 'Auf Standard zurücksetzen'
                                  : 'Reset to default',
                              icon: Icon(Icons.refresh,
                                  color: colors.textSecondary),
                              onPressed: _advancedAdditionalTransferTimeMinutes ==
                                      _defaultAdvancedAdditionalTransferTimeMinutes
                                  ? null
                                  : () async {
                                      setState(() {
                                        _advancedAdditionalTransferTimeMinutes =
                                            _defaultAdvancedAdditionalTransferTimeMinutes;
                                      });
                                      await _persistAdvancedSearchPreferences();
                                    },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Divider(color: colors.divider),
                  ListTile(
                    title: Text(
                      isGerman ? 'Umstiegsfaktor' : 'Transfer time factor',
                      style: TextStyle(color: colors.textPrimary),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isGerman
                              ? 'Gewichtet Umstiegszeit in der Routenbewertung. Höher = weniger/entspanntere Umstiege bevorzugt, niedriger = aggressiv schneller. Aktuell: ${_advancedTransferTimeFactor.toStringAsFixed(1)}.'
                              : 'Weights transfer time in route scoring. Higher = prefers fewer/looser transfers, lower = more aggressive fast options. Current: ${_advancedTransferTimeFactor.toStringAsFixed(1)}.',
                          style: TextStyle(
                              fontSize: 12, color: colors.textSecondary),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Slider(
                                value: _advancedTransferTimeFactor,
                                min: 0.7,
                                max: 2.5,
                                divisions: 18,
                                activeColor: colors.effectiveSeed,
                                thumbColor: colors.effectiveSeed,
                                onChanged: (value) {
                                  setState(
                                    () => _advancedTransferTimeFactor =
                                        (value * 10).round() / 10,
                                  );
                                },
                                onChangeEnd: (_) async {
                                  await _persistAdvancedSearchPreferences();
                                },
                              ),
                            ),
                            IconButton(
                              tooltip: isGerman
                                  ? 'Auf Standard zurücksetzen'
                                  : 'Reset to default',
                              icon: Icon(Icons.refresh,
                                  color: colors.textSecondary),
                              onPressed: (_advancedTransferTimeFactor -
                                              _defaultAdvancedTransferTimeFactor)
                                          .abs() <
                                      0.0001
                                  ? null
                                  : () async {
                                      setState(() {
                                        _advancedTransferTimeFactor =
                                            _defaultAdvancedTransferTimeFactor;
                                      });
                                      await _persistAdvancedSearchPreferences();
                                    },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _buildTransferImpactPreview(isGerman, colors),
                  Divider(color: colors.divider),
                  ListTile(
                    title: Text(
                      isGerman ? 'Pre-Transit Modi' : 'Pre-transit modes',
                      style: TextStyle(color: colors.textPrimary),
                    ),
                    subtitle: Text(
                      isGerman
                          ? 'Modi vor dem ersten ÖPNV-Abschnitt.'
                          : 'Modes before the first transit leg.',
                      style:
                          TextStyle(fontSize: 12, color: colors.textSecondary),
                    ),
                  ),
                  SwitchListTile(
                    title: Text(
                      _modeLabel('WALK', isGerman),
                      style: TextStyle(color: colors.textPrimary),
                    ),
                    value: _advancedPreTransitWalkEnabled,
                    thumbColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return primaryColor;
                      }
                      return null;
                    }),
                    onChanged: (value) async {
                      setState(() => _advancedPreTransitWalkEnabled = value);
                      await _persistAdvancedSearchPreferences();
                    },
                  ),
                  Divider(color: colors.divider),
                  SwitchListTile(
                    title: Text(
                      _modeLabel('BICYCLE', isGerman),
                      style: TextStyle(color: colors.textPrimary),
                    ),
                    value: _advancedPreTransitBikeEnabled,
                    thumbColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return primaryColor;
                      }
                      return null;
                    }),
                    onChanged: (value) async {
                      setState(() => _advancedPreTransitBikeEnabled = value);
                      await _persistAdvancedSearchPreferences();
                    },
                  ),
                  Divider(color: colors.divider),
                  ListTile(
                    title: Text(
                      isGerman ? 'Post-Transit Modi' : 'Post-transit modes',
                      style: TextStyle(color: colors.textPrimary),
                    ),
                    subtitle: Text(
                      isGerman
                          ? 'Modi nach dem letzten ÖPNV-Abschnitt.'
                          : 'Modes after the last transit leg.',
                      style:
                          TextStyle(fontSize: 12, color: colors.textSecondary),
                    ),
                  ),
                  SwitchListTile(
                    title: Text(
                      _modeLabel('WALK', isGerman),
                      style: TextStyle(color: colors.textPrimary),
                    ),
                    value: _advancedPostTransitWalkEnabled,
                    thumbColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return primaryColor;
                      }
                      return null;
                    }),
                    onChanged: (value) async {
                      setState(() => _advancedPostTransitWalkEnabled = value);
                      await _persistAdvancedSearchPreferences();
                    },
                  ),
                  Divider(color: colors.divider),
                  SwitchListTile(
                    title: Text(
                      _modeLabel('BICYCLE', isGerman),
                      style: TextStyle(color: colors.textPrimary),
                    ),
                    value: _advancedPostTransitBikeEnabled,
                    thumbColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return primaryColor;
                      }
                      return null;
                    }),
                    onChanged: (value) async {
                      setState(() => _advancedPostTransitBikeEnabled = value);
                      await _persistAdvancedSearchPreferences();
                    },
                  ),
                  Divider(color: colors.divider),
                  ListTile(
                    title: Text(
                      isGerman ? 'Gehgeschwindigkeit' : 'Walking speed',
                      style: TextStyle(color: colors.textPrimary),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isGerman
                              ? 'Beeinflusst Fußwege und Transfers. Aktuell: ${_advancedPedestrianSpeedKmh.toStringAsFixed(1)} km/h'
                              : 'Affects walking legs and transfers. Current: ${_advancedPedestrianSpeedKmh.toStringAsFixed(1)} km/h',
                          style: TextStyle(
                              fontSize: 12, color: colors.textSecondary),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Slider(
                                value: _advancedPedestrianSpeedKmh,
                                min: 2,
                                max: 10,
                                divisions: 80,
                                activeColor: colors.effectiveSeed,
                                thumbColor: colors.effectiveSeed,
                                onChanged: (value) {
                                  setState(
                                    () => _advancedPedestrianSpeedKmh =
                                        (value * 10).round() / 10,
                                  );
                                },
                                onChangeEnd: (_) async {
                                  await _persistAdvancedSearchPreferences();
                                },
                              ),
                            ),
                            IconButton(
                              tooltip: isGerman
                                  ? 'Auf Standard zurücksetzen'
                                  : 'Reset to default',
                              icon: Icon(Icons.refresh,
                                  color: colors.textSecondary),
                              onPressed: (_advancedPedestrianSpeedKmh -
                                              _defaultAdvancedPedestrianSpeedKmh)
                                          .abs() <
                                      0.0001
                                  ? null
                                  : () async {
                                      setState(() {
                                        _advancedPedestrianSpeedKmh =
                                            _defaultAdvancedPedestrianSpeedKmh;
                                      });
                                      await _persistAdvancedSearchPreferences();
                                    },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Divider(color: colors.divider),
                  ListTile(
                    title: Text(
                      isGerman ? 'Maximale Gehzeit' : 'Maximum walking time',
                      style: TextStyle(color: colors.textPrimary),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isGerman
                              ? 'Begrenzt Zu-/Abweg zu Transit in Minuten (pre/post). Aktuell: $_advancedMaxWalkingTimeMinutes min'
                              : 'Limits first/last-mile walking to transit in minutes (pre/post). Current: $_advancedMaxWalkingTimeMinutes min',
                          style: TextStyle(
                              fontSize: 12, color: colors.textSecondary),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Slider(
                                value:
                                    _advancedMaxWalkingTimeMinutes.toDouble(),
                                min: 5,
                                max: 120,
                                divisions: 23,
                                activeColor: colors.effectiveSeed,
                                thumbColor: colors.effectiveSeed,
                                onChanged: (value) {
                                  setState(
                                    () => _advancedMaxWalkingTimeMinutes =
                                        value.round(),
                                  );
                                },
                                onChangeEnd: (_) async {
                                  await _persistAdvancedSearchPreferences();
                                },
                              ),
                            ),
                            IconButton(
                              tooltip: isGerman
                                  ? 'Auf Standard zurücksetzen'
                                  : 'Reset to default',
                              icon: Icon(Icons.refresh,
                                  color: colors.textSecondary),
                              onPressed: _advancedMaxWalkingTimeMinutes ==
                                      _defaultAdvancedMaxWalkingTimeMinutes
                                  ? null
                                  : () async {
                                      setState(() {
                                        _advancedMaxWalkingTimeMinutes =
                                            _defaultAdvancedMaxWalkingTimeMinutes;
                                      });
                                      await _persistAdvancedSearchPreferences();
                                    },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Divider(color: colors.divider),
                  ListTile(
                    title: Text(
                      isGerman ? 'Fahrradgeschwindigkeit' : 'Cycling speed',
                      style: TextStyle(color: colors.textPrimary),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isGerman
                              ? 'Wird nur genutzt, wenn Fahrrad-Modi aktiv sind. Aktuell: ${_advancedCyclingSpeedKmh.toStringAsFixed(0)} km/h'
                              : 'Used only when bicycle modes are enabled. Current: ${_advancedCyclingSpeedKmh.toStringAsFixed(0)} km/h',
                          style: TextStyle(
                              fontSize: 12, color: colors.textSecondary),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Slider(
                                value: _advancedCyclingSpeedKmh,
                                min: 8,
                                max: 30,
                                divisions: 22,
                                activeColor: colors.effectiveSeed,
                                thumbColor: colors.effectiveSeed,
                                onChanged: (value) {
                                  setState(
                                      () => _advancedCyclingSpeedKmh = value);
                                },
                                onChangeEnd: (_) async {
                                  await _persistAdvancedSearchPreferences();
                                },
                              ),
                            ),
                            IconButton(
                              tooltip: isGerman
                                  ? 'Auf Standard zurücksetzen'
                                  : 'Reset to default',
                              icon: Icon(Icons.refresh,
                                  color: colors.textSecondary),
                              onPressed: (_advancedCyclingSpeedKmh -
                                              _defaultAdvancedCyclingSpeedKmh)
                                          .abs() <
                                      0.0001
                                  ? null
                                  : () async {
                                      setState(() {
                                        _advancedCyclingSpeedKmh =
                                            _defaultAdvancedCyclingSpeedKmh;
                                      });
                                      await _persistAdvancedSearchPreferences();
                                    },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ]),
              ],
              const SizedBox(height: 20),
              if (user == null)
                _buildAuthForm(context, colors)
              else
                _buildProfileSection(context, user, colors),
            ],
          ),
        ),
        if (_advancedUnlockCountdownSecondsLeft != null)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: colors.cardBg.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colors.effectiveSeed.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isGerman
                            ? 'Du bist dabei, die erweiterten Einstellungen auf diesem Gerät zu aktivieren.'
                            : 'You are about to unlock advanced settings for this device.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${_advancedUnlockCountdownSecondsLeft!}s',
                        style: TextStyle(
                          color: colors.effectiveSeed,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  bool _isBuiltInColor(Color color) {
    final argb = color.toARGB32();
    return appThemeColors.any((c) => c.toARGB32() == argb);
  }

  Color? _portfolioReservedColor() {
    final settings = _profile?['settings'];
    if (settings is! Map) return null;

    final claim = settings['theme_color_claim'];
    if (claim is! Map) return null;

    final rawHex = claim['hex']?.toString();
    if (rawHex == null || rawHex.trim().isEmpty) return null;

    final syncState = claim['sync_state']?.toString();
    final linkedPortfolioUid = claim['linked_portfolio_uid']?.toString();
    final hasPortfolioReservation = syncState == 'synced' ||
        (linkedPortfolioUid != null && linkedPortfolioUid.trim().isNotEmpty);
    if (!hasPortfolioReservation) return null;

    try {
      final hex = ColorClaimService.normalizeHex(rawHex);
      final value = int.parse(hex.substring(1), radix: 16);
      return Color(0xFF000000 | value);
    } on ColorClaimException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Color? _transCustomSlotColor(Color? portfolioColor) {
    if (_isBuiltInColor(widget.currentColor)) return null;
    if (portfolioColor != null &&
        portfolioColor.toARGB32() == widget.currentColor.toARGB32()) {
      return null;
    }
    return widget.currentColor;
  }

  Future<void> _handleThemeColorTap(Color color) async {
    final pendingArgb = color.toARGB32();
    if (_pendingThemeColorArgb == pendingArgb) return;

    setState(() => _pendingThemeColorArgb = pendingArgb);
    try {
      // Built-in colors can be used freely without checking availability
      if (_isBuiltInColor(color)) {
        await widget.onColorChanged(color);
        return;
      }

      // Custom colors require user to be logged in
      if (SupabaseService.currentUser == null) {
        await widget.onColorChanged(color);
        return;
      }

      final status = await ColorClaimService.checkAvailability(
        color,
        currentProfile: _profile,
      );
      if (!mounted) return;

      if (status.isUnavailableInTrans) {
        final owner = status.transOwnerLabel ?? 'another user';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_localizedColorTakenMessage(owner)),
          ),
        );
        return;
      }

      final claimResult = await ColorClaimService.claimColor(
        color,
        currentProfile: _profile,
      );
      await widget.onColorChanged(color);
      if (!mounted) return;

      final message = _buildThemeColorSuccessMessage(
        status,
        claimResult,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      unawaited(_loadProfile());
    } on ColorClaimException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save that theme color: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _pendingThemeColorArgb = null);
      }
    }
  }

  String _localizedColorTakenMessage(String owner) {
    final isGerman = Localizations.localeOf(context).languageCode == 'de';
    if (isGerman) {
      return 'Diese Farbe ist in Trans bereits von $owner beansprucht. Reserviere sie auf der Portfolio-Seite, wenn du eine app-übergreifende Farbe willst.';
    }
    return 'That color is already claimed in Trans by $owner. Reserve it on the portfolio site if you want a color that carries across apps.';
  }

  String _buildThemeColorSuccessMessage(
    ColorClaimStatus status,
    ColorClaimResult result,
  ) {
    final isGerman = Localizations.localeOf(context).languageCode == 'de';

    if (status.isTransOnlyAvailability) {
      final owner = status.portfolioOwnerLabel;
      if (isGerman) {
        return owner != null && owner.isNotEmpty
            ? 'Farbe in Trans gespeichert. Portfolio-weit ist sie bereits von $owner reserviert, also gilt sie hier nur für Trans. Wenn du dieselbe Farbe in allen Apps willst, reserviere sie auf der Portfolio-Seite.'
            : 'Farbe in Trans gespeichert. Portfolio-weit ist sie bereits reserviert, also gilt sie hier nur für Trans. Wenn du dieselbe Farbe in allen Apps willst, reserviere sie auf der Portfolio-Seite.';
      }
      return owner != null && owner.isNotEmpty
          ? 'Color saved in Trans. It is already reserved portfolio-wide by $owner, so this save only applies inside Trans. Reserve it on the portfolio site if you want the same color across all apps.'
          : 'Color saved in Trans. It is already reserved portfolio-wide, so this save only applies inside Trans. Reserve it on the portfolio site if you want the same color across all apps.';
    }

    if (status.portfolioClaimedByCurrentUser) {
      return isGerman
          ? 'Farbe in Trans gespeichert. Deine Portfolio-Reservierung deckt diese Farbe bereits app-übergreifend ab.'
          : 'Color saved in Trans. Your portfolio reservation already covers this color across apps.';
    }

    if (!status.portfolioStatusChecked) {
      return isGerman
          ? 'Farbe in Trans gespeichert. Die globale Verfügbarkeit konnte nicht geprüft werden. Wenn du dieselbe Farbe in allen Apps willst, reserviere sie auf der Portfolio-Seite.'
          : 'Color saved in Trans. Global availability could not be checked. Reserve it on the portfolio site if you want the same color across all apps.';
    }

    if (!result.attemptedPortfolioSync) {
      return isGerman
          ? 'Farbe in Trans gespeichert. Sie ist derzeit nur in Trans gesichert. Reserviere sie auf der Portfolio-Seite, wenn du sie app-übergreifend willst.'
          : 'Color saved in Trans. It is secured in Trans only for now. Reserve it on the portfolio site if you want it across all apps.';
    }

    if (!result.syncedToPortfolio) {
      return isGerman
          ? 'Farbe in Trans gespeichert. Die Sync-Vorbereitung für das Portfolio ist noch nicht abgeschlossen. Reserviere sie auf der Portfolio-Seite, wenn du sie app-übergreifend willst.'
          : 'Color saved in Trans. Portfolio sync is not finished yet. Reserve it on the portfolio site if you want it across all apps.';
    }

    return isGerman
        ? 'Farbe in Trans gespeichert. Wenn du dieselbe Farbe in allen Apps behalten willst, verwalte die Reservierung auf der Portfolio-Seite.'
        : 'Color saved in Trans. Manage the reservation on the portfolio site if you want to keep the same color across all apps.';
  }

  Future<void> _openCustomColorDialog() async {
    if (SupabaseService.currentUser == null) {
      if (!mounted) return;
      final isGerman = Localizations.localeOf(context).languageCode == 'de';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isGerman
                ? 'Melde dich an, um eine eigene Theme-Farbe zu verwenden und zu reservieren.'
                : 'Sign in to use and reserve a custom theme color.',
          ),
        ),
      );
      return;
    }

    final controller = TextEditingController(
      text: ColorClaimService.normalizeColor(widget.currentColor),
    );
    final rawValue = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final dialogColors = TransColors.of(dialogContext);
        final isGerman =
            Localizations.localeOf(dialogContext).languageCode == 'de';
        return AlertDialog(
          title: Text(isGerman ? 'Eigene Farbe' : 'Custom Color'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.none,
                decoration: const InputDecoration(
                  labelText: '#rrggbb',
                  hintText: '#5bcefa',
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  isGerman
                      ? 'Nur 6-stellige Hex-Farben werden unterstützt.'
                      : 'Only 6-digit hex colors are supported.',
                  style: TextStyle(
                      fontSize: 12, color: dialogColors.textSecondary),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(AppLocalizations.of(dialogContext)!.cancel),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: Text(isGerman ? 'Übernehmen' : 'Apply'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (rawValue == null || rawValue.isEmpty || !mounted) return;

    try {
      final hex = ColorClaimService.normalizeHex(rawValue);
      final value = int.parse(hex.substring(1), radix: 16);
      final color = Color(0xFF000000 | value);

      // Check if the color is a built-in color
      if (_isBuiltInColor(color)) {
        if (!mounted) return;
        final isGerman = Localizations.localeOf(context).languageCode == 'de';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isGerman
                  ? 'Diese Farbe ist bereits eine eingebaute Theme-Farbe. Wähle sie aus der Liste aus.'
                  : 'That color is already a built-in theme color. Select it from the list.',
            ),
          ),
        );
        return;
      }

      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
      await _handleThemeColorTap(color);
    } on ColorClaimException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  Widget _colorSeparator() {
    final colors = TransColors.of(context);
    return Container(
      width: 2,
      height: 30,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: colors.isDark ? Colors.white : Colors.black,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }

  Widget _customColorButton() {
    final colors = TransColors.of(context);
    return GestureDetector(
      onTap: _openCustomColorDialog,
      child: Container(
        width: 30,
        height: 30,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        decoration: BoxDecoration(
          color: colors.cardBg,
          shape: BoxShape.circle,
          border: Border.all(color: colors.divider),
        ),
        child: Icon(Icons.add, size: 18, color: colors.textPrimary),
      ),
    );
  }

  Widget _customColorCircle(Color color) {
    final isSelected = widget.currentColor.toARGB32() == color.toARGB32();
    final isPending = _pendingThemeColorArgb == color.toARGB32();

    return GestureDetector(
      onTap: () => _handleThemeColorTap(color),
      child: Container(
        width: 30,
        height: 30,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isSelected ? Border.all(color: Colors.white, width: 3) : null,
          boxShadow: isSelected
              ? [const BoxShadow(color: Colors.black26, blurRadius: 4)]
              : null,
        ),
        child: isSelected
            ? const Icon(Icons.check, size: 16, color: Colors.white)
            : isPending
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : null,
      ),
    );
  }

  Widget _portfolioColorCircle(Color color) {
    final isSelected = widget.currentColor.toARGB32() == color.toARGB32();
    final isPending = _pendingThemeColorArgb == color.toARGB32();

    return GestureDetector(
      onTap: () => _handleThemeColorTap(color),
      child: Container(
        width: 30,
        height: 30,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? Colors.white : Colors.white70,
            width: isSelected ? 3 : 1.5,
          ),
          boxShadow: isSelected
              ? [const BoxShadow(color: Colors.black26, blurRadius: 4)]
              : null,
        ),
        child: isSelected
            ? const Icon(Icons.check, size: 16, color: Colors.white)
            : isPending
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.lock_outline, size: 14, color: Colors.white),
      ),
    );
  }

  Widget _colorCircle(Color color) {
    final isSelected = widget.currentColor.toARGB32() == color.toARGB32();
    final isPending = _pendingThemeColorArgb == color.toARGB32();
    return GestureDetector(
      onTap: () => _handleThemeColorTap(color),
      child: Container(
        width: 30,
        height: 30,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border:
                isSelected ? Border.all(color: Colors.white, width: 3) : null,
            boxShadow: isSelected
                ? [const BoxShadow(color: Colors.black26, blurRadius: 4)]
                : null),
        child: isSelected
            ? const Icon(Icons.check, size: 16, color: Colors.white)
            : isPending
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : null,
      ),
    );
  }

  Widget _buildProfileSection(BuildContext context, user, TransColors colors) {
    final emoji = _profile?['avatar_emoji'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(AppLocalizations.of(context)!.profileSettings,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary)),
          const SizedBox(width: 16),
          GestureDetector(
              onTap: _pickAvatar,
              child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                      color: widget.currentColor, shape: BoxShape.circle),
                  child: ClipOval(
                      child: (emoji != null)
                          ? Center(
                              child: Text(emoji,
                                  style: const TextStyle(fontSize: 24)))
                          : const Icon(Icons.emoji_emotions,
                              size: 24, color: Colors.white)))),
          const SizedBox(width: 12),
          _buildMyStatus(colors),
        ]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: colors.settingsSectionBg,
              borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _profile?['username'] ??
                      AppLocalizations.of(context)!.noUsername,
                  style: TextStyle(fontSize: 18, color: colors.textPrimary),
                ),
                subtitle: Text(user.email ?? "",
                    style: TextStyle(color: colors.textSecondary)),
              ),
              Divider(color: colors.divider),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: Text(AppLocalizations.of(context)!.changeUsername,
                    style: TextStyle(color: colors.textPrimary)),
                subtitle: Text(
                  _profile?['username'] ??
                      AppLocalizations.of(context)!.noUsername,
                  style: TextStyle(color: colors.textSecondary),
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: _showUsernameDialog,
              ),
              Divider(color: colors.divider),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.alternate_email),
                title: Text(AppLocalizations.of(context)!.changeEmail,
                    style: TextStyle(color: colors.textPrimary)),
                subtitle: Text(user.email ?? "",
                    style: TextStyle(color: colors.textSecondary)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => _showEmailDialog((user.email ?? '').toString()),
              ),
              Divider(color: colors.divider),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lock_outline),
                title: Text(AppLocalizations.of(context)!.changePassword,
                    style: TextStyle(color: colors.textPrimary)),
                subtitle: Text(AppLocalizations.of(context)!.passwordChangeHint,
                    style: TextStyle(color: colors.textSecondary)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: _showChangePasswordDialog,
              ),
              Divider(color: colors.divider),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.link_outlined),
                title: Text(
                  Localizations.localeOf(context).languageCode == 'de'
                      ? 'Portfolio-Verknupfung'
                      : 'Portfolio Link',
                  style: TextStyle(color: colors.textPrimary),
                ),
                subtitle: Text(
                  _linkedPortfolioUid() != null
                      ? (Localizations.localeOf(context).languageCode == 'de'
                          ? 'Verbunden. Verwende "Mit Portfolio fortfahren", um die Anmeldung zu aktualisieren.'
                          : 'Connected. Use "Continue with Portfolio" to refresh sign-in.')
                      : (Localizations.localeOf(context).languageCode == 'de'
                          ? 'Noch nicht verbunden. Nutze "Mit Portfolio fortfahren" auf dem Login-Screen.'
                          : 'Not connected yet. Use "Continue with Portfolio" on the login screen.'),
                  style: TextStyle(color: colors.textSecondary),
                ),
                trailing: Icon(
                  _linkedPortfolioUid() != null
                      ? Icons.check_circle_outline
                      : Icons.info_outline,
                  size: 18,
                  color: colors.textSecondary,
                ),
              ),
              Divider(color: colors.divider),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.key_outlined),
                title: Text(
                  Localizations.localeOf(context).languageCode == 'de'
                      ? 'Trans-Link-Token kopieren'
                      : 'Copy Trans Link Token',
                  style: TextStyle(color: colors.textPrimary),
                ),
                subtitle: Text(
                  Localizations.localeOf(context).languageCode == 'de'
                      ? 'Im Portfolio bei Konto > Verbundene Apps einfügen.'
                      : 'Paste in portfolio at Account > Connected Apps.',
                  style: TextStyle(color: colors.textSecondary),
                ),
                trailing: const Icon(Icons.copy_rounded, size: 18),
                onTap: _copyTransLinkToken,
              ),
              Divider(color: colors.divider),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(AppLocalizations.of(context)!.logOut,
                      style: TextStyle(color: Colors.red)),
                  leading: const Icon(Icons.logout, color: Colors.red),
                  onTap: () async {
                    await SupabaseService.signOut();
                    if (mounted) setState(() {});
                  }),
              Divider(color: colors.divider),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(AppLocalizations.of(context)!.deleteAccount,
                      style: TextStyle(
                          color: Colors.red, fontWeight: FontWeight.bold)),
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  onTap: _showDeleteAccountDialog),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildAuthForm(BuildContext context, TransColors colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: colors.authFormBg, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
              _isLoginMode
                  ? AppLocalizations.of(context)!.login
                  : AppLocalizations.of(context)!.signUp,
              style: TextStyle(
                  color: colors.textPrimary, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment<bool>(
                value: true,
                label: Text(AppLocalizations.of(context)!.login),
              ),
              ButtonSegment<bool>(
                value: false,
                label: Text(AppLocalizations.of(context)!.signUp),
              ),
            ],
            selected: {_isLoginMode},
            onSelectionChanged: (selection) {
              setState(() => _isLoginMode = selection.first);
            },
          ),
          const SizedBox(height: 14),
          TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                  hintText: AppLocalizations.of(context)!.emailSettings)),
          if (!_isLoginMode) ...[
            const SizedBox(height: 10),
            TextField(
                controller: _usernameCtrl,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                    hintText: AppLocalizations.of(context)!.usernameSignUp)),
          ],
          const SizedBox(height: 10),
          TextField(
              controller: _passwordCtrl,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submitAuth(),
              obscureText: _obscureAuthPassword,
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context)!.password,
                suffixIcon: IconButton(
                  icon: Icon(_obscureAuthPassword
                      ? Icons.visibility
                      : Icons.visibility_off),
                  onPressed: () {
                    setState(
                        () => _obscureAuthPassword = !_obscureAuthPassword);
                  },
                ),
              )),
          if (_isLoginMode)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _showForgotPasswordDialog(context),
                child: Text(AppLocalizations.of(context)!.forgotPassword,
                    style: const TextStyle(fontSize: 12)),
              ),
            ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: _isAuthSubmitting ? null : _submitAuth,
            child: _isAuthSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isLoginMode
                    ? AppLocalizations.of(context)!.login
                    : AppLocalizations.of(context)!.signUp),
          ),
          if (_supportsOAuthSignIn) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Divider(color: colors.divider)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    _orLabel,
                    style: TextStyle(color: colors.textSecondary),
                  ),
                ),
                Expanded(child: Divider(color: colors.divider)),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _isAuthSubmitting ? null : _startGoogleSignIn,
              child: _buildGoogleSignInLabel(colors),
            ),
            if (_supportsAppleSignIn) ...[
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _isAuthSubmitting ? null : _startAppleSignIn,
                child: _buildAppleSignInLabel(colors),
              ),
            ],
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _isAuthSubmitting ? null : _startPortfolioSignIn,
              child: Text(
                Localizations.localeOf(context).languageCode == 'de'
                    ? 'Mit Portfolio fortfahren'
                    : 'Continue with Portfolio',
                style: TextStyle(color: colors.textPrimary),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGoogleSignInLabel(TransColors colors) {
    final isGerman = Localizations.localeOf(context).languageCode == 'de';
    final baseStyle = TextStyle(color: colors.textPrimary);

    if (isGerman) {
      return Text.rich(
        TextSpan(
          style: baseStyle,
          children: [
            const TextSpan(text: 'Mit '),
            _googleWordSpan(),
            const TextSpan(text: ' fortfahren'),
          ],
        ),
      );
    }

    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          const TextSpan(text: 'Continue with '),
          _googleWordSpan(),
        ],
      ),
    );
  }

  TextSpan _googleWordSpan() {
    const letters = [
      ('G', Color(0xFF4285F4)),
      ('o', Color(0xFFEA4335)),
      ('o', Color(0xFFFBBC05)),
      ('g', Color(0xFF4285F4)),
      ('l', Color(0xFF34A853)),
      ('e', Color(0xFFEA4335)),
    ];

    return TextSpan(
      children: [
        for (final (letter, color) in letters)
          TextSpan(
            text: letter,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }

  Widget _buildAppleSignInLabel(TransColors colors) {
    final isGerman = Localizations.localeOf(context).languageCode == 'de';
    final baseStyle = TextStyle(color: colors.textPrimary);

    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: isGerman ? 'Mit ' : 'Continue with '),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Transform.translate(
              offset: const Offset(0, 2.2),
              child: Icon(Icons.apple, color: colors.textPrimary, size: 18),
            ),
          ),
          const TextSpan(text: 'Apple'),
          if (isGerman) const TextSpan(text: ' fortfahren'),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, List<Widget> children) {
    final colors = TransColors.of(context);
    return Container(
        decoration: BoxDecoration(
            color: colors.settingsSectionBg,
            borderRadius: BorderRadius.circular(16)),
        child: Column(children: children));
  }

  void _showForgotPasswordDialog(BuildContext context) {
    final emailCtrl = TextEditingController(text: _emailCtrl.text.trim());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.resetPassword),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppLocalizations.of(context)!.enterEmailReset),
            const SizedBox(height: 10),
            TextField(
              controller: emailCtrl,
              decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.emailSettings),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = emailCtrl.text.trim();
              if (!_looksLikeEmail(email)) {
                _showMessage(
                  AppLocalizations.of(context)!.enterValidEmail,
                  reportable: true,
                  source: 'request password reset validation',
                );
                return;
              }
              try {
                _emailCtrl.text = email;
                await SupabaseService.resetPassword(email);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  _showMessage(
                      AppLocalizations.of(context)!.passwordResetEmailSent);
                }
              } catch (e, st) {
                if (!ctx.mounted) return;
                AppError.showSnackBar(
                  ctx,
                  error: e,
                  stackTrace: st,
                  source: 'request password reset email',
                );
              }
            },
            child: Text(AppLocalizations.of(context)!.send),
          ),
        ],
      ),
    ).then((_) => emailCtrl.dispose());
  }

  Widget _buildMyStatus(TransColors colors) {
    String statusText = AppLocalizations.of(context)!.inactive;
    Color statusColor = colors.statusOffline;
    Widget? statusIcon;

    if (_myLocation != null && _myLocation!['updated_at'] != null) {
      final now = DateTime.now().toUtc();
      final updated = DateTime.tryParse(_myLocation!['updated_at'])?.toUtc() ??
          DateTime(2000).toUtc();
      final isActive = now.difference(updated).inHours < 12;
      final currentLine = _myLocation!['current_line'];

      if (isActive) {
        statusText = AppLocalizations.of(context)!.activeRecently;
        statusColor = colors.statusActive;

        if (currentLine != null && currentLine.toString().isNotEmpty) {
          final diff = now.difference(updated);
          if (diff.inMinutes < 10) {
            statusText = AppLocalizations.of(context)!.onLine(currentLine);
            statusColor = colors.statusOnline;
            statusIcon = Icon(Icons.directions_bus,
                size: 12, color: colors.statusOnline);
          } else {
            statusText = AppLocalizations.of(context)!.lastOnLine(currentLine);
            statusColor = colors.textSecondary;
            statusIcon =
                Icon(Icons.history, size: 12, color: colors.textSecondary);
          }
        }
      }

      if (widget.signalLevel == 0) {
        if (isActive && currentLine == null) {
          statusText = AppLocalizations.of(context)!.activeRecentlyGhost;
          statusColor = colors.textSecondary;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (statusIcon != null) ...[statusIcon, const SizedBox(width: 4)],
            Text(statusText,
                style: TextStyle(fontSize: 12, color: statusColor)),
          ],
        ),
      ],
    );
  }
}
