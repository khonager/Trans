import 'package:flutter_test/flutter_test.dart';
import 'package:trans/utils/journey_extension.dart';

Map<String, dynamic> leg(
        String from, String to, String departure, String arrival) =>
    {
      'origin': {'id': from},
      'destination': {'id': to},
      'departure': departure,
      'arrival': arrival,
      'line': {'name': '$from-$to'},
    };

void main() {
  test('appends legs and keeps every section boundary', () {
    final first = {
      'source': 'motis',
      'duration': 120,
      'transfers': 0,
      'legs': [
        leg('A', 'B', '2026-10-19T09:00:00', '2026-10-19T09:30:00'),
      ],
    };
    final second = {
      'source': 'motis',
      'legs': [
        leg('B', 'C', '2026-10-19T09:45:00', '2026-10-19T10:15:00'),
      ],
    };
    final third = {
      'source': 'motis',
      'legs': [
        leg('C', 'D', '2026-10-19T10:30:00', '2026-10-19T11:00:00'),
      ],
    };

    final combined = appendJourneyData(original: first, onward: second);
    final extended = appendJourneyData(original: combined, onward: third);
    final legs = extended['legs'] as List;

    expect(legs, hasLength(3));
    expect(legs[0][routeExtensionStartKey], isNull);
    expect(legs[1][routeExtensionStartKey], isTrue);
    expect(legs[2][routeExtensionStartKey], isTrue);
    expect(extended['arrival'], '2026-10-19T11:00:00');
    expect(extended.containsKey('duration'), isFalse);
    expect(extended.containsKey('transfers'), isFalse);
    expect(first['legs'], hasLength(1));
    expect(second['legs'], hasLength(1));
    expect((second['legs'] as List).first[routeExtensionStartKey], isNull);
  });
}
