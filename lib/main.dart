import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'config/app_config.dart';
import 'screens/home_screen.dart';
import 'services/supabase_service.dart';

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
  Color _seedColor = const Color(0xFF4F46E5); // Default Indigo

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _listenToAuthChanges();
  }

  void _listenToAuthChanges() {
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedIn) {
        _syncThemeFromCloud();
      }
    });
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('isDark') ?? true;
    final colorVal = prefs.getInt('themeColor');
    
    setState(() {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
      if (colorVal != null) {
        _seedColor = Color(colorVal);
      }
    });
    
    if (SupabaseService.currentUser != null) {
      _syncThemeFromCloud();
    }
  }

  Future<void> _syncThemeFromCloud() async {
    final profile = await SupabaseService.getCurrentProfile();
    if (profile != null && profile['theme_color'] != null) {
      final colorVal = profile['theme_color'] as int;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('themeColor', colorVal);
      if (mounted) {
        setState(() => _seedColor = Color(colorVal));
      }
    }
  }

  Future<void> _toggleTheme(bool isDark) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDark', isDark);
    setState(() {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    });
  }

  Future<void> _updateColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeColor', color.value);
    
    setState(() => _seedColor = color);
    await SupabaseService.updateThemeColor(color.value);
  }

  @override
  Widget build(BuildContext context) {
    // Generate base schemes
    final lightScheme = ColorScheme.fromSeed(seedColor: _seedColor, brightness: Brightness.light);
    
    // For Dark Mode: We manually override 'primary' to be the saturated seed color
    // instead of the default pastel version. This ensures high contrast for White icons.
    final darkBase = ColorScheme.fromSeed(seedColor: _seedColor, brightness: Brightness.dark);
    final darkScheme = darkBase.copyWith(
      primary: _seedColor, 
      onPrimary: Colors.white, // Ensure icons on top are white
      primaryContainer: _seedColor.withOpacity(0.3),
      onPrimaryContainer: Colors.white,
    );

    return MaterialApp(
      title: 'Trans',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
          brightness: Brightness.light,
          scaffoldBackgroundColor: const Color(0xFFF3F4F6),
          colorScheme: lightScheme,
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          )
      ),
      darkTheme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF000000),
          colorScheme: darkScheme,
          useMaterial3: true,
          appBarTheme: AppBarTheme(
            backgroundColor: Colors.black.withOpacity(0.7),
            foregroundColor: Colors.white,
          ),
          // Ensure sliders and switches pop
          sliderTheme: SliderThemeData(
            activeTrackColor: _seedColor,
            thumbColor: Colors.white,
          ),
          switchTheme: SwitchThemeData(
            thumbColor: MaterialStateProperty.resolveWith((states) {
              if (states.contains(MaterialState.selected)) return Colors.white;
              return null;
            }),
            trackColor: MaterialStateProperty.resolveWith((states) {
              if (states.contains(MaterialState.selected)) return _seedColor;
              return null;
            }),
          )
      ),
      home: HomeScreen(
        onThemeChanged: _toggleTheme,
        isDarkMode: _themeMode == ThemeMode.dark,
        onColorChanged: _updateColor,
        currentColor: _seedColor,
      ),
    );
  }
}