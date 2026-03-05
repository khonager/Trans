import 'dart:ui'; // Needed for PointerDeviceKind
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'config/app_config.dart';
import 'config/app_theme.dart';
import 'screens/home_screen.dart';
import 'services/supabase_service.dart';

void main() async {
  usePathUrlStrategy();
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

// FIX: Enable Mouse Dragging for Web/Desktop
class CustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };
}

class TransApp extends StatefulWidget {
  const TransApp({super.key});

  @override
  State<TransApp> createState() => _TransAppState();
}

class _TransAppState extends State<TransApp> {
  ThemeMode _themeMode = ThemeMode.light; 
  bool _useSystemTheme = false;
  bool _onlyNahverkehr = false;
  bool _isGhostMode = false;
  Color _themeColor = appThemeColors[0]; 

  @override
  void initState() {
    super.initState();
    _readPreferences(); // Show immediate local state
    _initSync();        // Start cloud sync
    SupabaseService.settingsRefreshNotifier.addListener(_readPreferences);
  }

  @override
  void dispose() {
    SupabaseService.settingsRefreshNotifier.removeListener(_readPreferences);
    super.dispose();
  }

  Future<void> _initSync() async {
    await SupabaseService.loadAndSyncSettings();
  }

  Future<void> _readPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    
    final onlyNv = prefs.getBool('only_nahverkehr') ?? false;
    final colorVal = prefs.getInt('theme_color_value');
    final isGhost = prefs.getBool('ghost_mode') ?? false;
    final storedSystemSync = prefs.getBool('use_system_theme') ?? false;
    final storedIsDark = prefs.getBool('is_dark_mode');

    if (!mounted) return;

    setState(() {
      _onlyNahverkehr = onlyNv;
      _isGhostMode = isGhost;
      if (colorVal != null) _themeColor = Color(colorVal); else _themeColor = appThemeColors[0];
      
      _useSystemTheme = storedSystemSync;

      if (_useSystemTheme) {
        _themeMode = ThemeMode.system;
      } else {
        if (storedIsDark != null) {
          _themeMode = storedIsDark ? ThemeMode.dark : ThemeMode.light;
        } else {
          final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
          _themeMode = (brightness == Brightness.light) ? ThemeMode.light : ThemeMode.dark;
          prefs.setBool('is_dark_mode', _themeMode == ThemeMode.dark);
        }
      }
    });
  }

  void _toggleTheme(bool isDark) async {
    setState(() {
      _useSystemTheme = false; 
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_dark_mode', isDark);
    await prefs.setBool('use_system_theme', false);
    await SupabaseService.updateSettings({'is_dark_mode': isDark, 'use_system_theme': false});
  }

  void _toggleSystemSync(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _useSystemTheme = enabled;
      if (enabled) {
        _themeMode = ThemeMode.system;
      } else {
        final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
        _themeMode = (brightness == Brightness.dark) ? ThemeMode.dark : ThemeMode.light;
        prefs.setBool('is_dark_mode', _themeMode == ThemeMode.dark);
      }
    });
    await prefs.setBool('use_system_theme', enabled);
    await SupabaseService.updateSettings({'use_system_theme': enabled});
  }

  void _toggleNahverkehr(bool enabled) async {
    setState(() {
      _onlyNahverkehr = enabled;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('only_nahverkehr', enabled);
    await SupabaseService.updateSettings({'only_nahverkehr': enabled});
  }
  
  void _toggleGhostMode(bool enabled) async {
    setState(() {
      _isGhostMode = enabled;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ghost_mode', enabled);
    await SupabaseService.toggleGhostMode(enabled);
    await SupabaseService.updateSettings({'ghost_mode': enabled});
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
      scrollBehavior: CustomScrollBehavior(), // APPLY FIX
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'), // English, no country code
        Locale('de'), // German, no country code
      ],
      themeMode: _themeMode,
      theme: AppTheme.lightTheme(_themeColor),
      darkTheme: AppTheme.darkTheme(_themeColor),
      home: HomeScreen(
        isDarkMode: _themeMode == ThemeMode.dark,
        onThemeChanged: _toggleTheme,
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