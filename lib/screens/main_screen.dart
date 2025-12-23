import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibration/vibration.dart';

import '../models/station.dart';
import '../models/journey.dart';
import '../models/friend.dart';
import '../services/transport_api.dart';
import '../services/history_manager.dart';
import '../services/supabase_service.dart';
import '../utils/painters.dart';

class MainScreen extends StatefulWidget {
  final Function(bool) onThemeChanged;
  final bool isDarkMode;

  const MainScreen({super.key, required this.onThemeChanged, required this.isDarkMode});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final List<RouteTab> _tabs = [];
  String? _activeTabId;

  // Search State
  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _toController = TextEditingController();
  Station? _fromStation;
  Station? _toStation;
  List<Station> _suggestions = [];
  String _activeSearchField = '';
  Timer? _debounce;
  bool _isLoadingRoute = false;
  bool _isSuggestionsLoading = false;
  
  // Auth State
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  
  // Nahverkehr Filter
  bool _onlyNahverkehr = true; 

  // Location State
  Position? _currentPosition;
  bool _gettingLocation = true;

  // Notifications
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _determinePosition();
    _initNotifications();
    _startRoutineMonitor();
    _fetchSuggestions(forceHistory: true);
    
    // Update location periodically
    Timer.periodic(const Duration(minutes: 2), (timer) {
      if (_currentPosition != null && SupabaseService.currentUser != null) {
        SupabaseService.updateLocation(_currentPosition!);
      }
    });
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  // --- NOTIFICATIONS & ROUTINE ---
  Future<void> _initNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    final LinuxInitializationSettings initializationSettingsLinux =
    LinuxInitializationSettings(defaultActionName: 'Open notification');

