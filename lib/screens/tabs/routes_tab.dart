// ... imports stay same ...
import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vibration/vibration.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../models/station.dart';
import '../../models/journey.dart';
import '../../models/favorite.dart';
import '../../services/transport_api.dart';
import '../../services/supabase_service.dart';
import '../../services/history_manager.dart';
import '../../services/favorites_manager.dart';

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

// ... existing state class ... (omitted standard logic for brevity, only showing build method update)
class _RoutesTabState extends State<RoutesTab> {
  // ... [keep all variables and methods exactly as they were] ...
  final List<RouteTab> _tabs = [];
  String? _activeTabId;

  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _toController = TextEditingController();
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
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    final favs = await FavoritesManager.getFavorites();
    if (mounted) setState(() => _favorites = favs);
  }

  // --- SEARCH LOGIC ---
  Future<void> _fetchSuggestions({bool forceHistory = false}) async {
    // ... [keep existing logic] ...
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

    if (widget.currentPosition != null && _activeSearchField == 'from' && query.isEmpty) {
      final nearby = await TransportApi.getNearbyStops(
          widget.currentPosition!.latitude, widget.currentPosition!.longitude);
      for (var s in nearby) {
        if (!results.any((h) => h is Station && h.id == s.id)) results.insert(0, s);
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
        
        if (field == 'to' && _fromStation != null) {
          refLat = _fromStation!.latitude;
          refLng = _fromStation!.longitude;
        }

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
    setState(() {
      _suggestions = [];
      _activeSearchField = '';
    });
    FocusScope.of(context).unfocus();

    Station? target;

    if (fav.type == 'station') {
      target = fav.station;
      if (target == null) {
        _showEditFavoriteDialog(fav);
        return;
      }
    } else if (fav.type == 'friend' && fav.friendId != null) {
      setState(() => _isLoadingRoute = true);
      try {
        final data = await SupabaseService.client
            .from('user_locations')
            .select()
            .eq('user_id', fav.friendId!)
            .maybeSingle();
        
        if (data != null) {
          final lat = data['latitude'] as double;
          final lng = data['longitude'] as double;
          
          final stops = await TransportApi.getNearbyStops(lat, lng);
          if (stops.isNotEmpty) {
            target = stops.first;
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Routing to ${fav.label}'s location near ${target.name}")));
          } else {
            throw "No stations found near friend.";
          }
        } else {
          throw "Friend's location not found.";
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      } finally {
        setState(() => _isLoadingRoute = false);
      }
    }

    if (target != null) {
      setState(() {
        if (_activeSearchField == 'from' || (_fromStation == null && _toStation != null)) {
          _fromStation = target;
          _fromController.text = target!.name;
        } else {
          _toStation = target;
          _toController.text = target!.name;
        }
      });
    }
  }

  void _showEditFavoriteDialog(Favorite fav) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _EditFavoriteDialog(favorite: fav),
    );
    if (mounted) _loadFavorites();
  }
  
  void _addNewFavorite() {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    _showEditFavoriteDialog(Favorite(id: id, label: '', type: 'station'));
  }

  // --- ROUTE LOGIC --- (Keep as is)
  List<JourneyStep> _processLegs(List legs) {
    final List<JourneyStep> steps = [];
    final random = Random();
    List<dynamic> transferBuffer = [];
    DateTime? lastArrival; 

    void flushTransferBuffer(DateTime? nextRideDeparture, String? nextStationName) {
      if (transferBuffer.isEmpty && (lastArrival == null || nextRideDeparture == null)) return;

      DateTime blockStart;
      if (lastArrival != null) {
        blockStart = lastArrival!;
      } else if (transferBuffer.isNotEmpty) {
        blockStart = DateTime.parse(transferBuffer.first['departure'] ?? transferBuffer.first['plannedDeparture']);
      } else {
        return; 
      }

      DateTime blockEnd;
      if (nextRideDeparture != null) {
        blockEnd = nextRideDeparture;
      } else if (transferBuffer.isNotEmpty) {
        blockEnd = DateTime.parse(transferBuffer.last['arrival'] ?? transferBuffer.last['plannedArrival']);
      } else {
        blockEnd = blockStart;
      }

      int walkMinutes = 0;
      for (var leg in transferBuffer) {
        final dep = DateTime.parse(leg['departure'] ?? leg['plannedDeparture']);
        final arr = DateTime.parse(leg['arrival'] ?? leg['plannedArrival']);
        int dur = arr.difference(dep).inMinutes;
        
        final origin = leg['origin']?['name'];
        final dest = leg['destination']?['name'];
        
        if (origin != null && dest != null && origin == dest) {
        } else {
          walkMinutes += dur;
        }
      }

      int totalGapMinutes = blockEnd.difference(blockStart).inMinutes;
      if (totalGapMinutes < 0) totalGapMinutes = 0;

      int waitMinutes = totalGapMinutes - walkMinutes;
      if (waitMinutes < 1) waitMinutes = 0;

      List<String> breakdownParts = [];
      if (walkMinutes > 0) breakdownParts.add("Walk $walkMinutes min");
      if (waitMinutes > 0) breakdownParts.add("Wait $waitMinutes min");
      
      String breakdownText = breakdownParts.join(" • ");
      if (breakdownText.isEmpty) {
        if (totalGapMinutes > 0) breakdownText = "$totalGapMinutes min transfer";
        else breakdownText = "Immediate connection";
      }

      String actionText = "Transfer";
      if (walkMinutes > 0) {
        if (nextStationName != null && nextStationName.isNotEmpty && nextStationName != "Destination") {
           actionText = "Walk to $nextStationName";
        } else if (nextStationName == "Destination") {
           actionText = "Walk to Destination";
        } else {
           actionText = "Walk to connection";
        }
      } else {
        actionText = "Wait for connection";
      }

      String type = (walkMinutes > 0) ? 'walk' : 'wait';

      steps.add(JourneyStep(
        type: type,
        line: 'Transfer',
        instruction: actionText,
        duration: breakdownText,
        departureTime: "${blockStart.hour.toString().padLeft(2,'0')}:${blockStart.minute.toString().padLeft(2,'0')}",
        arrivalTime: "${blockEnd.hour.toString().padLeft(2,'0')}:${blockEnd.minute.toString().padLeft(2,'0')}",
        isWalking: type == 'walk',
      ));
      
      transferBuffer.clear();
    }

    for (int i = 0; i < legs.length; i++) {
      var leg = legs[i];
      bool isRide = (leg['line'] != null && leg['line']['name'] != null);
      
      if (!isRide) {
        transferBuffer.add(leg);
      } else {
        DateTime currentRideDeparture = DateTime.parse(leg['departure']);
        String startStationName = leg['origin']?['name'] ?? 'Station';
        
        flushTransferBuffer(currentRideDeparture, startStationName);

        final String lineName = leg['line']['name'].toString();
        final String destName = leg['direction'] ?? leg['destination']['name'] ?? 'Unknown';
        final String startStationId = leg['origin']?['id'];
        final String? platform = leg['platform'] ?? leg['departurePlatform'];
        final dep = DateTime.parse(leg['departure']);
        final arr = DateTime.parse(leg['arrival']);
        
        if (steps.isNotEmpty && steps.last.line == lineName && steps.last.type == 'ride') {
           var last = steps.removeLast();
           List<dynamic> mergedStops = [];
           if (last.stopovers != null) mergedStops.addAll(last.stopovers!);
           if (leg['stopovers'] != null) mergedStops.addAll(leg['stopovers']);

           steps.add(JourneyStep(
             type: 'ride',
             line: lineName,
             instruction: last.instruction, 
             duration: "Updated", 
             departureTime: last.departureTime,
             arrivalTime: "${arr.hour.toString().padLeft(2,'0')}:${arr.minute.toString().padLeft(2,'0')}",
             stopovers: mergedStops,
             chatCount: last.chatCount,
             startStationId: last.startStationId,
             platform: last.platform,
           ));
        } else {
          int legDurationMin = arr.difference(dep).inMinutes;
          String durationDisplay = legDurationMin > 60 ? "${legDurationMin ~/ 60}h ${legDurationMin % 60}min" : "$legDurationMin min";

          steps.add(JourneyStep(
            type: 'ride',
            line: lineName,
            instruction: "$lineName → $destName",
            duration: durationDisplay,
            departureTime: "${dep.hour.toString().padLeft(2, '0')}:${dep.minute.toString().padLeft(2, '0')}",
            arrivalTime: "${arr.hour.toString().padLeft(2, '0')}:${arr.minute.toString().padLeft(2, '0')}",
            chatCount: random.nextInt(15) + 1,
            startStationId: startStationId,
            platform: platform != null ? "Plat $platform" : null,
            stopovers: leg['stopovers'],
          ));
        }
        
        lastArrival = arr;
      }
    }
    
    flushTransferBuffer(null, "Destination");

    return steps;
  }
  
  Future<void> _findRoutes() async {
    Station? from = _fromStation;
    if (from == null && widget.currentPosition != null) {
       setState(() => _isLoadingRoute = true); 
       try {
         final nearby = await TransportApi.getNearbyStops(widget.currentPosition!.latitude, widget.currentPosition!.longitude);
         if (nearby.isNotEmpty) from = nearby.first;
         else {
           setState(() => _isLoadingRoute = false);
           if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No nearby stations found.")));
           return;
         }
       } catch (e) {
         setState(() => _isLoadingRoute = false);
         return;
       }
    }

    if (from == null || _toStation == null) {
      setState(() => _isLoadingRoute = false);
      return;
    }
    setState(() => _isLoadingRoute = true);

    DateTime? searchTime;
    if (_selectedDate != null && _selectedTime != null) {
      searchTime = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day, _selectedTime!.hour, _selectedTime!.minute);
    }

    try {
      final journeyData = await TransportApi.searchJourney(
          from.id, _toStation!.id, nahverkehrOnly: widget.onlyNahverkehr, when: searchTime, isArrival: _isArrival
      );

      if (journeyData != null && journeyData['legs'] != null) {
        final List legs = journeyData['legs'];
        final List<JourneyStep> steps = _processLegs(legs);
        
        String totalDurationStr = "";
        if (legs.isNotEmpty) {
           var firstLeg = legs.first;
           var lastLeg = legs.last;
           if (firstLeg['departure'] != null && lastLeg['arrival'] != null) {
             DateTime routeStart = DateTime.parse(firstLeg['departure']);
             DateTime routeEnd = DateTime.parse(lastLeg['arrival']);
             int totalMin = routeEnd.difference(routeStart).inMinutes;
             totalDurationStr = totalMin > 60 ? "${totalMin ~/ 60}h ${totalMin % 60}min" : "${totalMin}min";
           }
        }

        final newTabId = DateTime.now().millisecondsSinceEpoch.toString();
        String eta = "--:--";
        if (journeyData['arrival'] != null) {
          final arr = DateTime.parse(journeyData['arrival']);
          eta = "${arr.hour.toString().padLeft(2, '0')}:${arr.minute.toString().padLeft(2, '0')}";
        }

        final newTab = RouteTab(id: newTabId, title: _toStation!.name, subtitle: "${from.name} → ${_toStation!.name}", eta: eta, totalDuration: totalDurationStr, destinationId: _toStation!.id, steps: steps);

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

  Future<void> _openNewRouteTab(DateTime newDepartureTime, String startStationId, String finalDestId) async {
     // ... [keep existing logic] ...
     setState(() => _isLoadingRoute = true);
    try {
      final journeyData = await TransportApi.searchJourney(startStationId, finalDestId, nahverkehrOnly: widget.onlyNahverkehr, when: newDepartureTime, isArrival: false);

      if (journeyData != null && journeyData['legs'] != null) {
        final List legs = journeyData['legs'];
        final List<JourneyStep> steps = _processLegs(legs);
        
        String totalDurationStr = "0 min";
        if (legs.isNotEmpty) {
           var firstLeg = legs.first;
           var lastLeg = legs.last;
           String? startStr = firstLeg['departure'] ?? firstLeg['plannedDeparture'];
           String? endStr = lastLeg['arrival'] ?? lastLeg['plannedArrival'];
           if (startStr != null && endStr != null) {
             DateTime routeStart = DateTime.parse(startStr);
             DateTime routeEnd = DateTime.parse(endStr);
             int totalMin = routeEnd.difference(routeStart).inMinutes;
             totalDurationStr = totalMin > 60 ? "${totalMin ~/ 60}h ${totalMin % 60}min" : "${totalMin}min";
           }
        }

        final newTabId = DateTime.now().millisecondsSinceEpoch.toString();
        String eta = "--:--";
        if (journeyData['arrival'] != null) {
          final arr = DateTime.parse(journeyData['arrival']);
          eta = "${arr.hour.toString().padLeft(2, '0')}:${arr.minute.toString().padLeft(2, '0')}";
        }
        
        final newTab = RouteTab(id: newTabId, title: "Alternative", subtitle: "From ${newDepartureTime.hour}:${newDepartureTime.minute.toString().padLeft(2,'0')}", eta: eta, totalDuration: totalDurationStr, destinationId: finalDestId, steps: steps);

        setState(() {
          _tabs.add(newTab);
          _activeTabId = newTabId;
          _isLoadingRoute = false;
        });
      } else {
        setState(() => _isLoadingRoute = false);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not find route.")));
      }
    } catch (e) {
      setState(() => _isLoadingRoute = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
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

  void _showChat(BuildContext context, String lineName) {
    showModalBottomSheet(context: context, backgroundColor: Theme.of(context).scaffoldBackgroundColor, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))), builder: (ctx) => ChatSheet(lineId: lineName, title: lineName));
  }

  void _showGuide(BuildContext context, String? startStationId) {
    // ... [keep existing logic] ...
     if (startStationId == null) return;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (context, setStateDialog) {
          return AlertDialog(backgroundColor: Theme.of(ctx).cardColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)), title: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("Station Guide", style: TextStyle(color: Theme.of(ctx).textTheme.bodyLarge?.color)), IconButton(icon: const Icon(Icons.add_a_photo, color: Colors.blue), onPressed: () async { final picker = ImagePicker(); final picked = await picker.pickImage(source: ImageSource.camera, maxWidth: 1024); if (picked != null) { try { dynamic imageFile; if (kIsWeb) imageFile = await picked.readAsBytes(); else imageFile = File(picked.path); await SupabaseService.uploadStationImage(imageFile, startStationId); setStateDialog(() {}); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"))); } } })]), content: FutureBuilder<String?>(future: SupabaseService.getStationImage(startStationId), builder: (context, snapshot) { if (snapshot.connectionState == ConnectionState.waiting) return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator())); if (snapshot.data == null) return const Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.image_not_supported, size: 40), Text("No guide image found.")]); return ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.network(snapshot.data!, fit: BoxFit.cover, height: 200)); }), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close"))]);
        }));
  }

  void _showAlternatives(BuildContext context, String stationId, String finalDestinationId) {
     // ... [keep existing logic] ...
      showModalBottomSheet(context: context, backgroundColor: Theme.of(context).cardColor, builder: (ctx) {
        return FutureBuilder<List<Map<String, dynamic>>>(future: TransportApi.getDepartures(stationId, nahverkehrOnly: widget.onlyNahverkehr), builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("No alternatives found."));
            return ListView.builder(padding: const EdgeInsets.all(16), itemCount: snapshot.data!.length, itemBuilder: (ctx, idx) {
                final dep = snapshot.data![idx];
                final line = dep['line']['name'] ?? 'Unknown';
                final dir = dep['direction'] ?? 'Unknown';
                final planned = DateTime.parse(dep['plannedWhen'] ?? dep['when']);
                final time = "${planned.hour.toString().padLeft(2,'0')}:${planned.minute.toString().padLeft(2,'0')}";
                return ListTile(leading: const Icon(Icons.directions_bus), title: Text("$line to $dir"), trailing: Text(time), onTap: () { Navigator.pop(context); _openNewRouteTab(planned, stationId, finalDestinationId); });
              });
          });
      });
  }

  Future<void> _triggerVibration() async {
    if (kIsWeb) return; 
    if (await Vibration.hasVibrator() ?? false) Vibration.vibrate(duration: 500);
  }

  @override
  Widget build(BuildContext context) {
    final bool canSearch = (_fromStation != null || widget.currentPosition != null) && _toStation != null && !_isLoadingRoute;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // FIX: Get current theme color
    final primaryColor = Theme.of(context).primaryColor;

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
                    // FIX: Use primaryColor for active tab
                    decoration: BoxDecoration(color: isActive ? primaryColor : Theme.of(context).cardColor, borderRadius: BorderRadius.circular(20)),
                    child: Row(children: [Icon(Icons.directions, size: 16, color: isActive ? Colors.white : Colors.grey), const SizedBox(width: 6), Text(tab.title, style: TextStyle(color: isActive ? Colors.white : Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)), const SizedBox(width: 4), GestureDetector(onTap: () => _closeTab(tab.id), child: Icon(Icons.close, size: 14, color: isActive ? Colors.white70 : Colors.grey))]),
                  ),
                );
              },
            ),
          ),
        Expanded(child: _activeTabId == null ? _buildSearchView(canSearch, isDark, primaryColor) : _buildActiveRouteView(_tabs.firstWhere((t) => t.id == _activeTabId))),
      ],
    );
  }

  Widget _buildSearchView(bool canSearch, bool isDark, Color primaryColor) {
    final textColor = Theme.of(context).textTheme.bodyLarge?.color;
    final cardColor = Theme.of(context).cardColor;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 100),
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
                  Row(children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: primaryColor.withOpacity(0.2), borderRadius: BorderRadius.circular(8)), child: Icon(Icons.search, color: primaryColor)), const SizedBox(width: 12), Text("Plan Journey", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor))]),
                  const SizedBox(height: 20),
                  _buildTextField("From", _fromController, _fromStation != null, 'from', primaryColor, hint: (_fromStation == null && widget.currentPosition != null) ? "Current Location" : "Station..."),
                  if (_activeSearchField == 'from') _buildSuggestionsList(),
                  const SizedBox(height: 12),
                  _buildTextField("To", _toController, _toStation != null, 'to', primaryColor),
                  if (_activeSearchField == 'to') _buildSuggestionsList(),
                  const SizedBox(height: 20),
                  Text("Trip Time", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: isDark ? const Color(0xFF1F2937) : Colors.grey.shade200, borderRadius: BorderRadius.circular(16)),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => setState(() => _isArrival = !_isArrival), 
                          // FIX: Use primaryColor and fixed text blurriness (font size 13, normal weight)
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), 
                            decoration: BoxDecoration(color: primaryColor, borderRadius: BorderRadius.circular(12)), 
                            child: Text(_isArrival ? "Arrive by" : "Depart at", style: const TextStyle(color: Colors.white, fontSize: 13))
                          )
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: GestureDetector(onTap: () async { final now = DateTime.now(); final picked = await showDatePicker(context: context, initialDate: _selectedDate ?? now, firstDate: now.subtract(const Duration(days: 30)), lastDate: now.add(const Duration(days: 90))); if (picked != null) { setState(() { _selectedDate = picked; _selectedTime ??= TimeOfDay.now(); }); final t = await showTimePicker(context: context, initialTime: _selectedTime!); if (t != null) setState(() => _selectedTime = t); } }, child: _selectedDate != null ? Row(children: [Icon(Icons.calendar_today, size: 16, color: Colors.grey.shade600), const SizedBox(width: 6), Text("${_selectedDate!.day}.${_selectedDate!.month}  ${_selectedTime?.format(context) ?? ''}", style: TextStyle(color: textColor, fontWeight: FontWeight.bold))]) : Row(children: [Icon(Icons.calendar_today, size: 16, color: Colors.grey.shade600), const SizedBox(width: 6), const Text("Now", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))]))),
                        if (_selectedDate != null) IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () => setState(() { _selectedDate = null; _selectedTime = null; })),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text("Favorites", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 80,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _favorites.length + 1,
                      separatorBuilder: (_,__) => const SizedBox(width: 12),
                      itemBuilder: (ctx, idx) {
                         if (idx == _favorites.length) {
                           return GestureDetector(onTap: _addNewFavorite, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Container(width: 48, height: 48, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.add, color: Colors.blue)), const SizedBox(height: 4), const Text("Add", style: TextStyle(fontSize: 10))]));
                         }
                         final fav = _favorites[idx];
                         IconData icon = Icons.star;
                         if (fav.type == 'friend') icon = Icons.person;
                         else if (fav.label.toLowerCase() == 'home') icon = Icons.home;
                         else if (fav.label.toLowerCase() == 'work') icon = Icons.work;
                         
                         if (fav.iconCode != null) {
                           icon = kAvailableIcons.firstWhere(
                             (i) => i.codePoint == fav.iconCode,
                             orElse: () => icon,
                           );
                         }

                         return GestureDetector(
                           onTap: () => _onFavoriteTap(fav), 
                           onLongPress: () => _showEditFavoriteDialog(fav), 
                           child: Column(
                             mainAxisAlignment: MainAxisAlignment.center, 
                             children: [
                               Container(
                                 width: 48, height: 48, 
                                 // FIX: Use primaryColor for friends/stations if needed, or keep distinct colors
                                 decoration: BoxDecoration(color: (fav.type == 'friend' ? Colors.green : primaryColor).withOpacity(0.1), shape: BoxShape.circle), 
                                 child: Icon(icon, color: fav.type == 'friend' ? Colors.green : primaryColor, size: 20)
                               ), 
                               const SizedBox(height: 4), 
                               Text(fav.label, style: TextStyle(fontSize: 10, color: textColor))
                            ]
                          )
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(width: double.infinity, height: 56, child: ElevatedButton(onPressed: canSearch ? _findRoutes : null, style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: _isLoadingRoute ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text("Find Routes", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionsList() {
    // ... [keep existing logic] ...
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
                final item = _suggestions[idx];
                if (item is Favorite) return ListTile(leading: const Icon(Icons.star, size: 16, color: Colors.orange), title: Text(item.label, style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.bold)), onTap: () => _selectItem(item));
                final station = item as Station;
                return ListTile(
                  leading: const Icon(Icons.place, size: 16, color: Colors.grey), 
                  title: Text(station.name, style: TextStyle(color: textColor, fontSize: 14)), 
                  onTap: () => _selectItem(station),
                  onLongPress: () {
                    final newFav = Favorite(
                      id: DateTime.now().millisecondsSinceEpoch.toString(), 
                      label: station.name, 
                      type: 'station',
                      station: station
                    );
                    _showEditFavoriteDialog(newFav);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, bool isSelected, String fieldKey, Color primaryColor, {String hint = "Station..."}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Color iconColor = Colors.grey;
    if (isSelected) iconColor = primaryColor; else if (fieldKey == 'from' && hint == "Current Location") iconColor = Colors.blue;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Padding(padding: const EdgeInsets.only(left: 4, bottom: 4), child: Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold))), TextField(controller: controller, onChanged: (val) => _onSearchChanged(val, fieldKey), onTap: () => setState(() => _activeSearchField = fieldKey), style: TextStyle(color: isDark ? Colors.white : Colors.black), decoration: InputDecoration(filled: true, fillColor: isDark ? const Color(0xFF1F2937) : Colors.grey.shade200, prefixIcon: Icon(fieldKey == 'from' ? Icons.my_location : Icons.location_on, color: iconColor, size: 20), hintText: hint, hintStyle: TextStyle(color: hint == "Current Location" ? Colors.blue.withOpacity(0.5) : Colors.grey), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)))]);
  }

  Widget _buildActiveRouteView(RouteTab route) {
     // ... [keep existing logic] ...
     final textColor = Theme.of(context).textTheme.bodyLarge?.color;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0), 
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(route.title, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor)), Text(route.subtitle, style: const TextStyle(color: Colors.grey))])),
              Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.green.withOpacity(0.2), borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.timer_outlined, size: 16, color: Colors.green), const SizedBox(width: 4), Text(route.totalDuration, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold))]))
            ],
          ),
        ),
        
        for (int i = 0; i < route.steps.length; i++)
          _StepCard(
            step: route.steps[i], 
            isFirst: i == 0,
            finalDestinationId: route.destinationId,
            onOpenAlternatives: (stationId) => _showAlternatives(context, stationId, route.destinationId),
            onChat: (line) => _showChat(context, line),
            onGuide: (station) => _showGuide(context, station),
            onAlarmToggle: () => setState(() => _isWakeAlarmSet = !_isWakeAlarmSet),
            isAlarmSet: _isWakeAlarmSet,
          )
      ],
    );
  }
}

