import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vibration/vibration.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import 'package:trans/models/station.dart';
import 'package:trans/models/journey.dart';
import 'package:trans/models/favorite.dart';
import 'package:trans/services/transport_api.dart';
import 'package:trans/services/supabase_service.dart';
import 'package:trans/services/history_manager.dart';
import 'package:trans/services/favorites_manager.dart';
import 'package:trans/widgets/chat_sheet.dart';
import 'package:trans/config/app_theme.dart';
import 'package:trans/utils/format_utils.dart'; 
import '../map_screen.dart'; 

const List<IconData> kAvailableIcons = [
  Icons.star, Icons.home, Icons.work, Icons.favorite, 
  Icons.train, Icons.directions_bus, Icons.school, 
  Icons.person, Icons.location_on, Icons.shopping_cart, 
  Icons.fitness_center, Icons.local_cafe, Icons.local_airport
];

class RoutesTab extends StatefulWidget {
  final Position? currentPosition;
  final bool onlyNahverkehr;

  const RoutesTab({
    super.key,
    required this.currentPosition,
    required this.onlyNahverkehr
  });

  @override
  State<RoutesTab> createState() => _RoutesTabState();
}

class _RoutesTabState extends State<RoutesTab> {
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
  bool _isLoadingRoute = false;
  bool _isSuggestionsLoading = false;
  
  DateTime? _selectedDate; 
  TimeOfDay? _selectedTime;
  bool _isArrival = false; 

  bool _isWakeAlarmSet = false;
  StreamSubscription<Position>? _gpsStream;
  double? _gpsAccuracy;
  List<Favorite> _favorites = [];

  @override
  void initState() {
    super.initState();
    _fetchSuggestions(forceHistory: true);
    _loadFavorites();
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    _fromFocusNode.dispose();
    _toFocusNode.dispose();
    _scrollController.dispose();
    _debounce?.cancel();
    _gpsStream?.cancel();
    super.dispose();
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
    
    String msg = "Wake Alarm Set!";
    if (stopsBefore > 0) msg += " Alerting $stopsBefore stop(s) early.";
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

    const settings = LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 50);
    if (widget.currentPosition != null) {
       SupabaseService.updateLocation(widget.currentPosition!, currentLine: currentLine);
    }

