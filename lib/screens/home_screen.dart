import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'tabs/routes_tab.dart';
import 'tabs/friends_tab.dart';
import 'tabs/settings_tab.dart';
import '../services/supabase_service.dart';
import '../widgets/ticket_panel.dart'; 
import '../config/app_theme.dart';

class HomeScreen extends StatefulWidget {
  final Function(bool) onThemeChanged;
  final bool isDarkMode;
  final Function(Color) onColorChanged;
  final Color currentColor;

  const HomeScreen({
    super.key, 
    required this.onThemeChanged, 
    required this.isDarkMode,
    required this.onColorChanged,
    required this.currentColor,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  Position? _currentPosition;
  bool _onlyNahverkehr = true;
  Timer? _locationTimer;
  bool _gettingLocation = true; 

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 1), () {
      _determinePosition();
    });
    _locationTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (_currentPosition != null) SupabaseService.updateLocation(_currentPosition!);
    });
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    super.dispose();
  }

  Future<void> _determinePosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() => _currentPosition = pos);
        SupabaseService.updateLocation(pos);
      }
    } catch (e) {
      debugPrint("Location error: $e");
    } finally {
      if (mounted) setState(() => _gettingLocation = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: false,
      backgroundColor: colors.scaffoldBg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: colors.appBarBg,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: colors.appBarIconBg,
                  borderRadius: BorderRadius.circular(8)),
              child: Image.asset('assets/icon.png', width: 24, height: 24, errorBuilder: (_,__,___) => const Icon(Icons.directions_transit, size: 24, color: Colors.white)),
            ),
            const SizedBox(width: 10),
            Text("Trans",
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: colors.appBarTitle)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_onlyNahverkehr ? Icons.directions_bus : Icons.train,
                color: _onlyNahverkehr ? colors.appBarIconBg : Colors.grey),
            tooltip: _onlyNahverkehr ? "Deutschlandticket Mode (On)" : "All Trains",
            onPressed: () {
              setState(() => _onlyNahverkehr = !_onlyNahverkehr);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(_onlyNahverkehr ? "Deutschlandticket Mode: On" : "All Trains Allowed")));
            },
          ),
          if (_gettingLocation)
            const Padding(
                padding: EdgeInsets.only(right: 16),
                child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))),
        ],
      ),
      body: Stack(
        children: [
          _buildCurrentTab(),
          const TicketPanel(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.divider)),
            color: colors.navBarBg),
        child: BottomNavigationBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: colors.navBarSelected,
          unselectedItemColor: colors.navBarUnselected,
          currentIndex: _currentIndex,
          onTap: (idx) => setState(() => _currentIndex = idx),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.alt_route_outlined), label: 'Routes'),
            BottomNavigationBarItem(icon: Icon(Icons.people_outline), label: 'Friends'),
            BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: 'Settings'),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentTab() {
    switch (_currentIndex) {
      case 0:
        return RoutesTab(currentPosition: _currentPosition, onlyNahverkehr: _onlyNahverkehr);
      case 1:
        return FriendsTab(currentPosition: _currentPosition);
      case 2:
        return SettingsTab(
          isDarkMode: widget.isDarkMode,
          onThemeChanged: widget.onThemeChanged,
          onlyNahverkehr: _onlyNahverkehr,
          onNahverkehrChanged: (val) => setState(() => _onlyNahverkehr = val),
          currentColor: widget.currentColor,
          onColorChanged: widget.onColorChanged,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}