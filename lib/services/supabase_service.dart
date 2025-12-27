import 'dart:io';
import 'dart:typed_data'; 
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';

class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;
  static User? get currentUser => client.auth.currentUser;

  // --- AUTH ---
  static Future<void> signUp(String email, String password, String username) async {
    String? redirectUrl = kIsWeb ? null : 'io.supabase.trans://login-callback';
    final response = await client.auth.signUp(
      email: email, 
      password: password, 
      data: {'username': username},
      emailRedirectTo: redirectUrl, 
    );
    if (response.user != null) {
      await client.from('profiles').upsert({'id': response.user!.id, 'username': username});
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

  // --- PROFILES ---
  static Future<Map<String, dynamic>?> getCurrentProfile() async {
    final user = currentUser;
    if (user == null) return null;
    try {
      return await client.from('profiles').select().eq('id', user.id).single();
    } catch (e) {
      return null;
    }
  }

  static Future<String?> getUsername(String userId) async {
    try {
      final data = await client.from('profiles').select('username').eq('id', userId).maybeSingle();
      return data?['username'] as String?;
    } catch (e) {
      return null;
    }
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
      return null;
    }
  }

  // --- FRIENDS SYSTEM ---

  // 1. Send Request
  static Future<void> sendFriendRequest(String targetUserId) async {
    final user = currentUser;
    if (user == null) throw "Not logged in";
    if (user.id == targetUserId) throw "You cannot add yourself";

    final checkFriend = await client.from('friends').select().match({'user_id': user.id, 'friend_id': targetUserId}).maybeSingle();
    if (checkFriend != null) throw "Already friends!";

    final checkReq = await client.from('friend_requests').select()
      .or('and(sender_id.eq.${user.id},receiver_id.eq.$targetUserId),and(sender_id.eq.$targetUserId,receiver_id.eq.${user.id})')
      .maybeSingle();
      
    if (checkReq != null) throw "Request already pending!";

    await client.from('friend_requests').insert({
      'sender_id': user.id,
      'receiver_id': targetUserId, 
      'status': 'pending'
    });
  }

  // 2. Fetch Requests
  static Future<List<Map<String, dynamic>>> getPendingRequests() async {
    final user = currentUser;
    if (user == null) return [];
    
    final data = await client.from('friend_requests')
        .select()
        .eq('receiver_id', user.id)
        .eq('status', 'pending');
    
    if (data.isEmpty) return [];
    
    // Enrich with Sender Profiles
    final senderIds = (data as List).map((r) => r['sender_id']).toList();
    final profiles = await client.from('profiles').select().filter('id', 'in', senderIds);
    final profileMap = {for (var p in profiles) p['id']: p};

    return data.map((req) {
      final sender = profileMap[req['sender_id']];
      return {
        ...req,
        'sender_username': sender?['username'] ?? 'Unknown',
        'sender_avatar': sender?['avatar_url'],
      };
    }).toList();
  }

  static Stream<List<Map<String, dynamic>>> streamPendingRequests() {
    final user = currentUser;
    if (user == null) return const Stream.empty();
    // Re-use logic: Stream IDs, fetch details
    return client.from('friend_requests').stream(primaryKey: ['id']).eq('receiver_id', user.id).asyncMap((_) => getPendingRequests());
  }

  // 3. Fetch Friends (ROBUST: Friends Table -> Profiles + Locations)
  static Future<List<Map<String, dynamic>>> getFriends() async {
    final user = currentUser;
    if (user == null) return [];

    // A. Get Friend IDs from 'friends' table
    final friendsRelation = await client.from('friends').select('friend_id').eq('user_id', user.id);
    if (friendsRelation.isEmpty) return [];

    final friendIds = (friendsRelation as List).map((e) => e['friend_id']).toList();

    // B. Get Profiles (Name, Avatar)
    final profiles = await client.from('profiles').select().filter('id', 'in', friendIds);
    final profileMap = {for (var p in profiles) p['id']: p};

    // C. Get Locations (Lat, Long, Line) - might be empty for some
    final locations = await client.from('user_locations').select().filter('user_id', 'in', friendIds);
    final locationMap = {for (var l in locations) l['user_id']: l};

    // D. Merge
    List<Map<String, dynamic>> result = [];
    for (var id in friendIds) {
      final profile = profileMap[id];
      if (profile == null) continue; // Should not happen

      final loc = locationMap[id];
      result.add({
        'id': id,
        'username': profile['username'] ?? 'Unknown',
        'avatar_url': profile['avatar_url'],
        'latitude': loc?['latitude'],
        'longitude': loc?['longitude'],
        'updated_at': loc?['updated_at'], // Needed for "Active" check
        'current_line': loc?['current_line'],
      });
    }
    return result;
  }

  // Stream Friends (Listens to LOCATION updates to keep "Active" status live)
  static Stream<List<Map<String, dynamic>>> streamFriends() {
    final user = currentUser;
    if (user == null) return const Stream.empty();
    
    // We listen to user_locations so we update when friends move
    return client.from('user_locations').stream(primaryKey: ['user_id']).asyncMap((_) => getFriends());
  }

  static Future<void> acceptFriendRequest(String senderId) async {
    await client.rpc('accept_friend_request', params: {'request_sender_id': senderId});
  }

  static Future<void> rejectFriendRequest(String senderId) async {
    final user = currentUser;
    if (user == null) return;
    await client.from('friend_requests').delete().match({'sender_id': senderId, 'receiver_id': user.id});
  }

  static Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    if (query.length < 3) return [];
    try {
      final response = await client.from('profiles').select().ilike('username', '%$query%').limit(10);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  // --- LOCATION ---
  static Future<void> updateLocation(Position pos, {String? currentLine}) async {
    final user = currentUser;
    if (user == null) return;
    
    final updateData = {
      'user_id': user.id,
      'latitude': pos.latitude,
      'longitude': pos.longitude,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (currentLine != null) updateData['current_line'] = currentLine;

    await client.from('user_locations').upsert(updateData);
  }

  // --- CHAT & TICKET ---
  static Stream<List<Map<String, dynamic>>> getMessages(String lineId) {
    return client.from('messages').stream(primaryKey: ['id']).eq('line_id', lineId).order('created_at', ascending: true).limit(50).asyncMap((List<Map<String, dynamic>> messages) async {
          if (messages.isEmpty) return [];
          final userIds = messages.map((m) => m['user_id'] as String).toSet().toList();
          final profiles = await client.from('profiles').select().filter('id', 'in', userIds);
          final profileMap = {for (var p in profiles) p['id']: p};
          return messages.map((m) {
            final sender = profileMap[m['user_id']];
            return {
              ...m,
              'username': sender?['username'] ?? 'Unknown',
              'avatar_url': sender?['avatar_url'],
            };
          }).toList();
        });
  }

  static Future<void> sendMessage(String lineId, String content) async {
    final user = currentUser;
    if (user == null) return;
    await client.from('messages').insert({'line_id': lineId, 'user_id': user.id, 'content': content});
  }

  static Future<String?> getTicketUrl() async {
    final user = currentUser;
    if (user == null) return null;
    // This previously crashed if column didn't exist. Fixed by SQL above.
    final data = await client.from('profiles').select('ticket_url').eq('id', user.id).maybeSingle();
    return data?['ticket_url'] as String?;
  }
  
  static Future<String?> uploadTicketBytes(Uint8List bytes, String fileExt) async {
    final user = currentUser;
    if (user == null) return null;
    final fileName = '${user.id}/ticket_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
    await client.storage.from('tickets').uploadBinary(fileName, bytes);
    final imageUrl = client.storage.from('tickets').getPublicUrl(fileName);
    await client.from('profiles').update({'ticket_url': imageUrl}).eq('id', user.id);
    return imageUrl;
  }
  
  static Future<String?> uploadTicket(File imageFile) async {
    final user = currentUser;
    if (user == null) return null;
    final fileExt = imageFile.path.split('.').last;
    final fileName = '${user.id}/ticket_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
    await client.storage.from('tickets').upload(fileName, imageFile);
    final imageUrl = client.storage.from('tickets').getPublicUrl(fileName);
    await client.from('profiles').update({'ticket_url': imageUrl}).eq('id', user.id);
    return imageUrl;
  }

  static Future<String?> getStationImage(String stationId) async {
    final data = await client.from('station_images').select('image_url').eq('station_id', stationId).maybeSingle();
    return data?['image_url'] as String?;
  }
  
  static Future<void> uploadStationImage(dynamic imageFile, String stationId) async {
    final user = currentUser;
    if (user == null) return;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = '$stationId/$timestamp.jpg';
    if (imageFile is File) await client.storage.from('station_guides').upload(fileName, imageFile);
    else if (imageFile is Uint8List) await client.storage.from('station_guides').uploadBinary(fileName, imageFile);
    final publicUrl = client.storage.from('station_guides').getPublicUrl(fileName);
    await client.from('station_images').upsert({'station_id': stationId, 'image_url': publicUrl, 'uploaded_by': user.id, 'updated_at': DateTime.now().toIso8601String()});
  }
  
  static Future<List<Map<String, dynamic>>> getBlockedUsers() async {
    final user = currentUser;
    if (user == null) return [];
    final response = await client.from('user_blocks').select('blocked_id').eq('blocker_id', user.id);
    final List blockedIds = (response as List).map((e) => e['blocked_id']).toList();
    if (blockedIds.isEmpty) return [];
    final profiles = await client.from('profiles').select().filter('id', 'in', blockedIds);
    return List<Map<String, dynamic>>.from(profiles);
  }
  
  static Future<void> blockUser(String userId) async {
    final user = currentUser;
    if (user == null) return;
    await client.from('user_blocks').insert({'blocker_id': user.id, 'blocked_id': userId});
  }
  
  static Future<void> unblockUser(String userId) async {
    final user = currentUser;
    if (user == null) return;
    await client.from('user_blocks').delete().match({'blocker_id': user.id, 'blocked_id': userId});
  }
}