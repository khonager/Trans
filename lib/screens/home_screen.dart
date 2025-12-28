import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:trans/services/supabase_service.dart';
import 'tabs/routes_tab.dart';
import 'tabs/friends_tab.dart';
import 'tabs/settings_tab.dart';
import '../widgets/ticket_panel.dart';
import '../config/app_theme.dart';

class HomeScreen extends StatefulWidget {
  final bool isDarkMode;
  final Function(bool) onThemeChanged;
  
  // NEW: Sync Logic
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
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _determinePosition();
  }

  Future<void> _determinePosition() async {
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
  }

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    final screens = [
      RoutesTab(
        currentPosition: _currentPosition, 
        onlyNahverkehr: widget.onlyNahverkehr
      ),
      FriendsTab(currentPosition: _currentPosition),
      SettingsTab(
        isDarkMode: widget.isDarkMode,
        onThemeChanged: widget.onThemeChanged,
        // Pass down
        useSystemTheme: widget.useSystemTheme,
        onSystemSyncChanged: widget.onSystemSyncChanged,
        
        onlyNahverkehr: widget.onlyNahverkehr,
        onNahverkehrChanged: widget.onNahverkehrChanged,
        isGhostMode: widget.isGhostMode,
        onGhostModeChanged: widget.onGhostModeChanged,
        onColorChanged: widget.onColorChanged,
        currentColor: widget.currentColor,
      ),
    ];

    return Scaffold(
      backgroundColor: colors.scaffoldBg,
      body: Stack(
        children: [
          screens[_currentIndex],
          const TicketPanel(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        backgroundColor: colors.navBarBg,
        indicatorColor: colors.navBarSelected,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.directions), label: 'Routes'),
          NavigationDestination(icon: Icon(Icons.people), label: 'Friends'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}