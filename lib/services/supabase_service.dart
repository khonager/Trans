import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  static StreamSubscription? _friendReqSubscription;
  static StreamSubscription? _msgSubscription;

  // --- INITIALIZATION ---
  static Future<void> init() async {
    await NotificationManager.init();
    _startMessageListener();
    _startFriendRequestListener();
  }

  static void _startMessageListener() {
    final user = currentUser;
    if (user == null) return;

    _msgSubscription?.cancel();
    _msgSubscription = client
        .from('messages')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(5)
        .listen((List<Map<String, dynamic>> data) {
          for (final msg in data) {
            if (msg['receiver_id'] != user.id) continue;
            final created = DateTime.parse(msg['created_at']);
            // Only notify for messages received in the last 30 seconds (prevent old msg spam on restart)
            if (DateTime.now().toUtc().difference(created).inSeconds < 30) {
              // Simple dedupe by ID hash or just rely on OS to update if ID is same
              // If we really want to avoid re-notifying for the same message we've already shown in this session,
              // we could keep a Set<String> _notifiedMessageIds.
              // For now, the time check is a crude but effective filter for "live" updates.

              String body = 'You received a secure message.';
              // If it's NOT encrypted, show content. If it IS, keeping it generic is safer/easier unless we decrypt here.
              // Decryption requires keys which depends on sender.
              if (msg['is_encrypted'] == false) {
                body = msg['content'];
              }

              NotificationManager.showNotification(
                id: msg['id'].hashCode,
                title: 'New Private Message',
                body: body,
                channelId: 'private_messages',
                channelName: 'Private Messages',
              );
            }
          }
        });
  }

  static void _startFriendRequestListener() {
    final user = currentUser;
    if (user == null) return;

    _friendReqSubscription?.cancel();
    _friendReqSubscription = client
        .from('friend_requests')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(5)
        .listen((List<Map<String, dynamic>> data) {
          for (final req in data) {
            if (req['receiver_id'] != user.id || req['status'] != 'pending') {
              continue;
            }

            final created = DateTime.parse(req['created_at']);
            if (DateTime.now().toUtc().difference(created).inSeconds < 30) {
              NotificationManager.showNotification(
                id: req['id'].hashCode,
                title: 'New Friend Request',
                body: 'Someone wants to be your friend!',
                channelId: 'friend_requests',
                channelName: 'Friend Requests',
              );
            }
          }
        });
  }

  // --- AUTH ---
  static Future<bool> signUp(
      String email, String password, String username) async {
    String? redirectUrl = kIsWeb ? null : 'io.supabase.trans://login-callback';
    final response = await client.auth.signUp(
      email: email,
      password: password,
      data: {'username': username},
      emailRedirectTo: redirectUrl,
    );
    final user = response.user;
    final bool likelyExistingAccount =
        user != null && (user.identities?.isEmpty ?? false);
    if (likelyExistingAccount) {
      return false;
    }

    if (user != null) {
      // In some Supabase setups (email confirmation required), signup does not
      // immediately establish a writable authenticated session. Attempting a
      // profile upsert then can fail with RLS 42501.
      if (currentUser?.id == user.id) {
        await _ensureProfileRow(user.id, username: username);
      } else {
        debugPrint(
            'Skipping profile upsert after sign up (no active session yet).');
      }
    }

    if (currentUser != null) {
      _startMessageListener();
      _startFriendRequestListener();
    }
    return true;
  }

  static Future<void> signIn(String email, String password) async {
    await client.auth.signInWithPassword(email: email, password: password);
    final user = currentUser;
    if (user != null) {
      final username = user.userMetadata?['username']?.toString();
      await _ensureProfileRow(user.id, username: username);
    }
    _startMessageListener();
    _startFriendRequestListener();
    await loadAndSyncSettings();
  }

  static Future<void> _ensureProfileRow(String userId,
      {String? username}) async {
    try {
      await client.from('profiles').upsert({
        'id': userId,
        if (username != null && username.isNotEmpty) 'username': username,
      });
    } catch (e) {
      debugPrint('Profile upsert skipped/failed: $e');
    }
  }

  static Future<void> signOut() async {
    _msgSubscription?.cancel();
    _friendReqSubscription?.cancel();
    await client.auth.signOut();
  }

  static Future<void> updatePassword(String newPassword) async {
    await client.auth.updateUser(UserAttributes(password: newPassword));
  }

  static Future<void> updateUsername(String newUsername) async {
    final user = currentUser;
    if (user == null) return;
    await client.auth
        .updateUser(UserAttributes(data: {'username': newUsername}));
    await client
        .from('profiles')
        .update({'username': newUsername}).eq('id', user.id);
  }

  static Future<void> updateEmail(String newEmail) async {
    // This will trigger a confirmation email to both old and new email addresses
    // depending on Supabase project settings.
    await client.auth.updateUser(UserAttributes(email: newEmail));
  }

  static Future<void> reauthenticate(String password) async {
    final user = currentUser;
    if (user == null || user.email == null) throw "No user logged in";
    await client.auth
        .signInWithPassword(email: user.email!, password: password);
  }

  static Future<void> deleteAccount() async {
    final user = currentUser;
    if (user == null) return;

    // Call the RPC function to delete the user
    // This requires a postgres function 'delete_account' to be defined in Supabase
    await client.rpc('delete_account');

    // Sign out to clear local session
    await signOut();
  }

  static Future<void> resetPassword(String email) async {
    // configured Site URL (which should be https://khonager.github.io/Trans).
    // This allows the link to work on devices without the app (opens web app),
    // and devices with the app can intercept it via Universal Links / App Links.
    const redirectUrl = 'https://khonager.github.io/Trans/';
    await client.auth.resetPasswordForEmail(email, redirectTo: redirectUrl);
  }

  static Future<void> updateThemeColor(int colorValue) async {
    final user = currentUser;
    if (user == null) return;
    await client
        .from('profiles')
        .update({'theme_color': colorValue}).eq('id', user.id);
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
      final res = await client
          .from('profiles')
          .select('settings')
          .eq('id', user.id)
          .single();
      final currentSettings = res['settings'] ?? {};
      final updatedSettings = Map<String, dynamic>.from(currentSettings)
        ..addAll(newSettings);

      await client
          .from('profiles')
          .update({'settings': updatedSettings}).eq('id', user.id);
    } catch (e) {
      debugPrint("Error updating settings: $e");
    }
  }

  static Future<void> updateFavoritesInfo(
      List<Map<String, dynamic>> favorites) async {
    final user = currentUser;
    if (user == null) return;
    await client
        .from('profiles')
        .update({'favorites': favorites}).eq('id', user.id);
  }

  static Future<void> updatePreviousSearches(List<dynamic> searches) async {
    await updateSettings({'previous_searches': searches});
  }

  static Future<void> updateFrequentJourneys(List<dynamic> journeys) async {
    await updateSettings({'frequent_journeys': journeys});
  }

  static Future<void> updateRecentJourneys(List<dynamic> journeys) async {
    await updateSettings({'recent_journeys': journeys});
  }

  static Future<void> updateSavedJourneys(List<dynamic> journeys) async {
    await updateSettings({'saved_journeys': journeys});
  }

  static Future<void> loadAndSyncSettings() async {
    final user = currentUser;
    if (user == null) return;

    try {
      final data = await client
          .from('profiles')
          .select('settings, favorites')
          .eq('id', user.id)
          .single();
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
        await prefs.setString(
            'vibration_pattern', settings['vibration_pattern']);
      }
      if (settings.containsKey('vibration_intensity')) {
        await prefs.setInt(
            'vibration_intensity', settings['vibration_intensity']);
      }
      if (settings.containsKey('alarm_stops_before')) {
        await prefs.setInt(
            'alarm_stops_before', settings['alarm_stops_before']);
      }
      if (settings.containsKey('previous_searches')) {
        final List<String> list = (settings['previous_searches'] as List)
            .map((e) => json.encode(e))
            .toList()
            .cast<String>();
        await prefs.setStringList('recent_stations', list);
      }
      if (settings.containsKey('frequent_journeys')) {
        final List<String> list = (settings['frequent_journeys'] as List)
            .map((e) => json.encode(e))
            .toList()
            .cast<String>();
        await prefs.setStringList('frequent_journeys', list);
      }
      if (settings.containsKey('recent_journeys')) {
        final List<String> list = (settings['recent_journeys'] as List)
            .map((e) => json.encode(e))
            .toList()
            .cast<String>();
        await prefs.setStringList('recent_journeys', list);
      }
      if (settings.containsKey('saved_journeys')) {
        final List<String> list = (settings['saved_journeys'] as List)
            .map((e) => json.encode(e))
            .toList()
            .cast<String>();
        await prefs.setStringList('saved_journeys', list);
      }
      if (settings.containsKey('locale_code')) {
        await prefs.setString('locale_code', settings['locale_code']);
      }

      if (favorites.isNotEmpty) {
        final List<String> favs =
            favorites.map((f) => json.encode(f)).toList().cast<String>();
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

    await client
        .from('profiles')
        .update({'ghost_mode': enable}).eq('id', user.id);

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
    await client
        .from('profiles')
        .update({'avatar_emoji': emoji, 'avatar_url': null}).eq('id', user.id);
  }

  // --- FRIENDS SYSTEM ---
  static Future<List<Map<String, dynamic>>> getPendingRequests() async {
    final user = currentUser;
    if (user == null) return [];

    final data = await client
        .from('friend_requests')
        .select()
        .eq('receiver_id', user.id)
        .eq('status', 'pending');

    if (data.isEmpty) return [];

    final senderIds = (data as List).map((r) => r['sender_id']).toList();
    final profiles = await client
        .from('profiles')
        .select('id, username, avatar_url, avatar_emoji, theme_color')
        .filter('id', 'in', senderIds);
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
    return client
        .from('friend_requests')
        .stream(primaryKey: ['id'])
        .eq('receiver_id', user.id)
        .asyncMap((_) => getPendingRequests());
  }

  static Future<List<Map<String, dynamic>>> getFriends() async {
    final user = currentUser;
    if (user == null) return [];

    final myProfile = await client
        .from('profiles')
        .select('ghost_mode')
        .eq('id', user.id)
        .single();
    final bool amIGhost = myProfile['ghost_mode'] ?? false;

    dynamic friendsRelation;
    try {
      friendsRelation = await client
          .from('friends')
          .select(
              'user_id, friend_id, auto_added, is_auto_added, added_automatically')
          .or('user_id.eq.${user.id},friend_id.eq.${user.id}');
    } catch (e) {
      debugPrint(
          'friends table auto-added fields unavailable, falling back to full select: $e');
      friendsRelation = await client
          .from('friends')
          .select()
          .or('user_id.eq.${user.id},friend_id.eq.${user.id}');
    }
    if (friendsRelation.isEmpty) return [];

    final List<Map<String, dynamic>> friendRelations =
        List<Map<String, dynamic>>.from(friendsRelation);
    final autoAddedMap =
        friendAutoAddedMapForUser(user.id, friendRelations: friendRelations);
    final friendIds = autoAddedMap.keys.toList();
    if (friendIds.isEmpty) return [];

    final profiles = await client
        .from('profiles')
        .select(
            'id, username, avatar_url, avatar_emoji, theme_color, ghost_mode, created_at')
        .filter('id', 'in', friendIds);
    final profileMap = {for (var p in profiles) p['id']: p};

    final locations = await client
        .from('user_locations')
        .select()
        .filter('user_id', 'in', friendIds);
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
        'created_at': profile['created_at'],
        'is_auto_added': autoAddedMap[id] == true,
        'updated_at': updatedAt,
        'latitude': lat,
        'longitude': lng,
        'current_line': currentLine,
      });
    }
    return result;
  }

  static bool _isAutoAddedFriendRelation(Map<String, dynamic> relation) {
    const autoAddedKeys = [
      'auto_added',
      'is_auto_added',
      'added_automatically',
    ];
    for (final key in autoAddedKeys) {
      if (relation[key] == true) return true;
    }
    return false;
  }

  @visibleForTesting
  static Map<dynamic, bool> friendAutoAddedMapForUser(
    String userId, {
    required List<Map<String, dynamic>> friendRelations,
  }) {
    final autoAddedMap = <dynamic, bool>{};
    for (final relation in friendRelations) {
      final relationUserId = relation['user_id'];
      final relationFriendId = relation['friend_id'];

      dynamic friendId;
      if (relationUserId == userId) {
        friendId = relationFriendId;
      } else if (relationFriendId == userId) {
        friendId = relationUserId;
      } else if (relationUserId == null &&
          relationFriendId != null &&
          relationFriendId != userId) {
        // Legacy/incomplete rows that only carry friend_id for this user.
        friendId = relationFriendId;
      } else {
        continue;
      }

      if (friendId == null || friendId == userId) continue;
      final isAutoAdded = _isAutoAddedFriendRelation(relation);
      // Merge duplicate directional rows conservatively: if either side marks a
      // friendship as auto-added, keep that signal for the combined friend entry.
      autoAddedMap[friendId] = (autoAddedMap[friendId] ?? false) || isAutoAdded;
    }
    return autoAddedMap;
  }

  static Stream<List<Map<String, dynamic>>> streamFriends() {
    final user = currentUser;
    if (user == null) return const Stream.empty();

    late StreamController<List<Map<String, dynamic>>> controller;
    StreamSubscription? sub1;
    StreamSubscription? sub2;
    StreamSubscription? sub3;

    controller = StreamController<List<Map<String, dynamic>>>(
      onListen: () {
        Future<void>? inFlightRefresh;
        Future<void> update([dynamic _]) async {
          if (inFlightRefresh != null) return inFlightRefresh;
          inFlightRefresh = () async {
            try {
              final friends = await getFriends();
              if (!controller.isClosed) controller.add(friends);
            } catch (e) {
              debugPrint("Error streaming friends: $e");
            } finally {
              inFlightRefresh = null;
            }
          }();
          return inFlightRefresh;
        }

        // 1. Listen for location updates
        sub1 = client
            .from('user_locations')
            .stream(primaryKey: ['user_id']).listen(update);

        // 2. Listen for friend list changes (add/remove)
        // Assuming primary key is composite (user_id, friend_id)
        sub2 = client
            .from('friends')
            .stream(primaryKey: ['user_id', 'friend_id'])
            .eq('user_id', user.id)
            .listen(update);
        sub3 = client
            .from('friends')
            .stream(primaryKey: ['user_id', 'friend_id'])
            .eq('friend_id', user.id)
            .listen(update);

        // Initial fetch
        update();
      },
      onCancel: () async {
        await sub1?.cancel();
        await sub2?.cancel();
        await sub3?.cancel();
      },
    );

    return controller.stream;
  }

  static Future<void> sendFriendRequest(String targetUserId) async {
    final user = currentUser;
    if (user == null) throw "Not logged in";
    if (user.id == targetUserId) throw "You cannot add yourself";

    final checkFriend = await client
        .from('friends')
        .select()
        .match({'user_id': user.id, 'friend_id': targetUserId}).maybeSingle();
    if (checkFriend != null) throw "Already friends!";

    final checkReq = await client
        .from('friend_requests')
        .select()
        .or('and(sender_id.eq.${user.id},receiver_id.eq.$targetUserId),and(sender_id.eq.$targetUserId,receiver_id.eq.${user.id})')
        .maybeSingle();

    if (checkReq != null) {
      if (checkReq['status'] == 'pending') {
        throw "Request already pending!";
      } else {
        // Old request exists (accepted/rejected/etc), clear it to allow new request
        await client.from('friend_requests').delete().eq('id', checkReq['id']);
      }
    }

    await client.from('friend_requests').insert({
      'sender_id': user.id,
      'receiver_id': targetUserId,
      'status': 'pending'
    });
  }

  static Future<void> acceptFriendRequest(String senderId) async {
    await client
        .rpc('accept_friend_request', params: {'request_sender_id': senderId});
    friendsListRefresh.value++;
  }

  static Future<void> rejectFriendRequest(String senderId) async {
    final user = currentUser;
    if (user == null) return;
    await client
        .from('friend_requests')
        .delete()
        .match({'sender_id': senderId, 'receiver_id': user.id});
  }

  static Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    if (query.length < 3) return [];
    try {
      final response = await client
          .from('profiles')
          .select()
          .ilike('username', '%$query%')
          .limit(10);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  static Future<void> removeFriend(String friendId) async {
    final user = currentUser;
    if (user == null) return;
    try {
      await client.rpc('remove_friend', params: {'target_friend_id': friendId});
      friendsListRefresh.value++;
    } catch (e) {
      debugPrint("Error removing friend: $e");
    }
  }

  // --- LOCATION ---
  static Future<void> updateLocation(Position pos,
      {String? currentLine}) async {
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
      // In Ghost Mode, we do not update location at all.
      // The toggleGhostMode function already cleared the location once.
      // Continuing to push 'null' violates NOT NULL constraints if the columns are set that way.
      // If we simply want to stop tracking, we just return here.
      return;
    } else {
      updateData['latitude'] = pos.latitude;
      updateData['longitude'] = pos.longitude;
      updateData['current_line'] = currentLine; // Simplify assignment
    }

    await client.from('user_locations').upsert(updateData);
  }

  static Future<Map<String, dynamic>?> getMyLocation() async {
    final user = currentUser;
    if (user == null) return null;
    return await client
        .from('user_locations')
        .select()
        .eq('user_id', user.id)
        .maybeSingle();
  }

  static Stream<Map<String, dynamic>?> streamMyLocation() {
    final user = currentUser;
    if (user == null) return const Stream.empty();
    return client
        .from('user_locations')
        .stream(primaryKey: ['user_id'])
        .eq('user_id', user.id)
        .map((data) => data.isNotEmpty ? data.first : null);
  }

  static Future<void> clearJourneyStatus() async {
    final user = currentUser;
    if (user == null) return;
    await client
        .from('user_locations')
        .upsert({'user_id': user.id, 'current_line': null});
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
    return client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('line_id', lineId)
        .order('created_at', ascending: true)
        .limit(50)
        .asyncMap(_enrichMessages);
  }

  static Stream<List<Map<String, dynamic>>> getPrivateMessages(
      String otherUserId) {
    final myId = currentUser!.id;
    return client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('is_encrypted', true)
        .order('created_at', ascending: true)
        .limit(50)
        .asyncMap((rawMessages) async {
          final filtered = rawMessages.where((m) {
            final uid = m['user_id'];
            final rid = m['receiver_id'];
            return (uid == myId && rid == otherUserId) ||
                (uid == otherUserId && rid == myId);
          }).toList();

          return _enrichMessages(filtered, decryptForUser: otherUserId);
        });
  }

  static Future<List<Map<String, dynamic>>> _enrichMessages(
      List<Map<String, dynamic>> messages,
      {String? decryptForUser}) async {
    if (messages.isEmpty) return [];

    final userIds =
        messages.map((m) => m['user_id'] as String).toSet().toList();
    final profiles = await client
        .from('profiles')
        .select('id, username, avatar_url, avatar_emoji, theme_color')
        .filter('id', 'in', userIds);
    final profileMap = {for (var p in profiles) p['id']: p};

    final keyString =
        decryptForUser != null ? _getPrivateKey(decryptForUser) : null;
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

  static Future<void> sendPrivateMessage(
      String targetUserId, String content) async {
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
    final data = await client
        .from('profiles')
        .select('ticket_url')
        .eq('id', user.id)
        .maybeSingle();
    return data?['ticket_url'] as String?;
  }

  static Future<String?> uploadTicketBytes(
      Uint8List bytes, String fileExt) async {
    final user = currentUser;
    if (user == null) return null;
    final fileName =
        '${user.id}/ticket_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
    await client.storage.from('tickets').uploadBinary(fileName, bytes);
    final imageUrl = client.storage.from('tickets').getPublicUrl(fileName);
    await client
        .from('profiles')
        .update({'ticket_url': imageUrl}).eq('id', user.id);
    return imageUrl;
  }

  static Future<String?> uploadTicket(File imageFile) async {
    final user = currentUser;
    if (user == null) return null;
    final fileExt = imageFile.path.split('.').last;
    final fileName =
        '${user.id}/ticket_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
    await client.storage.from('tickets').upload(fileName, imageFile);
    final imageUrl = client.storage.from('tickets').getPublicUrl(fileName);
    await client
        .from('profiles')
        .update({'ticket_url': imageUrl}).eq('id', user.id);
    return imageUrl;
  }

  static Future<List<Map<String, dynamic>>> getBlockedUsers() async {
    final user = currentUser;
    if (user == null) return [];
    final response = await client
        .from('user_blocks')
        .select('blocked_id')
        .eq('blocker_id', user.id);
    final List blockedIds =
        (response as List).map((e) => e['blocked_id']).toList();
    if (blockedIds.isEmpty) return [];
    final profiles =
        await client.from('profiles').select().filter('id', 'in', blockedIds);
    return List<Map<String, dynamic>>.from(profiles);
  }

  static Future<void> blockUser(String userId) async {
    final user = currentUser;
    if (user == null) return;
    await client
        .from('user_blocks')
        .insert({'blocker_id': user.id, 'blocked_id': userId});
    await client
        .from('friends')
        .delete()
        .match({'user_id': user.id, 'friend_id': userId});
    await client
        .from('friends')
        .delete()
        .match({'user_id': userId, 'friend_id': user.id});
  }

  static Future<void> unblockUser(String userId) async {
    final user = currentUser;
    if (user == null) return;
    await client
        .from('user_blocks')
        .delete()
        .match({'blocker_id': user.id, 'blocked_id': userId});
  }
}
