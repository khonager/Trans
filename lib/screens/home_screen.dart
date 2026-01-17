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
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  bool _showTrainNumbers = false; 
  Position? _currentPosition;
  StreamSubscription<AuthState>? _authSubscription;
  final GlobalKey<RoutesTabState> _routesTabKey = GlobalKey<RoutesTabState>();


  @override
  void initState() {
    super.initState();
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
      });
    }
  }

  Future<void> _updateShowTrainNumbers(bool value) async {
    setState(() => _showTrainNumbers = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_train_numbers', value);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  void _setupAuthListener() {
    _authSubscription = SupabaseService.client.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      if (event == AuthChangeEvent.passwordRecovery) {
        _handlePasswordRecovery();
      }
    });
  }

  void _handlePasswordRecovery() {
    // Switch to Settings Tab
    _onTabChanged(2); // 2 is SettingsTab index
    
    // Show Password Reset Dialog
    // We need to wait for the tab switch to settle or just show a global dialog
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text("Reset Password"),
          content: const Text("You have securely logged in via the password reset link. Please set a new password now."),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                // The user is already on the settings tab, they can use the profile edit form.
                // Optionally we could trigger the edit mode in SettingsTab if we had access to it,
                // but for now, directing them to the tab is a good start. 
                // We'll show a snackbar to guide them.
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Tap the 'Edit' icon in your profile to set a new password.")),
                );
              },
              child: const Text("OK"),
            ),
          ],
        ),
      );
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
      ),
    ];

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;

        // 1. Try to handle back in RoutesTab if it is active
        if (_currentIndex == 0 && (_routesTabKey.currentState?.handleBack() ?? false)) {
          return;
        }

        // 2. Otherwise ask to quit
        final shouldQuit = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Quit App?'),
            content: const Text('Do you want to exit the application?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('No'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Yes'),
              ),
            ],
          ),
        ) ?? false;

        if (shouldQuit) {
          if (context.mounted) {
            SystemNavigator.pop();
          }
        }
      },
      child: Scaffold(
      backgroundColor: colors.scaffoldBg,
      // REVERT: Set to false to keep Ticket Panel stable
      resizeToAvoidBottomInset: false, 
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
        onDestinationSelected: _onTabChanged, // Updated to use the new method
        backgroundColor: colors.navBarBg,
        indicatorColor: colors.navBarSelected,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.directions), label: 'Routes'),
          NavigationDestination(icon: Icon(Icons.people), label: 'Friends'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    ));
  }
}