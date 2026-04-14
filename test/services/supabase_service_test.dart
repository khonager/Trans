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

  group('shouldHandleAuthCallbackManually', () {
    test('handles email confirmation token links manually', () {
      expect(
        SupabaseService.shouldHandleAuthCallbackManually(
          Uri.parse(
            'https://trans.khonager.de/auth/confirm?token_hash=abc&type=signup',
          ),
        ),
        isTrue,
      );
    });

    test('does not manually handle oauth pkce code links', () {
      expect(
        SupabaseService.shouldHandleAuthCallbackManually(
          Uri.parse('https://trans.khonager.de/?code=abc'),
        ),
        isFalse,
      );
    });

    test('does not manually handle implicit session fragments', () {
      expect(
        SupabaseService.shouldHandleAuthCallbackManually(
          Uri.parse('https://trans.khonager.de/#access_token=abc'),
        ),
        isFalse,
      );
    });
  });
}
