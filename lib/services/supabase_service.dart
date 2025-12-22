import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static final SupabaseClient client = Supabase.instance.client;

  static Future<void> signUp(String email, String password) async {
    // await client.auth.signUp(email: email, password: password);
  }
}