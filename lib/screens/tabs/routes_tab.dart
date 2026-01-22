import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vibration/vibration.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:trans/models/station.dart';
import 'package:trans/models/journey.dart';
import 'package:trans/models/favorite.dart';
import 'package:trans/services/transport_api.dart';
import 'package:trans/services/supabase_service.dart';
import 'package:trans/services/history_manager.dart';
import 'package:trans/services/favorites_manager.dart';
import 'package:trans/services/notification_manager.dart';
import 'package:trans/widgets/chat_sheet.dart';
import 'package:trans/config/app_theme.dart';
import 'package:trans/utils/format_utils.dart'; 
import '../map_screen.dart'; 
import 'route_results_view.dart';

const List<IconData> kAvailableIcons = [
  Icons.star, Icons.home, Icons.work, Icons.favorite, 
  Icons.train, Icons.directions_bus, Icons.school, 
  Icons.person, Icons.location_on, Icons.shopping_cart, 
  Icons.fitness_center, Icons.local_cafe, Icons.local_airport
];

class RoutesTab extends StatefulWidget {
  final Position? currentPosition;
  final bool onlyNahverkehr;
  final bool showTrainNumbers;

  const RoutesTab({
    super.key,
    required this.currentPosition,
    required this.onlyNahverkehr,
    this.showTrainNumbers = false,
  });

  @override
  State<RoutesTab> createState() => RoutesTabState();
}

class RoutesTabState extends State<RoutesTab> with WidgetsBindingObserver {
  final List<RouteTab> _tabs = [];
  String? _activeTabId;

  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _toController = TextEditingController();
  
  final FocusNode _fromFocusNode = FocusNode();
  final FocusNode _toFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  Station? _fromStation;
  Station? _toStation;
  
  List<dynamic> _suggestions = []; 
  String _activeSearchField = '';
  Timer? _debounce;
  Timer? _focusDebounce; // Delayed focus handling for Web clicks
  bool _isLoadingRoute = false;
  bool _isSuggestionsLoading = false;
  
  DateTime? _selectedDate; 
  TimeOfDay? _selectedTime;
  bool _isArrival = false; 

  bool _isWakeAlarmSet = false;
  StreamSubscription<Position>? _gpsStream;
  double? _gpsAccuracy;
  List<Favorite> _favorites = [];
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _wasKeyboardVisible = false;

  @override
  void initState() {
    super.initState();
    _fetchSuggestions(forceHistory: true);
    _loadFavorites();
    _initNotifications();
    WidgetsBinding.instance.addObserver(this);
    _fromFocusNode.addListener(_onFocusChange);
    _toFocusNode.addListener(_onFocusChange);
  }
  void _onFocusChange() {
    if (_fromFocusNode.hasFocus) {
      _focusDebounce?.cancel();
      if (_activeSearchField != 'from') {
         setState(() {
           _activeSearchField = 'from';
           _fetchSuggestions(forceHistory: _fromController.text.isEmpty);
         });
         _scrollToTop();
      }
    } else if (_toFocusNode.hasFocus) {
      _focusDebounce?.cancel();
      if (_activeSearchField != 'to') {
         setState(() {
           _activeSearchField = 'to';
           _fetchSuggestions(forceHistory: _toController.text.isEmpty);
         });
      }
    } else {
      // Delay clearing suggestions to allow click events (especially on Web) to register
      _focusDebounce?.cancel();
      _focusDebounce = Timer(const Duration(milliseconds: 200), () {
        if (mounted) {
          setState(() {
            _activeSearchField = '';
            _suggestions = []; 
          });
        }
      });
    }
  }

  void _initNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const initSettings = InitializationSettings(android: android, iOS: ios);
    await _notificationsPlugin.initialize(initSettings);
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    _fromFocusNode.dispose();
    _toFocusNode.dispose();
    _scrollController.dispose();
    _debounce?.cancel();
    _focusDebounce?.cancel();
    _gpsStream?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Handles the back button press.
  /// Returns true if the back navigation was handled internally (e.g., closing a route tab),
  /// and false otherwise (which should presumably trigger the app exit dialog).
  bool handleBack() {
    if (_activeTabId != null) {
      final idx = _tabs.indexWhere((t) => t.id == _activeTabId);
      if (idx != -1) {
        final currentTab = _tabs[idx];
        // If we are looking at a specific journey (details view), go back to list
        if (currentTab.activeJourney != null) {
          setState(() {
            _tabs[idx] = currentTab.copyWith(clearActiveJourney: true);
          });
          return true; 
        }
      }
      
      // If we are at the list view (or no active journey), close the tab
      _closeTab(_activeTabId!);
      return true;
    }
    // Check if search suggestions are open, maybe close them?
    // For now, let's say if suggestions are open, we just close them.
    if (_activeSearchField.isNotEmpty || _suggestions.isNotEmpty) {
       setState(() {
         _activeSearchField = '';
         _suggestions = [];
         FocusScope.of(context).unfocus();
       });
       return true;
    }
    
    return false;
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final bottomInset = View.of(context).viewInsets.bottom;
    final isVisible = bottomInset > 0;
    if (_wasKeyboardVisible && !isVisible) {
      // Keyboard JUST closed
      if (_fromFocusNode.hasFocus || _toFocusNode.hasFocus) {
         FocusScope.of(context).unfocus();
      }
    }
    _wasKeyboardVisible = isVisible;
  }