    _gpsStream = Geolocator.getPositionStream(locationSettings: settings).listen((Position pos) {
      if (mounted) setState(() => _gpsAccuracy = pos.accuracy);
      SupabaseService.updateLocation(pos, currentLine: currentLine);
      double dist = Geolocator.distanceBetween(pos.latitude, pos.longitude, targetLat!, targetLng!);
      if (dist < 500) { 
         _triggerVibration();
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
    if (query.isEmpty) return;
    setState(() => _isSuggestionsLoading = true);
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (query.length > 2) {
        double? refLat = widget.currentPosition?.latitude;
        double? refLng = widget.currentPosition?.longitude;
        try {
          final apiResults = await TransportApi.searchStations(query, lat: refLat, lng: refLng);
          if (mounted) {
            setState(() { 
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
          if (mounted) setState(() => _isSuggestionsLoading = false);
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
        if (_activeSearchField == 'from') {
           _fromStation = target;
           _fromController.text = target!.name;
           if (_toStation == null) {
             _activeSearchField = 'to';
             _toFocusNode.requestFocus();
             _scrollToTop();
           }
        } else if (_activeSearchField == 'to') {
           _toStation = target;
           _toController.text = target!.name;
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
  
  void _showAlternatives(BuildContext context, String stationId, String finalDestinationId) {
      Station fromDummy = Station(id: stationId, name: "From");
      Station toDummy = Station(id: finalDestinationId, name: "To");
      showModalBottomSheet(context: context, backgroundColor: Theme.of(context).cardColor, builder: (ctx) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: TransportApi.searchJourneys(fromDummy, toDummy, nahverkehrOnly: widget.onlyNahverkehr, when: DateTime.now(), results: 5), 
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("No routes to destination found."));
            return ListView.builder(padding: const EdgeInsets.all(16), itemCount: snapshot.data!.length, itemBuilder: (ctx, idx) {
                final journey = snapshot.data![idx];
                final legs = journey['legs'] as List;
                if (legs.isEmpty) return const SizedBox.shrink();
                final firstRide = legs.firstWhere((l) => l['line'] != null, orElse: () => legs.first);
                final line = firstRide['line'] != null ? firstRide['line']['name'] : 'Walk/Transfer';
                final dir = firstRide['direction'] ?? 'Destination';
                final depTime = DateTime.parse(firstRide['departure'] ?? firstRide['plannedDeparture']);
                return ListTile(leading: const Icon(Icons.alt_route), title: Text("$line to $dir"), subtitle: Text("Departs ${DateFormat('HH:mm').format(depTime)}"), onTap: () { Navigator.pop(context); _addJourneyTab(journey, title: "Alternative", subtitle: "Departs ${DateFormat('HH:mm').format(depTime)}"); });
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
    double? getLat(dynamic loc) => loc != null && loc['location'] != null ? loc['location']['latitude'] : (loc != null ? loc['latitude'] : null);
    double? getLng(dynamic loc) => loc != null && loc['location'] != null ? loc['location']['longitude'] : (loc != null ? loc['longitude'] : null);
    void flushTransferBuffer(DateTime? nextRideDeparture, String? nextStationName, double? nextRideStartLat, double? nextRideStartLng) {
      if (transferBuffer.isEmpty && (lastArrival == null || nextRideDeparture == null)) return;
      DateTime blockStart = (lastArrival != null) ? lastArrival! : DateTime.tryParse(transferBuffer.first['departure'] ?? transferBuffer.first['plannedDeparture'] ?? '') ?? DateTime.now();
      DateTime blockEnd = (nextRideDeparture != null) ? nextRideDeparture : (transferBuffer.isNotEmpty ? DateTime.tryParse(transferBuffer.last['arrival'] ?? transferBuffer.last['plannedArrival'] ?? '') ?? blockStart : blockStart);
      int walkMinutes = 0;
      for (var leg in transferBuffer) { try { walkMinutes += DateTime.parse(leg['arrival'] ?? leg['plannedArrival']).difference(DateTime.parse(leg['departure'] ?? leg['plannedDeparture'])).inMinutes; } catch(e) {} }
      int totalGapMinutes = blockEnd.difference(blockStart).inMinutes;
      if (totalGapMinutes < 0) totalGapMinutes = 0;
      double? startLat = getLat(transferBuffer.isNotEmpty ? transferBuffer.first['origin'] : null);
      if (startLat == null && steps.isNotEmpty) startLat = steps.last.endLat;
      double? startLng = getLng(transferBuffer.isNotEmpty ? transferBuffer.first['origin'] : null);
      if (startLng == null && steps.isNotEmpty) startLng = steps.last.endLng;
      steps.add(JourneyStep(type: (walkMinutes > 0) ? 'walk' : 'wait', line: 'Transfer', instruction: walkMinutes > 0 ? (nextStationName != null ? "Walk to $nextStationName" : "Walk") : "Transfer", duration: FormatUtils.formatDuration(totalGapMinutes), departureTime: "${blockStart.hour.toString().padLeft(2,'0')}:${blockStart.minute.toString().padLeft(2,'0')}", arrivalTime: "${blockEnd.hour.toString().padLeft(2,'0')}:${blockEnd.minute.toString().padLeft(2,'0')}", isWalking: walkMinutes > 0, startLat: startLat, startLng: startLng, endLat: nextRideStartLat, endLng: nextRideStartLng, path: transferBuffer.isNotEmpty ? transferBuffer.first['decodedPath'] : null));
      transferBuffer.clear();
    }
    for (var leg in legs) {
      if (leg['line'] != null && leg['line']['name'] != null) {
        DateTime? dep, arr;
        try { dep = DateTime.parse(leg['departure']); arr = DateTime.parse(leg['arrival']); } catch(e) {}
        if (dep == null || arr == null) continue;
        flushTransferBuffer(dep, leg['origin']?['name'], getLat(leg['origin']), getLng(leg['origin']));
        steps.add(JourneyStep(type: 'ride', line: leg['line']?['name']?.toString() ?? '?', instruction: "${leg['line']?['name'] ?? '?'} → ${leg['direction'] ?? 'Destination'}", duration: FormatUtils.formatDuration(arr.difference(dep).inMinutes), departureTime: DateFormat('HH:mm').format(dep), arrivalTime: DateFormat('HH:mm').format(arr), chatCount: random.nextInt(15), startStationId: leg['origin']?['id']?.toString(), platform: leg['platform']?.toString(), stopovers: leg['stopovers'], startLat: getLat(leg['origin']), startLng: getLng(leg['origin']), endLat: getLat(leg['destination']), endLng: getLng(leg['destination']), path: leg['decodedPath']));
        lastArrival = arr;
      } else { transferBuffer.add(leg); }
    }
    flushTransferBuffer(null, "Destination", null, null);
    return steps;
  }
  
  void _addJourneyTab(Map<String, dynamic> journeyData, {String title = "Route", String? subtitle}) {
    if (journeyData['legs'] == null) return;
    final List legs = journeyData['legs'];
    final List<JourneyStep> steps = _processLegs(legs);
    String duration = "";
    DateTime? arr;
    try {
      if (legs.isNotEmpty) {
        final start = DateTime.parse(legs.first['departure']);
        final end = DateTime.parse(legs.last['arrival']);
        duration = FormatUtils.formatDuration(end.difference(start).inMinutes);
      }
      if (journeyData['arrival'] != null) arr = DateTime.parse(journeyData['arrival']);
    } catch(e) {}
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    setState(() {
      _tabs.add(RouteTab(id: id, title: title == "Route" ? (_toStation?.name ?? "Route") : title, subtitle: subtitle ?? "Details", eta: arr != null ? DateFormat('HH:mm').format(arr) : "--:--", totalDuration: duration, destinationId: _toStation?.id ?? "", steps: steps));
      _activeTabId = id;
      if (title != "Alternative") { _fromStation = null; _toStation = null; _fromController.clear(); _toController.clear(); }
    });
  }

  Future<void> _findRoutes() async {
     if (_isLoadingRoute) return;
     Station? from = _fromStation;
     if (from == null && widget.currentPosition != null) {
        from = Station(id: 'gps', name: 'Current Location', type: 'location', latitude: widget.currentPosition!.latitude, longitude: widget.currentPosition!.longitude);
     }
     if (from == null || _toStation == null) { if (mounted) setState(() => _isLoadingRoute = false); return; }
     setState(() => _isLoadingRoute = true);
     try {
       final res = await TransportApi.searchJourneys(from, _toStation!, nahverkehrOnly: widget.onlyNahverkehr, when: _selectedDate != null ? DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day, _selectedTime?.hour ?? 0, _selectedTime?.minute ?? 0) : null, isArrival: _isArrival).timeout(const Duration(seconds: 15)); 
       if (mounted) {
         if (res.isNotEmpty) { _addJourneyTab(res.first); } else { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No routes found"))); }
       }
     } catch(e) {
       if(mounted && !e.toString().contains("Timeout")) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
     } finally {
       if (mounted) setState(() => _isLoadingRoute = false);
     }
  }

  Future<void> _triggerVibration() async {
    if (kIsWeb) return; 
    bool? hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == null || !hasVibrator) return;
    final prefs = await SharedPreferences.getInstance();
    final String patternName = prefs.getString('vibration_pattern') ?? 'standard';
    final int intensity = prefs.getInt('vibration_intensity') ?? 128;
    List<int> pattern = [0, 500];
    switch (patternName) {
      case 'heartbeat': pattern = [0, 150, 150, 150]; break;
      case 'tick': pattern = [0, 50]; break;
      case 'mario': pattern = [0, 150, 100, 150, 100, 150, 200, 300]; break;
      case 'fox': pattern = [0, 100, 50, 100, 50, 100, 50, 400, 200, 200, 100, 600]; break;
      case 'imperial': pattern = [0, 400, 200, 400, 200, 400, 200, 250, 100, 400, 200, 250, 100, 400]; break;
      case 'potter': pattern = [0, 300, 150, 150, 150, 300, 100, 300]; break;
      case 'indy': pattern = [0, 100, 50, 100, 50, 400, 200, 100, 50, 100, 50, 800]; break;
      case 'mission': pattern = [0, 500, 200, 500, 200, 150, 50, 150, 50]; break;
      case 'terminator': pattern = [0, 100, 100, 100, 200, 100, 50, 100]; break;
      case 'future': pattern = [0, 100, 50, 100, 50, 100, 200, 400, 100, 400, 100, 600]; break;
      case 'eva': pattern = [0, 100, 50, 100, 50, 100, 50, 100, 200, 300, 100, 300, 100, 300, 100, 300]; break;
      case 'pokemon': pattern = [0, 100, 50, 100, 50, 100, 200, 400, 100, 400, 100, 400]; break;
      case 'titan': pattern = [0, 200, 100, 200, 300, 200, 100, 200, 300, 600]; break;
      case 'bebop': pattern = [0, 300, 300, 300, 300, 300, 300, 600, 50, 50, 50, 50, 50, 50]; break;
    }
    if (await Vibration.hasAmplitudeControl() ?? false) {
      Vibration.vibrate(pattern: pattern, intensities: pattern.map((_) => intensity).toList());
    } else {
      Vibration.vibrate(pattern: pattern);
    }
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
  Widget build(BuildContext context) {
    final bool canSearch = (_fromStation != null || widget.currentPosition != null) && _toStation != null && !_isLoadingRoute;
    final colors = TransColors.of(context);
    final topPadding = MediaQuery.of(context).padding.top + 10;

    return Column(children: [
        // FIX: Dynamic Top Padding
        SizedBox(height: topPadding),
        
        if (_isWakeAlarmSet && _gpsAccuracy != null && _gpsAccuracy! > 100) Container(width: double.infinity, padding: const EdgeInsets.all(8), color: Colors.amber, child: const Text("⚠️ Weak GPS", textAlign: TextAlign.center)),
        if (_tabs.isNotEmpty) SizedBox(height: 50, child: ListView.builder(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: _tabs.length + 1, itemBuilder: (ctx, idx) { if (idx == _tabs.length) return IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => setState(() => _activeTabId = null)); final tab = _tabs[idx]; final isActive = tab.id == _activeTabId; return GestureDetector(onTap: () => setState(() => _activeTabId = tab.id), child: Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: isActive ? colors.navBarSelected : colors.cardBg, borderRadius: BorderRadius.circular(20)), child: Row(children: [Icon(Icons.directions, size: 16, color: isActive ? Colors.white : Colors.grey), const SizedBox(width: 6), Text(tab.title, style: TextStyle(color: isActive ? Colors.white : Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)), const SizedBox(width: 4), GestureDetector(onTap: () => _closeTab(tab.id), child: Icon(Icons.close, size: 14, color: isActive ? Colors.white70 : Colors.grey))])));})),
        Expanded(child: _activeTabId == null ? _buildSearchView(canSearch, colors) : _buildActiveRouteView(_tabs.firstWhere((t) => t.id == _activeTabId))),
    ]);
  }

  Widget _buildSearchView(bool canSearch, TransColors colors) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return SingleChildScrollView(
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
                        GestureDetector(
                          onTap: () => setState(() => _isArrival = !_isArrival),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), 
                            decoration: BoxDecoration(color: colors.timeToggleBg, borderRadius: BorderRadius.circular(12)),
                            child: Text(_isArrival ? "Arrive by" : "Depart at", style: TextStyle(color: colors.timeToggleText, fontWeight: FontWeight.w600, fontSize: 13, letterSpacing: 0.5))
                          )
                        ),
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
    );
  }

  Widget _buildSuggestionsList() {
    if (!_isSuggestionsLoading && _suggestions.isEmpty) return const SizedBox.shrink();
    final colors = TransColors.of(context);
    return Container(constraints: const BoxConstraints(maxHeight: 250), margin: const EdgeInsets.only(top: 8), decoration: BoxDecoration(color: colors.cardBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)), child: Column(mainAxisSize: MainAxisSize.min, children: [if (_isSuggestionsLoading) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator(minHeight: 2)), Flexible(child: ListView.separated(shrinkWrap: true, padding: EdgeInsets.zero, itemCount: _suggestions.length, separatorBuilder: (ctx, idx) => const Divider(height: 1, color: Colors.white10), itemBuilder: (ctx, idx) { final item = _suggestions[idx]; if (item is Favorite) return ListTile(leading: const Icon(Icons.star, size: 16, color: Colors.orange), title: Text(item.label, style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)), onTap: () => _selectItem(item)); final station = item as Station; IconData leadingIcon = Icons.place; if (station.type == 'address') leadingIcon = Icons.home_work; return ListTile(leading: Icon(leadingIcon, size: 16, color: Colors.grey), title: Text(station.name, style: TextStyle(color: colors.textPrimary, fontSize: 14)), onTap: () => _selectItem(station), onLongPress: () { final newFav = Favorite(id: DateTime.now().millisecondsSinceEpoch.toString(), label: station.name, type: 'station', station: station); _showEditFavoriteDialog(newFav); }); }))]));
  }

  Widget _buildTextField(String label, TextEditingController controller, FocusNode focusNode, bool isSelected, String fieldKey, {String hint = "Station..."}) {
    final colors = TransColors.of(context);
    Color iconColor = colors.searchInputIcon;
    if (isSelected) iconColor = Colors.greenAccent; 
    else if (fieldKey == 'from' && hint.contains("Location")) iconColor = Colors.blue;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Padding(padding: const EdgeInsets.only(left: 4, bottom: 4), child: Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold))), TextField(controller: controller, focusNode: focusNode, onChanged: (val) => _onSearchChanged(val, fieldKey), onTap: () { setState(() => _activeSearchField = fieldKey); _scrollToTop(); }, style: TextStyle(color: colors.searchInputText), decoration: InputDecoration(filled: true, fillColor: colors.searchInputFill, prefixIcon: Icon(fieldKey == 'from' ? Icons.my_location : Icons.location_on, color: iconColor, size: 20), hintText: hint, hintStyle: TextStyle(color: hint.contains("Location") ? Colors.blue.withValues(alpha: 0.5) : colors.searchHintText), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)))]);
  }

  Widget _buildActiveRouteView(RouteTab route) {
    final colors = TransColors.of(context);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 100), children: [Padding(padding: const EdgeInsets.symmetric(vertical: 8.0), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(route.title, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: colors.textPrimary)), Text(route.subtitle, style: TextStyle(color: colors.textSecondary))])), IconButton(icon: const Icon(Icons.map, color: Colors.blue), onPressed: () => _openMap(route)), const SizedBox(width: 8), Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.timer_outlined, size: 16, color: Colors.green), const SizedBox(width: 4), Text(route.totalDuration, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold))]))])), for (int i = 0; i < route.steps.length; i++) _StepCard(step: route.steps[i], isFirst: i == 0, finalDestinationId: route.destinationId, onOpenAlternatives: (stationId) => _showAlternatives(context, stationId, route.destinationId), onChat: (line) => _showChat(context, line), onAlarmToggle: () => _toggleWakeAlarm(route), isAlarmSet: _isWakeAlarmSet, onMapTap: () => _openMap(route, focusStep: route.steps[i]))]);
  }
}

