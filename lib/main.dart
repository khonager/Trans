import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config/app_config.dart';
import 'screens/home_screen.dart'; // Point to new file

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ... Init Supabase ...
  runApp(const TransApp());
}

class TransApp extends StatefulWidget {
  const TransApp({super.key});
  @override
  State<TransApp> createState() => _TransAppState();
}

class _TransAppState extends State<TransApp> {
  ThemeMode _themeMode = ThemeMode.dark;
  // ... Load Theme Logic ...

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // ... Theme config ...
      home: HomeScreen(
        onThemeChanged: (isDark) => setState(() => _themeMode = isDark ? ThemeMode.dark : ThemeMode.light),
        isDarkMode: _themeMode == ThemeMode.dark,
      ),
    );
  }
}