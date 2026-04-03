import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trans/services/supabase_service.dart';

void main() {
  group('otpTypeFromString', () {
    test('maps signup callback type', () {
      expect(SupabaseService.otpTypeFromString('signup'), OtpType.signup);
    });

    test('maps email_change callback type', () {
      expect(
        SupabaseService.otpTypeFromString('email_change'),
        OtpType.emailChange,
      );
    });

    test('returns null for unknown callback type', () {
      expect(SupabaseService.otpTypeFromString('unknown'), isNull);
    });
  });
}
