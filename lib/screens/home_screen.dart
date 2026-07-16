import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart'; // Added import for persistence
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trans/services/community_safety_service.dart';
import 'package:trans/services/supabase_service.dart';
import 'package:trans/services/transport_api.dart';
import 'package:trans/models/station.dart';
import 'package:trans/screens/transitous_live_map_screen.dart';
import 'tabs/routes_tab.dart';
import 'tabs/friends_tab.dart';
import 'tabs/settings_tab.dart';
import '../widgets/ticket_panel.dart';
import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../utils/app_error.dart';

class HomeScreen extends StatefulWidget {
  final bool isDarkMode;
  final Function(bool) onThemeChanged;
  final bool useSystemTheme;
  final Function(bool) onSystemSyncChanged;
  final bool onlyNahverkehr;
  final Function(bool) onNahverkehrChanged;
  final int signalLevel;
  final Future<void> Function(int) onSignalLevelChanged;
  final Future<void> Function(Color) onColorChanged;
  final Color currentColor;
  final Locale? locale;
  final Function(Locale) onLocaleChanged;

  const HomeScreen({
    super.key,
    required this.isDarkMode,
    required this.onThemeChanged,
    required this.useSystemTheme,
    required this.onSystemSyncChanged,
    required this.onlyNahverkehr,
    required this.onNahverkehrChanged,
    required this.signalLevel,
    required this.onSignalLevelChanged,
    required this.onColorChanged,
    required this.currentColor,
    required this.locale,
    required this.onLocaleChanged,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _showTrainNumbers = false;
  bool _alwaysWakeMe = false;
  bool _hasAcceptedCommunityTerms = false;
  Position? _currentPosition;
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<Position>? _alwaysLocationSubscription;
  final GlobalKey<RoutesTabState> _routesTabKey = GlobalKey<RoutesTabState>();
  bool _isShowingRecoveryDialog = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSavedTab(); // Load saved tab on startup
    _loadSettings(); // Load other settings
    if (!kIsWeb) {
      _determinePosition();
    }
    _setupAuthListener();
    SupabaseService.settingsRefreshNotifier
        .addListener(_handleSharingSettingsRefresh);
    unawaited(_syncAlwaysLocationSharing());
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final hasAcceptedCommunityTerms =
        await CommunitySafetyService.hasAcceptedTerms();
    TransportApi.configureEnabledSources(
      TransportApi.enabledSourcesFromPreferences(prefs),
    );
    if (mounted) {
      setState(() {
        _showTrainNumbers = prefs.getBool('show_train_numbers') ?? false;
        _alwaysWakeMe = prefs.getBool('always_wake_me') ?? false;
        _hasAcceptedCommunityTerms = hasAcceptedCommunityTerms;
        if (!hasAcceptedCommunityTerms && _currentIndex == 1) {
          _currentIndex = 0;
        }
      });
    }
  }

  Future<void> _updateShowTrainNumbers(bool value) async {
    setState(() => _showTrainNumbers = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_train_numbers', value);
  }

  Future<void> _updateAlwaysWakeMe(bool value) async {
    setState(() => _alwaysWakeMe = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('always_wake_me', value);
  }

  void _routeToSharedStation(Station station) {
    setState(() => _currentIndex = 0);
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setInt('current_tab_index', 0));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _routesTabKey.currentState?.routeToSharedPlace(station);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    _alwaysLocationSubscription?.cancel();
    SupabaseService.settingsRefreshNotifier
        .removeListener(_handleSharingSettingsRefresh);
    super.dispose();
  }

  void _handleSharingSettingsRefresh() {
    unawaited(_syncAlwaysLocationSharing());
  }

  void _handleHighAccuracyTrackingChanged(bool active) {
    if (active) {
      _alwaysLocationSubscription?.cancel();
      _alwaysLocationSubscription = null;
    } else {
      unawaited(_syncAlwaysLocationSharing());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !kIsWeb) {
      _determinePosition();
      unawaited(_syncAlwaysLocationSharing());
    }
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.signalLevel != widget.signalLevel) {
      unawaited(_syncAlwaysLocationSharing());
    }
  }

  Future<void> _syncAlwaysLocationSharing() async {
    final sharing = await SupabaseService.getJourneySharingSettings();
    if (!sharing.needsAlwaysLocation) {
      await _alwaysLocationSubscription?.cancel();
      _alwaysLocationSubscription = null;
      return;
    }
    if (_alwaysLocationSubscription != null || kIsWeb) return;
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }
    LocationSettings settings = const LocationSettings(
      accuracy: LocationAccuracy.low,
      distanceFilter: 250,
    );
    if (defaultTargetPlatform == TargetPlatform.android) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.low,
        distanceFilter: 250,
        intervalDuration: const Duration(minutes: 2),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Journey Signal',
          notificationText:
              'Keeping your location available to trusted friends',
          notificationIcon: AndroidResource(name: 'ic_launcher'),
          enableWakeLock: false,
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.low,
        activityType: ActivityType.other,
        distanceFilter: 250,
        pauseLocationUpdatesAutomatically: true,
        showBackgroundLocationIndicator: true,
      );
    }
    _alwaysLocationSubscription =
        Geolocator.getPositionStream(locationSettings: settings).listen(
      (position) {
        if (mounted) setState(() => _currentPosition = position);
        unawaited(SupabaseService.publishLocationSnapshot(
          position,
          isJourneyLocation: false,
        ));
      },
      onError: (Object error, StackTrace stackTrace) {
        AppError.log(error,
            stackTrace: stackTrace, source: 'Always-available location');
        _alwaysLocationSubscription?.cancel();
        _alwaysLocationSubscription = null;
      },
    );
  }

  void _setupAuthListener() {
    final client = SupabaseService.maybeClient;
    if (client == null) return;

    _authSubscription = client.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      if (event == AuthChangeEvent.passwordRecovery) {
        _handlePasswordRecovery();
        return;
      }

      if (event == AuthChangeEvent.signedIn ||
          event == AuthChangeEvent.initialSession) {
        unawaited(_prepareSignedInState());
      }

      if (event == AuthChangeEvent.signedIn ||
          event == AuthChangeEvent.signedOut ||
          event == AuthChangeEvent.initialSession ||
          event == AuthChangeEvent.userUpdated) {
        if (mounted) {
          setState(() {});
        }
      }
    });
  }

  Future<void> _prepareSignedInState() async {
    try {
      await SupabaseService.ensureCurrentUserReady();
      if (mounted) {
        setState(() {});
      }
    } catch (e, st) {
      AppError.log(e, stackTrace: st, source: 'HomeScreen auth listener');
    }
  }

  void _handlePasswordRecovery() {
    if (_isShowingRecoveryDialog) return;
    _isShowingRecoveryDialog = true;
    _onTabChanged(2);

    final newPasswordCtrl = TextEditingController();
    final confirmPasswordCtrl = TextEditingController();
    bool isSaving = false;
    final messenger = ScaffoldMessenger.of(context);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(AppLocalizations.of(context)!.resetPassword),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(AppLocalizations.of(context)!.resetPasswordMessage),
                const SizedBox(height: 12),
                TextField(
                  controller: newPasswordCtrl,
                  autofocus: true,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.newPasswordOpt,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmPasswordCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.confirmPassword,
                  ),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        final password = newPasswordCtrl.text.trim();
                        final confirm = confirmPasswordCtrl.text.trim();

                        if (password.isEmpty || confirm.isEmpty) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(AppLocalizations.of(context)!
                                  .fillRequiredFields),
                            ),
                          );
                          return;
                        }

                        if (password != confirm) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(AppLocalizations.of(context)!
                                  .passwordsDoNotMatch),
                            ),
                          );
                          return;
                        }

                        setState(() => isSaving = true);
                        try {
                          await SupabaseService.updatePassword(password);
                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext);
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(AppLocalizations.of(context)!
                                  .passwordUpdated),
                            ),
                          );
                        } catch (e, st) {
                          if (!dialogContext.mounted) return;
                          AppError.showSnackBar(
                            context,
                            error: e,
                            stackTrace: st,
                            source: 'password recovery update',
                          );
                          setState(() => isSaving = false);
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(AppLocalizations.of(context)!.update),
              ),
            ],
          ),
        ),
      ).whenComplete(() {
        _isShowingRecoveryDialog = false;
        newPasswordCtrl.dispose();
        confirmPasswordCtrl.dispose();
      });
    });
  }

  // Load the saved tab index from SharedPreferences
  Future<void> _loadSavedTab() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIndex = prefs.getInt('current_tab_index') ?? 0;
    if (mounted) {
      setState(() {
        _currentIndex = savedIndex;
      });
    }
  }

  // Save the tab index whenever it changes
  Future<void> _onTabChanged(int index) async {
    if (index == 1 && !_hasAcceptedCommunityTerms) {
      final accepted = await CommunitySafetyService.ensureTermsAccepted(
        context,
        entryPoint: Localizations.localeOf(context).languageCode == 'de'
            ? 'Freunde'
            : 'Friends',
      );
      if (!accepted) return;
      if (mounted) {
        setState(() => _hasAcceptedCommunityTerms = true);
      } else {
        _hasAcceptedCommunityTerms = true;
      }
    }

    setState(() => _currentIndex = index);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('current_tab_index', index);
  }

  Future<void> _openLiveMap() async {
    await HapticFeedback.mediumImpact();
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TransitousLiveMapScreen(
          currentPosition: _currentPosition,
        ),
      ),
    );
  }

  Widget _buildRoutesNavIcon() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: _openLiveMap,
      child: const SizedBox(
        width: 56,
        height: 56,
        child: Center(
          child: Icon(Icons.directions),
        ),
      ),
    );
  }

  List<NavigationDestination> _buildDestinations(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return [
      NavigationDestination(
        icon: _buildRoutesNavIcon(),
        selectedIcon: _buildRoutesNavIcon(),
        label: l10n.routes,
      ),
      NavigationDestination(
        icon: const Icon(Icons.people),
        label: l10n.friends,
      ),
      NavigationDestination(
        icon: const Icon(Icons.settings),
        label: l10n.settings,
      ),
    ];
  }

  Future<void> _determinePosition() async {
    try {
      bool serviceEnabled;
      LocationPermission permission;

      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      if (permission == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition();
      setState(() => _currentPosition = pos);

      unawaited(
        SupabaseService.publishLocationSnapshot(
          pos,
          isJourneyLocation: false,
        ).catchError(
          (Object error) => debugPrint('Location Sync Error (Ignored): $error'),
        ),
      );
    } catch (e) {
      debugPrint("Geolocation Error (Ignored): $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    final screens = [
      RoutesTab(
        key: _routesTabKey,
        currentPosition: _currentPosition,
        onlyNahverkehr: widget.onlyNahverkehr,
        showTrainNumbers: _showTrainNumbers,
        alwaysWakeMe: _alwaysWakeMe,
        signalLevel: widget.signalLevel,
        onHighAccuracyTrackingChanged: _handleHighAccuracyTrackingChanged,
      ),
      FriendsTab(
        currentPosition: _currentPosition,
        onRouteToStation: _routeToSharedStation,
        isActive: _currentIndex == 1,
      ),
      SettingsTab(
        isDarkMode: widget.isDarkMode,
        onThemeChanged: widget.onThemeChanged,
        useSystemTheme: widget.useSystemTheme,
        onSystemSyncChanged: widget.onSystemSyncChanged,
        onlyNahverkehr: widget.onlyNahverkehr,
        onNahverkehrChanged: widget.onNahverkehrChanged,
        signalLevel: widget.signalLevel,
        onSignalLevelChanged: widget.onSignalLevelChanged,
        onColorChanged: widget.onColorChanged,
        currentColor: widget.currentColor,
        showTrainNumbers: _showTrainNumbers,
        onShowTrainNumbersChanged: _updateShowTrainNumbers,
        alwaysWakeMe: _alwaysWakeMe,
        onAlwaysWakeMeChanged: _updateAlwaysWakeMe,
        locale: widget.locale,
        onLocaleChanged: widget.onLocaleChanged,
      ),
    ];

    return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;

          // 1. Try to handle back in RoutesTab if it is active
          if (_currentIndex == 0 &&
              (_routesTabKey.currentState?.handleBack() ?? false)) {
            return;
          }

          // 2. Otherwise ask to quit
          final shouldQuit = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(AppLocalizations.of(context)!.quitAppTitle),
                  content: Text(AppLocalizations.of(context)!.quitAppMessage),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(AppLocalizations.of(context)!.no),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(AppLocalizations.of(context)!.yes),
                    ),
                  ],
                ),
              ) ??
              false;

          if (shouldQuit) {
            if (context.mounted) {
              SystemNavigator.pop();
            }
          }
        },
        child: Scaffold(
          backgroundColor: colors.scaffoldBg,
          // ALLOW: Set to true to allow keyboard to push UI up
          resizeToAvoidBottomInset: true,
          body: Stack(
            children: [
              IndexedStack(
                index: _currentIndex,
                children: screens,
              ),
              const TicketPanel(),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: _onTabChanged,
            destinations: _buildDestinations(context),
          ),
        ));
  }
}
