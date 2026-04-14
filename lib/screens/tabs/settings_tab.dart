import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import '../../services/notification_manager.dart';
import '../../services/supabase_service.dart';
import '../../services/wake_alarm_settings.dart';
import '../../services/history_manager.dart';
import '../../config/app_theme.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../services/transport_api.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/app_error.dart';
import '../changelog_screen.dart';

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
  final bool isGhostMode;
  final Function(bool) onGhostModeChanged;
  final Function(Color) onColorChanged;
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
    required this.isGhostMode,
    required this.onGhostModeChanged,
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

  String _vibrationPattern = 'standard';
  int _vibrationIntensity = 128;
  String _wakeAlarmSound = WakeAlarmSettings.defaultSoundId;
  bool _wakeAlarmSoundEnabled = true;
  bool _wakeAlarmVibrationEnabled = true;
  bool _leaveAlarmSoundEnabled = true;
  bool _leaveAlarmVibrationEnabled = true;
  int _stopsBeforeAlarm = 1;
  String _apiMode = 'auto';
  String _alarmTriggerThreshold = '5%'; // NEW: '5%', '10%', or '500m'
// Removed _alwaysWakeMe internal state

  @override
  void dispose() {
    _hiddenManualAlarmTimer?.cancel();
    _locationSub?.cancel();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _usernameCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadSettings();
    _loadVersion();
    _subscribeToLocation();
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
    final prefs = await SharedPreferences.getInstance();
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
        _apiMode = prefs.getString('api_mode') ?? 'auto';
        _alarmTriggerThreshold =
            prefs.getString('alarm_trigger_threshold') ?? '5%';
        TransportApi.apiMode = _apiMode;
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

  Future<void> _saveApiMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_mode', mode);
    setState(() {
      _apiMode = mode;
      TransportApi.apiMode = mode;
    });
  }

  Future<void> _testVibration() async {
    if (kIsWeb) return;
    if (await Vibration.hasVibrator()) {
      final pattern =
          WakeAlarmSettings.vibrationPatternForId(_vibrationPattern);

      if (await Vibration.hasAmplitudeControl()) {
        // Correctly set intensity to 0 for pauses (even indices) and _vibrationIntensity for vibrations (odd indices)
        final intensities = List<int>.generate(
            pattern.length, (i) => i.isEven ? 0 : _vibrationIntensity);
        Vibration.vibrate(pattern: pattern, intensities: intensities);
      } else {
        Vibration.vibrate(pattern: pattern);
      }
    }
  }

  Future<void> _testLeaveVibration() async {
    if (kIsWeb || !_leaveAlarmVibrationEnabled) return;
    if (!await Vibration.hasVibrator()) return;

    final pattern = WakeAlarmSettings.vibrationPatternForId(_vibrationPattern);
    if (await Vibration.hasAmplitudeControl()) {
      final intensities = List<int>.generate(
        pattern.length,
        (i) => i.isEven ? 0 : _vibrationIntensity,
      );
      Vibration.vibrate(pattern: pattern, intensities: intensities);
    } else {
      Vibration.vibrate(pattern: pattern);
    }
  }

  Future<void> _previewWakeAlarmSound() async {
    if (kIsWeb) return;
    final l10n = AppLocalizations.of(context)!;
    try {
      await NotificationManager.previewWakeAlarm(
        title: l10n.wakeAlarmPreviewTitle,
        body: l10n.wakeAlarmPreviewBody,
        soundId: _wakeAlarmSound,
        vibrationPattern: WakeAlarmSettings.vibrationPatternForId(
          _vibrationPattern,
        ),
      );
    } catch (error) {
      if (!mounted) return;
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
        soundId: _leaveAlarmSoundEnabled
            ? _wakeAlarmSound
            : WakeAlarmSettings.silentSoundId,
        vibrationPattern: WakeAlarmSettings.vibrationPatternForId(
          _vibrationPattern,
        ),
      );
      await _testLeaveVibration();
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

  void _scheduleHiddenManualLeaveTimer(DateTime target) {
    _hiddenManualAlarmTimer?.cancel();
    final now = DateTime.now();
    final delay = target.difference(now);
    final safeDelay = delay.isNegative ? Duration.zero : delay;
    _hiddenManualAlarmTarget = target;
    _hiddenManualAlarmTimer = Timer(safeDelay, () {
      unawaited(_triggerHiddenManualLeaveTimer());
    });
  }

  Future<void> _showHiddenManualTimerDialog() async {
    if (kIsWeb || !mounted) return;

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
                    onPressed: () {
                      _hiddenManualAlarmTimer?.cancel();
                      _hiddenManualAlarmTimer = null;
                      _hiddenManualAlarmTarget = null;
                      Navigator.of(dialogContext).pop(false);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Hidden timer cancelled.')),
                      );
                    },
                    child: const Text('Clear'),
                  ),
                FilledButton(
                  onPressed: () {
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
                    _scheduleHiddenManualLeaveTimer(target);
                    Navigator.of(dialogContext).pop(true);
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
        ? 'Hidden timer set for ${TimeOfDay.fromDateTime(target).format(context)}'
        : 'Hidden timer scheduled';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(modeLabel)),
    );
  }

  void _showIosVibrationAvailabilityMessage() {
    if (defaultTargetPlatform != TargetPlatform.iOS || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context)!.iosWakeAlarmVibrationNoticeBody,
        ),
      ),
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
                                ? 'Konto dauerhaft geloescht.'
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
      await _loadProfile();
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
  }

  bool _looksLikeEmail(String value) {
    return value.contains('@') && value.contains('.');
  }

  bool get _supportsOAuthSignIn {
    if (kIsWeb) return true;

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => true,
      TargetPlatform.iOS => true,
      TargetPlatform.macOS => true,
      _ => false,
    };
  }

  String get _continueWithGoogleLabel {
    final isGerman = Localizations.localeOf(context).languageCode == 'de';
    return isGerman ? 'Mit Google fortfahren' : 'Continue with Google';
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

  Future<void> _startGoogleSignIn() async {
    await _startOAuthSignIn(
      action: SupabaseService.signInWithGoogle,
      source: 'sign in with google',
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

    return Padding(
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              ChangelogScreen(currentVersion: _version)),
                    );
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text("v$_version",
                        style: TextStyle(
                            color: colors.textSecondary.withValues(alpha: 0.7),
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
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
              SwitchListTile(
                  title: Text(AppLocalizations.of(context)!.ghostMode,
                      style: TextStyle(color: colors.textPrimary)),
                  subtitle: Text(AppLocalizations.of(context)!.hideLocation,
                      style:
                          TextStyle(fontSize: 12, color: colors.textSecondary)),
                  value: widget.isGhostMode,
                  activeTrackColor: Colors.red,
                  thumbColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return Colors.white;
                    }
                    return null;
                  }),
                  onChanged: (val) {
                    widget.onGhostModeChanged(val);
                    // Give it a moment to update DB then reload profile to see status change
                    Future.delayed(
                        const Duration(milliseconds: 500), _loadProfile);
                  }),
            ]),
            const SizedBox(height: 20),
          ],

          _buildSection(context, [
            ListTile(
              title: Text(AppLocalizations.of(context)!.darkMode,
                  style: TextStyle(color: colors.textPrimary)),
              subtitle: widget.useSystemTheme
                  ? Text(AppLocalizations.of(context)!.syncedWithSystem,
                      style:
                          TextStyle(fontSize: 12, color: colors.textSecondary))
                  : null,
              trailing: Switch(
                value: widget.isDarkMode,
                thumbColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return widget.useSystemTheme ? Colors.grey : primaryColor;
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
                        : AppLocalizations.of(context)!.manualModeEnabled)));
              },
            ),
            SwitchListTile(
                title: Text(AppLocalizations.of(context)!.deutschlandTicketMode,
                    style: TextStyle(color: colors.textPrimary)),
                subtitle: Text(AppLocalizations.of(context)!.onlyLocalTransport,
                    style:
                        TextStyle(fontSize: 12, color: colors.textSecondary)),
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
              subtitle: SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: appThemeColors.map((c) => _colorCircle(c)).toList(),
                ),
              ),
            ),
            Divider(color: colors.divider), // Separator
            SwitchListTile(
              title: Text(AppLocalizations.of(context)!.showTrainNumbers,
                  style: TextStyle(color: colors.textPrimary)),
              subtitle: Text(AppLocalizations.of(context)!.displayTripIds,
                  style: TextStyle(fontSize: 12, color: colors.textSecondary)),
              value: widget.showTrainNumbers,
              thumbColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return primaryColor;
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
                    style:
                        TextStyle(fontSize: 12, color: colors.textSecondary)),
                trailing: DropdownButton<int>(
                    value: _stopsBeforeAlarm,
                    dropdownColor: colors.cardBg,
                    underline: const SizedBox(),
                    items: [
                      DropdownMenuItem(
                          value: 0,
                          child: Text(AppLocalizations.of(context)!.atDest)),
                      DropdownMenuItem(
                          value: 1,
                          child: Text(AppLocalizations.of(context)!.oneStop)),
                      DropdownMenuItem(
                          value: 2,
                          child: Text(AppLocalizations.of(context)!.twoStops)),
                      DropdownMenuItem(
                          value: 3,
                          child:
                              Text(AppLocalizations.of(context)!.threeStops)),
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
                    style:
                        TextStyle(fontSize: 12, color: colors.textSecondary)),
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
                          child: Text(AppLocalizations.of(context)!.fixed500m)),
                    ],
                    onChanged: (val) => _saveAlarmThreshold(val!))),
            Divider(color: colors.divider),
            ListTile(
              title: Text(AppLocalizations.of(context)!.alarmSound,
                  style: TextStyle(color: colors.textPrimary)),
              subtitle: Text(
                WakeAlarmSettings.soundForId(_wakeAlarmSound).label,
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
              trailing: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  if (!kIsWeb)
                    Builder(
                      builder: (context) {
                        final previewButton = InkResponse(
                          radius: 24,
                          onTap: _previewWakeAlarmSound,
                          onLongPress: _showHiddenManualTimerDialog,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              Icons.play_arrow_rounded,
                              color: colors.textPrimary,
                            ),
                          ),
                        );

                        if (!_showPreviewTooltip) return previewButton;

                        return Tooltip(
                          message: AppLocalizations.of(context)!.previewSound,
                          child: previewButton,
                        );
                      },
                    ),
                  DropdownButton<String>(
                    value: _wakeAlarmSound,
                    dropdownColor: colors.cardBg,
                    underline: const SizedBox(),
                    items: WakeAlarmSettings.soundOptions
                        .map(
                          (option) => DropdownMenuItem(
                            value: option.id,
                            child: Text(option.label),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (val) async {
                      if (val == null) return;
                      setState(() => _wakeAlarmSound = val);
                      await _persistWakeAlarmSoundSetting();
                    },
                  ),
                ],
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
                      DropdownMenuItem(value: 'mario', child: Text("Mario")),
                      DropdownMenuItem(
                          value: 'fox', child: Text("20th Century")),
                      DropdownMenuItem(
                          value: 'imperial', child: Text("Imperial March")),
                      DropdownMenuItem(
                          value: 'potter', child: Text("Harry Potter")),
                      DropdownMenuItem(
                          value: 'indy', child: Text("Indiana Jones")),
                      DropdownMenuItem(
                          value: 'mission', child: Text("Mission Impossible")),
                      DropdownMenuItem(
                          value: 'terminator', child: Text("Terminator")),
                      DropdownMenuItem(
                          value: 'future', child: Text("Back to Future")),
                      DropdownMenuItem(value: 'eva', child: Text("Evangelion")),
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
                      _showIosVibrationAvailabilityMessage();
                    })),
            ListTile(
                title: Text(AppLocalizations.of(context)!.vibrationIntensity,
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
                      _showIosVibrationAvailabilityMessage();
                    })),
            if (defaultTargetPlatform == TargetPlatform.iOS)
              ListTile(
                leading: Icon(Icons.info_outline, color: colors.textSecondary),
                title: Text(
                  AppLocalizations.of(context)!
                      .iosWakeAlarmVibrationNoticeTitle,
                  style: TextStyle(color: colors.textPrimary),
                ),
                subtitle: Text(
                  AppLocalizations.of(context)!.iosWakeAlarmVibrationNoticeBody,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
              ),
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
                if (states.contains(WidgetState.selected)) return primaryColor;
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
                if (states.contains(WidgetState.selected)) return primaryColor;
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
              subtitle: Text(AppLocalizations.of(context)!.turnOnAlarmDefault,
                  style: TextStyle(fontSize: 12, color: colors.textSecondary)),
              value: widget.alwaysWakeMe,
              thumbColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return primaryColor;
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
                if (states.contains(WidgetState.selected)) return primaryColor;
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
                if (states.contains(WidgetState.selected)) return primaryColor;
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
                leading: Icon(Icons.block, color: colors.iconBlock),
                title: Text(AppLocalizations.of(context)!.blockedUsers,
                    style: TextStyle(color: colors.textPrimary)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: _showBlockedUsers),
            Divider(height: 1, color: colors.divider),
            ListTile(
                leading: Icon(Icons.delete_outline, color: colors.iconDelete),
                title: Text(AppLocalizations.of(context)!.clearSearchHistory,
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
                  AppLocalizations.of(context)!.selectedApiMode(_apiMode ==
                          'auto'
                      ? AppLocalizations.of(context)!.autoRecommended
                      : _apiMode == 'motis'
                          ? AppLocalizations.of(context)!.transitousOpenSource
                          : AppLocalizations.of(context)!.deutscheBahnLegacy),
                  style: TextStyle(fontSize: 12, color: colors.textSecondary)),
              trailing: DropdownButton<String>(
                value: _apiMode,
                dropdownColor: colors.cardBg,
                underline: const SizedBox(),
                items: [
                  DropdownMenuItem(
                      value: 'auto',
                      child: Text(AppLocalizations.of(context)!.autoModeShort)),
                  const DropdownMenuItem(
                      value: 'motis', child: Text("Transitous")),
                  DropdownMenuItem(
                      value: 'v6',
                      child: Text(AppLocalizations.of(context)!.dbV6)),
                ],
                onChanged: (val) => _saveApiMode(val!),
              ),
            )
          ]),
          const SizedBox(height: 20),
          if (user == null)
            _buildAuthForm(context, colors)
          else
            _buildProfileSection(context, user, colors),
        ],
      ),
    );
  }

  Widget _colorCircle(Color color) {
    final isSelected = widget.currentColor.toARGB32() == color.toARGB32();
    return GestureDetector(
      onTap: () => widget.onColorChanged(color),
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

      if (widget.isGhostMode) {
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
