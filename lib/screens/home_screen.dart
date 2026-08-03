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
  static const _ticketDockedPreferenceKey = 'ticket_docked_to_navigation';
  static const _currentTabIdPreferenceKey = 'current_tab_id';

  int _currentIndex = 0;
  bool _ticketDocked = false;
  bool _ticketDockAnimationPending = false;
  bool _qrRestoreArmed = false;
  bool _qrRestoreGestureActive = false;
  bool _qrRestoreCancelPending = false;
  bool _qrRestoreEverMovedUp = false;
  double _qrRestoreProgress = 0;
  double _qrRestoreSheetExtent = 0.1;
  String? _qrRestoreOriginTabId;
  bool _ticketDockTransitionInProgress = false;
  bool _showTrainNumbers = false;
  bool _alwaysWakeMe = false;
  bool _hasAcceptedCommunityTerms = false;
  Position? _currentPosition;
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<Position>? _alwaysLocationSubscription;
  final GlobalKey<RoutesTabState> _routesTabKey = GlobalKey<RoutesTabState>();
  final GlobalKey _ticketPanelKey = GlobalKey();
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
    unawaited(_persistCurrentTab());
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
          notificationTitle: 'Privacy Level',
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
    final ticketDocked = prefs.getBool(_ticketDockedPreferenceKey) ?? false;
    final savedTabId = prefs.getString(_currentTabIdPreferenceKey);
    final legacyIndex = prefs.getInt('current_tab_index') ?? 0;
    final savedIndex = savedTabId == null
        ? legacyIndex.clamp(0, ticketDocked ? 3 : 2)
        : _indexForTabId(savedTabId, ticketDocked: ticketDocked);
    if (mounted) {
      setState(() {
        _ticketDocked = ticketDocked;
        _currentIndex = savedIndex;
      });
    }
  }

  int _indexForTabId(String id, {required bool ticketDocked}) {
    switch (id) {
      case 'friends':
        return 1;
      case 'ticket':
        return ticketDocked ? 2 : 0;
      case 'settings':
        return ticketDocked ? 3 : 2;
      default:
        return 0;
    }
  }

  String _tabIdForIndex(int index) {
    if (index == 0) return 'routes';
    if (index == 1) return 'friends';
    if (_ticketDocked && index == 2) return 'ticket';
    return 'settings';
  }

  Future<void> _persistCurrentTab() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('current_tab_index', _currentIndex);
    await prefs.setString(
        _currentTabIdPreferenceKey, _tabIdForIndex(_currentIndex));
  }

  Future<void> _dockTicket() async {
    if (_ticketDocked || _ticketDockTransitionInProgress) return;
    _ticketDockTransitionInProgress = true;
    try {
      await HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() {
        _ticketDocked = true;
        _ticketDockAnimationPending = false;
        if (_currentIndex >= 2) _currentIndex += 1;
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_ticketDockedPreferenceKey, true);
      await _persistCurrentTab();
    } finally {
      _ticketDockTransitionInProgress = false;
    }
  }

  void _beginTicketDockAnimation() {
    if (_ticketDocked || _ticketDockAnimationPending || !mounted) return;
    setState(() => _ticketDockAnimationPending = true);
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
    await _persistCurrentTab();
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
        width: 48,
        height: 36,
        child: Center(
          child: Icon(Icons.directions),
        ),
      ),
    );
  }

  void _startQrRestore(LongPressStartDetails details) {
    if (!_ticketDocked || _qrRestoreGestureActive) return;
    HapticFeedback.selectionClick();
    final originTabId = _tabIdForIndex(_currentIndex);
    setState(() {
      _qrRestoreOriginTabId = originTabId;
      _qrRestoreArmed = true;
      _qrRestoreGestureActive = true;
      _qrRestoreEverMovedUp = false;
      _qrRestoreProgress = 0;
      _qrRestoreSheetExtent = 0.1;
      _ticketDocked = false;
      _currentIndex = _indexForTabId(originTabId, ticketDocked: false);
    });
  }

  void _moveQrRestore(LongPressMoveUpdateDetails details) {
    if (!_qrRestoreGestureActive) return;
    final upwardDistance = (-details.offsetFromOrigin.dy).clamp(0.0, 1000.0);
    final progress = (upwardDistance / 150).clamp(0.0, 1.0);
    final extraDistance = (upwardDistance - 150).clamp(0.0, 1000.0);
    final availableHeight = MediaQuery.sizeOf(context).height * 0.72;
    final extent = (0.1 + (extraDistance / availableHeight)).clamp(0.1, 0.85);
    setState(() {
      if (upwardDistance > 8) _qrRestoreEverMovedUp = true;
      _qrRestoreProgress = progress;
      _qrRestoreSheetExtent = extent;
    });
  }

  void _endQrRestore(LongPressEndDetails details) {
    if (!_qrRestoreGestureActive) return;
    final shouldRestore = !_qrRestoreEverMovedUp ||
        _qrRestoreProgress >= 0.22 ||
        _qrRestoreSheetExtent > 0.105;
    if (shouldRestore) {
      unawaited(_commitInteractiveQrRestore());
    } else {
      _cancelInteractiveQrRestore();
    }
  }

  Future<void> _commitInteractiveQrRestore() async {
    await HapticFeedback.mediumImpact();
    if (!mounted || !_qrRestoreGestureActive) return;
    setState(() {
      _qrRestoreGestureActive = false;
      _ticketDockAnimationPending = false;
      _qrRestoreOriginTabId = null;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_ticketDockedPreferenceKey, false);
    await _persistCurrentTab();
  }

  void _cancelInteractiveQrRestore() {
    setState(() {
      _qrRestoreGestureActive = false;
      _qrRestoreCancelPending = true;
    });
  }

  void _finishCancelledQrRestore() {
    if (!mounted || !_qrRestoreCancelPending) return;
    final originTabId = _qrRestoreOriginTabId ?? 'routes';
    setState(() {
      _ticketDocked = true;
      _qrRestoreCancelPending = false;
      _qrRestoreArmed = false;
      _qrRestoreProgress = 0;
      _qrRestoreSheetExtent = 0.1;
      _qrRestoreOriginTabId = null;
      _currentIndex = _indexForTabId(originTabId, ticketDocked: true);
    });
  }

  void _handleQrExitAnimationCompleted() {
    if (!mounted || _ticketDocked || _qrRestoreGestureActive) return;
    setState(() {
      _qrRestoreArmed = false;
      _qrRestoreProgress = 0;
      _qrRestoreSheetExtent = 0.1;
    });
  }

  Widget _buildQrNavIcon() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: _startQrRestore,
      onLongPressMoveUpdate: _moveQrRestore,
      onLongPressEnd: _endQrRestore,
      child: SizedBox(
        width: 48,
        height: 36,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: _qrRestoreArmed ? 34 : 24,
            height: _qrRestoreArmed ? 5 : 24,
            decoration: _qrRestoreArmed
                ? BoxDecoration(
                    color: TransColors.of(context).navBarSelected,
                    borderRadius: BorderRadius.circular(3),
                  )
                : null,
            child: _qrRestoreArmed ? null : const Icon(Icons.qr_code_2_rounded),
          ),
        ),
      ),
    );
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
    final ticketPanel = TicketPanel(
      key: _ticketPanelKey,
      fullPage: _ticketDocked,
      interactiveRestoreProgress:
          _qrRestoreGestureActive ? _qrRestoreProgress : null,
      interactiveRestoreSheetExtent: _qrRestoreSheetExtent,
      settleRestoreBackToNavigation: _qrRestoreCancelPending,
      onDockAnimationStarted: _beginTicketDockAnimation,
      onDockRequested: () => unawaited(_dockTicket()),
      onInteractiveRestoreCancelled: _finishCancelledQrRestore,
    );
    final screens = <Widget>[
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
      if (_ticketDocked) ticketPanel,
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

    return Stack(
      children: [
        PopScope(
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
                      content:
                          Text(AppLocalizations.of(context)!.quitAppMessage),
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
                  if (!_ticketDocked) ticketPanel,
                ],
              ),
              bottomNavigationBar: _AnimatedHomeNavigationBar(
                ticketDocked: _ticketDocked ||
                    _ticketDockAnimationPending ||
                    _qrRestoreGestureActive ||
                    _qrRestoreCancelPending,
                ticketEnabled: _ticketDocked ||
                    _qrRestoreGestureActive ||
                    _qrRestoreCancelPending,
                ticketPullProgress: _qrRestoreProgress,
                currentTabId: _tabIdForIndex(_currentIndex),
                routesLabel: AppLocalizations.of(context)!.routes,
                friendsLabel: AppLocalizations.of(context)!.friends,
                settingsLabel: AppLocalizations.of(context)!.settings,
                routesIcon: _buildRoutesNavIcon(),
                qrIcon: _buildQrNavIcon(),
                onTicketExitAnimationCompleted: _handleQrExitAnimationCompleted,
                onTabSelected: (id) => unawaited(
                  _onTabChanged(
                    _indexForTabId(id, ticketDocked: _ticketDocked),
                  ),
                ),
              ),
            )),
        if (_ticketDockAnimationPending)
          const Positioned.fill(
            child: IgnorePointer(
              child: _TicketDockFlightOverlay(),
            ),
          ),
      ],
    );
  }
}