  void _scrollToTop() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(0.0, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      }
    });
  }

  Future<void> _loadFavorites() async {
    final favs = await FavoritesManager.getFavorites();
    if (mounted) setState(() => _favorites = favs);
  }

  // --- WAKE ALARM LOGIC ---
  void _toggleWakeAlarm(RouteTab route) {
    if (_isWakeAlarmSet) {
      _stopWakeAlarm();
    } else {
      _startWakeAlarm(route);
    }
  }

  void _stopWakeAlarm() {
    _gpsStream?.cancel();
    _gpsStream = null;
    SupabaseService.clearJourneyStatus();
    if (mounted) setState(() => _isWakeAlarmSet = false);
  }

  Future<void> _startWakeAlarm(RouteTab route) async {
    if (route.steps.isEmpty) return;

    // 1. Request Permissions
    await NotificationManager.requestPermissions();
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Location permission denied. Alarm cannot work.")));
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Location permission permanently denied.")));
       return;
    }
    
    final prefs = await SharedPreferences.getInstance();
    final int stopsBefore = prefs.getInt('alarm_stops_before') ?? 1;

    final firstRide = route.steps.firstWhere((s) => s.type == 'ride', orElse: () => route.steps.first);
    final String currentLine = firstRide.line;

    double? targetLat = firstRide.endLat;
    double? targetLng = firstRide.endLng;

    if (firstRide.stopovers != null && firstRide.stopovers!.isNotEmpty && stopsBefore > 0) {
      final stops = firstRide.stopovers!;
      int targetIndex = stops.length - 1 - stopsBefore;
      if (targetIndex >= 0) {
        final stopData = stops[targetIndex];
        if (stopData['stop'] != null && stopData['stop']['location'] != null) {
           targetLat = stopData['stop']['location']['latitude'];
           targetLng = stopData['stop']['location']['longitude'];
        }
      }
    }

    if (targetLat == null || targetLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cannot start alarm: Missing destination coordinates.")));
      return;
    }

    if (mounted) setState(() => _isWakeAlarmSet = true);
    
    // 2. Configure Background Location (Foreground Service)
    AndroidSettings androidSettings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 50,
      forceLocationManager: true,
      intervalDuration: const Duration(seconds: 10),
      // Foreground Notification to keep service alive
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: "Trans Wake Alarm",
        notificationText: "Tracking your journey...",
        notificationIcon: AndroidResource(name: 'ic_launcher'),
        enableWakeLock: true,
      ),
    );

    AppleSettings appleSettings = AppleSettings(
      accuracy: LocationAccuracy.high,
      activityType: ActivityType.fitness,
      distanceFilter: 50,
      pauseLocationUpdatesAutomatically: false,
      showBackgroundLocationIndicator: true,
    );

    const LocationSettings settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 50,
    );

    LocationSettings activeSettings = settings;
    if (defaultTargetPlatform == TargetPlatform.android) activeSettings = androidSettings;
    if (defaultTargetPlatform == TargetPlatform.iOS) activeSettings = appleSettings;

    if (widget.currentPosition != null) {
       SupabaseService.updateLocation(widget.currentPosition!, currentLine: currentLine);
    }

    _gpsStream = Geolocator.getPositionStream(locationSettings: activeSettings).listen((Position pos) {
      if (mounted) setState(() => _gpsAccuracy = pos.accuracy);
      SupabaseService.updateLocation(pos, currentLine: currentLine);
      double dist = Geolocator.distanceBetween(pos.latitude, pos.longitude, targetLat!, targetLng!);
      if (dist < 500) { 
         _triggerVibration();
         _showNotification();
         if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Wake Up! Approaching your stop!"), backgroundColor: Colors.red));
           _stopWakeAlarm();
         }
      }
    });
  }

  void _openMap(RouteTab route, {JourneyStep? focusStep}) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => MapScreen(steps: route.steps, focusStep: focusStep, currentPosition: widget.currentPosition)));
  }

  // --- SEARCH LOGIC ---
  Future<void> _fetchSuggestions({bool forceHistory = false}) async {
    if (forceHistory) {
      final history = await SearchHistoryManager.getHistory();
      if (mounted) setState(() => _suggestions = history);
      return;
    }
    setState(() => _isSuggestionsLoading = true);
    List<dynamic> results = [];
    final query = _activeSearchField == 'from' ? _fromController.text : _toController.text;
    if (query.isNotEmpty) {
      final matchingFavs = _favorites.where((f) => f.label.toLowerCase().contains(query.toLowerCase())).toList();
      results.addAll(matchingFavs);
    }
    final history = await SearchHistoryManager.getHistory();
    if (history.isNotEmpty) {
       if (query.isNotEmpty) {
         results.addAll(history.where((s) => s.name.toLowerCase().contains(query.toLowerCase())));
       } else {
         results.addAll(history);
       }
    }
    if (mounted) setState(() { _suggestions = results; _isSuggestionsLoading = false; });
  }

  void _onSearchChanged(String query, String field) {
    setState(() => _activeSearchField = field);
    _fetchSuggestions();
    if (query.isEmpty) {

      if (field == 'from') {
         setState(() {
           _fromStation = null;
           _suggestions = [];
           _isSuggestionsLoading = false;
         });
         return;
      } else if (field == 'to') {
        setState(() {
          _toStation = null;
          _suggestions = [];
          _isSuggestionsLoading = false;
        });
        return;
      }
      return; 
    }
    setState(() => _isSuggestionsLoading = true);
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      if (query.length > 2) {
        double? refLat = widget.currentPosition?.latitude;
        double? refLng = widget.currentPosition?.longitude;
        try {
          final apiResults = await TransportApi.searchStations(query, lat: refLat, lng: refLng);
          if (mounted) {
            setState(() { 
              if (apiResults.isEmpty && _suggestions.isEmpty) {
                // Show message if no results at all
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Service temporarily busy. Try again or type more characters."), duration: Duration(seconds: 2))
                );
              }
              for (var s in apiResults) {
                 bool exists = _suggestions.any((existing) {
                   if (existing is Station) return existing.id == s.id;
                   if (existing is Favorite) return existing.station?.id == s.id;
                   return false;
                 });
                 if (!exists) _suggestions.add(s);
              }
              _isSuggestionsLoading = false; 
            });
          }
        } catch (e) {
          if (mounted) {
            setState(() => _isSuggestionsLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Service temporarily busy. Please try again."), duration: Duration(seconds: 2))
            );
          }
        }
      } else {
        if (mounted) setState(() => _isSuggestionsLoading = false);
      }
    });
  }

  void _selectItem(dynamic item) {
    if (item is Station) {
      _selectStation(item);
    } else if (item is Favorite) {
      _onFavoriteTap(item);
    }
  }

  void _selectStation(Station station) {
    SearchHistoryManager.saveStation(station);
    setState(() {
      if (_activeSearchField == 'from') {
        _fromStation = station;
        _fromController.text = station.name;
        if (_toStation == null) {
           _activeSearchField = 'to';
           _suggestions = []; 
           _toFocusNode.requestFocus();
           _scrollToTop();
           return; 
        }
      } else {
        _toStation = station;
        _toController.text = station.name;
      }
      _suggestions = [];
      _activeSearchField = '';
    });
    FocusScope.of(context).unfocus();
  }

  Future<void> _onFavoriteTap(Favorite fav) async {
    // Capture the active field BEFORE async operations or state clearing
    final currentField = _activeSearchField;
    
    setState(() { _suggestions = []; _activeSearchField = ''; });
    FocusScope.of(context).unfocus();
    Station? target;
    if (fav.type == 'station') {
      target = fav.station;
      if (target == null) { _showEditFavoriteDialog(fav); return; }
    } else if (fav.type == 'friend' && fav.friendId != null) {
      setState(() => _isLoadingRoute = true);
      try {
        final data = await SupabaseService.client.from('user_locations').select().eq('user_id', fav.friendId!).maybeSingle();
        if (data != null) {
          final stops = await TransportApi.getNearbyStops(data['latitude'], data['longitude']);
          if (mounted && stops.isNotEmpty) target = stops.first;
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      } finally {
        if (mounted) setState(() => _isLoadingRoute = false);
      }
    }

    if (target != null && mounted) {
      setState(() {
        if (currentField == 'from') {
           _fromStation = target;
           _fromController.text = target!.name;
           if (_toStation == null) {
             _activeSearchField = 'to';
             _toFocusNode.requestFocus();
             _scrollToTop();
           }
        } else if (currentField == 'to') {
           _toStation = target;
           _toController.text = target!.name;
           // If from is empty, maybe jump there? But usually 'to' is second.
           if (_fromStation == null && widget.currentPosition == null) {
              _activeSearchField = 'from';
              _fromFocusNode.requestFocus();
           }
        } else {
           if (_fromStation != null || widget.currentPosition != null) {
             _toStation = target;
             _toController.text = target!.name;
           } else {
             _fromStation = target;
             _fromController.text = target!.name;
             _toFocusNode.requestFocus();
             _scrollToTop();
           }
        }
      });
    }
  }

  void _closeTab(String id) {
    setState(() {
      _tabs.removeWhere((t) => t.id == id);
      if (_activeTabId == id) _activeTabId = _tabs.isNotEmpty ? _tabs.last.id : null;
    });
    _stopWakeAlarm();
  }
  
  void _showChat(BuildContext context, String lineName) {
    showModalBottomSheet(context: context, backgroundColor: Theme.of(context).scaffoldBackgroundColor, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))), builder: (ctx) => ChatSheet(lineId: lineName, title: lineName));
  }
  
  // FIX: Accept full Station object
  void _showAlternatives(BuildContext context, String stationId, Station destination, DateTime referenceTime, {double? lat, double? lng, String? stationName}) {
      Station fromDummy;
      // If we have coordinates, use them (Location based)
      if (lat != null && lng != null) {
         fromDummy = Station(id: stationId, name: stationName ?? "Origin", type: "location", latitude: lat, longitude: lng);
      } else {
         // Otherwise hope the ID is valid. If it's just a name, V6 API might fail if it's ambiguous, but usually ID is passed.
         // However, the previous error 'Missing origin' suggests the ID was empty or the API couldn't resolve "From".
         // The previous code was: Station(id: stationId, name: "From");
         // If stationId was "gps", we need coords.
         fromDummy = Station(id: stationId, name: stationName ?? "Origin", type: "station");
      }

      // Use destination station directly to preserve coordinates
      Station toDummy = destination;

      showModalBottomSheet(context: context, backgroundColor: Theme.of(context).cardColor, builder: (ctx) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: TransportApi.searchJourneys(
            fromDummy, 
            toDummy, 
            nahverkehrOnly: widget.onlyNahverkehr,
            when: referenceTime,
            results: 5
          ), 
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("No routes found."));
              return ListView.builder(padding: const EdgeInsets.all(16), itemCount: snapshot.data!.length, itemBuilder: (ctx, idx) {
                final journey = snapshot.data![idx];
                final legs = (journey['legs'] as List).cast<Map<String, dynamic>>();
                if (legs.isEmpty) return const SizedBox.shrink();
                final firstRide = legs.firstWhere((l) => l['line'] != null, orElse: () => legs.first);
                final line = firstRide['line'] != null ? firstRide['line']['name'] : 'Walk/Transfer';
                final dir = firstRide['direction'] ?? 'Destination';
                final depTime = DateTime.parse(firstRide['departure'] ?? firstRide['plannedDeparture']).toLocal();
                return ListTile(
                  leading: const Icon(Icons.alt_route), 
                  title: Text("$line to $dir"), 
                  subtitle: Text("Departs ${DateFormat('HH:mm').format(depTime)}"),
                  onTap: () { 
                    Navigator.pop(context); 
                    // Add to current tab's stack
                    final j = _createJourney(journey);
                    setState(() {
                      if (_activeTabId != null) {
                        final idx = _tabs.indexWhere((t) => t.id == _activeTabId);
                        if (idx != -1) {
                           final currentTab = _tabs[idx];
                           final newStack = List<Journey>.from(currentTab.stack);
                           if (!newStack.any((e) => e.departure == j.departure && e.arrival == j.arrival)) { // Avoid duplicates
                             newStack.add(j);
                           }
                           _tabs[idx] = currentTab.copyWith(
                             activeJourney: j,
                             stack: newStack,
                             steps: j.steps,
                             totalDuration: FormatUtils.formatDuration(j.duration.inMinutes)
                           );
                        }
                      } else {
                        // Fallback if no tab active? Should not happen if called from StepCard
                         _addJourneyTab(singleJourneyData: journey, title: "Alternative", subtitle: "Departs ${DateFormat('HH:mm').format(depTime)}"); 
                      }
                    });
                  }
                );
              });
          }
        );
      });
  }

  List<JourneyStep> _processLegs(List legs) {
    final List<JourneyStep> steps = [];
    final random = Random();
    List<dynamic> transferBuffer = [];
    DateTime? lastArrival;
    bool isFirstStep = true; // Track if this is the first step in the journey
    double? getLat(dynamic loc) => loc != null && loc['location'] != null ? loc['location']['latitude'] : (loc != null ? loc['latitude'] : null);
    double? getLng(dynamic loc) => loc != null && loc['location'] != null ? loc['location']['longitude'] : (loc != null ? loc['longitude'] : null);
    
    void flushTransferBuffer(DateTime? nextRideDeparture, String? nextStationName, double? nextRideStartLat, double? nextRideStartLng, {bool isFinalWalk = false}) {
      if (transferBuffer.isEmpty && (lastArrival == null || nextRideDeparture == null)) return;
      DateTime blockStart = (lastArrival != null) ? lastArrival! : (DateTime.tryParse(transferBuffer.first['departure'] ?? transferBuffer.first['plannedDeparture'] ?? '')?.toLocal() ?? DateTime.now());
      DateTime blockEnd = (nextRideDeparture != null) ? nextRideDeparture : (transferBuffer.isNotEmpty ? (DateTime.tryParse(transferBuffer.last['arrival'] ?? transferBuffer.last['plannedArrival'] ?? '')?.toLocal() ?? blockStart) : blockStart);
      int walkMinutes = 0;
      for (var leg in transferBuffer) { try { walkMinutes += DateTime.parse(leg['arrival'] ?? leg['plannedArrival']).toLocal().difference(DateTime.parse(leg['departure'] ?? leg['plannedDeparture']).toLocal()).inMinutes; } catch(e) {} }
      int totalGapMinutes = blockEnd.difference(blockStart).inMinutes;
      if (totalGapMinutes < 0) totalGapMinutes = 0;
      
      double? startLat = getLat(transferBuffer.isNotEmpty ? transferBuffer.first['origin'] : null);
      if (startLat == null && steps.isNotEmpty) startLat = steps.last.endLat;
      double? startLng = getLng(transferBuffer.isNotEmpty ? transferBuffer.first['origin'] : null);
      if (startLng == null && steps.isNotEmpty) startLng = steps.last.endLng;

      double? endLat = nextRideStartLat;
      double? endLng = nextRideStartLng;
      
      // If we are at the end (no next ride), try to get coordinates from the last transfer leg (e.g. walk to address)
      if (endLat == null && transferBuffer.isNotEmpty) {
          endLat = getLat(transferBuffer.last['destination']);
          endLng = getLng(transferBuffer.last['destination']);
      }
      
      // Get destination name from transfer buffer if not provided
      String? destName = nextStationName;
      if (destName == null && transferBuffer.isNotEmpty) {
        destName = transferBuffer.last['destination']?['name'];
      }

      // Determine instruction text based on context
      String instruction;
      if (walkMinutes > 0) {
        if (isFirstStep && destName != null) {
          instruction = "Walk to $destName"; // Initial walk to station
        } else if (isFinalWalk && destName != null) {
          instruction = "Walk to destination"; // Final walk to destination
        } else if (destName != null) {
          instruction = "Walk to $destName"; // Transfer walk
        } else {
          instruction = "Walk";
        }
      } else {
        instruction = "Wait for connection";
      }

      steps.add(JourneyStep(
        type: (walkMinutes > 0) ? 'walk' : 'wait',
        line: 'Transfer',
        instruction: instruction,
        duration: FormatUtils.formatDuration(totalGapMinutes),
        departureTime: "${blockStart.hour.toString().padLeft(2,'0')}:${blockStart.minute.toString().padLeft(2,'0')}",
        arrivalTime: "${blockEnd.hour.toString().padLeft(2,'0')}:${blockEnd.minute.toString().padLeft(2,'0')}",
        isWalking: walkMinutes > 0,
        startLat: startLat, startLng: startLng, endLat: endLat, endLng: endLng,
        path: transferBuffer.isNotEmpty ? transferBuffer.first['decodedPath'] : null,
        dateTime: blockStart
      ));
      transferBuffer.clear();
      isFirstStep = false; // After first flush, no longer first step
    }

    for (var leg in legs) {
      if (leg['line'] != null && leg['line']['name'] != null) {
        DateTime? dep, arr;
        DateTime? scheduledDep, scheduledArr;
        bool isCancelled = leg['cancelled'] == true;
        
        // Parse scheduled times first
        try {
          // Check both standard keys (scheduledDeparture) and V6/HAFAS keys (plannedDeparture)
          final sDep = leg['scheduledDeparture'] ?? leg['plannedDeparture'];
          if (sDep != null) {
            scheduledDep = DateTime.parse(sDep).toLocal();
          }
          final sArr = leg['scheduledArrival'] ?? leg['plannedArrival'];
          if (sArr != null) {
             scheduledArr = DateTime.parse(sArr).toLocal();
          }
        } catch(e) {}

        // Parse real-time times, fallback to scheduled
        try { 
          if (leg['departure'] != null) {
             dep = DateTime.parse(leg['departure']).toLocal();
          }
          if (leg['arrival'] != null) {
             arr = DateTime.parse(leg['arrival']).toLocal();
          }
        } catch(e) {}
        
        // Fallbacks
        dep ??= scheduledDep;
        arr ??= scheduledArr;
        
        // If still null, we can't show this leg
        if (dep == null || arr == null) continue;
        
        flushTransferBuffer(dep, leg['origin']?['name'], getLat(leg['origin']), getLng(leg['origin']));

        int? depDelay;
        int? arrDelay;

        // Calculate delays if scheduled times are available AND we have real times
        // If cancelled, delay calculation might be irrelevant or we assume 0 relative to scheduled
        if (scheduledDep != null && !isCancelled) {
           depDelay = dep.difference(scheduledDep).inMinutes;
        }
        if (scheduledArr != null && !isCancelled) {
           arrDelay = arr.difference(scheduledArr).inMinutes;
        }

        // Special handling for Motis: sometimes 'departureDelay' integer is provided directly
        if (depDelay == null && leg['departureDelay'] is int) {
           depDelay = (leg['departureDelay'] as int) ~/ 60; // Motis often uses seconds? Or check API. Usually it's ms or s. Motis V1 is min.
           // actually Motis v1 usually min.
        }

        steps.add(JourneyStep(
          type: 'ride',
          line: leg['line']?['name']?.toString() ?? '?',
          // If cancelled, show as cancelled in instruction or just handle in UI
          instruction: "${leg['line']?['name'] ?? '?'} → ${leg['direction'] ?? 'Destination'}",
          duration: FormatUtils.formatDuration(arr.difference(dep).inMinutes),
          departureTime: DateFormat('HH:mm').format(dep),
          arrivalTime: DateFormat('HH:mm').format(arr),
          chatCount: random.nextInt(15),
          startStationId: leg['origin']?['id']?.toString(),
          platform: leg['platform']?.toString(),
          stopovers: leg['stopovers'],
          startLat: getLat(leg['origin']), startLng: getLng(leg['origin']), endLat: getLat(leg['destination']), endLng: getLng(leg['destination']),
          path: leg['decodedPath'],
          dateTime: dep, // FIX: Store time
          departureDelay: depDelay,
          arrivalDelay: arrDelay,
          isCancelled: isCancelled,
          plannedDeparture: scheduledDep,
          plannedArrival: scheduledArr,
          destinationName: leg['destination']?['name'],
          headsign: leg['direction'],
          tripId: leg['line']?['fahrtNr']?.toString() ?? leg['tripId']?.toString(), // Populating tripId
        ));
        lastArrival = arr;
      } else { transferBuffer.add(leg); }
    }
    flushTransferBuffer(null, null, null, null, isFinalWalk: true);
    return steps;
  }
 

  Journey _createJourney(Map<String, dynamic> journeyData) {
    if (journeyData['legs'] == null) throw Exception("No legs data");
    final List legs = journeyData['legs'];
    final List<JourneyStep> steps = _processLegs(legs);
    
    DateTime? dep, arr;
    try {
      if (legs.isNotEmpty) {
        dep = DateTime.parse(legs.first['departure'] ?? legs.first['plannedDeparture']).toLocal();
        arr = DateTime.parse(legs.last['arrival'] ?? legs.last['plannedArrival']).toLocal();
      } else if (journeyData['departure'] != null && journeyData['arrival'] != null) {
        dep = DateTime.parse(journeyData['departure']).toLocal();
        arr = DateTime.parse(journeyData['arrival']).toLocal();
      }
    } catch(e) {}
    
    // Calculate transfer count (rides - 1)
    int rides = steps.where((s) => s.type == 'ride').length;
    int transfers = (rides > 0) ? rides - 1 : 0;
    
    int waitMinutes = 0;
    for (var step in steps) {
       if (step.type == 'wait' || step.type == 'transfer') {
         try {
           final parts = step.duration.split(' ');
           if (parts.isNotEmpty) waitMinutes += int.tryParse(parts[0]) ?? 0;
         } catch(_) {}
       }
    }

    return Journey(
      steps: steps,
      departure: dep ?? DateTime.now(),
      arrival: arr ?? DateTime.now(),
      duration: (dep != null && arr != null) ? arr.difference(dep) : Duration.zero,
      transferCount: transfers,
      totalWaitTime: Duration(minutes: waitMinutes),
      rawSource: journeyData,
      source: journeyData['source'] ?? 'unknown',
    );
  }

  void _addJourneyTab({Map<String, dynamic>? singleJourneyData, List<Map<String, dynamic>>? candidatesData, String title = "Route", String? subtitle}) {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    List<Journey> candidates = [];
    Journey? activeJourney;
    Station? dest;

    if (candidatesData != null) {
      for (var d in candidatesData) {
         try { candidates.add(_createJourney(d)); } catch(_) {}
      }
      if (candidates.isNotEmpty) {
         final lastLeg = candidates.first.rawSource['legs'].last;
         dest = Station(id: lastLeg['destination']['id'], name: lastLeg['destination']['name'] ?? "Destination", type: "station");
      }
    } else if (singleJourneyData != null) {
      try {
        activeJourney = _createJourney(singleJourneyData);
        candidates = [activeJourney];
        final lastLeg = singleJourneyData['legs'].last;
        dest = Station(id: lastLeg['destination']['id'], name: lastLeg['destination']['name'] ?? "Destination", type: "station");
      } catch(_) { return; }
    }
    
    if (dest == null) return;
    
    if (_toStation != null) dest = _toStation;

    setState(() {
      _tabs.add(RouteTab(
          id: id, 
          title: title == "Route" ? dest!.name : title, 
          subtitle: subtitle ?? "Details", 
          eta: activeJourney != null ? DateFormat('HH:mm').format(activeJourney.arrival) : "--:--", 
          totalDuration: activeJourney != null ? FormatUtils.formatDuration(activeJourney.duration.inMinutes) : "", 
          destination: dest!, 
          origin: _fromStation, // Store origin
          steps: activeJourney?.steps ?? [], 
          source: activeJourney?.source,
          candidates: candidates,
          activeJourney: activeJourney,
          stack: activeJourney != null ? [activeJourney] : [], // Init stack
      ));
      _activeTabId = id;
    });
  }


  Future<void> _findRoutes() async {
     if (_isLoadingRoute) return;
     Station? from = _fromStation;
     if (from == null) {
        if (_fromController.text.isEmpty || _fromController.text == "Current Location") {
           Position? pos = widget.currentPosition;
           if (pos == null) {
              try { pos = await Geolocator.getCurrentPosition(timeLimit: const Duration(seconds: 3)); } catch(_) {}
           }
           if (pos != null) {
              from = Station(id: 'gps', name: 'Current Location', type: 'location', latitude: pos.latitude, longitude: pos.longitude);
              // Resolve address for better UX
              try {
                final nearby = await TransportApi.getNearbyStops(pos.latitude, pos.longitude);
                if (nearby.isNotEmpty) {
                   from = nearby.first;
                   if (mounted) setState(() { _fromStation = from; _fromController.text = from!.name; });
                }
              } catch (_) {}
           } else { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Location not available."))); return; }
        } else {
           setState(() => _isLoadingRoute = true);
           try { final results = await TransportApi.searchStations(_fromController.text); if (results.isNotEmpty) { from = results.first; _fromStation = from; } else { throw "Start not found"; } } catch (e) { if (mounted) { setState(() => _isLoadingRoute = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e"))); } return; }
        }
     }
     if (_toStation == null) {
        if (_toController.text.isNotEmpty) {
           setState(() => _isLoadingRoute = true);
           try { final results = await TransportApi.searchStations(_toController.text); if (results.isNotEmpty) _toStation = results.first; else throw "Destination not found"; } catch (e) { if (mounted) { setState(() => _isLoadingRoute = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e"))); } return; }
        } else { return; }
     }
     setState(() => _isLoadingRoute = true);
     try {
       DateTime when;
       if (_selectedDate != null) {
          when = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day, _selectedTime?.hour ?? 0, _selectedTime?.minute ?? 0);
       } else {
          when = DateTime.now();
       }
       // If "Arrive By" is set but no date selected, "Now" usually implies "Depart Now", so we use departure=Now effectively.
       // But searchJourneys handles 'when'.
       final res = await TransportApi.searchJourneys(from!, _toStation!, nahverkehrOnly: widget.onlyNahverkehr, when: when, isArrival: _isArrival).timeout(const Duration(seconds: 20)); 
       if (mounted) { 
         if (res.isNotEmpty) { 
           _addJourneyTab(candidatesData: res); 
         } else { 
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No routes found. The service may be temporarily busy - please try again."))); 
         } 
       }
     } on TimeoutException catch(_) {
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Request timed out. Please try again.")));
     } catch(e) { 
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Service temporarily busy. Please try again in a moment."))); 
       }
     } finally { if (mounted) setState(() => _isLoadingRoute = false); }
  }

  Future<void> _triggerVibration() async {
    if (kIsWeb) return; 
    if (await Vibration.hasVibrator() ?? false) Vibration.vibrate(duration: 500);
  }

  Future<void> _showNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'wake_alarm_channel', 
      'Wake Alarm', 
      channelDescription: 'Alarms for arriving at station',
      importance: Importance.max,
      priority: Priority.high,
      enableVibration: true,
    );
    const details = NotificationDetails(android: androidDetails);
    await _notificationsPlugin.show(0, 'Wake Up!', 'Approaching your stop!', details);
  }

  void _showEditFavoriteDialog(Favorite fav) async {
    await showDialog(context: context, barrierDismissible: false, builder: (ctx) => _EditFavoriteDialog(favorite: fav));
    if (mounted) _loadFavorites();
  }
  
  void _addNewFavorite() {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    _showEditFavoriteDialog(Favorite(id: id, label: '', type: 'station'));
  }

  @override
  @override
  Widget build(BuildContext context) {
    final bool canSearch = (_fromStation != null || widget.currentPosition != null) && _toStation != null && !_isLoadingRoute;
    final colors = TransColors.of(context);
    final topPadding = MediaQuery.of(context).padding.top + 10;
    
    // Find active tab for secondary row
    RouteTab? activeTab;
    if (_activeTabId != null) {
      try {
        activeTab = _tabs.firstWhere((t) => t.id == _activeTabId);
      } catch (_) {}
    }

    return Column(children: [
        SizedBox(height: topPadding),
        if (_isWakeAlarmSet && _gpsAccuracy != null && _gpsAccuracy! > 100) Container(width: double.infinity, padding: const EdgeInsets.all(8), color: Colors.amber, child: const Text("⚠️ Weak GPS", textAlign: TextAlign.center)),
        
        // Main Tab Bar
        if (_tabs.isNotEmpty) SizedBox(height: 60, child: ListView.builder(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: _tabs.length + 1, itemBuilder: (ctx, idx) { 
          if (idx == _tabs.length) return Padding(padding: const EdgeInsets.only(bottom: 20), child: IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => setState(() => _activeTabId = null)));
          return _buildTabItem(_tabs[idx], colors);
        })),

        // Secondary Tab Row (Alternatives)
        if (activeTab != null && activeTab.stack.length > 1 && activeTab.isStackExpanded)
           _buildSecondaryTabs(activeTab, colors),

        Expanded(child: _activeTabId == null ? _buildSearchView(canSearch, colors) : _buildActiveRouteView(activeTab!)),
    ]);
  }

  Widget _buildTabItem(RouteTab tab, TransColors colors) {
    final isActive = tab.id == _activeTabId;
    final stackCount = tab.stack.length;
    final showStack = stackCount > 1;
    // User mockup shows 3 lines. "Subtabs" likely means alternatives.
    // If only 1 journey is open, do we show 1 line?
    // "just change how many lines there are based on how many subtabs there are".
    // If 1 tab, 1 subtab?
    // Usually "Stack" implies > 1.
    // But if secondary row shows selected item, maybe we always show count.
    // Let's assume stackCount > 0.
    
    return GestureDetector(
      onTap: () {
        setState(() {
          if (_activeTabId == tab.id) {
             // Toggle expansion if already active
             final idx = _tabs.indexWhere((t) => t.id == tab.id);
             if (idx != -1) {
               _tabs[idx] = tab.copyWith(isStackExpanded: !tab.isStackExpanded);
             }
          } else {
             _activeTabId = tab.id;
             // Ensure it opens expanded? yes, default is true.
          }
        });
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isActive ? colors.navBarSelected : colors.cardBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Close Button (Left)
                    GestureDetector(
                      onTap: () => _closeTab(tab.id),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(Icons.close, size: 14, color: isActive ? Colors.white70 : Colors.grey),
                      ),
                    ),
                    Icon(Icons.directions, size: 16, color: isActive ? Colors.white : Colors.grey),
                    const SizedBox(width: 6),
                    Text(
                      tab.title,
                      style: TextStyle(
                        color: isActive ? Colors.white : Colors.grey,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (showStack) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10), // Indent to clear rounded corners
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(
                      min(stackCount, 5), 
                      (index) => Expanded(
                        child: Container(
                          height: 3,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: colors.navBarSelected, // Theme color (Purple)
                            borderRadius: BorderRadius.circular(1.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSecondaryTabs(RouteTab tab, TransColors colors) {
    final stack = tab.stack;
    return Container(
      height: 50,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: stack.length,
        separatorBuilder: (ctx, idx) => const SizedBox(width: 8),
        itemBuilder: (ctx, idx) {
           final journey = stack[idx];
           final isSelected = tab.activeJourney == journey;
           
           final timeStr = "${DateFormat('HH:mm').format(journey.departure)} - ${DateFormat('HH:mm').format(journey.arrival)}";

           return GestureDetector(
             onTap: () {
                setState(() {
                  final tIdx = _tabs.indexWhere((t) => t.id == tab.id);
                  if (tIdx != -1) {
                    _tabs[tIdx] = tab.copyWith(
                      activeJourney: journey,
                      steps: journey.steps,
                      totalDuration: FormatUtils.formatDuration(journey.duration.inMinutes),
                    );
                  }
                });
             },
             child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? colors.navBarSelected : colors.cardBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Subtabs also have Close button? 
                    GestureDetector(
                      onTap: () {
                         // Remove this journey from stack
                         setState(() {
                           final tIdx = _tabs.indexWhere((t) => t.id == tab.id);
                           if (tIdx != -1) {
                             final newStack = List<Journey>.from(stack);
                             newStack.removeAt(idx);
                             
                             Journey? newActive = tab.activeJourney;
                             if (newActive == journey) {
                               // If we closed the active one, pick another (e.g. last or first)
                               newActive = newStack.isNotEmpty ? newStack.last : null;
                             }
                             
                             // If stack empty, close tab? Or just clear active?
                             // User: "show routes manually opens". If all closed, tab might close.
                             if (newStack.isEmpty) {
                               _closeTab(tab.id); 
                             } else {
                               _tabs[tIdx] = tab.copyWith(
                                 stack: newStack,
                                 activeJourney: newActive,
                                 steps: newActive?.steps ?? [], 
                                 totalDuration: newActive != null ? FormatUtils.formatDuration(newActive.duration.inMinutes) : "",
                                 clearActiveJourney: newActive == null,
                               );
                             }
                           }
                         });
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(Icons.close, size: 14, color: isSelected ? Colors.white70 : Colors.grey),
                      ),
                    ),
                    Text(
                      timeStr,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
             )
           );
        },
      ),
    );
  }

  Widget _buildSearchView(bool canSearch, TransColors colors) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      behavior: HitTestBehavior.translucent,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: EdgeInsets.only(bottom: 100 + keyboardHeight),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: colors.cardBg.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white10)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: colors.searchHeaderIconBg, borderRadius: BorderRadius.circular(8)), child: Icon(Icons.search, color: colors.searchHeaderIcon)), const SizedBox(width: 12), Text("Plan Journey", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colors.textPrimary))]),
                  const SizedBox(height: 20),
                  _buildTextField("From", _fromController, _fromFocusNode, _fromStation != null, 'from', hint: (_fromStation == null && widget.currentPosition != null) ? "Current Location" : "Station or Address..."),
                  if (_activeSearchField == 'from') _buildSuggestionsList(),
                  const SizedBox(height: 12),
                  _buildTextField("To", _toController, _toFocusNode, _toStation != null, 'to'),
                  if (_activeSearchField == 'to') _buildSuggestionsList(),
                  const SizedBox(height: 20),
                  Text("Trip Time", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colors.sectionHeader)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: colors.timeContainerBg, borderRadius: BorderRadius.circular(16)),
                    child: Row(
                      children: [
                        GestureDetector(onTap: () => setState(() => _isArrival = !_isArrival), child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: colors.timeToggleBg, borderRadius: BorderRadius.circular(12)), child: Text(_isArrival ? "Arrive by" : "Depart at", style: TextStyle(color: colors.timeToggleText, fontWeight: FontWeight.w600, fontSize: 13, letterSpacing: 0.5)))),
                        const SizedBox(width: 12),
                        Expanded(child: GestureDetector(onTap: () async { final now = DateTime.now(); final picked = await showDatePicker(context: context, initialDate: _selectedDate ?? now, firstDate: now.subtract(const Duration(days: 30)), lastDate: now.add(const Duration(days: 90))); if (picked != null) { setState(() { _selectedDate = picked; _selectedTime ??= TimeOfDay.now(); }); final t = await showTimePicker(context: context, initialTime: _selectedTime!); if (t != null) setState(() => _selectedTime = t); } }, child: _selectedDate != null ? Row(children: [Icon(Icons.calendar_today, size: 16, color: colors.sectionHeader), const SizedBox(width: 6), Text("${_selectedDate!.day}.${_selectedDate!.month}  ${_selectedTime?.format(context) ?? ''}", style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold))]) : Row(children: [Icon(Icons.calendar_today, size: 16, color: colors.sectionHeader), const SizedBox(width: 6), Text("Now", style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold))]))),
                        if (_selectedDate != null) IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () => setState(() { _selectedDate = null; _selectedTime = null; })),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text("Favorites", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colors.sectionHeader)),
                  const SizedBox(height: 8),
                  SizedBox(height: 80, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: _favorites.length + 1, separatorBuilder: (_,__) => const SizedBox(width: 12), itemBuilder: (ctx, idx) { if (idx == _favorites.length) { return GestureDetector(onTap: _addNewFavorite, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Container(width: 48, height: 48, decoration: BoxDecoration(color: colors.favAddBg, shape: BoxShape.circle), child: Icon(Icons.add, color: colors.favAddIcon)), const SizedBox(height: 4), const Text("Add", style: TextStyle(fontSize: 10))])); } final fav = _favorites[idx]; IconData icon = Icons.star; if (fav.type == 'friend') icon = Icons.person; else if (fav.label.toLowerCase() == 'home') icon = Icons.home; else if (fav.label.toLowerCase() == 'work') icon = Icons.work; if (fav.iconCode != null) { icon = kAvailableIcons.firstWhere((i) => i.codePoint == fav.iconCode, orElse: () => Icons.star); } Color bg = fav.type == 'friend' ? colors.favFriendBg : colors.favStationBg; Color fg = fav.type == 'friend' ? colors.favFriendIcon : colors.favStationIcon; return GestureDetector(onTap: () => _onFavoriteTap(fav), onLongPress: () => _showEditFavoriteDialog(fav), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Container(width: 48, height: 48, decoration: BoxDecoration(color: bg, shape: BoxShape.circle), child: Icon(icon, color: fg, size: 20)), const SizedBox(height: 4), Text(fav.label, style: TextStyle(fontSize: 10, color: colors.favText))])); })),
                  const SizedBox(height: 20),
                  SizedBox(width: double.infinity, height: 56, child: ElevatedButton(onPressed: canSearch ? _findRoutes : null, style: ElevatedButton.styleFrom(backgroundColor: colors.searchBtnBg, foregroundColor: colors.searchBtnText, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: _isLoadingRoute ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text("Find Routes", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)))),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildSuggestionsList() {
    if (!_isSuggestionsLoading && _suggestions.isEmpty) return const SizedBox.shrink();
    final colors = TransColors.of(context);
    return GestureDetector(
      onTap: () {
        // Capture taps on the list container (including scrolling area) 
        // to prevent them from bubbling up to the main view's tap handler
        // which closes the keyboard.
      },
      child: Container(
      constraints: const BoxConstraints(maxHeight: 250), 
      margin: const EdgeInsets.only(top: 8), 
      decoration: BoxDecoration(
        color: colors.cardBg, 
        borderRadius: BorderRadius.circular(16), 
        border: Border.all(color: Colors.white10)
      ), 
      child: Material( // Wrap in Material for InkWell/Hover effects
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.hardEdge,
        child: Column(
          mainAxisSize: MainAxisSize.min, 
          children: [
            if (_isSuggestionsLoading) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator(minHeight: 2)), 
            // Removed Flexible, rely on constraints + shrinkWrap
            Flexible( // Actually Flexible/Expanded is needed if content exceeds 250px inside Column?? 
              // Usually inside a Column with min size, if we want it to scroll, we need constraints.
              // We have max-height 250 on Container.
              // If we put ListView directly in Column(min), and list is huge:
              // ListView(shrinkWrap: true) tries to be infinite? No, it tries to be as big as content.
              // If content > 250, Container clips? Or errors?
              // The original code had Flexible.
              // Let's use Flexible but inside Material?
              // Wait, Material is around the Column now.
              // Let's put Material inside the Container, and Column inside Material.
              // And keep Flexible for safety with scrolling?
              // User reported "no hover". That implies hit test failure. 
              // Often caused by "invisible" widgets blocking or weird z-index if no Material.
              // Let's stick to the plan: Remove Flexible IF it was the cause (zero height?), OR ensure it works.
              // Actually, ListView(shrinkWrap: true) inside Flexible inside Column(min) is tricky.
              // Better: Container(height: constraint) -> ClipR -> Material -> ListView.
              // But we want header (Progress) + List.
              // Let's go with: Container -> Column -> (Progress, Flexible(ListView)).
              // AND ensure Material is wrapping the ListView items individually or the whole list.
              // Best practice: Material > ListView.
              child: ListView.separated(
                shrinkWrap: true, 
                padding: EdgeInsets.zero, 
                itemCount: _suggestions.length, 
                separatorBuilder: (ctx, idx) => const Divider(height: 1, color: Colors.white10), 
                itemBuilder: (ctx, idx) { 
                  final item = _suggestions[idx]; 
                  if (item is Favorite) {
                    return ListTile(
                      leading: const Icon(Icons.star, size: 16, color: Colors.orange), 
                      title: Text(item.label, style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)), 
                      onTap: () => _selectItem(item),
                      hoverColor: Colors.white10, // Explicit hover color if theme missing
                    ); 
                  }
                  final station = item as Station; 
                  IconData leadingIcon = Icons.place; 
                  if (station.type == 'address') leadingIcon = Icons.home_work; 
                  return ListTile(
                    leading: Icon(leadingIcon, size: 16, color: Colors.grey), 
                    title: Text(station.name, style: TextStyle(color: colors.textPrimary, fontSize: 14)), 
                    onTap: () => _selectItem(station), 
                    hoverColor: Colors.white10,
                    onLongPress: () { 
                      final newFav = Favorite(id: DateTime.now().millisecondsSinceEpoch.toString(), label: station.name, type: 'station', station: station); 
                      _showEditFavoriteDialog(newFav); 
                    }
                  ); 
                }
              )
            )
          ]
        ),
      )
    ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, FocusNode focusNode, bool isSelected, String fieldKey, {String hint = "Station..."}) {
    final colors = TransColors.of(context);
    Color iconColor = colors.searchInputIcon;
    if (isSelected) iconColor = Colors.greenAccent; 
    else if (fieldKey == 'from' && ((_fromStation?.id == 'gps') || hint.contains("Location"))) iconColor = Colors.blue;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Padding(padding: const EdgeInsets.only(left: 4, bottom: 4), child: Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold))), TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: (val) => _onSearchChanged(val, fieldKey),
        onTap: () { setState(() => _activeSearchField = fieldKey); _fetchSuggestions(); _scrollToTop(); },
        style: TextStyle(color: colors.searchInputText),
        decoration: InputDecoration(
          filled: true,
          fillColor: colors.searchInputFill,
          prefixIcon: Icon(fieldKey == 'from' ? Icons.my_location : Icons.location_on, color: iconColor, size: 20),
          suffixIcon: (controller.text.isNotEmpty || isSelected)
              ? IconButton(
                  icon: Icon(Icons.close, size: 16, color: colors.searchHintText),
                  onPressed: () {
                    controller.clear();
                    _onSearchChanged('', fieldKey);
                  },
                )
              : null,
          hintText: hint,
          hintStyle: TextStyle(color: hint.contains("Location") ? Colors.blue.withValues(alpha: 0.5) : colors.searchHintText),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)
        )
    )]);
  }


  Future<void> _loadMoreRoutes(RouteTab route, {required bool earlier}) async {
    if (_isLoadingRoute) return;
    
    // Determine reference time
    DateTime refDate;
    bool isArrival;
    
    if (earlier) {
      if (route.candidates == null || route.candidates!.isEmpty) return;
      refDate = route.candidates!.first.departure.subtract(const Duration(minutes: 1));
      isArrival = true; // Find connections arriving before the first one's departure
    } else {
      if (route.candidates == null || route.candidates!.isEmpty) return;
      refDate = route.candidates!.last.departure.add(const Duration(minutes: 1));
      isArrival = false; // Find connections departing after the last one
    }
    
    setState(() => _isLoadingRoute = true);
    
    try {
      final Station? originStation = route.origin ?? _fromStation;
      if (originStation == null) throw Exception("Origin station lost");

      final newResults = await TransportApi.searchJourneys(
        originStation,
        route.destination,
        nahverkehrOnly: widget.onlyNahverkehr,
        when: refDate,
        isArrival: isArrival,
        results: 5
      );
      
      if (newResults.isNotEmpty && mounted) {
        final List<Journey> newJourneys = [];
        for (var d in newResults) {
             try { newJourneys.add(_createJourney(d)); } catch(_) {}
        }
        
        // Filter duplicates
        final currentIds = route.candidates!.map((j) => "${j.departure.millisecondsSinceEpoch}_${j.arrival.millisecondsSinceEpoch}").toSet();
        final uniqueNew = newJourneys.where((j) => !currentIds.contains("${j.departure.millisecondsSinceEpoch}_${j.arrival.millisecondsSinceEpoch}")).toList();
        
        if (uniqueNew.isNotEmpty) {
           setState(() {
             final idx = _tabs.indexWhere((t) => t.id == route.id);
             if (idx != -1) {
               final updatedCandidates = List<Journey>.from(route.candidates!);
               if (earlier) {
                 updatedCandidates.insertAll(0, uniqueNew);
               } else {
                 updatedCandidates.addAll(uniqueNew);
               }
               _tabs[idx] = route.copyWith(candidates: updatedCandidates);
             }
           });
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Could not load more routes: $e")));
    } finally {
      if (mounted) setState(() => _isLoadingRoute = false);
    }
  }

  Future<void> _refreshRoutes(RouteTab route) async {
    if (_isLoadingRoute) return;
    
    // We want to reset pagination and reload the initial search window.
    // Since we don't store the exact initial time, we'll use a best guess:
    // If the user hasn't changed the search inputs, we could use them.
    // Or we could use the route's origin/destination and "now" or the *arrival* time of the active journey?
    // Safer bet for "Refresh" is to assume the user wants updated info for the *current* list.
    // But usually Pull-to-Refresh means "Reload from scratch", typically based on "Now".
    
    // Let's use the route's first departure time as the "when" to keep context, 
    // or just effectively restart the search.
    // Decision: Restart search from "Now" logic or original time parameter.
    
    setState(() => _isLoadingRoute = true);
    
    try {
      final Station? originStation = route.origin ?? _fromStation;
      if (originStation == null) throw Exception("Origin station lost");
      
      // Use "Now" for refresh context for now
      final DateTime refDate = DateTime.now(); 

      final newResults = await TransportApi.searchJourneys(
        originStation,
        route.destination,
        nahverkehrOnly: widget.onlyNahverkehr,
        when: refDate,
        isArrival: false, // Default to departure now
        results: 5
      );
      
      if (newResults.isNotEmpty && mounted) {
        final List<Journey> newJourneys = [];
        for (var d in newResults) {
             try { newJourneys.add(_createJourney(d)); } catch(_) {}
        }
        
        setState(() {
             final idx = _tabs.indexWhere((t) => t.id == route.id);
             if (idx != -1) {
               // Replace candidates entirely
               _tabs[idx] = route.copyWith(candidates: newJourneys);
             }
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Could not refresh routes: $e")));
    } finally {
      if (mounted) setState(() => _isLoadingRoute = false);
    }
  }

  Widget _buildActiveRouteView(RouteTab route) {
    if (route.activeJourney == null && route.candidates != null && route.candidates!.isNotEmpty) {
      return RouteResultsView(
        candidates: route.candidates!,
        onSelect: (journey) {
          setState(() {
            final idx = _tabs.indexWhere((t) => t.id == route.id);
            if (idx != -1) {
              final currentStack = List<Journey>.from(route.stack);
              if (!currentStack.contains(journey)) currentStack.add(journey);
              
              _tabs[idx] = route.copyWith(
                activeJourney: journey, 
                stack: currentStack,
                steps: journey.steps,
                totalDuration: FormatUtils.formatDuration(journey.duration.inMinutes),
              );
            }
          });
        },
        onBack: () => _closeTab(route.id),
        onLoadEarlier: () => _loadMoreRoutes(route, earlier: true),
        onLoadLater: () => _loadMoreRoutes(route, earlier: false),
        onRefresh: () => _refreshRoutes(route),
        showTrainNumbers: widget.showTrainNumbers, // Pass the setting
      );
    }
    
    final colors = TransColors.of(context);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 100), children: [
        Padding(padding: const EdgeInsets.symmetric(vertical: 8.0), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            if (route.candidates != null && route.candidates!.length > 1) 
               IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(), icon: const Icon(Icons.arrow_back), onPressed: () => setState(() {
                 final idx = _tabs.indexWhere((t) => t.id == route.id);
                 if (idx != -1) _tabs[idx] = route.copyWith(clearActiveJourney: true);
               })),
            if (route.candidates != null && route.candidates!.length > 1) const SizedBox(width: 8),

            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(route.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: colors.textPrimary)), Row(children: [Text(route.activeJourney != null ? "${DateFormat('HH:mm').format(route.activeJourney!.departure)} - ${DateFormat('HH:mm').format(route.activeJourney!.arrival)}" : route.subtitle, style: TextStyle(color: colors.textSecondary)), if (route.source != null) ...[const SizedBox(width: 8), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: route.source == 'motis' ? Colors.blue.withValues(alpha: 0.2) : Colors.red.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)), child: Row(children: [Icon(route.source == 'motis' ? Icons.public : Icons.dns, size: 10, color: route.source == 'motis' ? Colors.blue : Colors.red), const SizedBox(width: 4), Text(route.source == 'motis' ? 'Transitous' : 'DB', style: TextStyle(color: route.source == 'motis' ? Colors.blue : Colors.red, fontSize: 10, fontWeight: FontWeight.bold))]))]])])), IconButton(icon: const Icon(Icons.map, color: Colors.blue), onPressed: () => _openMap(route)), const SizedBox(width: 8), Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.timer_outlined, size: 16, color: Colors.green), const SizedBox(width: 4), Text(route.totalDuration, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold))]))])), 
        for (int i = 0; i < route.steps.length; i++) _StepCard(step: route.steps[i], isFirst: i == 0, finalDestinationId: route.destination.id, onOpenAlternatives: (stationId, time, {double? lat, double? lng, String? name}) => _showAlternatives(context, stationId, route.destination, time, lat: lat, lng: lng, stationName: name), onChat: (line) => _showChat(context, line), onAlarmToggle: () => _toggleWakeAlarm(route), isAlarmSet: _isWakeAlarmSet, onMapTap: () => _openMap(route, focusStep: route.steps[i]), showTrainNumbers: widget.showTrainNumbers)
    ]);
  }
}

