import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import 'favorites_policy.dart';
import 'notification_manager.dart';
import 'transport_api.dart';
import 'wake_alarm_settings.dart';
import '../utils/app_error.dart';

class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;
  static User? get currentUser => client.auth.currentUser;

  static final ValueNotifier<int> friendsListRefresh = ValueNotifier(0);
  static final ValueNotifier<int> settingsRefreshNotifier = ValueNotifier(0);
  static StreamSubscription? _friendReqSubscription;
  static StreamSubscription? _msgSubscription;
  static Future<void>? _pendingSignInPreparation;
  static String? _preparedUserId;
  static String? _pendingPortfolioBridgeState;

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
            try {
              if (msg['receiver_id'] != user.id) continue;
              final created = _tryParseTimestamp(
                msg['created_at'],
                source: 'messages.created_at',
              );
              if (created == null) continue;

              // Only notify for messages received in the last 30 seconds (prevent old msg spam on restart)
              if (DateTime.now().toUtc().difference(created).inSeconds < 30) {
                String body = 'You received a secure message.';
                if (msg['is_encrypted'] == false) {
                  body = (msg['content'] ?? body).toString();
                }

                NotificationManager.showNotification(
                  id: msg['id'].hashCode,
                  title: 'New Private Message',
                  body: body,
                  channelId: 'private_messages',
                  channelName: 'Private Messages',
                );
              }
            } catch (e, st) {
              AppError.log(e,
                  stackTrace: st,
                  source: 'SupabaseService._startMessageListener');
            }
          }
        }, onError: (error, stackTrace) {
          AppError.log(
            error,
            stackTrace: stackTrace is StackTrace ? stackTrace : null,
            source: 'SupabaseService._startMessageListener.onError',
          );
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
            try {
              if (req['receiver_id'] != user.id || req['status'] != 'pending') {
                continue;
              }

              final created = _tryParseTimestamp(
                req['created_at'],
                source: 'friend_requests.created_at',
              );
              if (created == null) continue;

              if (DateTime.now().toUtc().difference(created).inSeconds < 30) {
                NotificationManager.showNotification(
                  id: req['id'].hashCode,
                  title: 'New Friend Request',
                  body: 'Someone wants to be your friend!',
                  channelId: 'friend_requests',
                  channelName: 'Friend Requests',
                );
              }
            } catch (e, st) {
              AppError.log(e,
                  stackTrace: st,
                  source: 'SupabaseService._startFriendRequestListener');
            }
          }
        }, onError: (error, stackTrace) {
          AppError.log(
            error,
            stackTrace: stackTrace is StackTrace ? stackTrace : null,
            source: 'SupabaseService._startFriendRequestListener.onError',
          );
        });
  }

  static DateTime? _tryParseTimestamp(
    dynamic raw, {
    required String source,
  }) {
    if (raw == null) {
      AppError.log('Missing timestamp', source: source);
      return null;
    }

    try {
      return DateTime.parse(raw.toString()).toUtc();
    } catch (e, st) {
      AppError.log(e, stackTrace: st, source: source);
      return null;
    }
  }

  @visibleForTesting
  static void triggerFriendsListRefresh() {
    friendsListRefresh.value++;
  }

  @visibleForTesting
  static OtpType? otpTypeFromString(String? value) {
    switch (value) {
      case 'signup':
        return OtpType.signup;
      case 'invite':
        return OtpType.invite;
      case 'magiclink':
        return OtpType.magiclink;
      case 'recovery':
        return OtpType.recovery;
      case 'email':
        return OtpType.email;
      case 'email_change':
      case 'emailChange':
        return OtpType.emailChange;
      case 'phone_change':
      case 'phoneChange':
        return OtpType.phoneChange;
      case 'sms':
        return OtpType.sms;
      default:
        return null;
    }
  }

  static Map<String, String> _fragmentParameters(Uri uri) {
    final fragment = uri.fragment;
    if (fragment.isEmpty) return const {};

    try {
      return Uri.splitQueryString(fragment);
    } catch (_) {
      return const {};
    }
  }

  static String? _uriParameter(Uri uri, String key) {
    final queryValue = uri.queryParameters[key];
    if (queryValue != null && queryValue.isNotEmpty) {
      return queryValue;
    }

    final fragmentValue = _fragmentParameters(uri)[key];
    if (fragmentValue != null && fragmentValue.isNotEmpty) {
      return fragmentValue;
    }

    return null;
  }

  static bool isAuthConfirmUri(Uri uri) {
    final normalizedPath = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    final configuredBasePath = Uri.parse(AppConfig.webBaseUrl).path;
    final normalizedBasePath = configuredBasePath.endsWith('/')
        ? configuredBasePath.substring(0, configuredBasePath.length - 1)
        : configuredBasePath;
    final hasTokenHash = (_uriParameter(uri, 'token_hash') ?? '').isNotEmpty;
    final isRootPath = normalizedPath.isEmpty ||
        normalizedPath == '/' ||
        normalizedPath == normalizedBasePath;
    return hasTokenHash &&
        (normalizedPath.endsWith(AppConfig.authConfirmPath) || isRootPath);
  }

  static bool isAuthSessionUri(Uri uri) {
    final fragmentParameters = _fragmentParameters(uri);
    final hasAccessToken =
        (fragmentParameters['access_token'] ?? '').isNotEmpty;
    final hasAuthCode = (uri.queryParameters['code'] ?? '').isNotEmpty;
    final hasErrorDescription =
        (fragmentParameters['error_description'] ?? '').isNotEmpty;
    return hasAccessToken || hasAuthCode || hasErrorDescription;
  }

  static bool shouldHandleAuthCallbackManually(Uri uri) {
    // supabase_flutter already consumes OAuth/deep-link session callbacks.
    // We only manually handle OTP confirmation links that include token_hash.
    return isAuthConfirmUri(uri);
  }

  static bool isPortfolioBridgeUri(Uri uri) {
    final code = uri.queryParameters['bridge_code'];
    if (code == null || code.isEmpty) return false;

    if (kIsWeb) {
      final base = Uri.parse(AppConfig.webBaseUrl);
      final sameHost = uri.host == base.host;
      return sameHost;
    }

    return uri.scheme == 'io.supabase.trans';
  }

  static String _randomState() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static Future<void> signInWithPortfolio() async {
    final continueUrl = AppConfig.portfolioBridgeContinueUrl;
    if (continueUrl.isEmpty) {
      throw 'Portfolio bridge URL is not configured.';
    }

    final state = _randomState();
    _pendingPortfolioBridgeState = state;

    final uri = Uri.parse(continueUrl).replace(
      queryParameters: {
        'redirect_uri': AppConfig.portfolioBridgeRedirectUrl,
        'state': state,
      },
    );

    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!launched) {
      throw 'Could not open portfolio sign-in page.';
    }
  }

  static Future<void> handlePortfolioBridgeUri(Uri uri) async {
    final code = uri.queryParameters['bridge_code'];
    final state = uri.queryParameters['state'];
    final expectedState = _pendingPortfolioBridgeState;

    if (code == null || code.isEmpty) {
      throw 'Missing bridge code.';
    }

    if (expectedState != null && expectedState.isNotEmpty) {
      if (state == null || state.isEmpty || state != expectedState) {
        throw 'Portfolio bridge state mismatch. Please try again.';
      }
    }

    final endpoint = AppConfig.portfolioBridgeExchangeEndpoint;
    if (endpoint.isEmpty) {
      throw 'Portfolio bridge exchange endpoint is not configured.';
    }

    final response = await http.post(
      Uri.parse(endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: json.encode({
        'code': code,
        'state': state,
      }),
    );

    dynamic payload;
    try {
      payload = response.body.isNotEmpty ? json.decode(response.body) : {};
    } catch (_) {
      payload = <String, dynamic>{'error': response.body};
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw payload is Map<String, dynamic>
          ? (payload['error']?.toString() ??
              'Portfolio bridge exchange failed.')
          : 'Portfolio bridge exchange failed.';
    }

    final refreshToken = payload is Map<String, dynamic>
        ? payload['refreshToken']?.toString()
        : null;

    if (refreshToken == null || refreshToken.isEmpty) {
      throw 'Portfolio bridge did not return a refresh token.';
    }

    await client.auth.setSession(refreshToken);
    _pendingPortfolioBridgeState = null;
    await ensureCurrentUserReady();
  }

  static Future<void> _finishSignIn() async {
    final user = currentUser;
    if (user != null) {
      final username = user.userMetadata?['username']?.toString();
      await _ensureProfileRow(user.id, username: username);
    }
    _startMessageListener();
    _startFriendRequestListener();
    await loadAndSyncSettings();
    triggerFriendsListRefresh();
  }

  static Future<void> ensureCurrentUserReady() async {
    final user = currentUser;
    if (user == null) {
      _preparedUserId = null;
      return;
    }

    if (_preparedUserId == user.id) {
      return;
    }

    final pending = _pendingSignInPreparation;
    if (pending != null) {
      await pending;
      return;
    }

    final preparation = _finishSignIn();
    _pendingSignInPreparation = preparation;

    try {
      await preparation;
      _preparedUserId = user.id;
    } finally {
      if (identical(_pendingSignInPreparation, preparation)) {
        _pendingSignInPreparation = null;
      }
    }
  }

  static Future<OtpType?> handleAuthCallbackUri(Uri uri) async {
    final tokenHash = _uriParameter(uri, 'token_hash');
    final otpType = otpTypeFromString(_uriParameter(uri, 'type'));

    if (!shouldHandleAuthCallbackManually(uri) ||
        tokenHash == null ||
        tokenHash.isEmpty ||
        otpType == null) {
      return otpType;
    }

    await client.auth.verifyOTP(
      tokenHash: tokenHash,
      type: otpType,
    );

    if (currentUser != null) {
      await ensureCurrentUserReady();
    }

    return otpType;
  }

  static Future<bool> handleAuthSessionUri(Uri uri) async {
    if (!isAuthSessionUri(uri)) {
      return false;
    }

    // Give supabase_flutter's built-in deep-link observer a chance to consume
    // the callback first. This fallback covers cases where the app was cold-
    // started from an OAuth redirect and we already consumed the initial link.
    if (!kIsWeb) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (currentUser != null) {
        await ensureCurrentUserReady();
        return true;
      }
    }

    await client.auth.getSessionFromUrl(uri);
    await ensureCurrentUserReady();
    return true;
  }

  // --- AUTH ---
  static Future<bool> signUp(
      String email, String password, String username) async {
    final response = await client.auth.signUp(
      email: email,
      password: password,
      data: {'username': username},
      emailRedirectTo: AppConfig.authRedirectBaseUrl,
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
      await ensureCurrentUserReady();
    }
    return true;
  }

  static Future<void> signIn(String email, String password) async {
    await client.auth.signInWithPassword(email: email, password: password);
    await ensureCurrentUserReady();
  }

  static String _oauthRedirectUrlForCurrentPlatform() {
    if (!kIsWeb &&
        (Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
      return Uri.parse(AppConfig.webBaseUrl)
          .resolve('oauth-callback.html')
          .toString();
    }

    return AppConfig.authOAuthRedirectUrl;
  }

  static Future<void> signInWithGoogle() async {
    final launched = await client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: _oauthRedirectUrlForCurrentPlatform(),
      // Signing out of Supabase does not clear Google's Safari session on iOS,
      // so force the account chooser instead of silently reusing the last one.
      queryParams: const {'prompt': 'select_account'},
      authScreenLaunchMode: !kIsWeb && (Platform.isAndroid || Platform.isIOS)
          ? LaunchMode.externalApplication
          : LaunchMode.platformDefault,
    );

    if (!launched) {
      throw 'Could not start Google sign-in.';
    }
  }

  static Future<void> signInWithApple() async {
    final launched = await client.auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: _oauthRedirectUrlForCurrentPlatform(),
      authScreenLaunchMode: !kIsWeb && (Platform.isAndroid || Platform.isIOS)
          ? LaunchMode.externalApplication
          : LaunchMode.platformDefault,
    );

    if (!launched) {
      throw 'Could not start Apple sign-in.';
    }
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
    _preparedUserId = null;
    _pendingSignInPreparation = null;
    await client.auth.signOut();
    triggerFriendsListRefresh();
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

    // Call the backend RPC defined in supabase/migrations to delete the current
    // auth user plus app-owned rows that reference that user.
    await client.rpc('delete_account');

    // Sign out to clear local session
    await signOut();
  }

  static Future<void> resetPassword(String email) async {
    await client.auth.resetPasswordForEmail(
      email,
      redirectTo: AppConfig.authRedirectBaseUrl,
    );
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
    final sanitizedFavorites = sanitizeFavoritePayloads(favorites);
    await client
        .from('profiles')
        .update({'favorites': sanitizedFavorites}).eq('id', user.id);
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
      final favorites =
          sanitizeFavoritePayloads(data['favorites'] as List<dynamic>? ?? []);

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
      if (settings.containsKey('wake_alarm_sound')) {
        await prefs.setString('wake_alarm_sound', settings['wake_alarm_sound']);
      }
      if (settings
          .containsKey(WakeAlarmSettings.wakeSoundEnabledPreferenceKey)) {
        await prefs.setBool(
          WakeAlarmSettings.wakeSoundEnabledPreferenceKey,
          settings[WakeAlarmSettings.wakeSoundEnabledPreferenceKey],
        );
      }
      if (settings
          .containsKey(WakeAlarmSettings.wakeVibrationEnabledPreferenceKey)) {
        await prefs.setBool(
          WakeAlarmSettings.wakeVibrationEnabledPreferenceKey,
          settings[WakeAlarmSettings.wakeVibrationEnabledPreferenceKey],
        );
      }
      if (settings
          .containsKey(WakeAlarmSettings.leaveSoundEnabledPreferenceKey)) {
        await prefs.setBool(
          WakeAlarmSettings.leaveSoundEnabledPreferenceKey,
          settings[WakeAlarmSettings.leaveSoundEnabledPreferenceKey],
        );
      }
      if (settings
          .containsKey(WakeAlarmSettings.leaveVibrationEnabledPreferenceKey)) {
        await prefs.setBool(
          WakeAlarmSettings.leaveVibrationEnabledPreferenceKey,
          settings[WakeAlarmSettings.leaveVibrationEnabledPreferenceKey],
        );
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
      if (settings
          .containsKey(TransportApi.advancedTransferComfortPreferenceKey)) {
        final raw =
            settings[TransportApi.advancedTransferComfortPreferenceKey];
        if (raw is num) {
          await prefs.setDouble(
            TransportApi.advancedTransferComfortPreferenceKey,
            raw.toDouble(),
          );
        }
      }
      if (settings.containsKey(TransportApi.advancedBikePreferenceKey)) {
        final raw = settings[TransportApi.advancedBikePreferenceKey];
        if (raw is num) {
          await prefs.setDouble(
            TransportApi.advancedBikePreferenceKey,
            raw.toDouble(),
          );
        }
      }
      if (settings
          .containsKey(TransportApi.advancedMinTransferTimeMinutesPreferenceKey)) {
        final raw =
            settings[TransportApi.advancedMinTransferTimeMinutesPreferenceKey];
        if (raw is num) {
          await prefs.setInt(
            TransportApi.advancedMinTransferTimeMinutesPreferenceKey,
            raw.toInt(),
          );
        }
      }
      if (settings.containsKey(
          TransportApi.advancedAdditionalTransferTimeMinutesPreferenceKey)) {
        final raw = settings[
            TransportApi.advancedAdditionalTransferTimeMinutesPreferenceKey];
        if (raw is num) {
          await prefs.setInt(
            TransportApi.advancedAdditionalTransferTimeMinutesPreferenceKey,
            raw.toInt(),
          );
        }
      }
      if (settings
          .containsKey(TransportApi.advancedTransferTimeFactorPreferenceKey)) {
        final raw = settings[TransportApi.advancedTransferTimeFactorPreferenceKey];
        if (raw is num) {
          await prefs.setDouble(
            TransportApi.advancedTransferTimeFactorPreferenceKey,
            raw.toDouble(),
          );
        }
      }
      if (settings
          .containsKey(TransportApi.advancedPreTransitWalkEnabledPreferenceKey)) {
        final raw =
            settings[TransportApi.advancedPreTransitWalkEnabledPreferenceKey];
        if (raw is bool) {
          await prefs.setBool(
            TransportApi.advancedPreTransitWalkEnabledPreferenceKey,
            raw,
          );
        }
      }
      if (settings
          .containsKey(TransportApi.advancedPreTransitBikeEnabledPreferenceKey)) {
        final raw =
            settings[TransportApi.advancedPreTransitBikeEnabledPreferenceKey];
        if (raw is bool) {
          await prefs.setBool(
            TransportApi.advancedPreTransitBikeEnabledPreferenceKey,
            raw,
          );
        }
      }
      if (settings.containsKey(
          TransportApi.advancedPostTransitWalkEnabledPreferenceKey)) {
        final raw =
            settings[TransportApi.advancedPostTransitWalkEnabledPreferenceKey];
        if (raw is bool) {
          await prefs.setBool(
            TransportApi.advancedPostTransitWalkEnabledPreferenceKey,
            raw,
          );
        }
      }
      if (settings.containsKey(
          TransportApi.advancedPostTransitBikeEnabledPreferenceKey)) {
        final raw =
            settings[TransportApi.advancedPostTransitBikeEnabledPreferenceKey];
        if (raw is bool) {
          await prefs.setBool(
            TransportApi.advancedPostTransitBikeEnabledPreferenceKey,
            raw,
          );
        }
      }
      if (settings
          .containsKey(TransportApi.advancedCyclingSpeedKmhPreferenceKey)) {
        final raw = settings[TransportApi.advancedCyclingSpeedKmhPreferenceKey];
        if (raw is num) {
          await prefs.setDouble(
            TransportApi.advancedCyclingSpeedKmhPreferenceKey,
            raw.toDouble(),
          );
        }
      }
      if (settings
          .containsKey(TransportApi.advancedPedestrianSpeedKmhPreferenceKey)) {
        final raw =
            settings[TransportApi.advancedPedestrianSpeedKmhPreferenceKey];
        if (raw is num) {
          await prefs.setDouble(
            TransportApi.advancedPedestrianSpeedKmhPreferenceKey,
            raw.toDouble(),
          );
        }
      }
      if (settings
          .containsKey(TransportApi.advancedMaxWalkingTimeMinutesPreferenceKey)) {
        final raw =
            settings[TransportApi.advancedMaxWalkingTimeMinutesPreferenceKey];
        if (raw is num) {
          await prefs.setInt(
            TransportApi.advancedMaxWalkingTimeMinutesPreferenceKey,
            raw.toInt(),
          );
        }
      }

      final List<String> favs =
          favorites.map((f) => json.encode(f)).toList().cast<String>();
      await prefs.setStringList('saved_favorites', favs);

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

    triggerFriendsListRefresh();
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

    bool amIGhost = false;
    try {
      final myProfile = await client
          .from('profiles')
          .select('ghost_mode')
          .eq('id', user.id)
          .single();
      amIGhost = myProfile['ghost_mode'] == true;
    } catch (e) {
      debugPrint('profiles.ghost_mode unavailable, defaulting to visible: $e');
    }

    // Fetch friend relations bidirectionally.  Try with specific columns first;
    // fall back to a full select if the optional auto-added fields are missing.
    List<Map<String, dynamic>> friendRelations = [];
    try {
      final friendsAsUser = await client
          .from('friends')
          .select(
              'user_id, friend_id, auto_added, is_auto_added, added_automatically')
          .eq('user_id', user.id);
      final friendsAsFriend = await client
          .from('friends')
          .select(
              'user_id, friend_id, auto_added, is_auto_added, added_automatically')
          .eq('friend_id', user.id);
      friendRelations = mergeFriendRelations(
        friendsAsUser: List<Map<String, dynamic>>.from(friendsAsUser),
        friendsAsFriend: List<Map<String, dynamic>>.from(friendsAsFriend),
      );
    } catch (e) {
      debugPrint(
          'friends table auto-added fields unavailable, falling back to full select: $e');
      try {
        final friendsAsUser =
            await client.from('friends').select().eq('user_id', user.id);
        final friendsAsFriend =
            await client.from('friends').select().eq('friend_id', user.id);
        friendRelations = mergeFriendRelations(
          friendsAsUser: List<Map<String, dynamic>>.from(friendsAsUser),
          friendsAsFriend: List<Map<String, dynamic>>.from(friendsAsFriend),
        );
      } catch (e2) {
        debugPrint('friends table fallback select also failed: $e2');
        return [];
      }
    }
    if (friendRelations.isEmpty) return [];

    final autoAddedMap =
        friendAutoAddedMapForUser(user.id, friendRelations: friendRelations);
    final friendIds = autoAddedMap.keys.toList();
    if (friendIds.isEmpty) return [];

    // Fetch friend profiles.  Try with extended fields (ghost_mode, created_at)
    // and fall back gracefully when those columns are absent in older schemas.
    List profileRows = [];
    try {
      profileRows = await client
          .from('profiles')
          .select(
              'id, username, avatar_url, avatar_emoji, theme_color, ghost_mode, created_at')
          .filter('id', 'in', friendIds);
    } catch (e) {
      debugPrint(
          'profiles extended fields unavailable, falling back to basic select: $e');
      try {
        profileRows = await client
            .from('profiles')
            .select('id, username, avatar_url, avatar_emoji, theme_color')
            .filter('id', 'in', friendIds);
      } catch (e2) {
        debugPrint('profiles basic select also failed: $e2');
        return [];
      }
    }
    final profileMap = {for (var p in profileRows) p['id']: p};

    // Fetch friend locations.  Missing or inaccessible table just means no
    // real-time position is shown – friends are still listed.
    List locationRows = [];
    try {
      locationRows = await client
          .from('user_locations')
          .select()
          .filter('user_id', 'in', friendIds);
    } catch (e) {
      debugPrint(
          'user_locations unavailable, friends will show without location: $e');
    }
    final locationMap = {for (var l in locationRows) l['user_id']: l};

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

  @visibleForTesting
  static List<Map<String, dynamic>> mergeFriendRelations({
    required List<Map<String, dynamic>> friendsAsUser,
    required List<Map<String, dynamic>> friendsAsFriend,
  }) {
    final mergedFriends = <Map<String, dynamic>>[
      ...friendsAsUser,
      ...friendsAsFriend,
    ];
    final dedupedByPair = <String, Map<String, Map<String, dynamic>>>{};
    for (final relation in mergedFriends) {
      final a = relation['user_id']?.toString();
      final b = relation['friend_id']?.toString();
      if (a == null || b == null) continue;

      final normalizedPair = [a, b]..sort();
      final pairA = normalizedPair[0];
      final pairB = normalizedPair[1];
      final secondLevel = dedupedByPair.putIfAbsent(pairA, () => {});
      final existing = secondLevel[pairB];
      if (existing == null) {
        secondLevel[pairB] = relation;
        continue;
      }

      final relationAutoAdded = _isAutoAddedFriendRelation(relation);
      final existingAutoAdded = _isAutoAddedFriendRelation(existing);
      final mergedAutoAdded = relationAutoAdded || existingAutoAdded;
      final mergedRelation = <String, dynamic>{...existing};
      if (mergedAutoAdded) {
        mergedRelation['is_auto_added'] = true;
      }
      secondLevel[pairB] = mergedRelation;
    }
    return dedupedByPair.values
        .expand((relations) => relations.values)
        .toList();
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
            .stream(primaryKey: ['user_id']).listen(
          update,
          onError: (e) =>
              debugPrint('user_locations stream error (non-fatal): $e'),
        );

        // 2. Listen for friend list changes (add/remove)
        // Assuming primary key is composite (user_id, friend_id)
        sub2 = client
            .from('friends')
            .stream(primaryKey: ['user_id', 'friend_id'])
            .eq('user_id', user.id)
            .listen(
              update,
              onError: (e) =>
                  debugPrint('friends stream (user_id) error (non-fatal): $e'),
            );
        sub3 = client
            .from('friends')
            .stream(primaryKey: ['user_id', 'friend_id'])
            .eq('friend_id', user.id)
            .listen(
              update,
              onError: (e) => debugPrint(
                  'friends stream (friend_id) error (non-fatal): $e'),
            );

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
    triggerFriendsListRefresh();
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
      triggerFriendsListRefresh();
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
