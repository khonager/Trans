import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'config/app_config.dart';
import 'config/app_theme.dart';
import 'screens/home_screen.dart';
import 'services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await dotenv.load(fileName: ".env"); 

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  await SupabaseService.init();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const TransApp());
}

class TransApp extends StatefulWidget {
  const TransApp({super.key});

  @override
  State<TransApp> createState() => _TransAppState();
}

class _TransAppState extends State<TransApp> {
  ThemeMode _themeMode = ThemeMode.dark; // Default fallback
  bool _useSystemTheme = false; // Secret setting
  
  bool _onlyNahverkehr = false;
  bool _isGhostMode = false;
  Color _themeColor = appThemeColors[0]; 

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load Simple Values
    final onlyNv = prefs.getBool('only_nahverkehr') ?? false;
    final colorVal = prefs.getInt('theme_color_value');
    final isGhost = prefs.getBool('ghost_mode') ?? false;
    
    // Load Theme Logic
    final storedSystemSync = prefs.getBool('use_system_theme') ?? false;
    final storedIsDark = prefs.getBool('is_dark_mode');

    setState(() {
      _onlyNahverkehr = onlyNv;
      _isGhostMode = isGhost;
      if (colorVal != null) _themeColor = Color(colorVal);
      
      _useSystemTheme = storedSystemSync;

      if (_useSystemTheme) {
        _themeMode = ThemeMode.system;
      } else {
        // Manual Mode
        if (storedIsDark != null) {
          // Restore saved preference
          _themeMode = storedIsDark ? ThemeMode.dark : ThemeMode.light;
        } else {
          // FIRST RUN: Detect System, Default to Dark if unsure
          final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
          _themeMode = (brightness == Brightness.light) ? ThemeMode.light : ThemeMode.dark;
          
          // Save this initial state so it is "Manual" from now on
          prefs.setBool('is_dark_mode', _themeMode == ThemeMode.dark);
        }
      }
    });
  }

  void _toggleTheme(bool isDark) async {
    // If we toggle manually, we must disable system sync
    setState(() {
      _useSystemTheme = false; 
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_dark_mode', isDark);
    await prefs.setBool('use_system_theme', false);
  }

  void _toggleSystemSync(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _useSystemTheme = enabled;
      if (enabled) {
        _themeMode = ThemeMode.system;
      } else {
        // When disabling sync, snap to current actual brightness so it doesn't jump
        final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
        _themeMode = (brightness == Brightness.dark) ? ThemeMode.dark : ThemeMode.light;
        prefs.setBool('is_dark_mode', _themeMode == ThemeMode.dark);
      }
    });
    await prefs.setBool('use_system_theme', enabled);
  }

  void _toggleNahverkehr(bool enabled) async {
    setState(() {
      _onlyNahverkehr = enabled;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('only_nahverkehr', enabled);
  }
  
  void _toggleGhostMode(bool enabled) async {
    setState(() {
      _isGhostMode = enabled;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ghost_mode', enabled);
    await SupabaseService.toggleGhostMode(enabled);
  }
  
  void _updateThemeColor(Color color) async {
    setState(() {
      _themeColor = color;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_color_value', color.value);
    await SupabaseService.updateThemeColor(color.value);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trans',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: AppTheme.lightTheme(_themeColor),
      darkTheme: AppTheme.darkTheme(_themeColor),
      home: HomeScreen(
        isDarkMode: _themeMode == ThemeMode.dark, // This reflects current ACTUAL mode
        onThemeChanged: _toggleTheme,
        
        // Pass Sync Logic
        useSystemTheme: _useSystemTheme,
        onSystemSyncChanged: _toggleSystemSync,

        onlyNahverkehr: _onlyNahverkehr,
        onNahverkehrChanged: _toggleNahverkehr,
        isGhostMode: _isGhostMode,
        onGhostModeChanged: _toggleGhostMode,
        onColorChanged: _updateThemeColor,
        currentColor: _themeColor,
      ),
    );
  }
}