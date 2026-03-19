import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static String get supabaseUrl {
    // 1. Try finding it in .env (Local Dev)
    final url = dotenv.env['SUPABASE_URL'];
    if (url != null && url.isNotEmpty) {
      return url;
    }
    // 2. Fallback
    print("WARNING: SUPABASE_URL is missing from .env");
    return '';
  }

  static String get supabaseAnonKey {
    final key = dotenv.env['SUPABASE_ANON_KEY'];
    if (key != null && key.isNotEmpty) {
      return key;
    }
    print("WARNING: SUPABASE_ANON_KEY is missing from .env");
    return '';
  }
}
