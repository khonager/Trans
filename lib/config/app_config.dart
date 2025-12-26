import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static String get supabaseUrl {
    // 1. Try finding it in .env (Local Dev)
    final url = dotenv.env['SUPABASE_URL'];
    if (url != null && url.isNotEmpty) {
      return url;
    }
    // 2. If this code is running in the CI/CD build, this file 
    //    will be overwritten, so we should return an empty string 
    //    here locally if .env is missing.
    return '';
  }

  static String get supabaseAnonKey {
    final key = dotenv.env['SUPABASE_ANON_KEY'];
    if (key != null && key.isNotEmpty) {
      return key;
    }
    return '';
  }
}