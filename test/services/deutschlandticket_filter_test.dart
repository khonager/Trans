import 'package:flutter_test/flutter_test.dart';
import 'package:trans/services/transport_api.dart';

void main() {
  group('TransportApi Deutschlandticket leg filtering', () {
    test('flags ICE line names as non-Deutschlandticket', () {
      final leg = {
        'line': {
          'name': 'ICE 9590',
          'product': 'regional',
          'productName': 'ICE',
        },
      };

      expect(TransportApi.isNonDeutschlandticketLegForTesting(leg), isTrue);
    });

    test('flags IC-like aliases in line names as non-Deutschlandticket', () {
      final leg = {
        'line': {
          'name': '651A',
          'product': 'regional',
          'productName': 'IC',
        },
      };

      expect(TransportApi.isNonDeutschlandticketLegForTesting(leg), isTrue);
    });

    test('keeps regional services in Deutschlandticket mode', () {
      final leg = {
        'line': {
          'name': 'RE 1',
          'product': 'regional',
          'productName': 'RE',
        },
      };

      expect(TransportApi.isNonDeutschlandticketLegForTesting(leg), isFalse);
    });
  });
}
