import 'package:flutter_test/flutter_test.dart';
import 'package:trans/screens/tabs/settings_tab.dart';

void main() {
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