// ... _StepCard class (no major changes needed, just inherits theme) ...
class _StepCard extends StatelessWidget {
  final JourneyStep step;
  final bool isFirst;
  final String finalDestinationId;
  final Function(String) onOpenAlternatives;
  final Function(String) onChat;
  final Function(String) onGuide;
  final VoidCallback onAlarmToggle;
  final bool isAlarmSet;

  const _StepCard({required this.step, this.isFirst = false, required this.finalDestinationId, required this.onOpenAlternatives, required this.onChat, required this.onGuide, required this.onAlarmToggle, required this.isAlarmSet});

  @override
  Widget build(BuildContext context) {
    // ... [keep existing logic] ...
    final isTransfer = step.type == 'transfer' || step.type == 'wait' || step.type == 'walk';
    final cardColor = Theme.of(context).cardColor;
    final textColor = Theme.of(context).textTheme.bodyLarge?.color;

    if (isTransfer) {
      Widget iconWidget = const Icon(Icons.directions_walk, color: Colors.orange);
      if (step.type == 'wait') iconWidget = const Icon(Icons.man, color: Colors.orange);

      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.orange.withOpacity(0.3))),
        child: Row(children: [iconWidget, const SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(step.instruction, style: TextStyle(fontWeight: FontWeight.bold, color: textColor)), Text(step.duration, style: const TextStyle(color: Colors.orange, fontSize: 12))]))]),
      );
    }

    return Card(
      margin: EdgeInsets.only(bottom: 16, top: isFirst ? 0 : 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      color: cardColor,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          title: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text(step.instruction, style: TextStyle(fontWeight: FontWeight.bold, color: textColor))), Text("${step.departureTime} - ${step.arrivalTime}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigoAccent))]),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const SizedBox(height: 4), Text("${step.line} • ${step.duration}", style: const TextStyle(color: Colors.grey)), if (step.platform != null) Text(step.platform!, style: const TextStyle(color: Colors.greenAccent, fontSize: 12)), const SizedBox(height: 8), SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [_buildActionChip(Icons.chat_bubble_outline, "Chat", onTap: () => onChat(step.line)), const SizedBox(width: 8), if (step.startStationId != null) ...[_buildActionChip(Icons.alt_route, "Alt", onTap: () => onOpenAlternatives(step.startStationId!)), const SizedBox(width: 8), _buildActionChip(Icons.camera_alt_outlined, "Guide", onTap: () => onGuide(step.startStationId!)), const SizedBox(width: 8)], _buildActionChip(Icons.vibration, isAlarmSet ? "Alarm ON" : "Wake Me", isActive: isAlarmSet, onTap: onAlarmToggle)]))]),
          children: [
            if (step.stopovers != null && step.stopovers!.isNotEmpty)
              Container(
                decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.5)),
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
                        if (delay > 2) { timeStr += " (+${delay}')"; timeColor = Colors.red; } else { timeColor = Colors.green; }
                      }
                    }
                    return ListTile(dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 20), leading: const Icon(Icons.circle, size: 8, color: Colors.grey), title: Text(name, style: TextStyle(color: textColor, fontSize: 13)), trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text(timeStr, style: TextStyle(color: timeColor, fontSize: 12)), const SizedBox(width: 8), IconButton(icon: const Icon(Icons.alt_route, size: 16, color: Colors.blue), onPressed: () => onOpenAlternatives(stopId))]));
                  },
                ),
              )
            else const Padding(padding: EdgeInsets.all(16), child: Text("No intermediate stops info."))
          ],
        ),
      ),
    );
  }

  Widget _buildActionChip(IconData icon, String label, {bool isActive = false, required VoidCallback onTap}) {
    return GestureDetector(onTap: onTap, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: isActive ? Colors.indigoAccent : Colors.grey.withOpacity(0.2), borderRadius: BorderRadius.circular(20)), child: Row(children: [Icon(icon, size: 14, color: isActive ? Colors.white : Colors.grey), const SizedBox(width: 6), Text(label, style: TextStyle(color: isActive ? Colors.white : Colors.grey, fontSize: 12))])));
  }
}

