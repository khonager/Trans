import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

class AppConfig {
  static const bool isDevBuild =
      bool.fromEnvironment('IS_DEV', defaultValue: false);
  static const String authConfirmPath = '/auth/confirm';

  static String get webBaseUrl => isDevBuild
      ? 'https://trans.khonager.de/dev/'
      : 'https://trans.khonager.de/';

  static String get authRedirectBaseUrl => webBaseUrl;

  static String get supabaseUrl {
    // 1. Try finding it in .env (Local Dev)
    final url = dotenv.env['SUPABASE_URL'];
    if (url != null && url.isNotEmpty) {
      return url;
    }
    // 2. Fallback
    debugPrint("WARNING: SUPABASE_URL is missing from .env");
    return '';
  }

  static String get supabaseAnonKey {
    final key = dotenv.env['SUPABASE_ANON_KEY'];
    if (key != null && key.isNotEmpty) {
      return key;
    }
    debugPrint("WARNING: SUPABASE_ANON_KEY is missing from .env");
    return '';
  }

  static String get supportEmail {
    final email = dotenv.env['SUPPORT_EMAIL'];
    if (email != null && email.isNotEmpty) {
      return email;
    }
    return 'support@khonager.de';
  }
}
