import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart'; 
import '../../services/supabase_service.dart';
import '../../services/history_manager.dart';
import '../../config/app_theme.dart';
import '../../services/transport_api.dart';

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

  String _vibrationPattern = 'standard'; 
  int _vibrationIntensity = 128; 
  int _stopsBeforeAlarm = 1;
  String _apiMode = 'auto';

  @override
  void initState() {
    super.initState();
    _loadProfile(); 
    _loadSettings();
  }

  Future<void> _loadProfile() async {
    final profile = await SupabaseService.getCurrentProfile();
    if (mounted) setState(() {
      _profile = profile;
    });
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _vibrationPattern = prefs.getString('vibration_pattern') ?? 'standard';
        _vibrationIntensity = prefs.getInt('vibration_intensity') ?? 128;
        _stopsBeforeAlarm = prefs.getInt('alarm_stops_before') ?? 1;
        _apiMode = prefs.getString('api_mode') ?? 'auto';
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
    if (await Vibration.hasVibrator() ?? false) {
      List<int> pattern = [0, 500];

      switch (_vibrationPattern) {
        case 'heartbeat': pattern = [0, 150, 150, 150]; break;
        case 'tick': pattern = [0, 50]; break;
        case 'mario': pattern = [0, 150, 100, 150, 100, 150, 200, 300]; break;
        case 'fox': pattern = [0, 100, 50, 100, 50, 100, 50, 400, 200, 200, 100, 600]; break;
        case 'imperial': pattern = [0, 400, 200, 400, 200, 400, 200, 250, 100, 400, 200, 250, 100, 400]; break;
        case 'potter': pattern = [0, 300, 150, 150, 150, 300, 100, 300]; break;
        case 'indy': pattern = [0, 100, 50, 100, 50, 400, 200, 100, 50, 100, 50, 800]; break;
        case 'mission': pattern = [0, 500, 200, 500, 200, 150, 50, 150, 50]; break;
        case 'terminator': pattern = [0, 100, 100, 100, 200, 100, 50, 100]; break;
        case 'future': pattern = [0, 100, 50, 100, 50, 100, 200, 400, 100, 400, 100, 600]; break;
        case 'eva': pattern = [0, 100, 50, 100, 50, 100, 50, 100, 200, 300, 100, 300, 100, 300, 100, 300]; break;
        case 'pokemon': pattern = [0, 100, 50, 100, 50, 100, 200, 400, 100, 400, 100, 400]; break;
        case 'titan': pattern = [0, 200, 100, 200, 300, 200, 100, 200, 300, 600]; break;
        case 'bebop': pattern = [0, 300, 300, 300, 300, 300, 300, 600, 50, 50, 50, 50, 50, 50]; break;
      }

      if (await Vibration.hasAmplitudeControl() ?? false) {
        Vibration.vibrate(pattern: pattern, intensities: pattern.map((_) => _vibrationIntensity).toList());
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
        title: Text("Clear History", style: TextStyle(color: colors.textPrimary)),
        content: Text("Are you sure you want to delete your recent search history?", style: TextStyle(color: colors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed == true) {
      await SearchHistoryManager.clearHistory();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Search history cleared.")));
    }
  }

  void _showBlockedUsers() {
    final colors = TransColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.cardBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => FutureBuilder<List<Map<String, dynamic>>>(
        future: SupabaseService.getBlockedUsers(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final users = snapshot.data ?? [];
          return Container(
            padding: const EdgeInsets.all(20),
            height: 400,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Blocked Users", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colors.textPrimary)),
                const SizedBox(height: 16),
                if (users.isEmpty) Expanded(child: Center(child: Text("No blocked users", style: TextStyle(color: colors.textSecondary)))),
                if (users.isNotEmpty)
                  Expanded(
                    child: ListView.separated(
                      itemCount: users.length,
                      separatorBuilder: (_,__) => Divider(color: colors.divider),
                      itemBuilder: (ctx, idx) {
                        final u = users[idx];
                        return ListTile(
                          leading: CircleAvatar(backgroundImage: u['avatar_url'] != null ? NetworkImage(u['avatar_url']) : null, child: u['avatar_url'] == null ? const Icon(Icons.person) : null),
                          title: Text(u['username'] ?? "Unknown", style: TextStyle(color: colors.textPrimary)),
                          trailing: TextButton(
                            onPressed: () async {
                              await SupabaseService.unblockUser(u['id']);
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Unblocked ${u['username']}")));
                            },
                            child: const Text("Unblock"),
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

  @override
  Widget build(BuildContext context) {
    final user = SupabaseService.currentUser;
    final colors = TransColors.of(context);
    final primaryColor = Theme.of(context).primaryColor;
    
    // FIX: Dynamic Padding
    final topPadding = MediaQuery.of(context).padding.top + 10;
    // FIX: Keyboard padding - get keyboard height from viewInsets
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0, bottom: 16.0 + keyboardHeight),
      child: ListView(
        children: [
          SizedBox(height: topPadding),
          // Header Restored
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'lib/assets/logo.png', // Check path
                  height: 48,
                  width: 48,
                  errorBuilder: (c,e,s) => Icon(Icons.directions_transit, size: 48, color: primaryColor),
                ),
              ),
              const SizedBox(width: 16),
              Text("Trans", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: colors.textPrimary)),
              // DEV badge - only shows on dev builds
              if (const bool.fromEnvironment('IS_DEV', defaultValue: false)) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text("DEV", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 30),
          
          if (user != null) ...[
            Text("Privacy", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colors.settingsHeader)),
            const SizedBox(height: 8),
            _buildSection(context, [
              SwitchListTile(
                title: Text("Ghost Mode", style: TextStyle(color: colors.textPrimary)), 
                subtitle: Text("Hide location from everyone", style: TextStyle(fontSize: 12, color: colors.textSecondary)),
                value: widget.isGhostMode, 
                activeTrackColor: Colors.red,
                activeColor: Colors.white,
                onChanged: widget.onGhostModeChanged
              ),
            ]),
            const SizedBox(height: 20),
          ],

          _buildSection(context, [
            ListTile(
              title: Text("Dark Mode", style: TextStyle(color: colors.textPrimary)),
              subtitle: widget.useSystemTheme 
                  ? Text("Synced with System", style: TextStyle(fontSize: 12, color: colors.textSecondary))
                  : null,
              trailing: Switch(
                value: widget.isDarkMode,
                activeColor: widget.useSystemTheme ? Colors.grey : primaryColor,
                onChanged: widget.useSystemTheme 
                  ? (val) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("System Sync Active. Long press to disable.")));
                    } 
                  : widget.onThemeChanged,
              ),
              onLongPress: () {
                bool newState = !widget.useSystemTheme;
                widget.onSystemSyncChanged(newState);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(newState ? "System Sync Enabled 🔄" : "Manual Mode Enabled 🖐️")
                ));
              },
            ),
            
            SwitchListTile(
              title: Text("Deutschlandticket Mode", style: TextStyle(color: colors.textPrimary)), 
              subtitle: Text("Only local/regional transport", style: TextStyle(fontSize: 12, color: colors.textSecondary)), 
              value: widget.onlyNahverkehr, 
              activeColor: primaryColor,
              onChanged: widget.onNahverkehrChanged
            ),
          ]),
          
          const SizedBox(height: 20),
          Text("Appearance", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colors.settingsHeader)),
          const SizedBox(height: 8),
          _buildSection(context, [
            ListTile(
              title: Text("Theme Color", style: TextStyle(color: colors.textPrimary)),
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
              title: Text("Show Train Numbers", style: TextStyle(color: colors.textPrimary)),
              subtitle: Text("Display trip IDs (e.g. RB21 (12345))", style: TextStyle(fontSize: 12, color: colors.textSecondary)),
              value: widget.showTrainNumbers,
              activeColor: primaryColor,
              onChanged: widget.onShowTrainNumbersChanged,
            ),
          ]),

          const SizedBox(height: 20),
          Text("Notifications & Haptics", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colors.settingsHeader)),
          const SizedBox(height: 8),
          _buildSection(context, [
             ListTile(
               title: Text("Alarm Trigger", style: TextStyle(color: colors.textPrimary)), 
               subtitle: Text("Alert ${_stopsBeforeAlarm == 0 ? 'at destination' : '$_stopsBeforeAlarm stops before'}", style: TextStyle(fontSize: 12, color: colors.textSecondary)),
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
                 onChanged: (val) => _saveAlarmSettings(val!)
               )
             ),
             Divider(color: colors.divider),
             ListTile(
               title: Text("Alarm Pattern", style: TextStyle(color: colors.textPrimary)), 
               trailing: DropdownButton<String>(
                 value: _vibrationPattern, 
                 dropdownColor: colors.cardBg, 
                 underline: const SizedBox(), 
                 items: const [
                   DropdownMenuItem(value: 'standard', child: Text("Standard")), 
                   DropdownMenuItem(value: 'heartbeat', child: Text("Heartbeat")), 
                   DropdownMenuItem(value: 'tick', child: Text("Tick")),
                   DropdownMenuItem(value: 'mario', child: Text("Mario")),
                   DropdownMenuItem(value: 'fox', child: Text("20th Century")),
                   DropdownMenuItem(value: 'imperial', child: Text("Imperial March")),
                   DropdownMenuItem(value: 'potter', child: Text("Harry Potter")),
                   DropdownMenuItem(value: 'indy', child: Text("Indiana Jones")),
                   DropdownMenuItem(value: 'mission', child: Text("Mission Impossible")),
                   DropdownMenuItem(value: 'terminator', child: Text("Terminator")),
                   DropdownMenuItem(value: 'future', child: Text("Back to Future")),
                   DropdownMenuItem(value: 'eva', child: Text("Evangelion")),
                   DropdownMenuItem(value: 'pokemon', child: Text("Pokémon")),
                   DropdownMenuItem(value: 'titan', child: Text("Attack on Titan")),
                   DropdownMenuItem(value: 'bebop', child: Text("Cowboy Bebop")),
                 ], 
                 onChanged: (val) {
                   setState(() => _vibrationPattern = val!);
                   _persistVibrationSettings();
                   _testVibration();
                 }
               )
             ),
             ListTile(
               title: Text("Vibration Intensity", style: TextStyle(color: colors.textPrimary)), 
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
                 }
               )
             ),
          ]),
          
          const SizedBox(height: 20),
          Text("Data & Privacy", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colors.settingsHeader)),
          const SizedBox(height: 8),
          _buildSection(context, [
            ListTile(leading: Icon(Icons.block, color: colors.iconBlock), title: Text("Blocked Users", style: TextStyle(color: colors.textPrimary)), trailing: const Icon(Icons.arrow_forward_ios, size: 16), onTap: _showBlockedUsers),
            Divider(height: 1, color: colors.divider),
            ListTile(leading: Icon(Icons.delete_outline, color: colors.iconDelete), title: const Text("Clear Search History", style: TextStyle(color: Colors.red)), onTap: _clearHistory),
          ]),
          
          const SizedBox(height: 20),
          Text("Data Source (Advanced)", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colors.settingsHeader)),
          const SizedBox(height: 8),
          _buildSection(context, [
             ListTile(
               title: Text("Transport API", style: TextStyle(color: colors.textPrimary)),
               subtitle: Text("Selected: ${_apiMode == 'auto' ? 'Auto (Recommended)' : _apiMode == 'motis' ? 'Transitous (Open Source)' : 'Deutsche Bahn (Legacy)'}", style: TextStyle(fontSize: 12, color: colors.textSecondary)),
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
          if (user == null) _buildAuthForm(context, colors) else _buildProfileSection(context, user, colors),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _colorCircle(Color color) {
    final isSelected = widget.currentColor.value == color.value;
    return GestureDetector(
      onTap: () => widget.onColorChanged(color),
      child: Container(
        width: 30, height: 30,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isSelected ? Border.all(color: Colors.white, width: 3) : null,
          boxShadow: isSelected ? [const BoxShadow(color: Colors.black26, blurRadius: 4)] : null
        ),
        child: isSelected ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
      ),
    );
  }

  Widget _buildProfileSection(BuildContext context, user, TransColors colors) {
    final emoji = _profile?['avatar_emoji'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text("Profile", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colors.textPrimary)), 
          const SizedBox(width: 16), 
          GestureDetector(
            onTap: _pickAvatar, 
            child: Container(
              width: 48, height: 48, 
              decoration: BoxDecoration(color: widget.currentColor, shape: BoxShape.circle), 
              child: ClipOval(
                child: (emoji != null) 
                  ? Center(child: Text(emoji, style: const TextStyle(fontSize: 24)))
                  : const Icon(Icons.emoji_emotions, size: 24, color: Colors.white)
              )
            )
          )
        ]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: colors.settingsSectionBg, borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: [
              if (!_isEditing) ...[
                ListTile(contentPadding: EdgeInsets.zero, title: Text(_profile?['username'] ?? "No Username", style: TextStyle(fontSize: 18, color: colors.textPrimary)), subtitle: Text(user.email ?? "", style: TextStyle(color: colors.textSecondary)), trailing: IconButton(icon: const Icon(Icons.edit), onPressed: () { _usernameCtrl.text = _profile?['username'] ?? ""; _emailCtrl.text = user.email ?? ""; setState(() => _isEditing = true); })),
              ] else ...[
                TextField(controller: _usernameCtrl, decoration: const InputDecoration(labelText: "Username")),
                TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: "Email")), // Added Email Field
                TextField(controller: _newPasswordCtrl, decoration: const InputDecoration(labelText: "New Password (Optional)"), obscureText: true),
                const SizedBox(height: 10),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [TextButton(onPressed: () => setState(() => _isEditing = false), child: const Text("Cancel")), ElevatedButton(onPressed: () async { try { if (_usernameCtrl.text.isNotEmpty) await SupabaseService.updateUsername(_usernameCtrl.text); if (_emailCtrl.text.isNotEmpty && _emailCtrl.text != user.email) await SupabaseService.updateEmail(_emailCtrl.text); if (_newPasswordCtrl.text.isNotEmpty) await SupabaseService.updatePassword(_newPasswordCtrl.text); setState(() => _isEditing = false); _loadProfile(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile updated! Check email for confirmation if changed."))); } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"))); } }, child: const Text("Save"))])
              ],
              Divider(color: colors.divider),
              ListTile(contentPadding: EdgeInsets.zero, title: const Text("Log Out", style: TextStyle(color: Colors.red)), leading: const Icon(Icons.logout, color: Colors.red), onTap: () async { await SupabaseService.signOut(); if (mounted) setState(() {}); })
            ],
          ),
        )
      ],
    );
  }

  Widget _buildAuthForm(BuildContext context, TransColors colors) {
     return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: colors.authFormBg, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Text("Login / Sign Up", style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          TextField(controller: _emailCtrl, decoration: const InputDecoration(hintText: "Email")),
          const SizedBox(height: 10),
          TextField(controller: _usernameCtrl, decoration: const InputDecoration(hintText: "Username (Sign Up)")),
          const SizedBox(height: 10),
          TextField(controller: _passwordCtrl, obscureText: true, decoration: const InputDecoration(hintText: "Password")),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _showForgotPasswordDialog(context),
              child: const Text("Forgot Password?", style: TextStyle(fontSize: 12)),
            ),
          ),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            TextButton(
              onPressed: () async { 
                try { 
                  await SupabaseService.signIn(_emailCtrl.text, _passwordCtrl.text); 
                  await _loadProfile(); 
                  if (mounted) setState(() {}); 
                } catch (e) { 
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e"))); 
                } 
              }, 
              child: const Text("Login")
            ), 
            TextButton(
              onPressed: () async { 
                try { 
                  await SupabaseService.signUp(_emailCtrl.text, _passwordCtrl.text, _usernameCtrl.text); 
                  await _loadProfile(); 
                  if (mounted) setState(() {}); 
                } catch (e) { 
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e"))); 
                } 
              }, 
              child: const Text("Sign Up")
            )
          ])
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, List<Widget> children) {
    final colors = TransColors.of(context);
    return Container(decoration: BoxDecoration(color: colors.settingsSectionBg, borderRadius: BorderRadius.circular(16)), child: Column(children: children));
  }

  void _showForgotPasswordDialog(BuildContext context) {
    final emailCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Reset Password"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Enter your email to receive a password reset link."),
            const SizedBox(height: 10),
            TextField(
              controller: emailCtrl,
              decoration: const InputDecoration(labelText: "Email"),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
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
                    const SnackBar(content: Text("Password reset email sent (if account exists).")),
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
            child: const Text("Send"),
          ),
        ],
      ),
    );
  }
}