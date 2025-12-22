import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart'; // REQUIRED PACKAGE

// --- 1. MODELS & DATA ---

class Station {
  final String id;
  final String name;
  final double? distance; // Distance in meters, if available

  Station({required this.id, required this.name, this.distance});

  factory Station.fromJson(Map<String, dynamic> json) {
    // Handling different API response structures
    String name = json['name'] ?? 'Unknown Station';
    if (json['location'] != null && json['location']['name'] != null) {
       name = json['location']['name']; // For stops/nearby endpoint
    }
    
    return Station(
      id: json['id'] ?? '',
      name: name,
      distance: json['distance'] != null ? (json['distance'] as num).toDouble() : null,
    );
  }
}

class JourneyStep {
  final String type; 
  final String line;
  final String instruction;
  final String duration;
  final String departureTime;
  final String? alert; 
  final String? seating;
  final int? chatCount;

  JourneyStep({
    required this.type,
    required this.line,
    required this.instruction,
    required this.duration,
    required this.departureTime,
    this.alert,
    this.seating,
    this.chatCount,
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

  // Search with optional Location Bias
  static Future<List<Station>> searchStations(String query, {double? lat, double? lng}) async {
    if (query.length < 2) return [];
    try {
      // We append lat/long to bias the search results towards the user's location
      String url = '$_baseUrl/locations?query=$query&results=5';
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

  // Explicitly fetch nearby stops
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

  // Mock Data
  final List<Friend> _friends = [
    Friend('Alex', 'On Bus 42', Colors.blue, 40, 10),
    Friend('Sarah', 'At Central St.', Colors.green, 50, 60),
    Friend('Mike', 'On Tram 10', Colors.purple, 20, 80),
  ];

  @override
  void initState() {
    super.initState();
    _determinePosition();
  }

  // --- LOCATION LOGIC ---
  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _gettingLocation = false);
      return;
    }

    permission = await Geolocator.checkPermission();
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

    // Get position
    final pos = await Geolocator.getCurrentPosition();
    setState(() {
      _currentPosition = pos;
      _gettingLocation = false;
    });
    
    // Auto-fill nearby suggestions if we have location
    if (_currentPosition != null) {
      _fetchNearbySuggestions();
    }
  }

  Future<void> _fetchNearbySuggestions() async {
     if (_currentPosition == null) return;
     final nearby = await TransportApi.getNearbyStops(_currentPosition!.latitude, _currentPosition!.longitude);
     if (mounted && _activeSearchField == 'from' && _fromController.text.isEmpty) {
       setState(() {
         _suggestions = nearby;
       });
     }
  }

  // --- HANDLERS ---

  void _onSearchChanged(String query, String field) {
    setState(() => _activeSearchField = field);
    
    // If empty and we have location, show nearby stations
    if (query.isEmpty && _currentPosition != null && field == 'from') {
       _fetchNearbySuggestions();
       return;
    }

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (query.length > 2) {
        // PASS LOCATION TO API FOR BIASED SEARCH
        final results = await TransportApi.searchStations(
          query, 
          lat: _currentPosition?.latitude, 
          lng: _currentPosition?.longitude
        );
        setState(() {
          _suggestions = results;
        });
      } else {
        setState(() => _suggestions = []);
      }
    });
  }

  void _onFieldTap(String field) {
    setState(() => _activeSearchField = field);
    // Trigger nearby suggestion immediately on tap if field is empty
    if ((field == 'from' && _fromController.text.isEmpty) || (field == 'to' && _toController.text.isEmpty)) {
      if (_currentPosition != null) {
        _fetchNearbySuggestions();
      }
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
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _findRoutes() async {
    if (_fromStation == null || _toStation == null) return;
    setState(() => _isLoading = true);

    final journeyData = await TransportApi.searchJourney(_fromStation!.id, _toStation!.id);

    if (journeyData != null) {
      // ... (Same parsing logic as before) ...
      final List legs = journeyData['legs'];
      final List<JourneyStep> steps = [];
      final random = Random();

      for (var leg in legs) {
        final mode = leg['mode'];
        final lineName = leg['line'] != null ? leg['line']['name'] : mode.toString().toUpperCase();
        final dest = leg['destination']['name'];
        final depStr = leg['departure'];
        final arrStr = leg['arrival'];
        
        DateTime dep = DateTime.parse(depStr);
        DateTime arr = DateTime.parse(arrStr);
        int durationMin = arr.difference(dep).inMinutes;

        String? alert;
        String? seating;
        int? chatCount;

        if (mode != 'walking') {
          if (random.nextDouble() > 0.7) alert = "Smart Alt: Delay ahead.";
          if (random.nextDouble() > 0.6) seating = random.nextBool() ? "Front" : "Back";
          chatCount = random.nextInt(15) + 1;
        }

        steps.add(JourneyStep(
          type: mode == 'walking' ? 'walk' : 'transport',
          line: lineName,
          instruction: mode == 'walking' ? "Walk to $dest" : "$lineName to $dest",
          duration: "$durationMin min",
          departureTime: "${dep.hour.toString().padLeft(2, '0')}:${dep.minute.toString().padLeft(2, '0')}",
          alert: alert,
          seating: seating,
          chatCount: chatCount,
        ));
      }

      final newTabId = DateTime.now().millisecondsSinceEpoch.toString();
      final newTab = RouteTab(
        id: newTabId,
        title: _toStation!.name,
        subtitle: "${_fromStation!.name} → ${_toStation!.name}",
        eta: "${DateTime.parse(journeyData['arrival']).hour.toString().padLeft(2, '0')}:${DateTime.parse(journeyData['arrival']).minute.toString().padLeft(2, '0')}",
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No routes found.")));
      }
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

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: false, // Prevents bottom bar from jumping when keyboard opens
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.7),
        elevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFFA855F7)]),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.bolt, size: 20, color: Colors.white),
            ),
            const SizedBox(width: 10),
            const Text("Trans", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          ],
        ),
        actions: [
           if (_gettingLocation)
             const Padding(padding: EdgeInsets.only(right: 16), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
           if (!_gettingLocation && _currentPosition != null)
             const Padding(padding: EdgeInsets.only(right: 16), child: Icon(Icons.location_on, color: Colors.greenAccent, size: 20)),
        ],
      ),
      body: _buildBody(),
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
    if (_currentIndex == 1) return const Center(child: Text("Friends Map Placeholder", style: TextStyle(color: Colors.grey)));
    if (_currentIndex == 2) return const Center(child: Text("Settings Placeholder", style: TextStyle(color: Colors.grey)));
    
    return Stack(
      children: [
        Column(
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
        ),
        
        // Autocomplete / Nearby Dropdown
        if (_suggestions.isNotEmpty)
          Positioned(
            top: _activeSearchField == 'from' ? 240 : 310,
            left: 32, right: 32,
            child: Material(
              elevation: 8,
              color: const Color(0xFF1F2937),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: _suggestions.length,
                  separatorBuilder: (ctx, idx) => const Divider(height: 1, color: Colors.white10),
                  itemBuilder: (ctx, idx) {
                    final station = _suggestions[idx];
                    return ListTile(
                      // Visual cue if it's a nearby station
                      leading: station.distance != null 
                        ? const Icon(Icons.near_me, size: 16, color: Colors.greenAccent) 
                        : null,
                      title: Text(station.name, style: const TextStyle(color: Colors.white, fontSize: 14)),
                      trailing: station.distance != null 
                        ? Text("${station.distance!.toInt()}m", style: const TextStyle(color: Colors.grey, fontSize: 10))
                        : null,
                      onTap: () => _selectStation(station),
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSearchView() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF111827).withOpacity(0.8),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.search, color: Colors.indigoAccent),
                    ),
                    const SizedBox(width: 12),
                    const Text("Plan Journey", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
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
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _isLoading 
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text("Find Routes", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, bool isSelected, String fieldKey) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
        ),
        TextField(
          controller: controller,
          onChanged: (val) => _onSearchChanged(val, fieldKey),
          onTap: () => _onFieldTap(fieldKey),
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF1F2937),
            prefixIcon: Icon(
              fieldKey == 'from' ? Icons.my_location : Icons.location_on, 
              color: isSelected ? Colors.greenAccent : Colors.grey,
              size: 20,
            ),
            suffixIcon: _gettingLocation && fieldKey == 'from' 
              ? const SizedBox(width: 10, height: 10, child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2)))
              : (isSelected ? const Icon(Icons.check_circle, color: Colors.greenAccent, size: 16) : null),
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
        Text(route.title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        Text(route.subtitle, style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 20),
        ...route.steps.map((step) => Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(step.instruction, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(step.duration, style: const TextStyle(fontFamily: 'Monospace', color: Colors.grey)),
            ]),
            Text(step.line, style: const TextStyle(color: Colors.grey)),
          ]),
        ))
      ],
    );
  }
}