import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart'; // Added import for persistence
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trans/services/supabase_service.dart';
import 'tabs/routes_tab.dart';
import 'tabs/friends_tab.dart';
import 'tabs/settings_tab.dart';
import '../widgets/ticket_panel.dart';
import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';

class HomeScreen extends StatefulWidget {
  final bool isDarkMode;
  final Function(bool) onThemeChanged;
  final bool useSystemTheme;
  final Function(bool) onSystemSyncChanged;
  final bool onlyNahverkehr;
  final Function(bool) onNahverkehrChanged;
  final bool isGhostMode;
  final Function(bool) onGhostModeChanged;
  final Function(Color) onColorChanged;
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
    required this.isGhostMode,
    required this.onGhostModeChanged,
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
  Position? _currentPosition;
  StreamSubscription<AuthState>? _authSubscription;
  final GlobalKey<RoutesTabState> _routesTabKey = GlobalKey<RoutesTabState>();
  bool _isShowingRecoveryDialog = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSavedTab(); // Load saved tab on startup
    _loadSettings(); // Load other settings
    _determinePosition();
    _setupAuthListener();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _showTrainNumbers = prefs.getBool('show_train_numbers') ?? false;
        _alwaysWakeMe = prefs.getBool('always_wake_me') ?? false;
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _determinePosition();
    }
  }

  void _setupAuthListener() {
    _authSubscription =
        SupabaseService.client.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      if (event == AuthChangeEvent.passwordRecovery) {
        _handlePasswordRecovery();
      }
    });
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
                        } catch (e) {
                          if (!dialogContext.mounted) return;
                          messenger.showSnackBar(
                              SnackBar(content: Text("Error: $e")));
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
    setState(() => _currentIndex = index);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('current_tab_index', index);
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

      if (!widget.isGhostMode) {
        SupabaseService.updateLocation(pos);
      }
    } catch (e) {
      debugPrint("Location Error (Ignored): $e");
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
      ),
      FriendsTab(currentPosition: _currentPosition),
      SettingsTab(
        isDarkMode: widget.isDarkMode,
        onThemeChanged: widget.onThemeChanged,
        useSystemTheme: widget.useSystemTheme,
        onSystemSyncChanged: widget.onSystemSyncChanged,
        onlyNahverkehr: widget.onlyNahverkehr,
        onNahverkehrChanged: widget.onNahverkehrChanged,
        isGhostMode: widget.isGhostMode,
        onGhostModeChanged: widget.onGhostModeChanged,
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
            destinations: [
              NavigationDestination(
                  icon: const Icon(Icons.directions),
                  label: AppLocalizations.of(context)!.routes),
              NavigationDestination(
                  icon: const Icon(Icons.people),
                  label: AppLocalizations.of(context)!.friends),
              NavigationDestination(
                  icon: const Icon(Icons.settings),
                  label: AppLocalizations.of(context)!.settings),
            ],
          ),
        ));
  }
}
