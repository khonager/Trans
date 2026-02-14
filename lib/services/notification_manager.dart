import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationManager {
  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    final linuxSettings = const LinuxInitializationSettings(defaultActionName: 'Open notification');
    final initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings, linux: linuxSettings);

    await _notifications.initialize(settings: initSettings);

    // Create Channels (Android)
    final androidImplementation = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation != null) {
      await androidImplementation.createNotificationChannel(const AndroidNotificationChannel(
        'private_messages',
        'Private Messages',
        description: 'Notifications for encrypted private chats',
        importance: Importance.max,
      ));
      await androidImplementation.createNotificationChannel(const AndroidNotificationChannel(
        'friend_requests',
        'Friend Requests',
        description: 'Notifications for new friend requests',
        importance: Importance.high,
      ));
      await androidImplementation.createNotificationChannel(const AndroidNotificationChannel(
        'wake_alarm_channel', 
        'Wake Alarm', 
        description: 'Alarms for arriving at station',
        importance: Importance.max,
        enableVibration: true,
      ));
    }
  }

  static Future<void> requestPermissions() async {
    final androidImplementation = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation != null) {
      await androidImplementation.requestNotificationsPermission();
    }
    final iosImplementation = _notifications.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (iosImplementation != null) {
      await iosImplementation.requestPermissions(alert: true, badge: true, sound: true);
    }
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
    final details = NotificationDetails(android: androidDetails, iOS: const DarwinNotificationDetails());

    await _notifications.show(id: id, title: title, body: body, notificationDetails: details, payload: payload);
  }
}