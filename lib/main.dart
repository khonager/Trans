import 'dart:async';
import 'dart:convert';
import 'dart:io'; 
import 'dart:math';
import 'dart:ui'; 
import 'package:flutter/foundation.dart'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
// NEW PACKAGES
import 'package:vibration/vibration.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// --- 1. MODELS & DATA ---

class Station {
  final String id;
  final String name;
  final double? distance;

  Station({required this.id, required this.name, this.distance});

  factory Station.fromJson(Map<String, dynamic> json) {
    String name = json['name'] ?? 'Unknown Station';
    if (json['location'] != null && json['location']['name'] != null) {
       name = json['location']['name'];
    }
    return Station(
      id: json['id']?.toString() ?? '',
      name: name,
      distance: json['distance'] != null ? (json['distance'] as num).toDouble() : null,
    );
  }
}

class JourneyStep {
  final String type; // 'walk', 'ride', 'wait'
  final String line;
  final String instruction;
  final String duration;
  final String departureTime;
  final String? alert; 
  final String? seating;
  final int? chatCount;
  final String? startStationId; // Added to fetch alternatives

  JourneyStep({
    required this.type,
    required this.line,
    required this.instruction,
    required this.duration,
    required this.departureTime,
    this.alert,
    this.seating,
    this.chatCount,
    this.startStationId,
  });
}

class RouteTab {
  final String id;
  final String title;
  final String subtitle;
  final String eta;
  final List<JourneyStep> steps;

  RouteTab({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.eta,
    required this.steps,
  });
}

class Friend {
  final String name;
  final String status;
  final Color color;
  final double top;
  final double left;

  Friend(this.name, this.status, this.color, this.top, this.left);
}

// --- 2. API SERVICE ---

class TransportApi {
  static const String _baseUrl = 'https://v6.db.transport.rest';

  static Future<List<Station>> searchStations(String query, {double? lat, double? lng}) async {
    if (query.length < 2) return [];
    try {
      String url = '$_baseUrl/locations?query=${Uri.encodeComponent(query)}&results=5';
      if (lat != null && lng != null) {
        url += '&latitude=$lat&longitude=$lng'; 
      }
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        return data
            .where((d) => d['type'] == 'station' || d['type'] == 'stop')
            .map((json) => Station.fromJson(json))
            .toList();
      }
    } catch (e) {
      debugPrint("Error fetching stations: $e");
    }
    return [];
  }

  static Future<List<Station>> getNearbyStops(double lat, double lng) async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/stops/nearby?latitude=$lat&longitude=$lng&results=3'));
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        return data.map((json) => Station.fromJson(json)).toList();
      }
    } catch (e) {
      debugPrint("Error fetching nearby: $e");
    }
    return [];
  }

  static Future<Map<String, dynamic>?> searchJourney(String fromId, String toId) async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/journeys?from=$fromId&to=$toId&results=1'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['journeys'] != null && (data['journeys'] as List).isNotEmpty) {
          return data['journeys'][0];
        }
      }
    } catch (e) {
      debugPrint("Error fetching journey: $e");
    }
    return null;
  }

  // NEW: Fetch alternatives (Departures) for a specific stop
  static Future<List<Map<String, dynamic>>> getDepartures(String stationId) async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/stops/$stationId/departures?results=5&duration=20'));
      if (response.statusCode == 200) {
         final data = json.decode(response.body);
         if (data['departures'] != null) {
           return List<Map<String, dynamic>>.from(data['departures']);
         }
      }
    } catch (e) {
      debugPrint("Error fetching departures: $e");
    }
    return [];
  }
}

// --- 3. MAIN APP ---

void main() {
  runApp(const TransApp());
}

class TransApp extends StatelessWidget {
  const TransApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trans',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF000000),
        primaryColor: const Color(0xFF4F46E5),
        cardColor: const Color(0xFF111827),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

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
  bool _isLoading = false;

  // Location State
  Position? _currentPosition;
  bool _gettingLocation = true;

  // Notifications
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  // Mock Data
  final List<Friend> _friends = [
    Friend('Alex', 'On Bus 42 • 5 min away', Colors.blue, 40, 10),
    Friend('Sarah', 'Waiting at Central St.', Colors.green, 50, 60),
    Friend('Mike', 'On Tram 10 • Arriving soon', Colors.purple, 20, 80),
    Friend('Jessica', 'Walking to Station', Colors.orange, 70, 30),
    Friend('David', 'On U3 • Late', Colors.red, 10, 40),
  ];

  @override
  void initState() {
    super.initState();
    _determinePosition();
    _initNotifications();
    _startRoutineMonitor();
  }

