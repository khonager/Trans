import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static String get supabaseUrl {
    // 1. Try to get from --dart-define (Release build)
    const envUrl = String.fromEnvironment('SUPABASE_URL');
    if (envUrl.isNotEmpty) {
      return envUrl;
    }

    // 2. Fallback to .env file (Local Debug)
    final fileUrl = dotenv.env['SUPABASE_URL'];
    if (fileUrl != null && fileUrl.isNotEmpty) {
      return fileUrl;
    }
    
    // Return empty so main.dart can handle the error gracefully instead of crashing here
    return '';
  }

  static String get supabaseAnonKey {
    // 1. Try to get from --dart-define (Release build)
    const envKey = String.fromEnvironment('SUPABASE_ANON_KEY');
    if (envKey.isNotEmpty) {
      return envKey;
    }

    // 2. Fallback to .env file (Local Debug)
    final fileKey = dotenv.env['SUPABASE_ANON_KEY'];
    if (fileKey != null && fileKey.isNotEmpty) {
      return fileKey;
    }

    return '';
  }
}