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
  // FIX: Default to Light to ensure toggle matches visual state on first run
  ThemeMode _themeMode = ThemeMode.light; 
  bool _onlyNahverkehr = false;
  bool _isGhostMode = false;
  
  // FIX: Default to the first color in the list so it appears selected
  Color _themeColor = appThemeColors[0]; 

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load saved values
    final isDark = prefs.getBool('is_dark_mode');
    final onlyNv = prefs.getBool('only_nahverkehr') ?? false;
    final colorVal = prefs.getInt('theme_color_value');
    final isGhost = prefs.getBool('ghost_mode') ?? false;

    setState(() {
      if (isDark != null) {
        _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
      }
      _onlyNahverkehr = onlyNv;
      _isGhostMode = isGhost;
      
      // Load color, fallback to default list[0] if null
      if (colorVal != null) {
        _themeColor = Color(colorVal);
      } else {
        _themeColor = appThemeColors[0];
      }
    });
  }

  void _toggleTheme(bool isDark) async {
    setState(() {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_dark_mode', isDark);
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
        isDarkMode: _themeMode == ThemeMode.dark,
        onThemeChanged: _toggleTheme,
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