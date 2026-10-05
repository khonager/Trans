import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_manager.dart';

class TicketReplacementReminder {
  static const int notificationId = 9002;

  static DateTime nextReminderDate(DateTime replacementDate) =>
      DateTime(replacementDate.year, replacementDate.month + 1, 1, 9);

  static Future<void> schedule({
    required DateTime replacementDate,
    required String title,
    required String body,
  }) async {
    await NotificationManager.requestPermissions();
    await NotificationManager.scheduleNotification(
      id: notificationId,
      title: title,
      body: body,
      scheduledAt: nextReminderDate(replacementDate),
      details: const NotificationDetails(
        android: AndroidNotificationDetails(
          'ticket_replacement_reminder',
          'Ticket reminders',
          channelDescription: 'Monthly reminders to replace your ticket',
          importance: Importance.defaultImportance,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
}