    final InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: const DarwinInitializationSettings(),
      linux: initializationSettingsLinux,
    );

    await _flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  void _startRoutineMonitor() {
    Timer(const Duration(seconds: 30), () async {});
  }

  Future<void> _showNotification({required int id, required String title, required String body}) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
    AndroidNotificationDetails('trans_channel', 'Trans Alerts',
        channelDescription: 'Transport notifications',
        importance: Importance.max,
        priority: Priority.high);

    const NotificationDetails platformChannelSpecifics =
    NotificationDetails(android: androidPlatformChannelSpecifics);

    await _flutterLocalNotificationsPlugin.show(id, title, body, platformChannelSpecifics);
  }

  Future<void> _triggerVibration() async {
    try {
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(pattern: [500, 1000, 500, 1000]);
      }
    } catch (e) {
      debugPrint("Vibration error: $e");
    }
  }

  // --- LOCATION ---
  Future<void> _determinePosition() async {
    if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      _useMockLocation();
      return;
    }

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw 'Location services are disabled.';

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) throw 'Location permissions are denied';
      }

      if (permission == LocationPermission.deniedForever) throw 'Location permissions are permanently denied';

      final pos = await Geolocator.getCurrentPosition(timeLimit: const Duration(seconds: 5));

      if (mounted) {
        setState(() {
          _currentPosition = pos;
          _gettingLocation = false;
        });
        SupabaseService.updateLocation(pos);
      }
    } catch (e) {
      if (mounted) {
        _useMockLocation();
      }
    }
  }

  void _useMockLocation() {
    setState(() {
      _gettingLocation = false;
      _currentPosition = Position(
          longitude: 8.24, latitude: 50.07, timestamp: DateTime.now(),
          accuracy: 0, altitude: 0, heading: 0, speed: 0, speedAccuracy: 0,
          altitudeAccuracy: 0, headingAccuracy: 0
      );
    });
  }

  // --- SEARCH & SUGGESTIONS ---
  Future<void> _fetchSuggestions({bool forceHistory = false}) async {
    if (forceHistory) {
      final history = await SearchHistoryManager.getHistory();
      if (mounted) setState(() => _suggestions = history);
      return;
    }

    setState(() => _isSuggestionsLoading = true);
    List<Station> results = [];
    final history = await SearchHistoryManager.getHistory();
    if (history.isNotEmpty) results.addAll(history);

    if (_currentPosition != null && _activeSearchField == 'from') {
      final nearby = await TransportApi.getNearbyStops(_currentPosition!.latitude, _currentPosition!.longitude);
      for (var s in nearby) {
        if (!results.any((h) => h.id == s.id)) results.insert(0, s);
      }
    }

    if (mounted) setState(() { _suggestions = results; _isSuggestionsLoading = false; });
  }

  void _onSearchChanged(String query, String field) {
    setState(() => _activeSearchField = field);
    if (query.isEmpty) {
      _fetchSuggestions();
      return;
    }
    setState(() => _isSuggestionsLoading = true);
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (query.length > 2) {
        double? refLat = _currentPosition?.latitude;
        double? refLng = _currentPosition?.longitude;
        if (field == 'to' && _fromStation != null) {
          refLat = _fromStation!.latitude;
          refLng = _fromStation!.longitude;
        } else if (field == 'from' && _toStation != null) {
          refLat = _toStation!.latitude;
          refLng = _toStation!.longitude;
        }

        final results = await TransportApi.searchStations(query, lat: refLat, lng: refLng);
        if (mounted) setState(() { _suggestions = results; _isSuggestionsLoading = false; });
      } else {
        if (mounted) setState(() { _suggestions = []; _isSuggestionsLoading = false; });
      }
    });
  }

  void _onFieldTap(String field) {
    setState(() => _activeSearchField = field);
    if ((field == 'from' && _fromController.text.isEmpty) || (field == 'to' && _toController.text.isEmpty)) {
      _fetchSuggestions();
    }
  }

  void _selectStation(Station station) {
    SearchHistoryManager.saveStation(station);
    setState(() {
      if (_activeSearchField == 'from') {
        _fromStation = station;
        _fromController.text = station.name;
      } else {
        _toStation = station;
        _toController.text = station.name;
      }
      _suggestions = [];
      _activeSearchField = '';
    });
    FocusScope.of(context).unfocus();
  }

  Future<void> _findRoutes() async {
    if (_fromStation == null || _toStation == null) return;
    setState(() => _isLoadingRoute = true);

    try {
      final journeyData = await TransportApi.searchJourney(
          _fromStation!.id, 
          _toStation!.id, 
          nahverkehrOnly: _onlyNahverkehr
      );

      if (journeyData != null && journeyData['legs'] != null) {
        final List legs = journeyData['legs'];
        final List<JourneyStep> steps = [];
        final random = Random();

        for (var leg in legs) {
          final mode = leg['mode'] ?? 'transport';
          String lineName = 'Transport';
          if (leg['line'] != null && leg['line']['name'] != null) {
            lineName = leg['line']['name'].toString();
          } else {
            String rawMode = mode.toString().toUpperCase();
            lineName = rawMode == 'TRANSPORT' ? 'Train' : rawMode;
          }

          String destName = 'Destination';
          if (leg['destination'] != null && leg['destination']['name'] != null) {
            destName = leg['destination']['name'].toString();
          }

          String? platform;
          if (leg['platform'] != null) platform = "Plat ${leg['platform']}";
          else if (leg['departurePlatform'] != null) platform = "Plat ${leg['departurePlatform']}";

          String? startStationId;
          if (leg['origin'] != null && leg['origin']['id'] != null) {
            startStationId = leg['origin']['id'];
          }

          final depStr = leg['departure'] as String?;
          final arrStr = leg['arrival'] as String?;
          if (depStr == null || arrStr == null) continue;

          DateTime dep = DateTime.parse(depStr);
          DateTime arr = DateTime.parse(arrStr);
          int durationMin = arr.difference(dep).inMinutes;

          String? alert;
          String? seating;
          int? chatCount;
          bool isBus = lineName.toLowerCase().contains('bus');
          bool isWalk = mode == 'walking';
          bool isTrain = !isBus && !isWalk;
          
          String direction = leg['direction'] ?? '';
          bool isTerminating = direction.toLowerCase() == destName.toLowerCase();
          if ((isBus || isTrain) && !isTerminating) {
            seating = random.nextBool() ? "Front (Quick Exit)" : "Back (More Space)";
          }

          if (!isWalk) {
            chatCount = random.nextInt(15) + 1;
          }

          steps.add(JourneyStep(
            type: isWalk ? 'walk' : 'ride',
            line: lineName,
            instruction: isWalk ? "Walk to $destName" : "$lineName to $destName",
            duration: "$durationMin min",
            departureTime: "${dep.hour.toString().padLeft(2, '0')}:${dep.minute.toString().padLeft(2, '0')}",
            alert: alert,
            seating: seating,
            chatCount: chatCount,
            startStationId: startStationId,
            platform: platform,
          ));
        }

        final newTabId = DateTime.now().millisecondsSinceEpoch.toString();
        String eta = "--:--";
        if (journeyData['arrival'] != null) {
          final arr = DateTime.parse(journeyData['arrival']);
          eta = "${arr.hour.toString().padLeft(2, '0')}:${arr.minute.toString().padLeft(2, '0')}";
        }

        final newTab = RouteTab(
          id: newTabId,
          title: _toStation!.name,
          subtitle: "${_fromStation!.name} → ${_toStation!.name}",
          eta: eta,
          steps: steps,
        );

        setState(() {
          _tabs.add(newTab);
          _activeTabId = newTabId;
          _fromStation = null;
          _toStation = null;
          _fromController.clear();
          _toController.clear();
          _isLoadingRoute = false;
        });
      } else {
        setState(() => _isLoadingRoute = false);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No routes found.")));
      }
    } catch (e) {
      setState(() => _isLoadingRoute = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error finding routes.")));
    }
  }

  void _closeTab(String id) {
    setState(() {
      _tabs.removeWhere((t) => t.id == id);
      if (_activeTabId == id) {
        _activeTabId = _tabs.isNotEmpty ? _tabs.last.id : null;
      }
    });
  }

  // --- FRIENDS & ADD USER LOGIC ---

  void _showAddFriendSheet(BuildContext context) async {
    final profile = await SupabaseService.getCurrentProfile();
    final myUsername = profile != null ? profile['username'] : 'Unknown';
    final searchCtrl = TextEditingController();
    List<Map<String, dynamic>> searchResults = [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Container(
              height: 500,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade600, borderRadius: BorderRadius.circular(2)), margin: const EdgeInsets.only(bottom: 20)),
                  Text("Add Friends", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
                  const SizedBox(height: 16),
                  
                  // INVITE LINK SECTION
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Theme.of(context).primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Your Username", style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodyLarge?.color?.withOpacity(0.7))),
                              Text("@$myUsername", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, color: Colors.blue),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: "Add me on Trans App! My username is @$myUsername"));
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invite text copied!")));
                          },
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // SEARCH SECTION
                  TextField(
                    controller: searchCtrl,
                    style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
                    decoration: InputDecoration(
                      hintText: "Search by username...",
                      hintStyle: TextStyle(color: Colors.grey.shade600),
                      filled: true,
                      fillColor: Theme.of(context).scaffoldBackgroundColor,
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.arrow_forward, color: Colors.blue),
                        onPressed: () async {
                          final res = await SupabaseService.searchUsers(searchCtrl.text);
                          setSheetState(() => searchResults = res);
                        },
                      )
                    ),
                    onSubmitted: (val) async {
                      final res = await SupabaseService.searchUsers(val);
                      setSheetState(() => searchResults = res);
                    },
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.separated(
                      itemCount: searchResults.length,
                      separatorBuilder: (_,__) => const Divider(color: Colors.white10),
                      itemBuilder: (ctx, idx) {
                        final user = searchResults[idx];
                        return ListTile(
                          leading: CircleAvatar(child: Text(user['username'][0].toUpperCase())),
                          title: Text(user['username'], style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
                          trailing: IconButton(
                            icon: const Icon(Icons.person_add, color: Colors.green),
                            onPressed: () async {
                              try {
                                await SupabaseService.addFriend(user['id']);
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Added @${user['username']}!")));
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
                              }
                            },
                          ),
                        );
                      },
                    ),
                  )
                ],
              ),
            ),
          );
        }
      ),
    );
  }

  // --- OVERLAYS: CHAT & GUIDE ---

  void _showChat(BuildContext context, String lineName) {
    final msgController = TextEditingController();
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          height: 600,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade600, borderRadius: BorderRadius.circular(2)), margin: const EdgeInsets.only(bottom: 20)),
              Text("Chat: $lineName", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
              const SizedBox(height: 16),
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: SupabaseService.getMessages(lineName),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return Center(child: Text("No messages yet.", style: TextStyle(color: Colors.grey.shade600)));
                    }
                    
                    final msgs = snapshot.data!;
                    return ListView.builder(
                      reverse: false,
                      itemCount: msgs.length,
                      itemBuilder: (context, index) {
                        final msg = msgs[index];
                        return _buildChatMessage(
                           msg['user_id'].toString().substring(0, 4), 
                           msg['content'], 
                           "Now", 
                           Colors.blue
                        );
                      },
                    );
                  },
                ),
              ),
              if (SupabaseService.currentUser == null)
                const Padding(padding: EdgeInsets.all(8.0), child: Text("Log in to chat", style: TextStyle(color: Colors.grey)))
              else
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: msgController,
                        style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
                        decoration: InputDecoration(
                          hintText: "Message...",
                          hintStyle: TextStyle(color: Colors.grey.shade600),
                          filled: true,
                          fillColor: Theme.of(context).scaffoldBackgroundColor,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send, color: Colors.indigoAccent),
                      onPressed: () {
                         if (msgController.text.isNotEmpty) {
                           SupabaseService.sendMessage(lineName, msgController.text);
                           msgController.clear();
                         }
                      },
                    )
                  ],
                )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatMessage(String user, String text, String time, Color color) {
    final textColor = Theme.of(context).textTheme.bodyMedium?.color;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(backgroundColor: color, radius: 16, child: Text(user[0].toUpperCase(), style: const TextStyle(color: Colors.white))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [Text(user, style: TextStyle(color: textColor?.withOpacity(0.7), fontWeight: FontWeight.bold, fontSize: 12)), const SizedBox(width: 8), Text(time, style: const TextStyle(color: Colors.grey, fontSize: 10))]),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Theme.of(context).primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                  child: Text(text, style: TextStyle(color: textColor, fontSize: 14)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showGuide(BuildContext context, String? startStationId) {
    if (startStationId == null) return;
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text("Station Guide", style: TextStyle(color: Theme.of(ctx).textTheme.bodyLarge?.color)),
        content: FutureBuilder<String?>(
          future: SupabaseService.getStationImage(startStationId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()));
            final imageUrl = snapshot.data;
            if (imageUrl == null) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.image_not_supported, size: 40, color: Colors.grey),
                  const SizedBox(height: 10),
                  const Text("No guide image found for this stop.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                ],
              );
            }
            return ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(imageUrl, fit: BoxFit.cover, height: 200),
            );
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close", style: TextStyle(color: Colors.indigoAccent))),
        ],
      ),
    );
  }

  // --- UI BUILDING BLOCKS ---

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        elevation: 0,
        flexibleSpace: ClipRect(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: Container(color: Colors.transparent))),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFFA855F7)]), borderRadius: BorderRadius.circular(8)),
              child: Image.asset('assets/icon.png', width: 24, height: 24),
            ),
            const SizedBox(width: 10),
            Text("Trans", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: isDark ? Colors.white : Colors.black)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_onlyNahverkehr ? Icons.directions_bus : Icons.train, color: _onlyNahverkehr ? Colors.greenAccent : Colors.grey),
            tooltip: _onlyNahverkehr ? "Deutschlandticket Mode (On)" : "All Trains",
            onPressed: () {
              setState(() => _onlyNahverkehr = !_onlyNahverkehr);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_onlyNahverkehr ? "Deutschlandticket Mode: On" : "All Trains Allowed")));
            },
          ),
          if (_gettingLocation) const Padding(padding: EdgeInsets.only(right: 16), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
        ],
      ),
      body: Stack(
        children: [
          _buildBody(),
          if (_isLoadingRoute) Container(color: Colors.black54, child: const Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5)))),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(border: const Border(top: BorderSide(color: Colors.white10)), color: Theme.of(context).cardColor),
        child: BottomNavigationBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: const Color(0xFF6366F1),
          unselectedItemColor: Colors.grey,
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

  Widget _buildBody() {
    if (_currentIndex == 1) return _buildFriendsView();
    if (_currentIndex == 2) return _buildSettingsView();
    
    return Column(
      children: [
        const SizedBox(height: 100),
        if (_tabs.isNotEmpty)
          SizedBox(
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _tabs.length + 1,
              itemBuilder: (ctx, idx) {
                if (idx == _tabs.length) return IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => setState(() => _activeTabId = null));
                final tab = _tabs[idx];
                final isActive = tab.id == _activeTabId;
                return GestureDetector(
                  onTap: () => setState(() => _activeTabId = tab.id),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isActive ? const Color(0xFF4F46E5) : Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.directions, size: 16, color: isActive ? Colors.white : Colors.grey),
                        const SizedBox(width: 6),
                        Text(tab.title, style: TextStyle(color: isActive ? Colors.white : Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(width: 4),
                        GestureDetector(onTap: () => _closeTab(tab.id), child: Icon(Icons.close, size: 14, color: isActive ? Colors.white70 : Colors.grey))
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        Expanded(
          child: _activeTabId == null ? _buildSearchView() : _buildActiveRouteView(_tabs.firstWhere((t) => t.id == _activeTabId)),
        ),
      ],
    );
  }

  Widget _buildFriendsView() {
    final textColor = Theme.of(context).textTheme.bodyLarge?.color;
    
    return Column(
      children: [
        const SizedBox(height: 100),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Friends Live", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor)),
              if (SupabaseService.currentUser != null)
                IconButton(
                  icon: const Icon(Icons.person_add, color: Colors.blue),
                  onPressed: () => _showAddFriendSheet(context),
                )
            ],
          ),
        ),
        
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: SupabaseService.streamUsersLocations(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              
              final locations = snapshot.data!;
              if (locations.isEmpty) {
                 return Center(child: Text("No friends active.", style: TextStyle(color: Colors.grey.shade600)));
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: locations.length,
                itemBuilder: (ctx, idx) {
                  final loc = locations[idx];
                  final userId = loc['user_id'];
                  double dist = 0;
                  if (_currentPosition != null) {
                    dist = Geolocator.distanceBetween(_currentPosition!.latitude, _currentPosition!.longitude, loc['latitude'], loc['longitude']);
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10)
                    ),
                    child: Row(
                      children: [
                        Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.blue.withOpacity(0.2), shape: BoxShape.circle), child: const Center(child: Icon(Icons.person, color: Colors.blue))),
                        const SizedBox(width: 16),
                        FutureBuilder<String?>(
                          future: SupabaseService.getUsername(userId),
                          builder: (context, snap) {
                            final name = snap.data ?? "User ${userId.toString().substring(0,4)}";
                            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)), 
                              const SizedBox(height: 2), 
                              Text("${(dist/1000).toStringAsFixed(1)} km away", style: const TextStyle(fontSize: 12, color: Colors.grey))
                            ]);
                          }
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsView() {
    final isDark = widget.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black;
    final user = SupabaseService.currentUser;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 100),
          Text("Settings", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: textColor)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                SwitchListTile(
                  title: Text("Dark Mode", style: TextStyle(color: textColor)),
                  value: widget.isDarkMode,
                  onChanged: widget.onThemeChanged,
                ),
                SwitchListTile(
                  title: Text("Deutschlandticket Mode", style: TextStyle(color: textColor)),
                  subtitle: const Text("Only local/regional transport", style: TextStyle(fontSize: 12, color: Colors.grey)),
                  value: _onlyNahverkehr,
                  onChanged: (val) => setState(() => _onlyNahverkehr = val),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // AUTH SECTION
          if (user != null) 
             ListTile(
               title: Text("Logged in as ${user.email}", style: TextStyle(color: textColor)),
               trailing: IconButton(icon: const Icon(Icons.logout, color: Colors.red), onPressed: () {
                 SupabaseService.signOut();
                 setState((){});
               }),
             )
          else 
             Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    Text("Login / Sign Up", style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    TextField(controller: _emailController, decoration: const InputDecoration(hintText: "Email")),
                    const SizedBox(height: 10),
                    TextField(controller: _usernameController, decoration: const InputDecoration(hintText: "Username (for Sign Up)")),
                    const SizedBox(height: 10),
                    TextField(controller: _passwordController, obscureText: true, decoration: const InputDecoration(hintText: "Password")),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton(onPressed: () async {
                           if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
                             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enter email & password")));
                             return;
                           }
                           try {
                             await SupabaseService.signIn(_emailController.text, _passwordController.text);
                             setState((){});
                           } catch (e) {
                             ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
                           }
                        }, child: const Text("Login")),
                        
                        TextButton(onPressed: () async {
                           if (_emailController.text.isEmpty || _passwordController.text.isEmpty || _usernameController.text.isEmpty) {
                             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enter all fields")));
                             return;
                           }
                           try {
                             await SupabaseService.signUp(_emailController.text, _passwordController.text, _usernameController.text);
                             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Account created!")));
                             setState((){});
                           } catch (e) {
                             ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
                           }
                        }, child: const Text("Sign Up")),
                      ],
                    )
                  ],
                ),
             )
        ],
      ),
    );
  }

  Widget _buildSearchView() {
    final textColor = Theme.of(context).textTheme.bodyLarge?.color;
    final cardColor = Theme.of(context).cardColor;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: cardColor.withOpacity(0.9), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white10)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.2), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.search, color: Colors.indigoAccent)), const SizedBox(width: 12), Text("Plan Journey", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor))]),
                  const SizedBox(height: 20),
                  _buildTextField("From", _fromController, _fromStation != null, 'from'),
                  if (_activeSearchField == 'from') _buildSuggestionsList(),
                  const SizedBox(height: 12),
                  _buildTextField("To", _toController, _toStation != null, 'to'),
                  if (_activeSearchField == 'to') _buildSuggestionsList(),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: (_fromStation != null && _toStation != null && !_isLoadingRoute) ? _findRoutes : null,
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                      child: _isLoadingRoute ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text("Find Routes", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionsList() {
    if (!_isSuggestionsLoading && _suggestions.isEmpty) return const SizedBox.shrink();
    final textColor = Theme.of(context).textTheme.bodyLarge?.color;
    final cardColor = Theme.of(context).cardColor;

    return Container(
      constraints: const BoxConstraints(maxHeight: 250),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isSuggestionsLoading) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator(minHeight: 2)),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _suggestions.length,
              separatorBuilder: (ctx, idx) => const Divider(height: 1, color: Colors.white10),
              itemBuilder: (ctx, idx) {
                final station = _suggestions[idx];
                return ListTile(
                  leading: const Icon(Icons.place, size: 16, color: Colors.grey),
                  title: Text(station.name, style: TextStyle(color: textColor, fontSize: 14)),
                  onTap: () => _selectStation(station),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, bool isSelected, String fieldKey) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(left: 4, bottom: 4), child: Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold))),
        TextField(
          controller: controller, onChanged: (val) => _onSearchChanged(val, fieldKey), onTap: () => _onFieldTap(fieldKey),
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
          decoration: InputDecoration(
            filled: true, fillColor: isDark ? const Color(0xFF1F2937) : Colors.grey.shade200,
            prefixIcon: Icon(fieldKey == 'from' ? Icons.my_location : Icons.location_on, color: isSelected ? Colors.greenAccent : Colors.grey, size: 20),
            hintText: "Station...",
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }

  Widget _buildActiveRouteView(RouteTab route) {
    final textColor = Theme.of(context).textTheme.bodyLarge?.color;
    final cardColor = Theme.of(context).cardColor;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(route.title, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor)),
        Text(route.subtitle, style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 20),
        ...route.steps.map((step) {
          final bool isRide = step.type == 'ride';
          if (!isRide) {
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [Icon(Icons.directions_walk, color: Colors.grey), SizedBox(width: 16), Expanded(child: Text(step.instruction, style: TextStyle(color: textColor)))]),
            );
          }
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(step.instruction, style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
              Text(step.line, style: const TextStyle(color: Colors.grey)),
              if (step.platform != null) Text(step.platform!, style: const TextStyle(color: Colors.greenAccent, fontSize: 12)),
              
              // RE-ADDED: Row with Chat, Guide, Wake Me, and Alternatives
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // Chat
                      GestureDetector(
                        onTap: () => _showChat(context, step.line),
                        child: _buildActionChip(Icons.chat_bubble_outline, "Chat"),
                      ),
                      const SizedBox(width: 8),

                      // Guide (only if not a bus)
                      if (!step.line.toLowerCase().contains('bus')) ...[
                        GestureDetector(
                          onTap: () => _showGuide(context, step.startStationId),
                          child: _buildActionChip(Icons.camera_alt_outlined, "Guide"),
                        ),
                        const SizedBox(width: 8),
                      ],

                      // Wake Me (Vibration)
                      GestureDetector(
                        onTap: () {
                          Timer(const Duration(seconds: 2), _triggerVibration);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Wake alarm set for next stop!")));
                        },
                        child: _buildActionChip(Icons.vibration, "Wake Me"),
                      ),
                      const SizedBox(width: 8),

                      // Alternatives (Departures)
                      if (step.startStationId != null)
                        GestureDetector(
                          onTap: () => _showAlternatives(context, step.startStationId!),
                          child: _buildActionChip(Icons.alt_route, "Alternatives"),
                        ),
                    ],
                  ),
                ),
              )
            ]),
          );
        }).toList()
      ],
    );
  }

  Widget _buildActionChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: Colors.grey.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
      child: Row(children: [Icon(icon, size: 14, color: Colors.grey), const SizedBox(width: 6), Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12))]),
    );
  }
  
  void _showAlternatives(BuildContext context, String stationId) {
     showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      builder: (ctx) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: TransportApi.getDepartures(stationId, nahverkehrOnly: _onlyNahverkehr),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (!snapshot.hasData || snapshot.data!.isEmpty) return Center(child: Text("No alternatives found.", style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)));

            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Alternative Connections", style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.separated(
                      itemCount: snapshot.data!.length,
                      separatorBuilder: (_,__) => const Divider(color: Colors.white10),
                      itemBuilder: (ctx, idx) {
                        final dep = snapshot.data![idx];
                        final line = dep['line']['name'] ?? 'Unknown';
                        final dir = dep['direction'] ?? 'Unknown';
                        final planned = DateTime.parse(dep['plannedWhen']);
                        final time = "${planned.hour.toString().padLeft(2,'0')}:${planned.minute.toString().padLeft(2,'0')}";
                        
                        return ListTile(
                          leading: const Icon(Icons.directions_bus, color: Colors.grey),
                          title: Text("$line to $dir", style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
                          trailing: Text(time, style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color, fontWeight: FontWeight.bold)),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}