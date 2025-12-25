import 'dart:convert';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';

class UserRepository {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  final _profileController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get profileStream => _profileController.stream;

  Future<void> fetchProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    await _loadFromLocalCache();

    try {
      final data = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();

      if (data != null) {
        await _saveToLocalCache(data);
        _profileController.add(data);
      }
    } catch (e) {
      print('Profile sync failed, using offline data: $e');
    }
  }

  Future<String?> uploadAvatar(XFile imageFile) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    try {
      final bytes = await imageFile.readAsBytes();
      final fileExt = imageFile.path.split('.').last;
      final fileName = '${user.id}/avatar.$fileExt'; 

      await _supabase.storage.from('avatars').uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );

      final imageUrl = _supabase.storage.from('avatars').getPublicUrl(fileName);
      return imageUrl;
    } catch (e) {
      print('Image upload failed: $e');
      rethrow;
    }
  }

  Future<void> updateProfile({String? fullName, String? avatarUrl}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final updates = {
      'id': user.id,
      'updated_at': DateTime.now().toIso8601String(),
      if (fullName != null) 'full_name': fullName,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
    };

    try {
      final response = await _supabase
          .from('profiles')
          .upsert(updates)
          .select()
          .single();

      await _saveToLocalCache(response);
      _profileController.add(response);
    } catch (e) {
      print('Update failed: $e');
      rethrow;
    }
  }

  Future<void> _saveToLocalCache(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cached_profile', jsonEncode(data));
  }

  Future<void> _loadFromLocalCache() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('cached_profile');
    if (jsonString != null) {
      _profileController.add(jsonDecode(jsonString));
    }
  }
}