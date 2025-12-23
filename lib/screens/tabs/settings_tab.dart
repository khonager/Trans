import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/supabase_service.dart';

class SettingsTab extends StatefulWidget {
  final bool isDarkMode;
  final Function(bool) onThemeChanged;
  final bool onlyNahverkehr;
  final Function(bool) onNahverkehrChanged;

  const SettingsTab({
    super.key,
    required this.isDarkMode,
    required this.onThemeChanged,
    required this.onlyNahverkehr,
    required this.onNahverkehrChanged,
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

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await SupabaseService.getCurrentProfile();
    if (mounted) setState(() => _profile = profile);
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      await SupabaseService.uploadAvatar(File(picked.path));
      _loadProfile(); // Refresh
    }
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
          // App Settings
          _buildSection(context, [
            SwitchListTile(
              title: Text("Dark Mode", style: TextStyle(color: textColor)),
              value: widget.isDarkMode,
              onChanged: widget.onThemeChanged,
            ),
            SwitchListTile(
              title: Text("Deutschlandticket Mode", style: TextStyle(color: textColor)),
              subtitle: const Text("Only local/regional transport"),
              value: widget.onlyNahverkehr,
              onChanged: widget.onNahverkehrChanged,
            ),
          ]),

          const SizedBox(height: 20),
          
          if (user == null)
            _buildAuthForm(context)
          else
            _buildProfileSection(context, user, textColor),
        ],
      ),
    );
  }

  Widget _buildProfileSection(BuildContext context, user, Color? textColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Profile", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: [
              // Avatar
              GestureDetector(
                onTap: _pickAvatar,
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: Colors.indigo,
                  backgroundImage: _profile?['avatar_url'] != null 
                      ? NetworkImage(_profile!['avatar_url']) 
                      : null,
                  child: _profile?['avatar_url'] == null 
                      ? const Icon(Icons.camera_alt, color: Colors.white) 
                      : null,
                ),
              ),
              const SizedBox(height: 10),
              
              if (!_isEditing) ...[
                Text(_profile?['username'] ?? "No Username", style: TextStyle(fontSize: 18, color: textColor)),
                Text(user.email ?? "", style: TextStyle(color: textColor?.withOpacity(0.6))),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () {
                    _usernameCtrl.text = _profile?['username'] ?? "";
                    setState(() => _isEditing = true);
                  },
                  child: const Text("Edit Profile"),
                )
              ] else ...[
                TextField(controller: _usernameCtrl, decoration: const InputDecoration(labelText: "Username")),
                TextField(controller: _newPasswordCtrl, decoration: const InputDecoration(labelText: "New Password (Optional)"), obscureText: true),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(onPressed: () => setState(() => _isEditing = false), child: const Text("Cancel")),
                    ElevatedButton(
                      onPressed: () async {
                        try {
                          if (_usernameCtrl.text.isNotEmpty) {
                            await SupabaseService.updateUsername(_usernameCtrl.text);
                          }
                          if (_newPasswordCtrl.text.isNotEmpty) {
                            await SupabaseService.updatePassword(_newPasswordCtrl.text);
                          }
                          setState(() => _isEditing = false);
                          _loadProfile();
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile updated!")));
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
                        }
                      },
                      child: const Text("Save"),
                    ),
                  ],
                )
              ],
              
              const Divider(),
              ListTile(
                title: const Text("Log Out", style: TextStyle(color: Colors.red)),
                leading: const Icon(Icons.logout, color: Colors.red),
                onTap: () async {
                  await SupabaseService.signOut();
                  if (mounted) setState(() {});
                },
              )
            ],
          ),
        )
      ],
    );
  }

  Widget _buildAuthForm(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          const Text("Login / Sign Up", style: TextStyle(fontWeight: FontWeight.bold)),
          TextField(controller: _emailCtrl, decoration: const InputDecoration(hintText: "Email")),
          TextField(controller: _usernameCtrl, decoration: const InputDecoration(hintText: "Username (Sign Up)")),
          TextField(controller: _passwordCtrl, obscureText: true, decoration: const InputDecoration(hintText: "Password")),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton(
                onPressed: () async {
                  try {
                    await SupabaseService.signIn(_emailCtrl.text, _passwordCtrl.text);
                    if (mounted) setState(() {});
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e")));
                  }
                },
                child: const Text("Login"),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    await SupabaseService.signUp(_emailCtrl.text, _passwordCtrl.text, _usernameCtrl.text);
                    if (mounted) setState(() {});
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e")));
                  }
                },
                child: const Text("Sign Up"),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
      child: Column(children: children),
    );
  }
}