// ... _EditFavoriteDialog ...
class _EditFavoriteDialog extends StatefulWidget {
  final Favorite favorite;
  const _EditFavoriteDialog({required this.favorite});

  @override
  State<_EditFavoriteDialog> createState() => _EditFavoriteDialogState();
}

class _EditFavoriteDialogState extends State<_EditFavoriteDialog> {
  // ... [keep logic] ...
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
    final primaryColor = Theme.of(context).primaryColor;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Theme.of(context).cardColor,
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isNew ? "Add Favorite" : "Edit Favorite", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
            const SizedBox(height: 20),
            
            TextField(controller: _labelCtrl, decoration: const InputDecoration(labelText: "Label (e.g. Home, Bestie)")),
            const SizedBox(height: 10),
            
            Row(children: [
              Expanded(child: RadioListTile<String>(title: const Text("Station"), value: 'station', groupValue: _currentType, activeColor: primaryColor, contentPadding: EdgeInsets.zero, onChanged: (val) => setState(() => _currentType = val!))),
              Expanded(child: RadioListTile<String>(title: const Text("Friend"), value: 'friend', groupValue: _currentType, activeColor: primaryColor, contentPadding: EdgeInsets.zero, onChanged: (val) => setState(() => _currentType = val!))),
            ]),
            
