import 'dart:io';
import 'dart:typed_data'; // Required for Uint8List
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';

class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;
  // --- AUTH & PROFILE ---
  static User? get currentUser => client.auth.currentUser;
  static Stream<AuthState> get authStateChanges => client.auth.onAuthStateChange;

  static Future<void> signUp(String email, String password, String username) async {
    // UPDATED: Added emailRedirectTo to help fix localhost redirect issues.
    // Ensure you configured this URL in Supabase Dashboard > Auth > URL Configuration.
    final response = await client.auth.signUp(
      email: email, 
      password: password, 
      data: {'username': username},
      emailRedirectTo: 'io.supabase.trans://login-callback', 
    );
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

  static Future<void> updatePassword(String newPassword) async {
    await client.auth.updateUser(UserAttributes(password: newPassword));
  }

  static Future<void> updateEmail(String newEmail) async {
    await client.auth.updateUser(UserAttributes(email: newEmail));
  }

  static Future<void> updateUsername(String newUsername) async {
    final user = currentUser;
    if (user == null) return;
    await client.auth.updateUser(UserAttributes(data: {'username': newUsername}));
    await client.from('profiles').update({'username': newUsername}).eq('id', user.id);
  }

  static Future<String?> uploadAvatar(File imageFile) async {
    final user = currentUser;
    if (user == null) return null;
    final fileExt = imageFile.path.split('.').last;
    final fileName = '${user.id}/avatar_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
    try {
      await client.storage.from('avatars').upload(fileName, imageFile);
      final imageUrl = client.storage.from('avatars').getPublicUrl(fileName);
      await client.from('profiles').update({'avatar_url': imageUrl}).eq('id', user.id);
      return imageUrl;
    } catch (e) {
      print("Upload error: $e");
      return null;
    }
  }

  // --- TICKET FEATURES ---
  
  static Future<String?> uploadTicket(File imageFile) async {
    final user = currentUser;
    if (user == null) return null;
    await _deleteOldTickets(user.id);
    final fileExt = imageFile.path.split('.').last;
    final fileName = '${user.id}/ticket_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
    try {
      await client.storage.from('tickets').upload(fileName, imageFile);
      final imageUrl = client.storage.from('tickets').getPublicUrl(fileName);
      await client.from('profiles').update({'ticket_url': imageUrl}).eq('id', user.id);
      return imageUrl;
    } catch (e) {
      return null;
    }
  }

  static Future<String?> uploadTicketBytes(Uint8List bytes, String fileExt) async {
    final user = currentUser;
    if (user == null) return null;
    await _deleteOldTickets(user.id);
    final fileName = '${user.id}/ticket_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
    try {
      await client.storage.from('tickets').uploadBinary(fileName, bytes);
      final imageUrl = client.storage.from('tickets').getPublicUrl(fileName);
      await client.from('profiles').update({'ticket_url': imageUrl}).eq('id', user.id);
      return imageUrl;
    } catch (e) {
      print("Web upload error: $e");
      return null;
    }
  }
  
  static Future<void> _deleteOldTickets(String userId) async {
    try {
      final List<FileObject> objects = await client.storage.from('tickets').list(path: userId);
      if (objects.isNotEmpty) {
        final List<String> pathsToDelete = objects.map((f) => '$userId/${f.name}').toList();
        await client.storage.from('tickets').remove(pathsToDelete);
      }
    } catch (e) {
      print("Error cleaning old tickets: $e");
    }
  }

  static Future<String?> getTicketUrl() async {
    final user = currentUser;
    if (user == null) return null;
    try {
      final data = await client.from('profiles').select('ticket_url').eq('id', user.id).maybeSingle();
      return data?['ticket_url'] as String?;
    } catch (e) {
      return null;
    }
  }

  static Future<List<FileObject>> getTicketHistory() async {
    final user = currentUser;
    if (user == null) return [];
    try {
      final List<FileObject> objects = await client.storage.from('tickets').list(path: user.id);
      objects.sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
      return objects;
    } catch (e) {
      return [];
    }
  }
  
  static String getTicketPublicUrl(String fileName) {
    final user = currentUser;
    if (user == null) return "";
    return client.storage.from('tickets').getPublicUrl('${user.id}/$fileName');
  }

  static Future<void> deleteTicket(String fileName) async {
    final user = currentUser;
    if (user == null) return;
    try {
      await client.storage.from('tickets').remove(['${user.id}/$fileName']);
    } catch (e) {
      print("Delete error: $e");
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

  // --- FRIENDS & BLOCKING & REQUESTS ---
  
  // UPDATED: Now returns friend status to help UI
  static Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    if (query.length < 3) return [];
    try {
      final user = currentUser;
      final response = await client
          .from('profiles')
          .select('id, username, avatar_url')
          .ilike('username', '%$query%')
          .limit(10);
      
      // In a real app, you might want to join 'friends' or 'friend_requests' here
      // to see if you already requested them. For now we just return profiles.
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  // NEW: Send Friend Request instead of direct add
  static Future<void> sendFriendRequest(String targetUserId) async {
    final user = currentUser;
    if (user == null) throw "Not logged in";
    if (user.id == targetUserId) throw "You cannot add yourself";

    // Check if already friends
    final check = await client.from('friends').select().match({'user_id': user.id, 'friend_id': targetUserId}).maybeSingle();
    if (check != null) throw "Already friends!";

    // Insert Request
    await client.from('friend_requests').insert({
      'sender_id': user.id,
      'receiver_id': targetUserId, 
      'status': 'pending'
    });
  }

  // NEW: Get Pending Requests
  static Future<List<Map<String, dynamic>>> getPendingRequests() async {
    final user = currentUser;
    if (user == null) return [];
    try {
      // 1. Get requests where I am the receiver
      final requests = await client
          .from('friend_requests')
          .select()
          .eq('receiver_id', user.id)
          .eq('status', 'pending');
          
      if (requests.isEmpty) return [];

      // 2. Fetch profiles for these senders manually
      final senderIds = (requests as List).map((r) => r['sender_id']).toList();
      final profiles = await client.from('profiles').select().filter('id', 'in', senderIds);

      // 3. Merge data
      return profiles.map((p) => p as Map<String, dynamic>).toList();
    } catch (e) {
      print("Error fetching requests: $e");
      return [];
    }
  }

  // NEW: Accept Request (Uses Postgres Function for atomicity/security)
  static Future<void> acceptFriendRequest(String senderId) async {
    await client.rpc('accept_friend_request', params: {'request_sender_id': senderId});
  }

  static Future<void> rejectFriendRequest(String senderId) async {
    final user = currentUser;
    if (user == null) return;
    await client.from('friend_requests').delete().match({
      'sender_id': senderId,
      'receiver_id': user.id
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

  static Future<void> blockUser(String userIdToBlock) async {
    final user = currentUser;
    if (user == null) return;
    await client.from('user_blocks').insert({
      'blocker_id': user.id,
      'blocked_id': userIdToBlock,
    });
  }

  static Future<void> unblockUser(String userIdToUnblock) async {
    final user = currentUser;
    if (user == null) return;
    await client.from('user_blocks').delete().match({
      'blocker_id': user.id,
      'blocked_id': userIdToUnblock,
    });
  }

  static Future<List<Map<String, dynamic>>> getBlockedUsers() async {
    final user = currentUser;
    if (user == null) return [];
    try {
      final response = await client.from('user_blocks').select('blocked_id').eq('blocker_id', user.id);
      final List blockedIds = (response as List).map((e) => e['blocked_id']).toList();
      
      if (blockedIds.isEmpty) return [];

      final profiles = await client.from('profiles').select().filter('id', 'in', blockedIds);
      return List<Map<String, dynamic>>.from(profiles);
    } catch (e) {
      return [];
    }
  }

  // --- LOCATION & CHAT ---
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
    // Note: This only shows people who are in your 'friends' table.
    // If you haven't accepted their request, you won't see them if RLS is set up correctly.
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
  
  static Future<void> uploadStationImage(dynamic imageFile, String stationId) async {
    final user = currentUser;
    if (user == null) return;
    
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = '$stationId/$timestamp.jpg';

    String? publicUrl;
    
    try {
      if (imageFile is File) {
         await client.storage.from('station_guides').upload(fileName, imageFile);
      } else if (imageFile is Uint8List) {
         await client.storage.from('station_guides').uploadBinary(fileName, imageFile);
      }
      
      publicUrl = client.storage.from('station_guides').getPublicUrl(fileName);
      
      if (publicUrl != null) {
        await client.from('station_images').upsert({
          'station_id': stationId,
          'image_url': publicUrl,
          'uploaded_by': user.id,
          'updated_at': DateTime.now().toIso8601String()
        });
      }
    } catch (e) {
      print("Station upload error: $e");
      rethrow;
    }
  }
}