class _StepCard extends StatefulWidget {
  final JourneyStep step;
  final bool isFirst;
  final String finalDestinationId;
  final Function(String, DateTime, {double? lat, double? lng, String? name}) onOpenAlternatives;
  final Function(String) onChat;
  final VoidCallback onAlarmToggle;
  final VoidCallback onMapTap;
  final bool isAlarmSet;
  final bool showTrainNumbers;

  const _StepCard({
    required this.step, 
    this.isFirst = false, 
    required this.finalDestinationId, 
    required this.onOpenAlternatives, 
    required this.onChat, 
    required this.onAlarmToggle, 
    required this.isAlarmSet, 
    required this.onMapTap,
    required this.showTrainNumbers,
  });

  @override
  State<_StepCard> createState() => _StepCardState();
}

class _StepCardState extends State<_StepCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    final step = widget.step;
    final bool isWait = step.type == 'wait';
    final isTransfer = step.type == 'transfer' || isWait || step.type == 'walk';

    if (isTransfer) { 
      Widget iconWidget = Icon(Icons.directions_walk, color: colors.stepTransferText); 
      if (isWait) iconWidget = Icon(Icons.man, color: colors.stepTransferText); 
      return GestureDetector(onTap: isWait ? null : widget.onMapTap, child: Container(margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: colors.stepTransferBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: colors.stepTransferBorder)), child: Row(children: [iconWidget, const SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(step.instruction, style: TextStyle(fontWeight: FontWeight.bold, color: colors.textPrimary)), Text(step.duration, style: TextStyle(color: colors.stepTransferText, fontSize: 12))]))]))); 
    }
    
    return Card(
      margin: EdgeInsets.only(bottom: 16, top: widget.isFirst ? 0 : 4), 
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), 
      elevation: 0, 
      color: colors.stepCardBg, 
      child: Theme(data: Theme.of(context).copyWith(dividerColor: Colors.transparent), child: ExpansionTile(
        tilePadding: const EdgeInsets.fromLTRB(16, 8, 0, 8), 
        onExpansionChanged: (val) => setState(() => _isExpanded = val),
        title: Builder(
          builder: (context) {
             final dest = (step.destinationName ?? step.instruction.split('→').last.trim());
             final head = (step.headsign ?? '').trim();
             // Check if destination is practically the headsign (End of Line)
             // Use simple string containment or equality check
             final isEnd = dest.isNotEmpty && head.isNotEmpty && (head.toLowerCase().contains(dest.toLowerCase()) || dest.toLowerCase().contains(head.toLowerCase()));
             final displayDest = isEnd ? "End of Line" : dest;

             // Title: Bus Number -> Destination (Expanded) + Arrow (Right)
             return Row(
               crossAxisAlignment: CrossAxisAlignment.start,
               children: [
                 Expanded(
                   child: Row(
                     children: [
                       Builder(
                          builder: (context) {
                            String displayLine = step.line.trim();
                            
                            if (!widget.showTrainNumbers) {
                               final regexParens = RegExp(r'\s*\(\d+\)$');
                               displayLine = displayLine.replaceAll(regexParens, '').trim();

                               if (step.tripId != null) {
                                   displayLine = displayLine.replaceAll(step.tripId!, "").trim();
                               }
                            }

                            String suffix = "";
                            if (widget.showTrainNumbers && step.tripId != null) {
                               if (!displayLine.contains(step.tripId!)) {
                                  suffix = " (${step.tripId})";
                               }
                            }
                            
                            return Text(
                              "$displayLine$suffix",
                              style: TextStyle(fontWeight: FontWeight.bold, color: colors.textPrimary)
                            );
                          }
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.arrow_right_alt, size: 24, color: colors.textPrimary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            displayDest, 
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: colors.textPrimary), 
                            overflow: TextOverflow.visible, 
                          )
                        ),
                     ],
                   )
                 ),
                 const SizedBox(width: 8),
                 // Manual Arrow on Top Line with Rotation
                 AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.keyboard_arrow_down, color: _isExpanded ? colors.effectiveSeed : colors.textSecondary)
                 ),
               ],
             );
          }
        ),
        trailing: const SizedBox.shrink(), // Hide default centered arrow
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 4), 
          // Info Line: Headsign • Duration
          Text("${step.headsign ?? ''}  •  ${step.duration}", style: TextStyle(color: colors.textSecondary)), 
          if (step.platform != null) Text(step.platform!, style: TextStyle(color: colors.stepPlatformText, fontSize: 12)), 
          
          const SizedBox(height: 12), // Spacer before actions
          
          // Action Buttons + Time (Bottom Row)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Actions (Left)
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal, 
                  child: Row(children: [
                    _buildActionChip(
                      context, 
                      Icons.chat_bubble_outline, 
                      "Chat", 
                      onTap: () => widget.onChat(step.line)
                    ), 
                    const SizedBox(width: 8), 
                    if (step.startStationId != null && step.dateTime != null) ...[
                      _buildActionChip(
                        context, 
                        Icons.alt_route, 
                        "Alt", 
                        onTap: () => widget.onOpenAlternatives(step.startStationId!, step.dateTime!, lat: step.startLat, lng: step.startLng)
                      ), 
                      const SizedBox(width: 8)
                    ], 
                    _buildActionChip(context, Icons.vibration, widget.isAlarmSet ? "Alarm ON" : "Wake Me", isActive: widget.isAlarmSet, onTap: widget.onAlarmToggle)
                  ])
                )
              ),
              const SizedBox(width: 8),
              
              // Time (Right)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("${step.departureTime} - ${step.arrivalTime}", style: TextStyle(fontWeight: FontWeight.bold, color: step.isCancelled ? colors.textSecondary : colors.stepTimeText, decoration: step.isCancelled ? TextDecoration.lineThrough : null)),
                  if (step.isCancelled)
                     const Text(" CANCELLED", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 12))
                  else if (step.departureDelay != null && step.departureDelay != 0)
                     Text(" (${step.departureDelay! > 0 ? '+' : ''}${step.departureDelay})", style: TextStyle(fontWeight: FontWeight.bold, color: step.departureDelay! > 0 ? colors.delayLate : colors.delayOnTime))
                ],
              )
            ],
          )
        ]), 
        children: [
          if (step.stopovers != null && step.stopovers!.isNotEmpty) 
            Container(decoration: BoxDecoration(color: colors.stepStopoversBg), child: ListView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: step.stopovers!.length, itemBuilder: (ctx, idx) { 
              final stop = step.stopovers![idx]; 
              final name = stop['stop']['name']; 
              final stopId = stop['stop']['id']; 
              final plannedDep = stop['plannedDeparture'] ?? stop['scheduledDeparture'] ?? stop['plannedArrival'] ?? stop['scheduledArrival']; 
              final actualDep = stop['departure'] ?? stop['arrival']; 
              String timeStr = "--:--"; 
              Color timeColor = Colors.grey; 
              DateTime? exactStopDate;

              if (plannedDep != null) { 
                final p = DateTime.parse(plannedDep); 
                exactStopDate = p;
                timeStr = "${p.hour.toString().padLeft(2,'0')}:${p.minute.toString().padLeft(2,'0')}"; 
                if (actualDep != null) { 
                  final a = DateTime.parse(actualDep); 
                  final delay = a.difference(p).inMinutes; 
                  if (delay > 2) { timeStr += " (+${delay}')"; timeColor = colors.delayLate; } 
                  else { timeColor = colors.delayOnTime; } 
                } 
              } 
              return ListTile(
                dense: true, 
                contentPadding: const EdgeInsets.symmetric(horizontal: 20), 
                leading: const Icon(Icons.circle, size: 8, color: Colors.grey), 
                title: Text(name, style: TextStyle(color: colors.textPrimary, fontSize: 13)), 
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(timeStr, style: TextStyle(color: timeColor, fontSize: 12)), 
                  const SizedBox(width: 8), 
                  if (exactStopDate != null)
                    IconButton(
                      icon: const Icon(Icons.alt_route, size: 16, color: Colors.blue), 
                      // FIX: Pass exact stop time and location if available
                      onPressed: () => widget.onOpenAlternatives(stopId, exactStopDate!, lat: stop['stop']['location']?['latitude'], lng: stop['stop']['location']?['longitude'], name: name)
                    )
                ])
              ); 
            })) 
          else const Padding(padding: EdgeInsets.all(16), child: Text("No intermediate stops info.")),
          // Always show the link to the final destination as the last item
          Container(
            decoration: BoxDecoration(color: colors.stepStopoversBg),
            child: ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: const Icon(Icons.flag, size: 14, color: Colors.red),
              title: Text("Get off at ${step.destinationName ?? 'Destination'}", style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
              trailing: Builder(builder: (context) {
                 String timeStr = step.arrivalTime;
                 Color timeColor = colors.delayOnTime;
                 if (step.arrivalDelay != null && step.arrivalDelay! > 0) {
                   timeColor = colors.delayLate;
                   timeStr += " (+${step.arrivalDelay})";
                 }
                 return Text(timeStr, style: TextStyle(color: timeColor, fontWeight: FontWeight.bold, fontSize: 13));
              }),
            )
          )
        ]
      ))
    );
  }
  
  Widget _buildActionChip(BuildContext context, IconData icon, String label, {bool isActive = false, required VoidCallback onTap}) {
    final colors = TransColors.of(context);
    return GestureDetector(onTap: onTap, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: isActive ? colors.chipActiveBg : colors.chipBg, borderRadius: BorderRadius.circular(20)), child: Row(children: [Icon(icon, size: 14, color: isActive ? colors.chipActiveFg : colors.chipFg), const SizedBox(width: 6), Text(label, style: TextStyle(color: isActive ? colors.chipActiveFg : colors.chipFg, fontSize: 12))])));
  }
}


