import 'package:flutter_test/flutter_test.dart';
import 'package:trans/screens/tabs/routes_tab.dart';

void main() {
  test('formats ride line with numeric platform', () {
    final formatted = formatRideLineWithPlatform('RB21', '6');
    expect(formatted, 'RB21 (Pl. 6)');
  });

  test('does not duplicate platform suffix when already present', () {
    final formatted = formatRideLineWithPlatform('RB21 (Pl. 6)', '6');
    expect(formatted, 'RB21 (Pl. 6)');
  });

  test('does not duplicate platform suffix when Gl. suffix already present', () {
    final formatted = formatRideLineWithPlatform('RE 50 (Gl. 2)', '2');
    expect(formatted, 'RE 50 (Gl. 2)');
  });

  test('formats display line with fallback arrival platform', () {
    final formatted = formatRideDisplayLine(
      line: 'RE29',
      platform: null,
      arrivalPlatform: '9',
      tripId: null,
      showTrainNumbers: false,
    );
    expect(formatted, 'RE29 (Pl. 9)');
  });

  test('hides train number in parentheses but keeps platform', () {
    final formatted = formatRideDisplayLine(
      line: 'RE54 (4616)',
      platform: '2',
      arrivalPlatform: null,
      tripId: '4616',
      showTrainNumbers: false,
    );
    expect(formatted, 'RE54 (Pl. 2)');
  });

  test('long press logic shows delete for started routes', () {
    final shouldShow = savedJourneyLongPressShowsDelete(
      isCompleted: false,
      isLegacy: false,
      hasStarted: true,
    );
    expect(shouldShow, isTrue);
  });
}
