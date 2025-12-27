import 'dart:io';
import 'dart:typed_data'; 
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';

class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;
  
  // --- AUTH & PROFILE ---
  static User? get currentUser => client.auth.currentUser;
  static Stream<AuthState> get authStateChanges => client.auth.onAuthStateChange;

  static Future<void> signUp(String email, String password, String username) async {
    // Web needs null to use Site URL, Mobile needs deep link
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
  
  // Mobile Upload
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

  // Web Upload (This was missing or hidden)
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

  // --- FRIENDS & BLOCKING ---
  
  static Future<Map<String, dynamic>?> getCurrentProfile() async {
    final user = currentUser;
    if (user == null) return null;
    try {
      return await client.from('profiles').select().eq('id', user.id).single();
    } catch (e) {
      return null;
    }
  }

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

  static Future<void> sendFriendRequest(String targetUserId) async {
    final user = currentUser;
    if (user == null) throw "Not logged in";
    if (user.id == targetUserId) throw "You cannot add yourself";

    final checkFriend = await client.from('friends').select().match({'user_id': user.id, 'friend_id': targetUserId}).maybeSingle();
    if (checkFriend != null) throw "Already friends!";

    // Check existing request
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

  static Stream<List<Map<String, dynamic>>> streamPendingRequests() {
    final user = currentUser;
    if (user == null) return const Stream.empty();
    
    // Fixed: Single .eq() filter
    return client.from('friend_requests')
        .stream(primaryKey: ['id'])
        .eq('receiver_id', user.id)
        .map((data) => List<Map<String, dynamic>>.from(data.where((r) => r['status'] == 'pending')));
  }

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

  static Stream<List<Map<String, dynamic>>> streamFriendsWithLocation() {
    final user = currentUser;
    if (user == null) return const Stream.empty();

    return client.from('user_locations').stream(primaryKey: ['user_id']).asyncMap((locations) async {
       List<Map<String, dynamic>> enriched = [];
       for (var loc in locations) {
         if (loc['user_id'] == user.id) continue;
         final profile = await client.from('profiles').select('username, avatar_url').eq('id', loc['user_id']).maybeSingle();
         if (profile != null) {
           final Map<String, dynamic> data = Map.from(loc);
           data['username'] = profile['username'];
           data['avatar_url'] = profile['avatar_url'];
           enriched.add(data);
         }
       }
       // Sort: Active (<12h) first, then Alphabetical
       final now = DateTime.now();
       enriched.sort((a, b) {
         final dateA = DateTime.tryParse(a['updated_at'].toString()) ?? DateTime(2000);
         final dateB = DateTime.tryParse(b['updated_at'].toString()) ?? DateTime(2000);
         final isActiveA = now.difference(dateA).inHours < 12;
         final isActiveB = now.difference(dateB).inHours < 12;
         
         if (isActiveA && !isActiveB) return -1;
         if (!isActiveA && isActiveB) return 1;
         return (a['username'] as String).toLowerCase().compareTo((b['username'] as String).toLowerCase());
       });
       return enriched;
    });
  }

  static Stream<List<Map<String, dynamic>>> getMessages(String lineId) {
    return client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('line_id', lineId)
        .order('created_at', ascending: true)
        .limit(50)
        .asyncMap((List<Map<String, dynamic>> messages) async {
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
    await client.from('messages').insert({
      'line_id': lineId, 
      'user_id': user.id, 
      'content': content
    });
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
      rethrow;
    }
  }
}