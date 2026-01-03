import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data'; 
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'notification_manager.dart';

class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;
  static User? get currentUser => client.auth.currentUser;

  static final ValueNotifier<int> friendsListRefresh = ValueNotifier(0);
  static final ValueNotifier<int> settingsRefreshNotifier = ValueNotifier(0);
  static StreamSubscription? _msgSubscription;

  // --- INITIALIZATION ---
  static Future<void> init() async {
    await NotificationManager.init();
    _startMessageListener();
  }

  static void _startMessageListener() {
    final user = currentUser;
    if (user == null) return;

    _msgSubscription?.cancel();
    _msgSubscription = client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('receiver_id', user.id)
        .limit(1)
        .listen((List<Map<String, dynamic>> data) {
          if (data.isNotEmpty) {
            final msg = data.first;
            final created = DateTime.parse(msg['created_at']);
            if (DateTime.now().toUtc().difference(created).inSeconds < 10) {
              NotificationManager.showNotification(
                id: msg['id'].hashCode,
                title: 'New Private Message',
                body: 'You received a secure message.',
              );
            }
          }
        });
  }

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
      _startMessageListener();
    }
  }

  static Future<void> signIn(String email, String password) async {
    await client.auth.signInWithPassword(email: email, password: password);
    _startMessageListener();
    await loadAndSyncSettings(); 
  }

  static Future<void> signOut() async {
    _msgSubscription?.cancel();
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

  static Future<void> updateEmail(String newEmail) async {
    // This will trigger a confirmation email to both old and new email addresses 
    // depending on Supabase project settings.
    await client.auth.updateUser(UserAttributes(email: newEmail));
  }

  static Future<void> resetPassword(String email) async {
    String? redirectUrl = kIsWeb ? null : 'io.supabase.trans://login-callback';
    await client.auth.resetPasswordForEmail(email, redirectTo: redirectUrl);
  }
  
  static Future<void> updateThemeColor(int colorValue) async {
    final user = currentUser;
    if (user == null) return;
    await client.from('profiles').update({'theme_color': colorValue}).eq('id', user.id);
    // Also update settings json for consistency if we move fully there, but for now keep theme_color column usage primarily
    // or we can mirror it to settings. Let's mirror it to make settings the source of truth eventually.
    await updateSettings({'theme_color_value': colorValue});
  }

  // --- SETTINGS SYNC ---
  static Future<void> updateSettings(Map<String, dynamic> newSettings) async {
    final user = currentUser;
    if (user == null) return;
    
    // Get current settings first to merge (shallow merge)
    try {
      final res = await client.from('profiles').select('settings').eq('id', user.id).single();
      final currentSettings = res['settings'] ?? {};
      final updatedSettings = Map<String, dynamic>.from(currentSettings)..addAll(newSettings);
      
      await client.from('profiles').update({'settings': updatedSettings}).eq('id', user.id);
    } catch (e) {
      debugPrint("Error updating settings: $e");
    }
  }

  static Future<void> updateFavoritesInfo(List<Map<String, dynamic>> favorites) async {
    final user = currentUser;
    if (user == null) return;
    await client.from('profiles').update({'favorites': favorites}).eq('id', user.id);
  }

  static Future<void> loadAndSyncSettings() async {
    final user = currentUser;
    if (user == null) return;

    try {
      final data = await client.from('profiles').select('settings, favorites').eq('id', user.id).single();
      final settings = data['settings'] as Map<String, dynamic>? ?? {};
      final favorites = data['favorites'] as List<dynamic>? ?? [];

      // Apply to SharedPreferences
      final prefs = await SharedPreferences.getInstance();

      // Settings
      if (settings.containsKey('theme_color_value')) {
        await prefs.setInt('theme_color_value', settings['theme_color_value']);
      }
      if (settings.containsKey('is_dark_mode')) {
        await prefs.setBool('is_dark_mode', settings['is_dark_mode']);
      }
      if (settings.containsKey('use_system_theme')) {
        await prefs.setBool('use_system_theme', settings['use_system_theme']);
      }
      if (settings.containsKey('only_nahverkehr')) {
        await prefs.setBool('only_nahverkehr', settings['only_nahverkehr']);
      }
      if (settings.containsKey('ghost_mode')) {
        await prefs.setBool('ghost_mode', settings['ghost_mode']);
      }
      if (settings.containsKey('vibration_pattern')) {
        await prefs.setString('vibration_pattern', settings['vibration_pattern']);
      }
      if (settings.containsKey('vibration_intensity')) {
        await prefs.setInt('vibration_intensity', settings['vibration_intensity']);
      }
      if (settings.containsKey('alarm_stops_before')) {
        await prefs.setInt('alarm_stops_before', settings['alarm_stops_before']);
      }

      if (favorites.isNotEmpty) {
        final List<String> favs = favorites.map((f) => json.encode(f)).toList().cast<String>();
        await prefs.setStringList('saved_favorites', favs);
      }
      
      // Notify app to reload settings
      settingsRefreshNotifier.value++;
      
    } catch (e) {
      debugPrint("Error syncing settings: $e");
    }
  }

  // --- GHOST MODE ---
  static Future<void> toggleGhostMode(bool enable) async {
    final user = currentUser;
    if (user == null) return;

    await client.from('profiles').update({'ghost_mode': enable}).eq('id', user.id);
    
    if (enable) {
      // Clear sensitive data, keep updated_at
      await client.from('user_locations').update({
        'latitude': null,
        'longitude': null,
        'current_line': null,
        'updated_at': DateTime.now().toUtc().toIso8601String()
      }).eq('user_id', user.id);
    }
    
    friendsListRefresh.value++;
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

    final myProfile = await client.from('profiles').select('ghost_mode').eq('id', user.id).single();
    final bool amIGhost = myProfile['ghost_mode'] ?? false;

    final friendsRelation = await client.from('friends').select('friend_id').eq('user_id', user.id);
    if (friendsRelation.isEmpty) return [];

    final friendIds = (friendsRelation as List).map((e) => e['friend_id']).toList();

    final profiles = await client.from('profiles').select('id, username, avatar_url, avatar_emoji, theme_color, ghost_mode').filter('id', 'in', friendIds);
    final profileMap = {for (var p in profiles) p['id']: p};

    final locations = await client.from('user_locations').select().filter('user_id', 'in', friendIds);
    final locationMap = {for (var l in locations) l['user_id']: l};

    List<Map<String, dynamic>> result = [];
    for (var id in friendIds) {
      final profile = profileMap[id];
      if (profile == null) continue;

      final loc = locationMap[id];
      final bool isFriendGhost = profile['ghost_mode'] ?? false;

      final bool showDetails = !amIGhost && !isFriendGhost;

      dynamic updatedAt = (loc != null) ? loc['updated_at'] : null;
      dynamic lat, lng, currentLine;

      if (showDetails && loc != null) {
        lat = loc['latitude'];
        lng = loc['longitude'];
        currentLine = loc['current_line'];
      }

      result.add({
        'id': id,
        'username': profile['username'] ?? 'Unknown',
        'avatar_url': profile['avatar_url'],
        'avatar_emoji': profile['avatar_emoji'],
        'theme_color': profile['theme_color'],
        'ghost_mode': isFriendGhost,
        'updated_at': updatedAt, 
        'latitude': lat,
        'longitude': lng,
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

  static Future<void> removeFriend(String friendId) async {
    final user = currentUser;
    if (user == null) return;
    await client.from('friends').delete().match({'user_id': user.id, 'friend_id': friendId});
    await client.from('friends').delete().match({'user_id': friendId, 'friend_id': user.id});
    friendsListRefresh.value++;
  }

  // --- LOCATION ---
  static Future<void> updateLocation(Position pos, {String? currentLine}) async {
    final user = currentUser;
    if (user == null) return;
    
    // Check actual DB profile or use client-side logic? 
    // Best to read from DB once or pass state. 
    // For now we do a quick check. Ideally passed from UI.
    final profile = await getCurrentProfile();
    final bool isGhost = profile != null && profile['ghost_mode'] == true;
    
    final Map<String, dynamic> updateData = {
      'user_id': user.id,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    
    if (isGhost) {
      updateData['latitude'] = null;
      updateData['longitude'] = null;
      updateData['current_line'] = null; 
    } else {
      updateData['latitude'] = pos.latitude;
      updateData['longitude'] = pos.longitude;
      if (currentLine != null) {
        updateData['current_line'] = currentLine;
      }
    }

    await client.from('user_locations').upsert(updateData);
  }
  
  static Future<void> clearJourneyStatus() async {
    final user = currentUser;
    if (user == null) return;
    await client.from('user_locations').upsert({
      'user_id': user.id,
      'current_line': null 
    });
  }

  // --- CHAT ---
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
    final storedContent = "${iv.base64}:${encrypted.base64}";

    await client.from('messages').insert({
      'line_id': null, 
      'user_id': user.id, 
      'receiver_id': targetUserId,
      'content': storedContent,
      'is_encrypted': true
    });
  }

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
    await client.from('friends').delete().match({'user_id': user.id, 'friend_id': userId});
    await client.from('friends').delete().match({'user_id': userId, 'friend_id': user.id});
  }
  static Future<void> unblockUser(String userId) async {
    final user = currentUser;
    if (user == null) return;
    await client.from('user_blocks').delete().match({'blocker_id': user.id, 'blocked_id': userId});
  }
}