import 'dart:convert';
import 'dart:io';
import 'dart:typed_data'; 
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

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

  static Future<void> updateUsername(String newUsername) async {
    final user = currentUser;
    if (user == null) return;
    await client.auth.updateUser(UserAttributes(data: {'username': newUsername}));
    await client.from('profiles').update({'username': newUsername}).eq('id', user.id);
  }
  
  static Future<void> updateThemeColor(int colorValue) async {
    final user = currentUser;
    if (user == null) return;
    await client.from('profiles').update({'theme_color': colorValue}).eq('id', user.id);
  }

  // --- GHOST MODE & PRIVACY ---
  static Future<void> toggleGhostMode(bool enable) async {
    final user = currentUser;
    if (user == null) return;

    if (enable) {
      await client.from('profiles').update({'ghost_mode': true}).eq('id', user.id);
      await client.from('user_locations').delete().eq('user_id', user.id);
    } else {
      // Trigger penalty when turning OFF
      await client.rpc('disable_ghost_mode', params: {'user_uuid': user.id});
    }
  }

  static Future<void> requestLocationAccess(String friendId) async {
    final user = currentUser;
    if (user == null) return;
    await client.from('friends')
      .update({'can_see_location': true})
      .match({'user_id': user.id, 'friend_id': friendId});
  }

  // --- PROFILES & EMOJIS ---
  static Future<Map<String, dynamic>?> getCurrentProfile() async {
    final user = currentUser;
    if (user == null) return null;
    try {
      return await client.from('profiles').select().eq('id', user.id).single();
    } catch (e) {
      return null;
    }
  }

  static Future<void> updateAvatarEmoji(String emoji) async {
    final user = currentUser;
    if (user == null) return;
    await client.from('profiles').update({
      'avatar_emoji': emoji, 
      'avatar_url': null 
    }).eq('id', user.id);
  }

  // --- FRIENDS SYSTEM ---
  static Future<List<Map<String, dynamic>>> getPendingRequests() async {
    final user = currentUser;
    if (user == null) return [];
    
    final data = await client.from('friend_requests')
        .select()
        .eq('receiver_id', user.id)
        .eq('status', 'pending');
    
    if (data.isEmpty) return [];
    
    final senderIds = (data as List).map((r) => r['sender_id']).toList();
    final profiles = await client.from('profiles').select('id, username, avatar_url, avatar_emoji, theme_color').filter('id', 'in', senderIds);
    final profileMap = {for (var p in profiles) p['id']: p};

    return data.map((req) {
      final sender = profileMap[req['sender_id']];
      return {
        ...req,
        'sender_username': sender?['username'] ?? 'Unknown',
        'sender_avatar': sender?['avatar_url'],
        'sender_emoji': sender?['avatar_emoji'],
        'theme_color': sender?['theme_color'],
      };
    }).toList();
  }

  static Stream<List<Map<String, dynamic>>> streamPendingRequests() {
    final user = currentUser;
    if (user == null) return const Stream.empty();
    return client.from('friend_requests').stream(primaryKey: ['id']).eq('receiver_id', user.id).asyncMap((_) => getPendingRequests());
  }

  static Future<List<Map<String, dynamic>>> getFriends() async {
    final user = currentUser;
    if (user == null) return [];

    // 1. Check MY Ghost Mode status first
    final myProfile = await client.from('profiles').select('ghost_mode').eq('id', user.id).single();
    final bool amIGhost = myProfile['ghost_mode'] ?? false;

    final friendsRelation = await client.from('friends').select('friend_id, can_see_location').eq('user_id', user.id);
    if (friendsRelation.isEmpty) return [];

    final friendIds = (friendsRelation as List).map((e) => e['friend_id']).toList();
    final permissionMap = {for (var e in friendsRelation) e['friend_id']: e['can_see_location']};

    final profiles = await client.from('profiles').select('id, username, avatar_url, avatar_emoji, theme_color, ghost_mode').filter('id', 'in', friendIds);
    final profileMap = {for (var p in profiles) p['id']: p};

    final locations = await client.from('user_locations').select().filter('user_id', 'in', friendIds);
    final locationMap = {for (var l in locations) l['user_id']: l};

    List<Map<String, dynamic>> result = [];
    for (var id in friendIds) {
      final profile = profileMap[id];
      if (profile == null) continue;

      final loc = locationMap[id];
      final bool canSee = permissionMap[id] ?? true;
      final bool isFriendGhost = profile['ghost_mode'] ?? false;

      // FIX: If I am a ghost, I see NOTHING.
      final bool showLocation = !amIGhost && canSee && !isFriendGhost;

      dynamic lat, lng, updatedAt, currentLine;
      if (showLocation && loc != null) {
        lat = loc['latitude'];
        lng = loc['longitude'];
        updatedAt = loc['updated_at'];
        currentLine = loc['current_line'];
      }

      result.add({
        'id': id,
        'username': profile['username'] ?? 'Unknown',
        'avatar_url': profile['avatar_url'],
        'avatar_emoji': profile['avatar_emoji'],
        'theme_color': profile['theme_color'],
        'ghost_mode': isFriendGhost, // Keep seeing friend's status, just not location
        'can_see_location': canSee, 
        'latitude': lat,
        'longitude': lng,
        'updated_at': updatedAt, 
        'current_line': currentLine,
      });
    }
    return result;
  }

  static Stream<List<Map<String, dynamic>>> streamFriends() {
    final user = currentUser;
    if (user == null) return const Stream.empty();
    return client.from('user_locations').stream(primaryKey: ['user_id']).asyncMap((_) => getFriends());
  }

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
    
    // Check local ghost mode to avoid unnecessary DB calls, but DB policy handles it too
    final profile = await getCurrentProfile();
    if (profile != null && profile['ghost_mode'] == true) {
      return; 
    }
    
    final Map<String, dynamic> updateData = {
      'user_id': user.id,
      'latitude': pos.latitude,
      'longitude': pos.longitude,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    
    // Allow updating ONLY location without changing line if currentLine is NOT passed
    // But if currentLine IS passed (even if null), update it.
    if (currentLine != null) {
      updateData['current_line'] = currentLine;
    } 
    // If explicitly null (to clear it), we handle it. But Dart optional params default to null.
    // So we need a way to distinguish "Don't change" vs "Clear".
    // For this app: if we call this, we usually want to set the line. 
    // If we want to CLEAR it, pass an empty string or handle logic in RoutesTab.
    // Logic: If currentLine is passed, use it. If not, don't overwrite existing line.
    
    // However, the caller RoutesTab passes it.
    // To allow clearing, let's assume if it's passed as 'null', we don't send it?
    // No, we need to be able to clear it.
    // Let's rely on upsert behavior.
    
    // Revised Logic for Active Status:
    // We update 'current_line' whenever we have a new value. 
    if (currentLine != null) {
        updateData['current_line'] = currentLine;
    }

    await client.from('user_locations').upsert(updateData);
  }
  
  // Method to explicitly clear line status (when ride ends)
  static Future<void> clearJourneyStatus() async {
    final user = currentUser;
    if (user == null) return;
    await client.from('user_locations').upsert({
      'user_id': user.id,
      'current_line': null // Explicitly clear it
    });
  }

  // --- CHAT (Public & Private) ---
  static String _getPrivateKey(String otherUserId) {
    final myId = currentUser!.id;
    final List<String> ids = [myId, otherUserId]..sort();
    final combined = ids.join('_');
    final bytes = utf8.encode(combined);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 32); 
  }

  static Stream<List<Map<String, dynamic>>> getMessages(String lineId) {
    return client.from('messages').stream(primaryKey: ['id'])
      .eq('line_id', lineId)
      .order('created_at', ascending: true)
      .limit(50)
      .asyncMap(_enrichMessages);
  }

  static Stream<List<Map<String, dynamic>>> getPrivateMessages(String otherUserId) {
    final myId = currentUser!.id;
    return client.from('messages').stream(primaryKey: ['id'])
      .eq('is_encrypted', true)
      .order('created_at', ascending: true)
      .limit(50)
      .asyncMap((rawMessages) async {
        final filtered = rawMessages.where((m) {
          final uid = m['user_id'];
          final rid = m['receiver_id'];
          return (uid == myId && rid == otherUserId) || (uid == otherUserId && rid == myId);
        }).toList();

        return _enrichMessages(filtered, decryptForUser: otherUserId);
      });
  }

  static Future<List<Map<String, dynamic>>> _enrichMessages(List<Map<String, dynamic>> messages, {String? decryptForUser}) async {
    if (messages.isEmpty) return [];
    
    final userIds = messages.map((m) => m['user_id'] as String).toSet().toList();
    final profiles = await client.from('profiles').select('id, username, avatar_url, avatar_emoji, theme_color').filter('id', 'in', userIds);
    final profileMap = {for (var p in profiles) p['id']: p};

    final keyString = decryptForUser != null ? _getPrivateKey(decryptForUser) : null;
    final enc.Key? key = keyString != null ? enc.Key.fromUtf8(keyString) : null;
    final encrypter = key != null ? enc.Encrypter(enc.AES(key)) : null;

    return messages.map((m) {
      final sender = profileMap[m['user_id']];
      String content = m['content'];
      
      if (m['is_encrypted'] == true && encrypter != null) {
        try {
          final parts = content.split(':');
          if (parts.length == 2) {
            final iv = enc.IV.fromBase64(parts[0]);
            final cipher = parts[1];
            content = encrypter.decrypt64(cipher, iv: iv);
          } else {
             content = "[Corrupt Message]";
          }
        } catch (e) {
          content = "[Error decrypting]";
        }
      }

      return {
        ...m,
        'content': content, 
        'username': sender?['username'] ?? 'Unknown',
        'avatar_url': sender?['avatar_url'],
        'avatar_emoji': sender?['avatar_emoji'],
        'theme_color': sender?['theme_color'],
      };
    }).toList();
  }

  static Future<void> sendMessage(String lineId, String content) async {
    final user = currentUser;
    if (user == null) return;
    await client.from('messages').insert({
      'line_id': lineId, 
      'user_id': user.id, 
      'content': content,
      'is_encrypted': false
    });
  }

  static Future<void> sendPrivateMessage(String targetUserId, String content) async {
    final user = currentUser;
    if (user == null) return;
    
    final keyString = _getPrivateKey(targetUserId);
    final key = enc.Key.fromUtf8(keyString);
    final iv = enc.IV.fromLength(16); 
    final encrypter = enc.Encrypter(enc.AES(key));
    
    final encrypted = encrypter.encrypt(content, iv: iv);
    
    // Store IV + Ciphertext
    final storedContent = "${iv.base64}:${encrypted.base64}";

    await client.from('messages').insert({
      'line_id': null, 
      'user_id': user.id, 
      'receiver_id': targetUserId,
      'content': storedContent,
      'is_encrypted': true
    });
  }

  // --- TICKET & BLOCKING ---
  static Future<String?> getTicketUrl() async {
    final user = currentUser;
    if (user == null) return null;
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
    // Delete relationship BOTH ways
    await client.from('friends').delete().match({'user_id': user.id, 'friend_id': userId});
    await client.from('friends').delete().match({'user_id': userId, 'friend_id': user.id});
  }
  
  static Future<void> unblockUser(String userId) async {
    final user = currentUser;
    if (user == null) return;
    await client.from('user_blocks').delete().match({'blocker_id': user.id, 'blocked_id': userId});
  }
}