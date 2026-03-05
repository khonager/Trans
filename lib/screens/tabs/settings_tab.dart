import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import '../../services/supabase_service.dart';
import '../../services/history_manager.dart';
import '../../config/app_theme.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../services/transport_api.dart';
import '../../l10n/app_localizations.dart';
import '../changelog_screen.dart';

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
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();

  bool _isEditing = false;

  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _myLocation;
  StreamSubscription? _locationSub;

  String _version = "";

  String _vibrationPattern = 'standard';
  int _vibrationIntensity = 128;
  int _stopsBeforeAlarm = 1;
  String _apiMode = 'auto';
  String _alarmTriggerThreshold = '5%'; // NEW: '5%', '10%', or '500m'
// Removed _alwaysWakeMe internal state

  @override
  void dispose() {
    _locationSub?.cancel();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _usernameCtrl.dispose();
    _newPasswordCtrl.dispose();
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
    if (mounted) setState(() => _version = info.version);
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
      'vibration_intensity': _vibrationIntensity
    });
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
      List<int> pattern = [0, 500];

      switch (_vibrationPattern) {
        // Heartbeat: LUB-dub (pause) LUB-dub
        case 'heartbeat':
          pattern = [0, 100, 100, 250, 600, 100, 100, 250];
          break;
        // Tick: Single sharp, concise tap
        case 'tick':
          pattern = [0, 30];
          break;
        // Mario 1-UP: do-mi-so-do-so-do (Very fast ascending)
        case 'mario':
          pattern = [0, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 200];
          break;
        // 20th Century Fox: rhythmic fanfare (Dun-dun, dun-dun, dun-dun-dun-DUN!)
        case 'fox':
          pattern = [
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
            400
          ];
          break;
        // Imperial March: Bold Triplets (DUN DUN DUN, dun-pa-DUN, dun-pa-DUN)
        case 'imperial':
          pattern = [
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
            450
          ];
          break;
        // Harry Potter: Hedwig's Theme (B... E-G-F#-E... B-A)
        case 'potter':
          pattern = [
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
            400
          ];
          break;
        // Indiana Jones: Raiders March - Ta-da-dad-DAAA... Ta-da-DAAAA!
        case 'indy':
          pattern = [
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
            600
          ];
          break;
        // Mission Impossible: 5/4 syncopated (DUN DUN, da-da, DUN DUN, da-da)
        case 'mission':
          pattern = [
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
            120
          ];
          break;
        // Terminator: Menacing Industrial (DUN-DUN, dun-DUN-DUN)
        case 'terminator':
          pattern = [0, 250, 250, 250, 400, 200, 200, 250, 200, 250];
          break;
        // Back to the Future: Aggressively syncopated riff
        case 'future':
          pattern = [0, 150, 150, 150, 150, 300, 200, 100, 50, 100, 50, 400];
          break;
        // Evangelion: Driving beats (da-da-DA-da, da-da-DA-da)
        case 'eva':
          pattern = [
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
            100
          ];
          break;
        // Pokémon: Jingle (ba-da ba-DA-DA!)
        case 'pokemon':
          pattern = [0, 100, 100, 100, 100, 300, 150, 100, 100, 300];
          break;
        // Attack on Titan: Epic building choir (sa-sa-GAYO!)
        case 'titan':
          pattern = [0, 200, 150, 200, 150, 250, 250, 400, 400, 600];
          break;
        // Cowboy Bebop: Fast Jazz (3..2..1.. JAM!)
        case 'bebop':
          pattern = [0, 150, 400, 150, 400, 150, 400, 150, 600, 1000];
          break;
      }

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
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Search history cleared.")));
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
          if (snapshot.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator());
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
                  labelText: "Password",
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
                      setState(() {
                        isLoading = true;
                        errorMsg = null;
                      });
                      try {
                        await SupabaseService.reauthenticate(passwordCtrl.text);
                        await SupabaseService.deleteAccount();
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          if (mounted) setState(() {});
                        }
                      } catch (e) {
                        setState(() {
                          errorMsg =
                              "Incorrect password or error (RPC missing?)";
                          isLoading = false;
                        });
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

  @override
  Widget build(BuildContext context) {
    final user = SupabaseService.currentUser;
    final colors = TransColors.of(context);
    final primaryColor = Theme.of(context).primaryColor;

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
              if (const bool.fromEnvironment('IS_DEV',
                  defaultValue: false)) ...[
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
              const Spacer(),
              // Version Display & Link
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
                    if (states.contains(WidgetState.selected))
                      return Colors.white;
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
                  if (states.contains(WidgetState.selected))
                    return widget.useSystemTheme ? Colors.grey : primaryColor;
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
                        ? "System Sync Enabled 🔄"
                        : "Manual Mode Enabled 🖐️")));
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
                  if (states.contains(WidgetState.selected))
                    return primaryColor;
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
                    "Alert ${_stopsBeforeAlarm == 0 ? 'at destination' : '$_stopsBeforeAlarm stops before'}",
                    style:
                        TextStyle(fontSize: 12, color: colors.textSecondary)),
                trailing: DropdownButton<int>(
                    value: _stopsBeforeAlarm,
                    dropdownColor: colors.cardBg,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text("At Dest")),
                      DropdownMenuItem(value: 1, child: Text("1 Stop")),
                      DropdownMenuItem(value: 2, child: Text("2 Stops")),
                      DropdownMenuItem(value: 3, child: Text("3 Stops")),
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
                            ? 'of leg covered'
                            : 'from target'),
                    style:
                        TextStyle(fontSize: 12, color: colors.textSecondary)),
                trailing: DropdownButton<String>(
                    value: _alarmTriggerThreshold,
                    dropdownColor: colors.cardBg,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(
                          value: '5%', child: Text("5% Remaining")),
                      DropdownMenuItem(
                          value: '10%', child: Text("10% Remaining")),
                      DropdownMenuItem(
                          value: '500m', child: Text("Fixed 500m")),
                    ],
                    onChanged: (val) => _saveAlarmThreshold(val!))),
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
                    onChanged: (val) {
                      setState(() => _vibrationPattern = val!);
                      _persistVibrationSettings();
                      _testVibration();
                    })),
            ListTile(
                title: Text(AppLocalizations.of(context)!.vibrationIntensity,
                    style: TextStyle(color: colors.textPrimary)),
                subtitle: Slider(
                    value: _vibrationIntensity.toDouble(),
                    min: 1,
                    max: 255,
                    activeColor: primaryColor,
                    thumbColor: primaryColor,
                    onChanged: (val) {
                      setState(() => _vibrationIntensity = val.toInt());
                    },
                    onChangeEnd: (val) {
                      _persistVibrationSettings();
                      _testVibration();
                    })),
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
                  "Selected: ${_apiMode == 'auto' ? 'Auto (Recommended)' : _apiMode == 'motis' ? 'Transitous (Open Source)' : 'Deutsche Bahn (Legacy)'}",
                  style: TextStyle(fontSize: 12, color: colors.textSecondary)),
              trailing: DropdownButton<String>(
                value: _apiMode,
                dropdownColor: colors.cardBg,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 'auto', child: Text("Auto")),
                  DropdownMenuItem(value: 'motis', child: Text("Transitous")),
                  DropdownMenuItem(value: 'v6', child: Text("DB (v6)")),
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
              if (!_isEditing) ...[
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                        _profile?['username'] ??
                            AppLocalizations.of(context)!.noUsername,
                        style:
                            TextStyle(fontSize: 18, color: colors.textPrimary)),
                    subtitle: Text(user.email ?? "",
                        style: TextStyle(color: colors.textSecondary)),
                    trailing: IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () {
                          _usernameCtrl.text = _profile?['username'] ?? "";
                          _emailCtrl.text = user.email ?? "";
                          setState(() => _isEditing = true);
                        })),
              ] else ...[
                TextField(
                    controller: _usernameCtrl,
                    decoration: InputDecoration(
                        labelText: AppLocalizations.of(context)!.username)),
                TextField(
                    controller: _emailCtrl,
                    decoration: InputDecoration(
                        labelText: AppLocalizations.of(context)!
                            .emailSettings)), // Added Email Field
                TextField(
                    controller: _newPasswordCtrl,
                    decoration: InputDecoration(
                        labelText:
                            AppLocalizations.of(context)!.newPasswordOpt),
                    obscureText: true),
                const SizedBox(height: 10),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton(
                          onPressed: () => setState(() => _isEditing = false),
                          child: Text(AppLocalizations.of(context)!.cancel)),
                      ElevatedButton(
                          onPressed: () async {
                            try {
                              if (_usernameCtrl.text.isNotEmpty)
                                await SupabaseService.updateUsername(
                                    _usernameCtrl.text);
                              if (_emailCtrl.text.isNotEmpty &&
                                  _emailCtrl.text != user.email)
                                await SupabaseService.updateEmail(
                                    _emailCtrl.text);
                              if (_newPasswordCtrl.text.isNotEmpty)
                                await SupabaseService.updatePassword(
                                    _newPasswordCtrl.text);
                              setState(() => _isEditing = false);
                              _loadProfile();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            AppLocalizations.of(context)!
                                                .profileUpdated)));
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text("Error: $e")));
                              }
                            }
                          },
                          child: Text(AppLocalizations.of(context)!.save))
                    ])
              ],
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
        children: [
          Text(AppLocalizations.of(context)!.loginSignUp,
              style: TextStyle(
                  color: colors.textPrimary, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          TextField(
              controller: _emailCtrl,
              decoration: InputDecoration(
                  hintText: AppLocalizations.of(context)!.emailSettings)),
          const SizedBox(height: 10),
          TextField(
              controller: _usernameCtrl,
              decoration: InputDecoration(
                  hintText: AppLocalizations.of(context)!.usernameSignUp)),
          const SizedBox(height: 10),
          TextField(
              controller: _passwordCtrl,
              obscureText: true,
              decoration: InputDecoration(
                  hintText: AppLocalizations.of(context)!.password)),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _showForgotPasswordDialog(context),
              child: Text(AppLocalizations.of(context)!.forgotPassword,
                  style: TextStyle(fontSize: 12)),
            ),
          ),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            TextButton(
                onPressed: () async {
                  try {
                    await SupabaseService.signIn(
                        _emailCtrl.text, _passwordCtrl.text);
                    await _loadProfile();
                    if (mounted) setState(() {});
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text("$e")));
                    }
                  }
                },
                child: Text(AppLocalizations.of(context)!.login)),
            TextButton(
                onPressed: () async {
                  try {
                    await SupabaseService.signUp(_emailCtrl.text,
                        _passwordCtrl.text, _usernameCtrl.text);
                    await _loadProfile();
                    if (mounted) setState(() {});
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text("$e")));
                    }
                  }
                },
                child: Text(AppLocalizations.of(context)!.signUp))
          ])
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
    final emailCtrl = TextEditingController();
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
              if (email.isEmpty) return;
              try {
                await SupabaseService.resetPassword(email);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(AppLocalizations.of(context)!
                            .passwordResetEmailSent)),
                  );
                }
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Error: $e")),
                  );
                }
              }
            },
            child: Text(AppLocalizations.of(context)!.send),
          ),
        ],
      ),
    );
  }

  Widget _buildMyStatus(TransColors colors) {
    String statusText = "Inactive";
    Color statusColor = colors.statusOffline;
    Widget? statusIcon;

    if (_myLocation != null && _myLocation!['updated_at'] != null) {
      final now = DateTime.now().toUtc();
      final updated = DateTime.tryParse(_myLocation!['updated_at'])?.toUtc() ??
          DateTime(2000).toUtc();
      final isActive = now.difference(updated).inHours < 12;
      final currentLine = _myLocation!['current_line'];

      if (isActive) {
        statusText = "Active recently";
        statusColor = colors.statusActive;

        if (currentLine != null && currentLine.toString().isNotEmpty) {
          final diff = now.difference(updated);
          if (diff.inMinutes < 10) {
            statusText = "On $currentLine";
            statusColor = colors.statusOnline;
            statusIcon = Icon(Icons.directions_bus,
                size: 12, color: colors.statusOnline);
          } else {
            statusText = "Last on $currentLine";
            statusColor = colors.textSecondary;
            statusIcon =
                Icon(Icons.history, size: 12, color: colors.textSecondary);
          }
        }
      }

      if (widget.isGhostMode) {
        if (isActive && currentLine == null) {
          statusText = "Active recently (Ghost)";
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
