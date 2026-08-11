import 'package:flutter_test/flutter_test.dart';
import 'package:trans/screens/tabs/settings_tab.dart';

void main() {
  group('usesStackedPrivacyLevelLayout', () {
    test('moves the picker below the text on small screens', () {
      expect(usesStackedPrivacyLevelLayout(425), isTrue);
    });

    test('keeps the picker beside the text when there is room', () {
      expect(usesStackedPrivacyLevelLayout(540), isFalse);
    });
  });

  group('deleteAccountErrorMessage', () {
    test('returns invalid password message for auth credential failures', () {
      final message = deleteAccountErrorMessage(
        'AuthException(message: Invalid login credentials)',
        invalidPasswordMessage: 'Incorrect password.',
        fallbackMessage: 'Service temporarily busy. Please try again.',
      );

      expect(message, 'Incorrect password.');
    });

    test('returns fallback message for rpc or backend failures', () {
      final message = deleteAccountErrorMessage(
        'PostgrestException(message: function public.delete_account() does not exist)',
        invalidPasswordMessage: 'Incorrect password.',
        fallbackMessage: 'Service temporarily busy. Please try again.',
      );

      expect(message, 'Service temporarily busy. Please try again.');
    });
  });
}