class _StepCard extends StatelessWidget {
  final JourneyStep step;
  final bool isFirst;
  final String finalDestinationId;
  final Function(String) onOpenAlternatives;
  final Function(String) onChat;
  final VoidCallback onAlarmToggle;
  final VoidCallback onMapTap;
  final bool isAlarmSet;

  const _StepCard({
    required this.step, 
    this.isFirst = false, 
    required this.finalDestinationId, 
    required this.onOpenAlternatives, 
    required this.onChat, 
    required this.onAlarmToggle, 
    required this.isAlarmSet, 
    required this.onMapTap
  });

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    
    // FIX: Wait steps often have 0 distance or invalid paths, so disable map click
    final bool isWait = step.type == 'wait';
    final isTransfer = step.type == 'transfer' || isWait || step.type == 'walk';

    if (isTransfer) { 
      Widget iconWidget = Icon(Icons.directions_walk, color: colors.stepTransferText); 
      if (isWait) iconWidget = Icon(Icons.man, color: colors.stepTransferText); 
      
      return GestureDetector(
        // FIX: Only allow map tap if NOT waiting
        onTap: isWait ? null : onMapTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 16), 
          padding: const EdgeInsets.all(16), 
          decoration: BoxDecoration(
            color: colors.stepTransferBg, 
            borderRadius: BorderRadius.circular(16), 
            border: Border.all(color: colors.stepTransferBorder)
          ), 
          child: Row(children: [
            iconWidget, 
            const SizedBox(width: 16), 
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(step.instruction, style: TextStyle(fontWeight: FontWeight.bold, color: colors.textPrimary)), 
              Text(step.duration, style: TextStyle(color: colors.stepTransferText, fontSize: 12))
            ]))
          ])
        )
      ); 
    }
    
    return Card(
      margin: EdgeInsets.only(bottom: 16, top: isFirst ? 0 : 4), 
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), 
      elevation: 0, 
      color: colors.stepCardBg, 
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent), 
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), 
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween, 
            children: [
              Expanded(child: Text(step.instruction, style: TextStyle(fontWeight: FontWeight.bold, color: colors.textPrimary))), 
              Text("${step.departureTime} - ${step.arrivalTime}", style: TextStyle(fontWeight: FontWeight.bold, color: colors.stepTimeText))
            ]
          ), 
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start, 
            children: [
              const SizedBox(height: 4), 
              Text("${step.line} • ${step.duration}", style: TextStyle(color: colors.textSecondary)), 
              if (step.platform != null) Text(step.platform!, style: TextStyle(color: colors.stepPlatformText, fontSize: 12)), 
              const SizedBox(height: 8), 
              SingleChildScrollView(
                scrollDirection: Axis.horizontal, 
                child: Row(children: [
                  _buildActionChip(context, Icons.chat_bubble_outline, "Chat", onTap: () => onChat(step.line)), 
                  const SizedBox(width: 8), 
                  if (step.startStationId != null) ...[
                    _buildActionChip(context, Icons.alt_route, "Alt", onTap: () => onOpenAlternatives(step.startStationId!)), 
                    const SizedBox(width: 8)
                  ], 
                  _buildActionChip(context, Icons.vibration, isAlarmSet ? "Alarm ON" : "Wake Me", isActive: isAlarmSet, onTap: onAlarmToggle)
                ])
              )
            ]
          ), 
          children: [
            if (step.stopovers != null && step.stopovers!.isNotEmpty) 
              Container(
                decoration: BoxDecoration(color: colors.stepStopoversBg), 
                child: ListView.builder(
                  shrinkWrap: true, 
                  physics: const NeverScrollableScrollPhysics(), 
                  itemCount: step.stopovers!.length, 
                  itemBuilder: (ctx, idx) { 
                    final stop = step.stopovers![idx]; 
                    final name = stop['stop']['name']; 
                    final stopId = stop['stop']['id']; 
                    final plannedDep = stop['plannedDeparture'] ?? stop['plannedArrival']; 
                    final actualDep = stop['departure'] ?? stop['arrival']; 
                    String timeStr = "--:--"; 
                    Color timeColor = Colors.grey; 
                    if (plannedDep != null) { 
                      final p = DateTime.parse(plannedDep); 
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
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min, 
                        children: [
                          Text(timeStr, style: TextStyle(color: timeColor, fontSize: 12)), 
                          const SizedBox(width: 8), 
                          IconButton(icon: const Icon(Icons.alt_route, size: 16, color: Colors.blue), onPressed: () => onOpenAlternatives(stopId))
                        ]
                      )
                    ); 
                  }
                )
              ) 
            else const Padding(padding: EdgeInsets.all(16), child: Text("No intermediate stops info."))
          ]
        )
      )
    );
  }
  
  Widget _buildActionChip(BuildContext context, IconData icon, String label, {bool isActive = false, required VoidCallback onTap}) {
    final colors = TransColors.of(context);
    return GestureDetector(
      onTap: onTap, 
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), 
        decoration: BoxDecoration(color: isActive ? colors.chipActiveBg : colors.chipBg, borderRadius: BorderRadius.circular(20)), 
        child: Row(children: [
          Icon(icon, size: 14, color: isActive ? colors.chipActiveFg : colors.chipFg), 
          const SizedBox(width: 6), 
          Text(label, style: TextStyle(color: isActive ? colors.chipActiveFg : colors.chipFg, fontSize: 12))
        ])
      )
    );
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