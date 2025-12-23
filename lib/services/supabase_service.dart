import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';

class SupabaseService {
  static final SupabaseClient client = Supabase.instance.client;

  // --- AUTH & PROFILE ---
  static User? get currentUser => client.auth.currentUser;
  static Stream<AuthState> get authStateChanges => client.auth.onAuthStateChange;

  static Future<void> signUp(String email, String password, String username) async {
    final response = await client.auth.signUp(
      email: email, 
      password: password, 
      data: {'username': username}
    );
    // Note: Profile creation is usually handled by a Supabase Trigger, 
    // but if you do it manually:
    if (response.user != null) {
      await client.from('profiles').upsert({
        'id': response.user!.id,
        'username': username,
      });
    }
  }

  static Future<void> signIn(String email, String password) async {
    await client.auth.signInWithPassword(email: email, password: password);
  }

  static Future<void> signOut() async {
    await client.auth.signOut();
  }

  // UPDATE: Change Password
  static Future<void> updatePassword(String newPassword) async {
    await client.auth.updateUser(UserAttributes(password: newPassword));
  }

  // UPDATE: Change Email
  static Future<void> updateEmail(String newEmail) async {
    await client.auth.updateUser(UserAttributes(email: newEmail));
  }

  // UPDATE: Change Username (Metadata & Profile Table)
  static Future<void> updateUsername(String newUsername) async {
    final user = currentUser;
    if (user == null) return;

    // Update Auth Metadata
    await client.auth.updateUser(UserAttributes(data: {'username': newUsername}));
    
    // Update Public Profile
    await client.from('profiles').update({'username': newUsername}).eq('id', user.id);
  }

  // UPDATE: Upload & Set Avatar
  static Future<String?> uploadAvatar(File imageFile) async {
    final user = currentUser;
    if (user == null) return null;

    final fileExt = imageFile.path.split('.').last;
    final fileName = '${user.id}/avatar_${DateTime.now().millisecondsSinceEpoch}.$fileExt';

    try {
      await client.storage.from('avatars').upload(fileName, imageFile);
      final imageUrl = client.storage.from('avatars').getPublicUrl(fileName);
      
      // Update profile with new avatar URL
      await client.from('profiles').update({'avatar_url': imageUrl}).eq('id', user.id);
      return imageUrl;
    } catch (e) {
      print("Upload error: $e");
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getCurrentProfile() async {
    final user = currentUser;
    if (user == null) return null;
    try {
      return await client.from('profiles').select().eq('id', user.id).single();
    } catch (e) {
      return null;
    }
  }

  // --- FRIENDS & SEARCH ---
  static Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    if (query.length < 3) return [];
    try {
      final response = await client
          .from('profiles')
          .select('id, username, avatar_url')
          .ilike('username', '%$query%')
          .limit(10);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  static Future<void> addFriend(String friendId) async {
    final user = currentUser;
    if (user == null) throw "Not logged in";
    if (user.id == friendId) throw "You cannot add yourself";

    await client.from('friends').insert({
      'user_id': user.id,
      'friend_id': friendId,
    });
  }

  static Future<String?> getUsername(String userId) async {
    try {
      final data = await client.from('profiles').select('username').eq('id', userId).maybeSingle();
      return data?['username'] as String?;
    } catch (e) {
      return null;
    }
  }

  // --- LOCATION & CHAT (Unchanged mainly) ---
  static Future<void> updateLocation(Position pos) async {
    final user = currentUser;
    if (user == null) return;
    await client.from('user_locations').upsert({
      'user_id': user.id,
      'latitude': pos.latitude,
      'longitude': pos.longitude,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  static Stream<List<Map<String, dynamic>>> streamUsersLocations() {
    return client.from('user_locations').stream(primaryKey: ['user_id']).map((data) => List<Map<String, dynamic>>.from(data));
  }

  static Stream<List<Map<String, dynamic>>> getMessages(String lineId) {
    return client.from('messages').stream(primaryKey: ['id']).eq('line_id', lineId).order('created_at', ascending: true).limit(50).map((data) => List<Map<String, dynamic>>.from(data));
  }

  static Future<void> sendMessage(String lineId, String content) async {
    final user = currentUser;
    if (user == null) return;
    await client.from('messages').insert({'line_id': lineId, 'user_id': user.id, 'content': content});
  }

  static Future<String?> getStationImage(String stationId) async {
    try {
      final data = await client.from('station_images').select('image_url').eq('station_id', stationId).maybeSingle();
      return data?['image_url'] as String?;
    } catch (e) {
      return null;
    }
  }
}