class _EditFavoriteDialog extends StatefulWidget {
  final Favorite favorite;
  const _EditFavoriteDialog({required this.favorite});
  @override
  State<_EditFavoriteDialog> createState() => _EditFavoriteDialogState();
}

class _EditFavoriteDialogState extends State<_EditFavoriteDialog> {
  late TextEditingController _labelCtrl;
  final TextEditingController _searchCtrl = TextEditingController();
  late String _currentType;
  Station? _selectedStation;
  String? _selectedFriendId;
  int? _selectedIconCode;
  List<Station> _suggestions = [];
  Timer? _debounce;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: widget.favorite.label);
    _currentType = widget.favorite.type;
    _selectedStation = widget.favorite.station;
    _selectedFriendId = widget.favorite.friendId;
    _selectedIconCode = widget.favorite.iconCode;
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isNew = widget.favorite.id.isEmpty;
    final colors = TransColors.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: colors.cardBg,
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(20),
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isNew ? "Add Favorite" : "Edit Favorite", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colors.textPrimary)),
              const SizedBox(height: 20),
              TextField(controller: _labelCtrl, decoration: const InputDecoration(labelText: "Label (e.g. Home, Bestie)")),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: RadioListTile<String>(title: const Text("Station"), value: 'station', groupValue: _currentType, contentPadding: EdgeInsets.zero, onChanged: (val) => setState(() => _currentType = val!))),
                Expanded(child: RadioListTile<String>(title: const Text("Friend"), value: 'friend', groupValue: _currentType, contentPadding: EdgeInsets.zero, onChanged: (val) => setState(() => _currentType = val!))),
              ]),
              const SizedBox(height: 10),
              SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: kAvailableIcons.map((icon) { final isSelected = _selectedIconCode == icon.codePoint; return GestureDetector(onTap: () => setState(() => _selectedIconCode = icon.codePoint), child: Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: isSelected ? colors.navBarSelected : colors.chipBg, shape: BoxShape.circle), child: Icon(icon, size: 20, color: isSelected ? Colors.white : Colors.grey))); }).toList())),
              const SizedBox(height: 10),
              if (_currentType == 'station') ...[
                if (_selectedStation != null) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.train, color: Colors.indigo), title: Text(_selectedStation!.name, style: const TextStyle(fontWeight: FontWeight.bold)), trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() { _selectedStation = null; _searchCtrl.clear(); _suggestions = []; })))
                else ...[
                  TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(labelText: "Search Station Name", prefixIcon: const Icon(Icons.search), suffix: SizedBox(width: 16, height: 16, child: _isLoading ? const CircularProgressIndicator(strokeWidth: 2) : null)),
                    onChanged: (val) {
                      if (_debounce?.isActive ?? false) _debounce!.cancel();
                      if (val.trim().isEmpty) { if (mounted) setState(() => _suggestions = []); return; }
                      _debounce = Timer(const Duration(milliseconds: 400), () async {
                        if (!mounted) return;
                        setState(() => _isLoading = true);
                        try {
                          final res = await TransportApi.searchStations(val).timeout(const Duration(seconds: 10));
                          if (mounted) setState(() { _suggestions = res; _isLoading = false; });
                        } catch (e) {
                          if (mounted) setState(() => _isLoading = false);
                        }
                      });
                    },
                  ),
                  if (_suggestions.isNotEmpty) Container(height: 150, margin: const EdgeInsets.only(top: 8), decoration: BoxDecoration(border: Border.all(color: Colors.white10), borderRadius: BorderRadius.circular(8)), child: ListView.builder(itemCount: _suggestions.length, itemBuilder: (context, idx) { final s = _suggestions[idx]; return ListTile(dense: true, title: Text(s.name), onTap: () { if (!mounted) return; setState(() { _selectedStation = s; _suggestions = []; if (_labelCtrl.text.isEmpty) _labelCtrl.text = s.name; }); }); }))
                ]
              ],
              if (_currentType == 'friend') ...[
                 TextField(decoration: const InputDecoration(labelText: "Search Friend Username"), onSubmitted: (val) async { final res = await SupabaseService.searchUsers(val); if (res.isNotEmpty && mounted) { setState(() { _selectedFriendId = res.first['id']; if (_labelCtrl.text.isEmpty) { _labelCtrl.text = res.first['username']; } }); } }),
                 if (_selectedFriendId != null) const Padding(padding: EdgeInsets.only(top: 8), child: Text("Friend Selected", style: TextStyle(color: Colors.green))),
              ],
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [if (!isNew && widget.favorite.id != 'home' && widget.favorite.id != 'work') TextButton(onPressed: () async { await FavoritesManager.deleteFavorite(widget.favorite.id); if (mounted) Navigator.pop(context, true); }, child: const Text("Delete", style: TextStyle(color: Colors.red))), const SizedBox(width: 8), TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")), ElevatedButton(onPressed: () async { if (_labelCtrl.text.isNotEmpty) { final newFav = Favorite(id: isNew ? DateTime.now().millisecondsSinceEpoch.toString() : widget.favorite.id, label: _labelCtrl.text, type: _currentType, station: _selectedStation, friendId: _selectedFriendId, iconCode: _selectedIconCode); await FavoritesManager.saveFavorite(newFav); if (mounted) Navigator.pop(context, true); } }, child: const Text("Save"))])
            ],
          ),
        ),
      ),
    );
  }
}