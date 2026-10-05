import 'package:flutter_test/flutter_test.dart';
import 'package:trans/services/ticket_replacement_reminder.dart';

void main() {
  test('schedules for the first of the following calendar month', () {
    expect(
      TicketReplacementReminder.nextReminderDate(DateTime(2026, 1, 31, 23)),
      DateTime(2026, 2, 1, 9),
    );
    expect(
      TicketReplacementReminder.nextReminderDate(DateTime(2026, 12, 1)),
      DateTime(2027, 1, 1, 9),
    );
  });
}