  // --- NOTIFICATIONS & ROUTINE LOGIC ---
  
  Future<void> _initNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: DarwinInitializationSettings(),
    );
    await _flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  // FEATURE: Automatically notice routine transfers and notify
  void _startRoutineMonitor() {
    // Simulating a background check for a "Routine" connection (e.g. Home -> Work)
    Timer(const Duration(seconds: 10), () async {
      await _showNotification(
        id: 1, 
        title: "Routine Alert: Bus 42 Delayed", 
        body: "Your usual 08:30 bus is 5 min late. Consider taking Tram 10."
      );
    });
  }

  Future<void> _showNotification({required int id, required String title, required String body}) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails('trans_channel', 'Trans Alerts',
            channelDescription: 'Transport notifications',
            importance: Importance.max,
            priority: Priority.high,
            ticker: 'ticker');
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    await _flutterLocalNotificationsPlugin.show(id, title, body, platformChannelSpecifics);
  }

  Future<void> _triggerVibration() async {
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(pattern: [500, 1000, 500, 1000]);
    }
  }

  // --- LOCATION LOGIC ---
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
        _fetchNearbySuggestions();
      }
    } catch (e) {
      if (mounted) {
        debugPrint("Location Failed: $e. Using Mock.");
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
    _fetchNearbySuggestions();
  }

  Future<void> _fetchNearbySuggestions() async {
     if (_currentPosition == null) return;
     final nearby = await TransportApi.getNearbyStops(_currentPosition!.latitude, _currentPosition!.longitude);
     if (mounted && _activeSearchField == 'from' && _fromController.text.isEmpty) {
       setState(() { _suggestions = nearby; });
     }
  }

  // --- HANDLERS ---

  void _onSearchChanged(String query, String field) {
    setState(() => _activeSearchField = field);
    if (query.isEmpty && _currentPosition != null && field == 'from') {
       _fetchNearbySuggestions();
       return;
    }
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async { 
      if (query.length > 2) {
        final results = await TransportApi.searchStations(
          query, lat: _currentPosition?.latitude, lng: _currentPosition?.longitude
        );
        if (mounted) setState(() => _suggestions = results);
      } else {
        if (mounted) setState(() => _suggestions = []);
      }
    });
  }

  void _onFieldTap(String field) {
    setState(() => _activeSearchField = field);
    if ((field == 'from' && _fromController.text.isEmpty) || (field == 'to' && _toController.text.isEmpty)) {
      if (_currentPosition != null) _fetchNearbySuggestions();
    }
  }

  void _selectStation(Station station) {
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
    setState(() => _isLoading = true);

    try {
      final journeyData = await TransportApi.searchJourney(_fromStation!.id, _toStation!.id);

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

          // FEATURE: Suggest seating
          // Logic: Random for prototype, but enabled for all 'ride' steps
          if (isBus || isTrain) {
             seating = random.nextBool() ? "Front (Quick Exit)" : "Back (More Space)";
          }

          if (!isWalk) {
            if (random.nextDouble() > 0.8) alert = "Smart Alt: Delay ahead.";
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
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No routes found.")));
      }
    } catch (e) {
      setState(() => _isLoading = false);
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

  // --- OVERLAYS & DIALOGS ---

  void _showChat(BuildContext context, String lineName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111827),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          height: 500,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade800, borderRadius: BorderRadius.circular(2)), margin: const EdgeInsets.only(bottom: 20)),
              Row(
                children: [
                  Text("Chat: $lineName", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                  const Spacer(),
                  const Icon(Icons.people, size: 16, color: Colors.green),
                  const SizedBox(width: 4),
                  const Text("12 Online", style: TextStyle(color: Colors.green, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  children: [
                    _buildChatMessage("Traveler88", "Is it full in the back?", "10:02", Colors.blue),
                    _buildChatMessage("Commuter_Jane", "Yeah, standing room only.", "10:03", Colors.purple),
                  ],
                ),
              ),
              TextField(
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Message...",
                  hintStyle: TextStyle(color: Colors.grey.shade600),
                  filled: true,
                  fillColor: Colors.black,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  suffixIcon: const Icon(Icons.send, color: Colors.indigoAccent),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatMessage(String user, String text, String time, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(backgroundColor: color, radius: 16, child: Text(user[0], style: const TextStyle(color: Colors.white))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [Text(user, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12)), const SizedBox(width: 8), Text(time, style: const TextStyle(color: Colors.grey, fontSize: 10))]),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)),
                  child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 14)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showGuide(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text("Station Guide", style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 160,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: const Center(child: Icon(Icons.camera_alt, size: 40, color: Colors.grey)),
            ),
            const SizedBox(height: 16),
            const Text("Follow signs to Platform 4.\nUse escalator B to avoid the crowd.", style: TextStyle(color: Colors.grey), textAlign: TextAlign.center),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Got it", style: TextStyle(color: Colors.indigoAccent))),
        ],
      ),
    );
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: false, 
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.7),
        elevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: Container(color: Colors.transparent)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFFA855F7)]), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.bolt, size: 20, color: Colors.white),
            ),
            const SizedBox(width: 10),
            const Text("Trans", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          ],
        ),
        actions: [
           if (_gettingLocation) const Padding(padding: EdgeInsets.only(right: 16), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
           if (!_gettingLocation && _currentPosition != null) const Padding(padding: EdgeInsets.only(right: 16), child: Icon(Icons.location_on, color: Colors.greenAccent, size: 20)),
        ],
      ),
      body: Stack(
        children: [
          _buildBody(),
          if (_isLoading) Container(color: Colors.black54, child: const Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5)))),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.white10)), color: Color(0xFF0F0F10)),
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
    if (_currentIndex == 2) return const Center(child: Text("Settings", style: TextStyle(color: Colors.grey)));
    
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
                      color: isActive ? const Color(0xFF4F46E5) : const Color(0xFF1F2937),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.directions, size: 16, color: Colors.white),
                        const SizedBox(width: 6),
                        Text(tab.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(width: 4),
                        GestureDetector(onTap: () => _closeTab(tab.id), child: const Icon(Icons.close, size: 14, color: Colors.white70))
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
    return Column(
      children: [
        const SizedBox(height: 100),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Align(alignment: Alignment.centerLeft, child: Text("Friends Live", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white))),
        ),
        Container(
          height: 240,
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFF1F2937), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white10)),
          child: Stack(
            children: [
              Positioned.fill(child: Opacity(opacity: 0.1, child: CustomPaint(painter: _GridPainter()))),
              ..._friends.map((f) => Positioned(
                top: f.top * 2.2, left: f.left * 3.5,
                child: Column(
                  children: [
                    Container(
                      width: 32, height: 32, alignment: Alignment.center,
                      decoration: BoxDecoration(color: f.color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: f.color.withOpacity(0.5), blurRadius: 10, spreadRadius: 2)], border: Border.all(color: Colors.white, width: 2)),
                      child: Text(f.name[0], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                    ),
                  ],
                ),
              )),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _friends.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (ctx, idx) {
              final f = _friends[idx];
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFF1F2937).withOpacity(0.5), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
                child: Row(
                  children: [
                    Container(width: 40, height: 40, decoration: BoxDecoration(color: f.color.withOpacity(0.2), shape: BoxShape.circle), child: Center(child: Text(f.name[0], style: TextStyle(color: f.color, fontWeight: FontWeight.bold)))),
                    const SizedBox(width: 16),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(f.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)), const SizedBox(height: 2), Text(f.status, style: const TextStyle(fontSize: 12, color: Colors.grey))]),
                    const Spacer(),
                    IconButton(icon: const Icon(Icons.chat_bubble_outline, size: 20, color: Colors.grey), onPressed: (){})
                  ],
                ),
              );
            },
          ),
        )
      ],
    );
  }

  Widget _buildSearchView() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: const Color(0xFF111827).withOpacity(0.8), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white10)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.2), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.search, color: Colors.indigoAccent)), const SizedBox(width: 12), const Text("Plan Journey", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white))]),
                  const SizedBox(height: 20),
                  _buildTextField("From", _fromController, _fromStation != null, 'from'),
                  const SizedBox(height: 12),
                  _buildTextField("To", _toController, _toStation != null, 'to'),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: (_fromStation != null && _toStation != null && !_isLoading) ? _findRoutes : null,
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                      child: _isLoading ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text("Find Routes", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  )
                ],
              ),
            ),
            if (_suggestions.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(color: const Color(0xFF1F2937), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
                child: ListView.separated(
                  shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), padding: EdgeInsets.zero,
                  itemCount: _suggestions.length,
                  separatorBuilder: (ctx, idx) => const Divider(height: 1, color: Colors.white10),
                  itemBuilder: (ctx, idx) {
                    final station = _suggestions[idx];
                    return ListTile(
                      leading: station.distance != null ? const Icon(Icons.near_me, size: 16, color: Colors.greenAccent) : null,
                      title: Text(station.name, style: const TextStyle(color: Colors.white, fontSize: 14)),
                      trailing: station.distance != null ? Text("${station.distance!.toInt()}m", style: const TextStyle(color: Colors.grey, fontSize: 10)) : null,
                      onTap: () => _selectStation(station),
                    );
                  },
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, bool isSelected, String fieldKey) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(left: 4, bottom: 4), child: Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold))),
        TextField(
          controller: controller, onChanged: (val) => _onSearchChanged(val, fieldKey), onTap: () => _onFieldTap(fieldKey),
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true, fillColor: const Color(0xFF1F2937),
            prefixIcon: Icon(fieldKey == 'from' ? Icons.my_location : Icons.location_on, color: isSelected ? Colors.greenAccent : Colors.grey, size: 20),
            suffixIcon: _gettingLocation && fieldKey == 'from' ? const SizedBox(width: 10, height: 10, child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2))) : (isSelected ? const Icon(Icons.check_circle, color: Colors.greenAccent, size: 16) : null),
            hintText: fieldKey == 'from' && _currentPosition != null ? "Current Location" : "Station or City...",
            hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildActiveRouteView(RouteTab route) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(route.title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
        Text(route.subtitle, style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 20),
        ...route.steps.map((step) {
          final bool isRide = step.type == 'ride';
          
          if (!isRide) {
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(step.type == 'walk' ? Icons.directions_walk : Icons.compare_arrows, size: 20, color: Colors.grey),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(step.instruction, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                      Text(step.duration, style: const TextStyle(color: Colors.grey, fontSize: 12, fontFamily: 'Monospace')),
                    ]),
                  ),
                ],
              ),
            );
          }

          // Transport Card
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(child: Text(step.instruction, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white), overflow: TextOverflow.ellipsis)),
                Text(step.duration, style: const TextStyle(fontFamily: 'Monospace', color: Colors.grey)),
              ]),
              Text(step.line, style: const TextStyle(color: Colors.grey)),
              
              if (step.alert != null)
                Container(
                  margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.orange.withOpacity(0.15), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.withOpacity(0.3))),
                  child: Row(children: [const Icon(Icons.warning_amber, color: Colors.orange, size: 16), const SizedBox(width: 8), Expanded(child: Text(step.alert!, style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)))]),
                ),

              // FEATURE: Seating Suggestion UI
              if (step.seating != null)
                Container(
                  margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.blue.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.airline_seat_recline_extra, color: Colors.blueAccent, size: 16), const SizedBox(width: 8), Text("Sit: ${step.seating}", style: const TextStyle(color: Colors.blueAccent, fontSize: 12))]),
                ),

              // FEATURE: Alternatives & Wake Me
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // CHAT BUTTON
                      GestureDetector(
                        onTap: () => _showChat(context, step.line),
                        child: _buildActionChip(Icons.chat_bubble_outline, "Chat (${step.chatCount ?? 0})"),
                      ),
                      const SizedBox(width: 8),
                      
                      // GUIDE BUTTON
                      if (!step.line.toLowerCase().contains('bus'))
                        GestureDetector(
                          onTap: () => _showGuide(context),
                          child: _buildActionChip(Icons.camera_alt_outlined, "Guide"),
                        ),
                      if (!step.line.toLowerCase().contains('bus')) const SizedBox(width: 8),

                      // FEATURE: VIBRATE / WAKE ME
                      GestureDetector(
                        onTap: () {
                           // Mocking the "Next Stop" calculation for wake up
                           Timer(const Duration(seconds: 2), _triggerVibration);
                           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Wake alarm set for next stop!")));
                        },
                        child: _buildActionChip(Icons.vibration, "Wake Me"),
                      ),
                      const SizedBox(width: 8),

                      // FEATURE: CHECK ALTERNATIVES
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
      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20)),
      child: Row(children: [Icon(icon, size: 14, color: Colors.white70), const SizedBox(width: 6), Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12))]),
    );
  }

  void _showAlternatives(BuildContext context, String stationId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: TransportApi.getDepartures(stationId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("No alternatives found.", style: TextStyle(color: Colors.white)));

            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Alternative Connections", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
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
                        final delay = dep['delay'] != null ? (dep['delay'] / 60).round() : 0;
                        
                        return ListTile(
                          leading: const Icon(Icons.directions_bus, color: Colors.grey),
                          title: Text("$line to $dir", style: const TextStyle(color: Colors.white)),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(time, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              if (delay > 0) Text("+$delay min", style: const TextStyle(color: Colors.redAccent, fontSize: 12))
                              else const Text("On time", style: const TextStyle(color: Colors.greenAccent, fontSize: 12))
                            ],
                          ),
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

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withOpacity(0.1)..strokeWidth = 1;
    for (double i = 0; i < size.width; i += 20) canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    for (double i = 0; i < size.height; i += 20) canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}