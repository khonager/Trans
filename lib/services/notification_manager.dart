import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'wake_alarm_settings.dart';
import 'wake_alarm_preview_player.dart';
import 'wake_alarm_sound_storage.dart';

class NotificationManager {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static const MethodChannel _timezoneChannel =
      MethodChannel('de.khonager.trans/device_timezone');
  static bool _timezonesInitialized = false;

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
    await _configureLocalTimezone();
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

  static Future<void> _configureLocalTimezone() async {
    if (_timezonesInitialized) return;

    tz_data.initializeTimeZones();
    try {
      final timezoneName = await _timezoneChannel.invokeMethod<String>('get');
      if (timezoneName != null && timezoneName.isNotEmpty) {
        tz.setLocalLocation(tz.getLocation(timezoneName));
      }
    } catch (error) {
      debugPrint('Falling back to UTC timezone for notifications: $error');
    }
    _timezonesInitialized = true;
  }

  static Future<tz.TZDateTime> zonedDateTimeFromLocal(DateTime dateTime) async {
    await _configureLocalTimezone();
    return tz.TZDateTime.from(dateTime, tz.local);
  }

  static Future<void> requestExactAlarmPermissionIfNeeded() async {
    final androidImplementation =
        _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation == null) return;
    try {
      await androidImplementation.requestExactAlarmsPermission();
    } catch (error) {
      debugPrint('Exact alarm permission request failed: $error');
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
    bool soundEnabled = true,
    bool vibrationEnabled = true,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final androidImplementation =
        _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation == null) return;
    final sound = WakeAlarmSettings.soundForId(soundId);
    final playSound = soundEnabled && sound.playSound;
    await androidImplementation.deleteNotificationChannel(
        channelId: 'wake_alarm_channel');
    await androidImplementation
        .createNotificationChannel(AndroidNotificationChannel(
      'wake_alarm_channel',
      'Wake Alarm',
      description: 'Alarms for arriving at station',
      importance: Importance.max,
      playSound: playSound,
      sound: playSound ? sound.androidSound : null,
      enableVibration: vibrationEnabled,
      vibrationPattern:
          vibrationEnabled ? Int64List.fromList(vibrationPattern) : null,
      audioAttributesUsage: AudioAttributesUsage.alarm,
    ));
  }

  static AndroidNotificationDetails buildWakeAlarmAndroidDetails({
    required List<int> vibrationPattern,
    required String soundId,
    bool fullScreenIntent = false,
    bool soundEnabled = true,
    bool vibrationEnabled = true,
  }) {
    final sound = WakeAlarmSettings.soundForId(soundId);
    final playSound = soundEnabled && sound.playSound;
    return AndroidNotificationDetails(
      'wake_alarm_channel',
      'Wake Alarm',
      channelDescription: 'Alarms for arriving at station',
      importance: Importance.max,
      priority: Priority.high,
      playSound: playSound,
      sound: playSound ? sound.androidSound : null,
      enableVibration: vibrationEnabled,
      vibrationPattern:
          vibrationEnabled ? Int64List.fromList(vibrationPattern) : null,
      fullScreenIntent: fullScreenIntent,
      category: AndroidNotificationCategory.alarm,
      audioAttributesUsage: AudioAttributesUsage.alarm,
    );
  }

  static DarwinNotificationDetails buildWakeAlarmIosDetails({
    required String soundId,
    bool soundEnabled = true,
  }) {
    final sound = WakeAlarmSettings.soundForId(soundId);
    return DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: soundEnabled && sound.playSound,
      presentBanner: true,
      presentList: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
      sound: soundEnabled && sound.playSound ? sound.fileName : null,
    );
  }

  static Future<void> updateLeaveAlarmChannel(
    List<int> vibrationPattern, {
    required String soundId,
    bool soundEnabled = true,
    bool vibrationEnabled = true,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final androidImplementation =
        _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation == null) return;
    final sound = WakeAlarmSettings.soundForId(soundId);
    final playSound = soundEnabled && sound.playSound;
    await androidImplementation.deleteNotificationChannel(
        channelId: 'saved_route_leave_channel');
    await androidImplementation
        .createNotificationChannel(AndroidNotificationChannel(
      'saved_route_leave_channel',
      'Saved Route Reminders',
      description: 'Reminders for saved-route departure times',
      importance: Importance.high,
      playSound: playSound,
      sound: playSound ? sound.androidSound : null,
      enableVibration: vibrationEnabled,
      vibrationPattern:
          vibrationEnabled ? Int64List.fromList(vibrationPattern) : null,
      audioAttributesUsage: AudioAttributesUsage.alarm,
    ));
  }

  static AndroidNotificationDetails buildLeaveAlarmAndroidDetails({
    required List<int> vibrationPattern,
    required String soundId,
    bool soundEnabled = true,
    bool vibrationEnabled = true,
  }) {
    final sound = WakeAlarmSettings.soundForId(soundId);
    final playSound = soundEnabled && sound.playSound;
    return AndroidNotificationDetails(
      'saved_route_leave_channel',
      'Saved Route Reminders',
      channelDescription: 'Reminders for saved-route departure times',
      importance: Importance.high,
      priority: Priority.high,
      playSound: playSound,
      sound: playSound ? sound.androidSound : null,
      enableVibration: vibrationEnabled,
      vibrationPattern:
          vibrationEnabled ? Int64List.fromList(vibrationPattern) : null,
    );
  }

  static DarwinNotificationDetails buildLeaveAlarmIosDetails({
    required String soundId,
    bool soundEnabled = true,
  }) {
    final sound = WakeAlarmSettings.soundForId(soundId);
    return DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: soundEnabled && sound.playSound,
      presentBanner: true,
      presentList: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
      sound: soundEnabled && sound.playSound ? sound.fileName : null,
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

  static Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledAt,
    required NotificationDetails details,
    String? payload,
  }) async {
    await _configureLocalTimezone();
    final scheduledDate = await zonedDateTimeFromLocal(scheduledAt);
    await _notifications.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      notificationDetails: details,
      payload: payload,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }
}