class _TicketDockFlightOverlay extends StatelessWidget {
  const _TicketDockFlightOverlay();

  double _mix(double from, double to, double t) => from + (to - from) * t;

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    final size = MediaQuery.sizeOf(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final bodyHeight = size.height - 72 - bottomInset;
    final start = Offset(size.width / 2, (bodyHeight * 0.9) + 15);
    final end = Offset(size.width * 5 / 8, bodyHeight + 20);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeInOutCubic,
      builder: (context, progress, child) {
        final center = Offset(
          _mix(start.dx, end.dx, progress),
          _mix(start.dy, end.dy, progress),
        );
        final morph = ((progress - 0.68) / 0.28).clamp(0.0, 1.0);
        return Stack(
          children: [
            Positioned(
              left: center.dx - 42,
              top: center.dy - 18,
              width: 84,
              height: 36,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: 1 - morph,
                    child: Container(
                      width: _mix(64, 12, morph),
                      height: _mix(6, 5, morph),
                      decoration: BoxDecoration(
                        color: colors.navBarSelected,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  Opacity(
                    opacity: morph,
                    child: Transform.scale(
                      scale: 0.72 + (0.28 * morph),
                      child: Icon(
                        Icons.qr_code_2_rounded,
                        color: colors.navBarUnselected,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AnimatedHomeNavigationBar extends StatefulWidget {
  final bool ticketDocked;
  final bool ticketEnabled;
  final double ticketPullProgress;
  final String currentTabId;
  final String routesLabel;
  final String friendsLabel;
  final String settingsLabel;
  final Widget routesIcon;
  final Widget qrIcon;
  final VoidCallback onTicketExitAnimationCompleted;
  final ValueChanged<String> onTabSelected;

  const _AnimatedHomeNavigationBar({
    required this.ticketDocked,
    required this.ticketEnabled,
    required this.ticketPullProgress,
    required this.currentTabId,
    required this.routesLabel,
    required this.friendsLabel,
    required this.settingsLabel,
    required this.routesIcon,
    required this.qrIcon,
    required this.onTicketExitAnimationCompleted,
    required this.onTabSelected,
  });

  @override
  State<_AnimatedHomeNavigationBar> createState() =>
      _AnimatedHomeNavigationBarState();
}

class _AnimatedHomeNavigationBarState extends State<_AnimatedHomeNavigationBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _layoutAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      value: widget.ticketDocked ? 1 : 0,
    );
    _layoutAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );
    _controller.addStatusListener(_handleAnimationStatus);
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) {
      widget.onTicketExitAnimationCompleted();
    }
  }

  @override
  void didUpdateWidget(_AnimatedHomeNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ticketDocked == widget.ticketDocked) return;
    if (widget.ticketDocked) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_handleAnimationStatus);
    _controller.dispose();
    super.dispose();
  }

  double _mix(double from, double to, double t) => from + (to - from) * t;

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    final textStyle = Theme.of(context).textTheme.labelMedium;

    return Material(
      color: colors.navBarBg,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return AnimatedBuilder(
                animation: _layoutAnimation,
                builder: (context, child) {
                  final t = _layoutAnimation.value;
                  final width = constraints.maxWidth;
                  final dockingTicket =
                      widget.ticketDocked && !widget.ticketEnabled;

                  double centerFor(String id) {
                    switch (id) {
                      case 'routes':
                        return _mix(width / 6, width / 8, t);
                      case 'friends':
                        return _mix(width / 2, width * 3 / 8, t);
                      case 'ticket':
                        if (dockingTicket) {
                          return _mix(width / 2, width * 5 / 8, t);
                        }
                        return width * 5 / 8;
                      default:
                        return _mix(width * 5 / 6, width * 7 / 8, t);
                    }
                  }

                  Widget item({
                    required String id,
                    required String label,
                    required Widget icon,
                    double opacity = 1,
                    double iconVerticalOffset = 0,
                    double labelOpacity = 1,
                    double scale = 1,
                    bool enabled = true,
                  }) {
                    final selected = widget.currentTabId == id;
                    final foreground = selected
                        ? colors.navBarSelected
                        : colors.navBarUnselected;
                    return Positioned(
                      left: centerFor(id) - 42,
                      top: 2,
                      width: 84,
                      height: 68,
                      child: IgnorePointer(
                        ignoring: !enabled,
                        child: Opacity(
                          opacity: opacity,
                          child: Transform.scale(
                            scale: scale,
                            child: Semantics(
                              button: true,
                              selected: selected,
                              label: label,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => widget.onTabSelected(id),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Transform.translate(
                                      offset: Offset(0, iconVerticalOffset),
                                      child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 240),
                                        width: selected ? 64 : 48,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? colors.navBarIndicator
                                              : Colors.transparent,
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: IconTheme(
                                          data:
                                              IconThemeData(color: foreground),
                                          child: Center(
                                            child: icon,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Opacity(
                                      opacity: labelOpacity,
                                      child: Text(
                                        label,
                                        maxLines: 1,
                                        overflow: TextOverflow.fade,
                                        softWrap: false,
                                        style: textStyle?.copyWith(
                                          color: foreground,
                                          fontWeight: selected
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      item(
                        id: 'routes',
                        label: widget.routesLabel,
                        icon: widget.routesIcon,
                      ),
                      item(
                        id: 'friends',
                        label: widget.friendsLabel,
                        icon: const Icon(Icons.people),
                      ),
                      item(
                        id: 'ticket',
                        label: 'QR',
                        icon: widget.qrIcon,
                        opacity: dockingTicket
                            ? 0
                            : t * (1 - widget.ticketPullProgress),
                        iconVerticalOffset: dockingTicket ? 0 : -30 * (1 - t),
                        labelOpacity: dockingTicket
                            ? ((t - 0.58) / 0.32).clamp(0.0, 1.0)
                            : 1,
                        scale: dockingTicket ? 1 : 0.76 + (0.24 * t),
                        enabled: widget.ticketEnabled,
                      ),
                      item(
                        id: 'settings',
                        label: widget.settingsLabel,
                        icon: const Icon(Icons.settings),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
