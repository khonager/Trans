// lib/main.dart
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'config/app_config.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    // Expected in Release
  }

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  runApp(const TransApp());
}

class TransApp extends StatefulWidget {
  const TransApp({super.key});

  @override
  State<TransApp> createState() => _TransAppState();
}

class _TransAppState extends State<TransApp> {
  ThemeMode _themeMode = ThemeMode.dark;
  Color _seedColor = const Color(0xFF4F46E5); // Default indigo
  bool _useMaterialYou = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('isDark') ?? true;
    final colorValue = prefs.getInt('themeColor');
    final useMaterialYou = prefs.getBool('useMaterialYou') ?? false;

    setState(() {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
      if (colorValue != null) {
        _seedColor = Color(colorValue);
      }
      _useMaterialYou = useMaterialYou;
    });
  }

  Future<void> _toggleTheme(bool isDark) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDark', isDark);
    setState(() {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    });
  }

  Future<void> _updateColorTheme(Color color, bool useMaterialYou) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeColor', color.value);
    await prefs.setBool('useMaterialYou', useMaterialYou);
    setState(() {
      _seedColor = color;
      _useMaterialYou = useMaterialYou;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        ColorScheme lightScheme;
        ColorScheme darkScheme;

        if (lightDynamic != null && darkDynamic != null && _useMaterialYou) {
          // Use Material You (Android 12+)
          lightScheme = lightDynamic.harmonized();
          darkScheme = darkDynamic.harmonized();
        } else {
          // Use Custom Seed Color
          lightScheme = ColorScheme.fromSeed(
            seedColor: _seedColor,
            brightness: Brightness.light,
          );
          darkScheme = ColorScheme.fromSeed(
            seedColor: _seedColor,
            brightness: Brightness.dark,
          );
        }

        return MaterialApp(
          title: 'Trans',
          debugShowCheckedModeBanner: false,
          themeMode: _themeMode,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: lightScheme,
            scaffoldBackgroundColor: lightScheme.surface,
            cardColor: lightScheme.surfaceContainerLow,
            appBarTheme: AppBarTheme(
              backgroundColor: lightScheme.surface,
              foregroundColor: lightScheme.onSurface,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: darkScheme,
            scaffoldBackgroundColor: Colors.black, // Keep pure black for OLED preference? Or use darkScheme.surface
            cardColor: const Color(0xFF111827),
            appBarTheme: AppBarTheme(
              backgroundColor: Colors.black.withOpacity(0.7),
              foregroundColor: Colors.white,
            ),
          ),
          home: HomeScreen(
            onThemeChanged: _toggleTheme,
            onColorChanged: _updateColorTheme,
            isDarkMode: _themeMode == ThemeMode.dark,
            currentColor: _seedColor,
            useMaterialYou: _useMaterialYou,
          ),
        );
      },
    );
  }
}