import 'dart:async';
import 'dart:ui'; // Needed for PointerDeviceKind
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
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
import 'utils/app_error.dart';

enum StartupAuthNotice {
  emailConfirmed,
  emailUpdated,
  emailConfirmationFailed,
  magicLinkSignedIn,
}

Future<void> main() async {
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    AppError.log(
      details.exception,
      stackTrace: details.stack,
      source: 'FlutterError.onError',
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppError.log(
      error,
      stackTrace: stack,
      source: 'PlatformDispatcher.onError',
    );
    return true;
  };

  await runZonedGuarded(() async {
    bool initFailed = false;
    String? initError;
    StartupAuthNotice? startupAuthNotice;

    try {
      await dotenv.load(fileName: ".env");

      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        anonKey: AppConfig.supabaseAnonKey,
      );

      if (kIsWeb) {
        try {
          final otpType = await SupabaseService.handleAuthCallbackUri(Uri.base);
          if (otpType == OtpType.signup) {
            startupAuthNotice = StartupAuthNotice.emailConfirmed;
          } else if (otpType == OtpType.emailChange) {
            startupAuthNotice = StartupAuthNotice.emailUpdated;
          } else if (otpType == OtpType.magiclink) {
            startupAuthNotice = StartupAuthNotice.magicLinkSignedIn;
          }
        } catch (e, st) {
          startupAuthNotice = StartupAuthNotice.emailConfirmationFailed;
          AppError.log(
            e,
            stackTrace: st,
            source: 'web auth confirm startup',
          );
        }
      }

      await SupabaseService.init();
    } catch (e, st) {
      initFailed = true;
      initError = e.toString();
      AppError.log(e, stackTrace: st, source: 'main initialization');
    }

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    runApp(
      TransApp(
        initFailed: initFailed,
        initError: initError,
        startupAuthNotice: startupAuthNotice,
      ),
    );
  }, (error, stack) {
    AppError.log(error, stackTrace: stack, source: 'runZonedGuarded');
  });
}

// FIX: Enable Mouse Dragging for Web/Desktop
class CustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.trackpad,
      };
}

class TransApp extends StatefulWidget {
  final bool initFailed;
  final String? initError;
  final StartupAuthNotice? startupAuthNotice;

  const TransApp({
    super.key,
    this.initFailed = false,
    this.initError,
    this.startupAuthNotice,
  });

  @override
  State<TransApp> createState() => _TransAppState();
}

class _TransAppState extends State<TransApp> {
  final AppLinks _appLinks = AppLinks();
  ThemeMode _themeMode = ThemeMode.light;
  bool _useSystemTheme = false;
  bool _onlyNahverkehr = false;
  bool _isGhostMode = false;
  Color _themeColor = appThemeColors[0];
  Locale? _locale;
  StreamSubscription<Uri>? _authLinkSubscription;

