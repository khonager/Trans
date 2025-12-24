import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'tabs/routes_tab.dart';
import 'tabs/friends_tab.dart';
import 'tabs/settings_tab.dart';
import '../services/supabase_service.dart';
import '../widgets/ticket_panel.dart'; // Import the new widget

class HomeScreen extends StatefulWidget {
  final Function(bool) onThemeChanged;
  final bool isDarkMode;

  const HomeScreen({super.key, required this.onThemeChanged, required this.isDarkMode});

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
    _determinePosition();
    // Update location every 2 mins
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
      if (!serviceEnabled) {
        setState(() => _gettingLocation = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
           setState(() => _gettingLocation = false);
           return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
         setState(() => _gettingLocation = false);
         return;
      }

      final pos = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _currentPosition = pos;
          _gettingLocation = false;
        });
        SupabaseService.updateLocation(pos);
      }
    } catch (e) {
      if (mounted) setState(() => _gettingLocation = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: false, // Prevents bottom nav from jumping up
      appBar: AppBar(
        elevation: 0,
        // RESTORED: Blur effect
        flexibleSpace: ClipRect(
            child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(color: Colors.transparent))),
        title: Row(
          children: [
            // RESTORED: Gradient Logo
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFFA855F7)]),
                  borderRadius: BorderRadius.circular(8)),
              child: Image.asset('assets/icon.png', width: 24, height: 24, errorBuilder: (_,__,___) => const Icon(Icons.directions_transit, size: 24, color: Colors.white)),
            ),
            const SizedBox(width: 10),
            Text("Trans",
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: isDark ? Colors.white : Colors.black)),
          ],
        ),
        actions: [
          // RESTORED: Deutschlandticket Toggle in AppBar
          IconButton(
            icon: Icon(_onlyNahverkehr ? Icons.directions_bus : Icons.train,
                color: _onlyNahverkehr ? Colors.greenAccent : Colors.grey),
            tooltip: _onlyNahverkehr
                ? "Deutschlandticket Mode (On)"
                : "All Trains",
            onPressed: () {
              setState(() => _onlyNahverkehr = !_onlyNahverkehr);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(_onlyNahverkehr
                      ? "Deutschlandticket Mode: On"
                      : "All Trains Allowed")));
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
          // Main Content Layer
          IndexedStack(
            index: _currentIndex,
            children: [
              // ROUTES TAB
              RoutesTab(
                currentPosition: _currentPosition,
                onlyNahverkehr: _onlyNahverkehr,
              ),
              // FRIENDS TAB
              FriendsTab(currentPosition: _currentPosition),
              // SETTINGS TAB
              SettingsTab(
                isDarkMode: widget.isDarkMode,
                onThemeChanged: widget.onThemeChanged,
                onlyNahverkehr: _onlyNahverkehr,
                onNahverkehrChanged: (val) => setState(() => _onlyNahverkehr = val),
              ),
            ],
          ),

          // Ticket Layer (Floating above content, anchored to bottom of body)
          const TicketPanel(),
        ],
      ),
      // RESTORED: Bottom Nav Styling
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
            border: const Border(top: BorderSide(color: Colors.white10)),
            color: Theme.of(context).cardColor),
        child: BottomNavigationBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: const Color(0xFF6366F1),
          unselectedItemColor: Colors.grey,
          currentIndex: _currentIndex,
          onTap: (idx) => setState(() => _currentIndex = idx),
          items: const [
            BottomNavigationBarItem(
                icon: Icon(Icons.alt_route_outlined), label: 'Routes'),
            BottomNavigationBarItem(
                icon: Icon(Icons.people_outline), label: 'Friends'),
            BottomNavigationBarItem(
                icon: Icon(Icons.settings_outlined), label: 'Settings'),
          ],
        ),
      ),
    );
  }
}