            const SizedBox(height: 10),
            const Text("Pick Icon", style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: kAvailableIcons.map((icon) {
                  final isSelected = _selectedIconCode == icon.codePoint;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedIconCode = icon.codePoint),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isSelected ? primaryColor : Colors.grey.withOpacity(0.1),
                        shape: BoxShape.circle
                      ),
                      child: Icon(icon, size: 20, color: isSelected ? Colors.white : Colors.grey),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 10),
            // ... [content area logic] ...
            if (_currentType == 'station') ...[
              if (_selectedStation != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.train, color: Colors.indigo),
                  title: Text(_selectedStation!.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() { _selectedStation = null; _searchCtrl.clear(); _suggestions = []; })),
                )
              else ...[
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    labelText: "Search Station Name",
                    prefixIcon: const Icon(Icons.search),
                    suffix: SizedBox(width: 16, height: 16, child: _isLoading ? const CircularProgressIndicator(strokeWidth: 2) : null),
                  ),
                  onChanged: (val) {
                    if (_debounce?.isActive ?? false) _debounce!.cancel();
                    if (val.isEmpty) {
                      if (mounted) setState(() => _suggestions = []);
                      return;
                    }
                    _debounce = Timer(const Duration(milliseconds: 400), () async {
                      if (!mounted) return;
                      setState(() => _isLoading = true);
                      try {
                        final res = await TransportApi.searchStations(val);
                        if (mounted) setState(() { _suggestions = res; _isLoading = false; });
                      } catch (e) {
                        if (mounted) setState(() => _isLoading = false);
                      }
                    });
                  },
                ),
                if (_suggestions.isNotEmpty)
                  Container(
                    height: 150,
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(border: Border.all(color: Colors.white10), borderRadius: BorderRadius.circular(8)),
                    child: ListView.builder(
                      itemCount: _suggestions.length,
                      itemBuilder: (context, idx) {
                        final s = _suggestions[idx];
                        return ListTile(
                          dense: true,
                          title: Text(s.name),
                          onTap: () {
                            if (!mounted) return;
                            setState(() {
                              _selectedStation = s;
                              _suggestions = [];
                              if (_labelCtrl.text.isEmpty) _labelCtrl.text = s.name;
                            });
                          },
                        );
                      },
                    ),
                  )
              ]
            ],
            
            if (_currentType == 'friend') ...[
               TextField(
                  decoration: const InputDecoration(labelText: "Search Friend Username"),
                  onSubmitted: (val) async {
                    final res = await SupabaseService.searchUsers(val);
                    if (res.isNotEmpty && mounted) {
                      setState(() {
                        _selectedFriendId = res.first['id'];
                        if (_labelCtrl.text.isEmpty) {
                           _labelCtrl.text = res.first['username'];
                        }
                      });
                    }
                  },
               ),
               if (_selectedFriendId != null) const Padding(padding: EdgeInsets.only(top: 8), child: Text("Friend Selected", style: TextStyle(color: Colors.green))),
            ],

            const SizedBox(height: 20),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!isNew && widget.favorite.id != 'home' && widget.favorite.id != 'work')
                  TextButton(
                    onPressed: () async {
                      await FavoritesManager.deleteFavorite(widget.favorite.id);
                      if (mounted) Navigator.pop(context, true); 
                    },
                    child: const Text("Delete", style: TextStyle(color: Colors.red)),
                  ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (_labelCtrl.text.isNotEmpty) {
                      final newFav = Favorite(
                        id: isNew ? DateTime.now().millisecondsSinceEpoch.toString() : widget.favorite.id,
                        label: _labelCtrl.text,
                        type: _currentType,
                        station: _selectedStation,
                        friendId: _selectedFriendId,
                        iconCode: _selectedIconCode
                      );
                      await FavoritesManager.saveFavorite(newFav);
                      if (mounted) Navigator.pop(context, true); 
                    }
                  },
                  child: const Text("Save"),
                )
              ],
            )
          ],
        ),
      ),
    );
  }
}

