import 'dart:convert';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserRepository {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  // Stream controller to broadcast profile updates to your UI
  final _profileController = StreamController<Map<String, dynamic>>.broadcast();

  // Expose the stream so your UI can listen to it (using StreamBuilder)
  Stream<Map<String, dynamic>> get profileStream => _profileController.stream;

  /// The main function to call when the app starts or the profile screen loads.
  /// 
  /// Strategy: 
  /// 1. Load from Local Storage immediately (Fast, works offline).
  /// 2. Fetch from Supabase (Slow, requires internet).
  /// 3. If Supabase succeeds, update Local Storage + UI.
  Future<void> fetchProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    // 1. Try to load local cache first
    await _loadFromLocalCache();

    // 2. Fetch from network
    try {
      final data = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();

      // 3. If successful, save to cache and emit new data
      if (data != null) {
        await _saveToLocalCache(data);
        _profileController.add(data);
      }
    } catch (e) {
      // If network fails, we just rely on the local data we already emitted.
      print('Network fetch failed, using offline data: $e');
    }
  }

  /// Updates the profile.
  /// 
  /// Strategy:
  /// 1. Update Supabase (Cloud).
  /// 2. If successful, update Local Cache immediately.
  Future<void> updateProfile({String? fullName, String? avatarUrl}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final updates = {
      'id': user.id,
      'updated_at': DateTime.now().toIso8601String(),
      if (fullName != null) 'full_name': fullName,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
    };

    // 1. Push to Cloud
    // This will throw an error if offline, which is good (user knows update failed)
    final response = await _supabase
        .from('profiles')
        .upsert(updates)
        .select()
        .single();

    // 2. Update Local Cache with the response from server
    await _saveToLocalCache(response);
    
    // 3. Update the stream so UI refreshes
    _profileController.add(response);
  }

  // --- Helper Methods ---

  Future<void> _saveToLocalCache(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cached_profile', jsonEncode(data));
  }

  Future<void> _loadFromLocalCache() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('cached_profile');
    
    if (jsonString != null) {
      try {
        final data = jsonDecode(jsonString);
        _profileController.add(data);
      } catch (e) {
        print('Error parsing local cache: $e');
      }
    }
  }
}