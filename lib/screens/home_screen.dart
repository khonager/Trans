import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'tabs/routes_tab.dart';
import 'tabs/friends_tab.dart';
import 'tabs/settings_tab.dart';
import '../services/supabase_service.dart';

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
    // Check permissions and get position (Copy logic from original file)
    // For brevity:
    try {
      final pos = await Geolocator.getCurrentPosition();
      setState(() => _currentPosition = pos);
      SupabaseService.updateLocation(pos);
    } catch (e) {
      debugPrint("Loc error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        flexibleSpace: ClipRect(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: Container(color: Colors.transparent))),
        title: const Text("Trans"),
        elevation: 0,
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          RoutesTab(currentPosition: _currentPosition, onlyNahverkehr: _onlyNahverkehr),
          FriendsTab(currentPosition: _currentPosition),
          SettingsTab(
            isDarkMode: widget.isDarkMode,
            onThemeChanged: widget.onThemeChanged,
            onlyNahverkehr: _onlyNahverkehr,
            onNahverkehrChanged: (val) => setState(() => _onlyNahverkehr = val),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (idx) => setState(() => _currentIndex = idx),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.alt_route), label: 'Routes'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Friends'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}