import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart'; 
import '../../services/supabase_service.dart';
import '../../services/history_manager.dart';

class SettingsTab extends StatefulWidget {
  final bool isDarkMode;
  final Function(bool) onThemeChanged;
  final bool onlyNahverkehr;
  final Function(bool) onNahverkehrChanged;
  
  final Function(Color, bool) onColorChanged;
  final Color currentColor;
  final bool useMaterialYou;

  const SettingsTab({
    super.key,
    required this.isDarkMode,
    required this.onThemeChanged,
    required this.onlyNahverkehr,
    required this.onNahverkehrChanged,
    required this.onColorChanged,
    required this.currentColor,
    required this.useMaterialYou,
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

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadSettings();
  }

  Future<void> _loadProfile() async {
    final profile = await SupabaseService.getCurrentProfile();
    if (mounted) setState(() => _profile = profile);
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _vibrationPattern = prefs.getString('vibration_pattern') ?? 'standard';
      _vibrationIntensity = prefs.getInt('vibration_intensity') ?? 128;
    });
  }

  Future<void> _saveVibrationSettings(String pattern, int intensity) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vibration_pattern', pattern);
    await prefs.setInt('vibration_intensity', intensity);
    setState(() {
      _vibrationPattern = pattern;
      _vibrationIntensity = intensity;
    });
  }

  Future<void> _testVibration() async {
    if (kIsWeb) return;
    if (await Vibration.hasVibrator() ?? false) {
      List<int> pattern = [0, 500]; 
      if (_vibrationPattern == 'heartbeat') pattern = [0, 200, 100, 200];
      if (_vibrationPattern == 'tick') pattern = [0, 50];

      if (await Vibration.hasAmplitudeControl() ?? false) {
        Vibration.vibrate(pattern: pattern, intensities: pattern.map((_) => _vibrationIntensity).toList());
      } else {
        Vibration.vibrate(pattern: pattern);
      }
    }
  }

  Future<void> _pickAvatar() async {
    showModalBottomSheet(context: context, builder: (ctx) {
      return Container(
        height: 150,
        color: Theme.of(context).cardColor,
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.emoji_emotions),
              title: const Text("Choose Emoji"),
              onTap: () {
                Navigator.pop(ctx);
                _showEmojiPicker();
              },
            ),
            ListTile(
              leading: const Icon(Icons.image),
              title: const Text("Upload Image"),
              onTap: () async {
                Navigator.pop(ctx);
                final picker = ImagePicker();
                final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 800, maxHeight: 800, imageQuality: 80);
                if (picked != null) {
                  await SupabaseService.uploadAvatar(File(picked.path));
                  _loadProfile();
                }
              },
            ),
          ],
        ),
      );
    });
  }

  void _showEmojiPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      builder: (ctx) {
        // Updated for emoji_picker_flutter ^4.0.0
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).cardColor,
        title: Text("Clear History", style: TextStyle(color: Theme.of(ctx).textTheme.bodyLarge?.color)),
        content: const Text("Are you sure you want to delete your recent search history?"),
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
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
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
                Text("Blocked Users", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
                const SizedBox(height: 16),
                if (users.isEmpty) const Expanded(child: Center(child: Text("No blocked users"))),
                if (users.isNotEmpty)
                  Expanded(
                    child: ListView.separated(
                      itemCount: users.length,
                      separatorBuilder: (_,__) => const Divider(color: Colors.white10),
                      itemBuilder: (ctx, idx) {
                        final u = users[idx];
                        return ListTile(
                          leading: CircleAvatar(backgroundImage: u['avatar_url'] != null ? NetworkImage(u['avatar_url']) : null, child: u['avatar_url'] == null ? const Icon(Icons.person) : null),
                          title: Text(u['username'] ?? "Unknown", style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
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
    final textColor = Theme.of(context).textTheme.bodyLarge?.color;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          const SizedBox(height: 100),
          Text("Settings", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: textColor)),
          const SizedBox(height: 20),
          
          _buildSection(context, [
            SwitchListTile(
              title: Text("Dark Mode", style: TextStyle(color: textColor)), 
              value: widget.isDarkMode, 
              onChanged: widget.onThemeChanged
            ),
            SwitchListTile(
              title: Text("Deutschlandticket Mode", style: TextStyle(color: textColor)), 
              subtitle: const Text("Only local/regional transport", style: TextStyle(fontSize: 12, color: Colors.grey)), 
              value: widget.onlyNahverkehr, 
              onChanged: widget.onNahverkehrChanged
            ),
          ]),
          
          const SizedBox(height: 20),
          Text("Appearance", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textColor?.withOpacity(0.7))),
          const SizedBox(height: 8),
          _buildSection(context, [
            if (Platform.isAndroid)
              SwitchListTile(
                title: Text("Material You (Android)", style: TextStyle(color: textColor)),
                subtitle: const Text("Use system wallpaper colors", style: TextStyle(fontSize: 12, color: Colors.grey)),
                value: widget.useMaterialYou,
                onChanged: (val) => widget.onColorChanged(widget.currentColor, val),
              ),
            if (!widget.useMaterialYou || !Platform.isAndroid)
              ListTile(
                title: Text("App Theme Color", style: TextStyle(color: textColor)),
                subtitle: SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _colorCircle(const Color(0xFF4F46E5)), // Indigo
                      _colorCircle(Colors.blue),
                      _colorCircle(Colors.teal),
                      _colorCircle(Colors.green),
                      _colorCircle(Colors.orange),
                      _colorCircle(Colors.red),
                      _colorCircle(Colors.purple),
                      _colorCircle(Colors.pink),
                    ],
                  ),
                ),
              ),
          ]),

          const SizedBox(height: 20),
          Text("Notifications & Haptics", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textColor?.withOpacity(0.7))),
          const SizedBox(height: 8),
          _buildSection(context, [
             ListTile(title: Text("Get-off Alarm Pattern", style: TextStyle(color: textColor)), trailing: DropdownButton<String>(value: _vibrationPattern, dropdownColor: Theme.of(context).cardColor, underline: const SizedBox(), items: const [DropdownMenuItem(value: 'standard', child: Text("Standard")), DropdownMenuItem(value: 'heartbeat', child: Text("Heartbeat")), DropdownMenuItem(value: 'tick', child: Text("Tick"))], onChanged: (val) => _saveVibrationSettings(val!, _vibrationIntensity))),
             ListTile(title: Text("Vibration Intensity", style: TextStyle(color: textColor)), subtitle: Slider(value: _vibrationIntensity.toDouble(), min: 1, max: 255, activeColor: Theme.of(context).primaryColor, onChanged: (val) => _saveVibrationSettings(_vibrationPattern, val.toInt()), onChangeEnd: (_) => _testVibration())),
          ]),
          
          const SizedBox(height: 20),
          Text("Data & Privacy", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textColor?.withOpacity(0.7))),
          const SizedBox(height: 8),
          _buildSection(context, [
            ListTile(leading: const Icon(Icons.block, color: Colors.orange), title: Text("Blocked Users", style: TextStyle(color: textColor)), trailing: const Icon(Icons.arrow_forward_ios, size: 16), onTap: _showBlockedUsers),
            const Divider(height: 1),
            ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red), title: const Text("Clear Search History", style: TextStyle(color: Colors.red)), onTap: _clearHistory),
          ]),
          const SizedBox(height: 20),
          if (user == null) _buildAuthForm(context, textColor) else _buildProfileSection(context, user, textColor),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _colorCircle(Color color) {
    final isSelected = widget.currentColor.value == color.value;
    return GestureDetector(
      onTap: () => widget.onColorChanged(color, false),
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

  Widget _buildProfileSection(BuildContext context, user, Color? textColor) {
    final emoji = _profile?['avatar_emoji'];
    final imgUrl = _profile?['avatar_url'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text("Profile", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)), 
          const SizedBox(width: 16), 
          GestureDetector(
            onTap: _pickAvatar, 
            child: Container(
              width: 48, height: 48, 
              decoration: const BoxDecoration(color: Colors.indigo, shape: BoxShape.circle), 
              child: ClipOval(
                child: (emoji != null) 
                  ? Center(child: Text(emoji, style: const TextStyle(fontSize: 24)))
                  : (imgUrl != null 
                      ? Image.network(imgUrl, fit: BoxFit.cover, loadingBuilder: (_, child, p) => p == null ? child : const CircularProgressIndicator()) 
                      : const Icon(Icons.camera_alt, size: 20, color: Colors.white))
              )
            )
          )
        ]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: [
              if (!_isEditing) ...[
                ListTile(contentPadding: EdgeInsets.zero, title: Text(_profile?['username'] ?? "No Username", style: TextStyle(fontSize: 18, color: textColor)), subtitle: Text(user.email ?? "", style: TextStyle(color: textColor?.withOpacity(0.6))), trailing: IconButton(icon: const Icon(Icons.edit), onPressed: () { _usernameCtrl.text = _profile?['username'] ?? ""; setState(() => _isEditing = true); })),
              ] else ...[
                TextField(controller: _usernameCtrl, decoration: const InputDecoration(labelText: "Username")),
                TextField(controller: _newPasswordCtrl, decoration: const InputDecoration(labelText: "New Password (Optional)"), obscureText: true),
                const SizedBox(height: 10),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [TextButton(onPressed: () => setState(() => _isEditing = false), child: const Text("Cancel")), ElevatedButton(onPressed: () async { try { if (_usernameCtrl.text.isNotEmpty) await SupabaseService.updateUsername(_usernameCtrl.text); if (_newPasswordCtrl.text.isNotEmpty) await SupabaseService.updatePassword(_newPasswordCtrl.text); setState(() => _isEditing = false); _loadProfile(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile updated!"))); } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"))); } }, child: const Text("Save"))])
              ],
              const Divider(),
              ListTile(contentPadding: EdgeInsets.zero, title: const Text("Log Out", style: TextStyle(color: Colors.red)), leading: const Icon(Icons.logout, color: Colors.red), onTap: () async { await SupabaseService.signOut(); if (mounted) setState(() {}); })
            ],
          ),
        )
      ],
    );
  }

  Widget _buildAuthForm(BuildContext context, Color? textColor) {
     return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Text("Login / Sign Up", style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          TextField(controller: _emailCtrl, decoration: const InputDecoration(hintText: "Email")),
          const SizedBox(height: 10),
          TextField(controller: _usernameCtrl, decoration: const InputDecoration(hintText: "Username (Sign Up)")),
          const SizedBox(height: 10),
          TextField(controller: _passwordCtrl, obscureText: true, decoration: const InputDecoration(hintText: "Password")),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [TextButton(onPressed: () async { try { await SupabaseService.signIn(_emailCtrl.text, _passwordCtrl.text); if (mounted) setState(() {}); } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e"))); } }, child: const Text("Login")), TextButton(onPressed: () async { try { await SupabaseService.signUp(_emailCtrl.text, _passwordCtrl.text, _usernameCtrl.text); if (mounted) setState(() {}); } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e"))); } }, child: const Text("Sign Up"))])
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, List<Widget> children) {
    return Container(decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)), child: Column(children: children));
  }
}