  @override
  void initState() {
    super.initState();
    _readPreferences(); // Show immediate local state
    _initSync(); // Start cloud sync
    SupabaseService.settingsRefreshNotifier.addListener(_readPreferences);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.startupAuthNotice != null) {
        await _showStartupAuthNotice(widget.startupAuthNotice!);
      }
      await _initAuthLinks();
    });
  }

  @override
  void dispose() {
    _authLinkSubscription?.cancel();
    SupabaseService.settingsRefreshNotifier.removeListener(_readPreferences);
    super.dispose();
  }

  Future<void> _initSync() async {
    await SupabaseService.loadAndSyncSettings();
  }

  Future<void> _showStartupAuthNotice(StartupAuthNotice notice) async {
    if (!mounted) return;
    final isGerman = Localizations.localeOf(context).languageCode == 'de';
    final message = switch (notice) {
      StartupAuthNotice.emailConfirmed => isGerman
          ? 'E-Mail bestaetigt. Du bist jetzt angemeldet.'
          : 'Email confirmed. You are now signed in.',
      StartupAuthNotice.emailUpdated => isGerman
          ? 'E-Mail-Adresse bestaetigt und aktualisiert.'
          : 'Email address confirmed and updated.',
      StartupAuthNotice.emailConfirmationFailed => isGerman
          ? 'E-Mail-Bestaetigung fehlgeschlagen. Bitte Link erneut oeffnen oder eine neue E-Mail anfordern.'
          : 'Email confirmation failed. Please open the link again or request a new email.',
      StartupAuthNotice.magicLinkSignedIn => isGerman
          ? 'Du wurdest ueber den Magic Link angemeldet.'
          : 'You were signed in through the magic link.',
    };

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _initAuthLinks() async {
    if (kIsWeb) {
      return;
    }

    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        await _processAuthUri(initialUri);
      }
    } catch (e, st) {
      AppError.log(e, stackTrace: st, source: 'initial auth link');
    }

    _authLinkSubscription = _appLinks.uriLinkStream.listen(
      (uri) {
        unawaited(_processAuthUri(uri));
      },
      onError: (error, stackTrace) {
        AppError.log(
          error,
          stackTrace: stackTrace is StackTrace ? stackTrace : null,
          source: 'auth link stream',
        );
      },
    );
  }

  Future<void> _processAuthUri(Uri uri) async {
    try {
      final otpType = await SupabaseService.handleAuthCallbackUri(uri);
      if (otpType == null) return;

      switch (otpType) {
        case OtpType.signup:
          await _showStartupAuthNotice(StartupAuthNotice.emailConfirmed);
        case OtpType.emailChange:
          await _showStartupAuthNotice(StartupAuthNotice.emailUpdated);
        case OtpType.magiclink:
          await _showStartupAuthNotice(StartupAuthNotice.magicLinkSignedIn);
        case OtpType.recovery:
          break;
        default:
          break;
      }
    } catch (e, st) {
      AppError.log(e, stackTrace: st, source: 'auth confirm callback');
      await _showStartupAuthNotice(StartupAuthNotice.emailConfirmationFailed);
    }
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
      if (colorVal != null) {
        _themeColor = Color(colorVal);
      } else {
        _themeColor = appThemeColors[0];
      }

      _useSystemTheme = storedSystemSync;

      if (_useSystemTheme) {
        _themeMode = ThemeMode.system;
      } else {
        if (storedIsDark != null) {
          _themeMode = storedIsDark ? ThemeMode.dark : ThemeMode.light;
        } else {
          final brightness =
              WidgetsBinding.instance.platformDispatcher.platformBrightness;
          _themeMode = (brightness == Brightness.light)
              ? ThemeMode.light
              : ThemeMode.dark;
          prefs.setBool('is_dark_mode', _themeMode == ThemeMode.dark);
        }
      }

      final localeCode = prefs.getString('locale_code');
      if (localeCode != null) {
        _locale = Locale(localeCode);
      } else {
        _locale = null; // System default
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
    await SupabaseService.updateSettings(
        {'is_dark_mode': isDark, 'use_system_theme': false});
  }

  void _toggleSystemSync(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _useSystemTheme = enabled;
      if (enabled) {
        _themeMode = ThemeMode.system;
      } else {
        final brightness =
            WidgetsBinding.instance.platformDispatcher.platformBrightness;
        _themeMode =
            (brightness == Brightness.dark) ? ThemeMode.dark : ThemeMode.light;
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
    await prefs.setInt('theme_color_value', color.toARGB32());
    await SupabaseService.updateThemeColor(color.toARGB32());
  }

  void _changeLocale(Locale locale) async {
    setState(() {
      _locale = locale;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale_code', locale.languageCode);
    await SupabaseService.updateSettings({'locale_code': locale.languageCode});
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
      locale: _locale,
      themeMode: _themeMode,
      theme: AppTheme.lightTheme(_themeColor),
      darkTheme: AppTheme.darkTheme(_themeColor),
      home: Scaffold(
        body: Column(
          children: [
            if (widget.initFailed)
              Container(
                color: Colors.red,
                padding: const EdgeInsets.all(8),
                width: double.infinity,
                child: Text(
                  'Initialization Error: ${widget.initError}',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            Expanded(
              child: HomeScreen(
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
                locale: _locale,
                onLocaleChanged: _changeLocale,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
