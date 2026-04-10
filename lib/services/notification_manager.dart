import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'wake_alarm_settings.dart';
import 'wake_alarm_preview_player.dart';
import 'wake_alarm_sound_storage.dart';

class NotificationManager {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    final linuxSettings = const LinuxInitializationSettings(
        defaultActionName: 'Open notification');
    final initSettings = InitializationSettings(
        android: androidSettings, iOS: iosSettings, linux: linuxSettings);

    await _notifications.initialize(settings: initSettings);
    await _ensureDarwinWakeAlarmSounds();

    // Create Channels (Android)
    final androidImplementation =
        _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation != null) {
      await androidImplementation
          .createNotificationChannel(const AndroidNotificationChannel(
        'private_messages',
        'Private Messages',
        description: 'Notifications for encrypted private chats',
        importance: Importance.max,
      ));
      await androidImplementation
          .createNotificationChannel(const AndroidNotificationChannel(
        'friend_requests',
        'Friend Requests',
        description: 'Notifications for new friend requests',
        importance: Importance.high,
      ));
      await androidImplementation
          .createNotificationChannel(const AndroidNotificationChannel(
        'wake_alarm_channel',
        'Wake Alarm',
        description: 'Alarms for arriving at station',
        importance: Importance.max,
        enableVibration: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ));
    }
  }

  static Future<void> requestPermissions() async {
    final androidImplementation =
        _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation != null) {
      await androidImplementation.requestNotificationsPermission();
    }
    final iosImplementation =
        _notifications.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    if (iosImplementation != null) {
      await iosImplementation.requestPermissions(
          alert: true, badge: true, sound: true);
    }
  }

  /// Recreates the wake_alarm_channel with [vibrationPattern] so that
  /// background notifications use the user's custom vibration.
  /// On Android 8.0+ channel settings are immutable after first creation,
  /// so we delete the old channel and create a fresh one each time the
  /// alarm is started.
  static Future<void> updateWakeAlarmChannel(
    List<int> vibrationPattern, {
    required String soundId,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final androidImplementation =
        _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation == null) return;
    final sound = WakeAlarmSettings.soundForId(soundId);
    await androidImplementation.deleteNotificationChannel(
        channelId: 'wake_alarm_channel');
    await androidImplementation
        .createNotificationChannel(AndroidNotificationChannel(
      'wake_alarm_channel',
      'Wake Alarm',
      description: 'Alarms for arriving at station',
      importance: Importance.max,
      playSound: sound.playSound,
      sound: sound.androidSound,
      enableVibration: true,
      vibrationPattern: Int64List.fromList(vibrationPattern),
      audioAttributesUsage: AudioAttributesUsage.alarm,
    ));
  }

  static AndroidNotificationDetails buildWakeAlarmAndroidDetails({
    required List<int> vibrationPattern,
    required String soundId,
    bool fullScreenIntent = false,
  }) {
    final sound = WakeAlarmSettings.soundForId(soundId);
    return AndroidNotificationDetails(
      'wake_alarm_channel',
      'Wake Alarm',
      channelDescription: 'Alarms for arriving at station',
      importance: Importance.max,
      priority: Priority.high,
      playSound: sound.playSound,
      sound: sound.androidSound,
      enableVibration: true,
      vibrationPattern: Int64List.fromList(vibrationPattern),
      fullScreenIntent: fullScreenIntent,
      category: AndroidNotificationCategory.alarm,
      audioAttributesUsage: AudioAttributesUsage.alarm,
    );
  }

  static DarwinNotificationDetails buildWakeAlarmIosDetails({
    required String soundId,
  }) {
    final sound = WakeAlarmSettings.soundForId(soundId);
    return DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: sound.playSound,
      presentBanner: true,
      presentList: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
      sound: sound.playSound ? sound.fileName : null,
    );
  }

  static Future<void> previewWakeAlarm({
    required String title,
    required String body,
    required String soundId,
    required List<int> vibrationPattern,
  }) async {
    final sound = WakeAlarmSettings.soundForId(soundId);
    if (await WakeAlarmPreviewPlayer.play(sound)) return;
    if (kIsWeb) return;

    await _ensureDarwinWakeAlarmSounds();
    await requestPermissions();
    await updateWakeAlarmChannel(vibrationPattern, soundId: soundId);

    final details = NotificationDetails(
      android: buildWakeAlarmAndroidDetails(
        vibrationPattern: vibrationPattern,
        soundId: soundId,
      ),
      iOS: buildWakeAlarmIosDetails(soundId: soundId),
    );

    await _notifications.show(
      id: 9001,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  static Future<void> _ensureDarwinWakeAlarmSounds() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    await ensureDarwinWakeAlarmSounds(WakeAlarmSettings.bundledSoundOptions);
  }

  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    String channelId = 'private_messages',
    String channelName = 'Private Messages',
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      importance: Importance.max,
      priority: Priority.high,
    );
    final details = NotificationDetails(
        android: androidDetails, iOS: const DarwinNotificationDetails());

    await _notifications.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payload);
  }
}
