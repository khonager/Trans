import 'dart:convert';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart'; // Add this package if not present

class UserRepository {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  // Stream controller to broadcast profile updates to your UI
  final _profileController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get profileStream => _profileController.stream;

  /// Fetches profile with "Cache-First, then Network" strategy.
  Future<void> fetchProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    // 1. Load Local (Instant)
    await _loadFromLocalCache();

    // 2. Fetch Remote (Async)
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

  /// Uploads an image file to Supabase Storage and returns the public URL.
  /// Call this BEFORE calling updateProfile().
  /// Uses XFile to ensure compatibility with Web and Mobile.
  Future<String?> uploadAvatar(XFile imageFile) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    try {
      final bytes = await imageFile.readAsBytes();
      final fileExt = imageFile.path.split('.').last;
      final fileName = '${user.id}/avatar.$fileExt'; 

      // Upload binary data (works on Web & Mobile)
      await _supabase.storage.from('avatars').uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );

      // Get the public URL
      final imageUrl = _supabase.storage.from('avatars').getPublicUrl(fileName);
      return imageUrl;
    } catch (e) {
      print('Image upload failed: $e');
      rethrow;
    }
  }

  /// Updates profile metadata (Name, Avatar URL)
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
      // 1. Update Cloud
      final response = await _supabase
          .from('profiles')
          .upsert(updates)
          .select()
          .single();

      // 2. Update Local & Stream
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