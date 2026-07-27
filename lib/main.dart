import 'dart:async';
import 'dart:io';
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
import 'services/color_claim_service.dart';
import 'services/supabase_service.dart';
import 'services/linux_url_scheme_registration.dart';
import 'models/journey_sharing.dart';
import 'utils/app_error.dart';

enum StartupAuthNotice {
  emailConfirmed,
  emailUpdated,
  emailConfirmationFailed,
  magicLinkSignedIn,
  portfolioSignedIn,
  portfolioSignInFailed,
}

Future<void> main() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    usePathUrlStrategy();

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
          if (SupabaseService.isPortfolioBridgeUri(Uri.base)) {
            await SupabaseService.handlePortfolioBridgeUri(Uri.base);
            startupAuthNotice = StartupAuthNotice.portfolioSignedIn;
          } else if (SupabaseService.shouldHandleAuthCallbackManually(
              Uri.base)) {
            final otpType =
                await SupabaseService.handleAuthCallbackUri(Uri.base);
            if (otpType == OtpType.signup) {
              startupAuthNotice = StartupAuthNotice.emailConfirmed;
            } else if (otpType == OtpType.emailChange) {
              startupAuthNotice = StartupAuthNotice.emailUpdated;
            } else if (otpType == OtpType.magiclink ||
                otpType == OtpType.email) {
              startupAuthNotice = StartupAuthNotice.magicLinkSignedIn;
            }
          }
        } catch (e, st) {
          startupAuthNotice = SupabaseService.isPortfolioBridgeUri(Uri.base)
              ? StartupAuthNotice.portfolioSignInFailed
              : StartupAuthNotice.emailConfirmationFailed;
          AppError.log(
            e,
            stackTrace: st,
            source: 'web auth confirm startup',
          );
        }
      }

      await SupabaseService.init();

      if (!kIsWeb && Platform.isLinux) {
        await LinuxUrlSchemeRegistration.ensureRegistered();
      }
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
  int _signalLevel = JourneySignalLevel.defaultForNewUsers;
  Color _themeColor = appThemeColors[0];
  Locale? _locale;
  StreamSubscription<Uri>? _authLinkSubscription;
  int _appRefreshKey = 0;
  bool _isAppRefreshing = false;

  @override
  void initState() {
    super.initState();
    _readPreferences(); // Show immediate local state
    _initSync(); // Start cloud sync
    SupabaseService.settingsRefreshNotifier.addListener(_readPreferences);
    SupabaseService.appRefreshNotifier.addListener(_handleAppRefreshRequest);
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
    SupabaseService.appRefreshNotifier.removeListener(_handleAppRefreshRequest);
    super.dispose();
  }

  Future<void> _initSync() async {
    await SupabaseService.loadAndSyncSettings();
  }

  void _handleAppRefreshRequest() {
    unawaited(_refreshAppShell());
  }

  Future<void> _refreshAppShell() async {
    if (_isAppRefreshing) return;
    if (!mounted) return;

    setState(() => _isAppRefreshing = true);
    await Future.wait<void>([
      _readPreferences(),
      Future<void>.delayed(const Duration(milliseconds: 650)),
    ]);

    if (!mounted) return;
    setState(() {
      _appRefreshKey++;
      _isAppRefreshing = false;
    });
  }

  Future<void> _showStartupAuthNotice(StartupAuthNotice notice) async {
    if (!mounted) return;
    final isGerman = Localizations.localeOf(context).languageCode == 'de';
    final message = switch (notice) {
      StartupAuthNotice.emailConfirmed => isGerman
          ? 'E-Mail bestätigt. Du bist jetzt angemeldet.'
          : 'Email confirmed. You are now signed in.',
      StartupAuthNotice.emailUpdated => isGerman
          ? 'E-Mail-Adresse bestätigt und aktualisiert.'
          : 'Email address confirmed and updated.',
      StartupAuthNotice.emailConfirmationFailed => isGerman
          ? 'E-Mail-Bestätigung fehlgeschlagen. Bitte Link erneut öffnen oder eine neue E-Mail anfordern.'
          : 'Email confirmation failed. Please open the link again or request a new email.',
      StartupAuthNotice.magicLinkSignedIn => isGerman
          ? 'Du wurdest über den Magic Link angemeldet.'
          : 'You were signed in through the magic link.',
      StartupAuthNotice.portfolioSignedIn => isGerman
          ? 'Du wurdest mit deinem Portfolio-Konto angemeldet.'
          : 'You were signed in with your portfolio account.',
      StartupAuthNotice.portfolioSignInFailed => isGerman
          ? 'Portfolio-Anmeldung fehlgeschlagen. Bitte erneut versuchen.'
          : 'Portfolio sign-in failed. Please try again.',
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
      if (SupabaseService.isPortfolioBridgeUri(uri)) {
        await SupabaseService.handlePortfolioBridgeUri(uri);
        await _showStartupAuthNotice(StartupAuthNotice.portfolioSignedIn);
        SupabaseService.requestAppRefresh();
        return;
      }

      final otpType = await SupabaseService.handleAuthCallbackUri(uri);
      if (otpType != null) {
        switch (otpType) {
          case OtpType.signup:
            await _showStartupAuthNotice(StartupAuthNotice.emailConfirmed);
          case OtpType.emailChange:
            await _showStartupAuthNotice(StartupAuthNotice.emailUpdated);
          case OtpType.magiclink:
          case OtpType.email:
            await _showStartupAuthNotice(StartupAuthNotice.magicLinkSignedIn);
          case OtpType.recovery:
            break;
          default:
            break;
        }
        if (SupabaseService.currentUser != null) {
          SupabaseService.requestAppRefresh();
        }
        return;
      }

      final handled = await SupabaseService.handleAuthSessionUri(uri);
      if (handled) {
        SupabaseService.requestAppRefresh();
      }
    } catch (e, st) {
      AppError.log(e, stackTrace: st, source: 'auth confirm callback');
      if (SupabaseService.shouldHandleAuthCallbackManually(uri)) {
        await _showStartupAuthNotice(StartupAuthNotice.emailConfirmationFailed);
      }
    }
  }

  Future<void> _readPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    final onlyNv = prefs.getBool('only_nahverkehr') ?? false;
    final colorVal = prefs.getInt('theme_color_value');
    final signalLevel =
        prefs.getInt(SupabaseService.privacyLevelPreferenceKey) ??
            prefs.getInt('journey_signal_level') ??
            ((prefs.getBool('ghost_mode') ?? true) ? 0 : 1);
    final storedSystemSync = prefs.getBool('use_system_theme') ?? false;
    final storedIsDark = prefs.getBool('is_dark_mode');

    if (!mounted) return;

    setState(() {
      _onlyNahverkehr = onlyNv;
      _signalLevel = JourneySignalLevel.clamp(signalLevel);
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

  Future<void> _setSignalLevel(int level) async {
    final normalized = JourneySignalLevel.clamp(level);
    setState(() => _signalLevel = normalized);
    await SupabaseService.setMySignalLevel(normalized);
  }

  Future<void> _updateThemeColor(Color color) async {
    setState(() {
      _themeColor = color;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_color_value', color.toARGB32());
    await SupabaseService.updateThemeColor(color.toARGB32());
    await SupabaseService.updateSettings({
      'theme_color_hex': ColorClaimService.normalizeColor(color),
    });
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
      home: Stack(
        children: [
          Scaffold(
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
                    key: ValueKey(_appRefreshKey),
                    isDarkMode: _themeMode == ThemeMode.dark,
                    onThemeChanged: _toggleTheme,
                    useSystemTheme: _useSystemTheme,
                    onSystemSyncChanged: _toggleSystemSync,
                    onlyNahverkehr: _onlyNahverkehr,
                    onNahverkehrChanged: _toggleNahverkehr,
                    signalLevel: _signalLevel,
                    onSignalLevelChanged: _setSignalLevel,
                    onColorChanged: _updateThemeColor,
                    currentColor: _themeColor,
                    locale: _locale,
                    onLocaleChanged: _changeLocale,
                  ),
                ),
              ],
            ),
          ),
          if (_isAppRefreshing)
            const Positioned.fill(child: _AppRefreshOverlay()),
        ],
      ),
    );
  }
}

class _AppRefreshOverlay extends StatefulWidget {
  const _AppRefreshOverlay();

  @override
  State<_AppRefreshOverlay> createState() => _AppRefreshOverlayState();
}

class _AppRefreshOverlayState extends State<_AppRefreshOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: const Offset(0, -0.08),
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.94),
      child: Center(
        child: SlideTransition(
          position: _offset,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.asset(
              isDark ? 'lib/assets/logo_light.png' : 'lib/assets/logo_dark.png',
              width: 88,
              height: 88,
              errorBuilder: (context, error, stackTrace) => Icon(
                Icons.directions_transit,
                size: 72,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
