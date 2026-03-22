import 'package:flutter_test/flutter_test.dart';
import 'package:trans/screens/tabs/routes_tab.dart';

void main() {
  test('saved route reminder option keeps selected minutes as lead time', () {
    final option = savedJourneyReminderOptionFromWait(5);
    expect(option.waitMinutes, 5);
    expect(option.leadMinutes, 5);
  });

}
