import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  group('signed-out local state', () {
    test('clears account data but preserves guest-safe device data', () async {
      SharedPreferences.setMockInitialValues({
        'saved_favorites': <String>['favorite'],
        'saved_journeys': <String>['journey'],
        'locale_code': 'de',
        'privacy_level': 6,
        'saved_ticket_base64': 'ticket',
        'current_tab_index': 2,
        'enabled_api_sources': <String>['transitous'],
      });

      await SupabaseService.prepareSignedOutState();
      final prefs = await SharedPreferences.getInstance();

      expect(prefs.containsKey('saved_favorites'), isFalse);
      expect(prefs.containsKey('saved_journeys'), isFalse);
      expect(prefs.containsKey('locale_code'), isFalse);
      expect(prefs.containsKey('privacy_level'), isFalse);
      expect(prefs.getString('saved_ticket_base64'), 'ticket');
      expect(prefs.getInt('current_tab_index'), 2);
      expect(
        prefs.getStringList('enabled_api_sources'),
        <String>['transitous'],
      );
    });
  });
}