class ChatSheet extends StatefulWidget {
  final String lineId;
  final String title;
  const ChatSheet({super.key, required this.lineId, required this.title});
  @override
  State<ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<ChatSheet> {
  final TextEditingController _msgCtrl = TextEditingController();
  
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 600,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2))),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Row(children: [const CircleAvatar(backgroundColor: Colors.indigo, child: Icon(Icons.directions_bus, color: Colors.white)), const SizedBox(width: 12), Text(widget.title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color))])),
          const Divider(),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: SupabaseService.getMessages(widget.lineId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final msgs = snapshot.data!;
                if (msgs.isEmpty) return const Center(child: Text("No messages yet.", style: TextStyle(color: Colors.grey)));
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: msgs.length,
                  itemBuilder: (ctx, idx) {
                    final msg = msgs[idx];
                    final isMe = msg['user_id'] == SupabaseService.currentUser?.id;
                    final username = msg['username'] ?? 'Unknown';
                    final avatar = msg['avatar_url'];
                    final emoji = msg['avatar_emoji']; // Fetch Emoji
                    final themeColorVal = msg['theme_color']; // Fetch Theme Color
                    final Color themeColor = themeColorVal != null ? Color(themeColorVal) : Colors.indigo;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isMe) 
                            CircleAvatar(
                              radius: 16, 
                              // FIX: Use friend's theme color for background
                              backgroundColor: themeColor,
                              backgroundImage: avatar != null ? NetworkImage(avatar) : null, 
                              child: (avatar == null && emoji != null) 
                                ? Text(emoji, style: const TextStyle(fontSize: 16))
                                : (avatar == null ? Text(username[0].toUpperCase()) : null)
                            ),
                          const SizedBox(width: 8),
                          Column(crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
                            if (!isMe) Padding(padding: const EdgeInsets.only(left: 4, bottom: 2), child: Text(username, style: const TextStyle(fontSize: 10, color: Colors.grey))),
                            Container(constraints: const BoxConstraints(maxWidth: 240), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: isMe ? Colors.blue : Theme.of(context).cardColor, borderRadius: BorderRadius.only(topLeft: const Radius.circular(16), topRight: const Radius.circular(16), bottomLeft: isMe ? const Radius.circular(16) : Radius.zero, bottomRight: isMe ? Radius.zero : const Radius.circular(16)), border: isMe ? null : Border.all(color: Colors.white10)), child: Text(msg['content'], style: TextStyle(color: isMe ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color)))
                          ])
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(padding: const EdgeInsets.all(16), child: Row(children: [Expanded(child: TextField(controller: _msgCtrl, decoration: InputDecoration(hintText: "Say something...", filled: true, fillColor: Theme.of(context).cardColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 20)), onSubmitted: (_) => _send())), const SizedBox(width: 8), CircleAvatar(backgroundColor: Colors.blue, child: IconButton(icon: const Icon(Icons.send, color: Colors.white), onPressed: _send))]))
        ],
      ),
    );
  }
  void _send() { if (_msgCtrl.text.trim().isEmpty) return; SupabaseService.sendMessage(widget.lineId, _msgCtrl.text.trim()); _msgCtrl.clear(); }
}