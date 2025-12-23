import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';

class SupabaseService {
  static final SupabaseClient client = Supabase.instance.client;

  // --- AUTH ---
  static User? get currentUser => client.auth.currentUser;

  static Stream<AuthState> get authStateChanges => client.auth.onAuthStateChange;

  static Future<void> signUp(String email, String password, String username) async {
    final response = await client.auth.signUp(email: email, password: password, data: {'username': username});
    // Create public profile entry immediately
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

  // --- LOCATION & FRIENDS ---
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

  // Stream of users locations (Replacing mock friends list)
  static Stream<List<Map<String, dynamic>>> streamUsersLocations() {
    return client
        .from('user_locations')
        .stream(primaryKey: ['user_id'])
        .map((data) => List<Map<String, dynamic>>.from(data));
  }
  
  static Future<String?> getUsername(String userId) async {
    final data = await client.from('profiles').select('username').eq('id', userId).maybeSingle();
    return data?['username'] as String?;
  }

  // --- CHAT ---
  // Filters chat messages by the specific transport line ID (e.g., "Bus 42")
  static Stream<List<Map<String, dynamic>>> getMessages(String lineId) {
    return client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('line_id', lineId)
        .order('created_at', ascending: true)
        .limit(50) 
        .map((data) => List<Map<String, dynamic>>.from(data));
  }

  static Future<void> sendMessage(String lineId, String content) async {
    final user = currentUser;
    if (user == null) return;

    await client.from('messages').insert({
      'line_id': lineId,
      'user_id': user.id,
      'content': content,
    });
  }

  // --- STATION IMAGES ---
  static Future<String?> getStationImage(String stationId) async {
    try {
      final data = await client.from('station_images').select('image_url').eq('station_id', stationId).maybeSingle();
      return data?['image_url'] as String?;
    } catch (e) {
      return null;
    }
  }

  // NOTE: Requires image_picker plugin implementation in UI to be fully usable
  static Future<void> uploadStationImage(String stationId, File imageFile) async {
    final user = currentUser;
    if (user == null) return;

    final fileName = '${stationId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await client.storage.from('station_guides').upload(fileName, imageFile);
    
    final publicUrl = client.storage.from('station_guides').getPublicUrl(fileName);
    
    await client.from('station_images').insert({
      'station_id': stationId,
      'image_url': publicUrl,
      'user_id': user.id,
    });
  }
}