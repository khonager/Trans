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

import '../../models/station.dart';
import '../../models/journey.dart';
import '../../models/favorite.dart';
import '../../services/transport_api.dart';
import '../../services/supabase_service.dart';
import '../../services/history_manager.dart';
import '../../services/favorites_manager.dart';

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
  // Tab Management
  final List<RouteTab> _tabs = [];
  String? _activeTabId;

  // Search State
  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _toController = TextEditingController();
  Station? _fromStation;
  Station? _toStation;
  
  List<dynamic> _suggestions = []; 
  String _activeSearchField = '';
  Timer? _debounce;
  bool _isLoadingRoute = false;
  bool _isSuggestionsLoading = false;
  
  // Time Planning
  DateTime? _selectedDate; 
  TimeOfDay? _selectedTime;
  bool _isArrival = false; 

  // Haptics
  bool _isWakeAlarmSet = false;

  // Favorites
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
    if (forceHistory) {
      final history = await SearchHistoryManager.getHistory();
      if (mounted) setState(() => _suggestions = history);
      return;
    }

    setState(() => _isSuggestionsLoading = true);
    List<dynamic> results = [];
    final query = _activeSearchField == 'from' ? _fromController.text : _toController.text;

    // 1. Matching Favorites
    if (query.isNotEmpty) {
      final matchingFavs = _favorites.where((f) => f.label.toLowerCase().contains(query.toLowerCase())).toList();
      results.addAll(matchingFavs);
    }

    // 2. History
    final history = await SearchHistoryManager.getHistory();
    if (history.isNotEmpty) {
       if (query.isNotEmpty) {
         results.addAll(history.where((s) => s.name.toLowerCase().contains(query.toLowerCase())));
       } else {
         results.addAll(history);
       }
    }

    // 3. Nearby
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

  // --- FAVORITE LOGIC ---

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
    final bool? shouldReload = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _EditFavoriteDialog(favorite: fav),
    );

    if (shouldReload == true && mounted) {
      _loadFavorites();
    }
  }
  
  void _addNewFavorite() {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    _showEditFavoriteDialog(Favorite(id: id, label: '', type: 'station'));
  }

  // --- ROUTE LOGIC ---

  List<JourneyStep> _processLegs(List legs) {
    final List<JourneyStep> steps = [];
    final random = Random();

    for (int i = 0; i < legs.length; i++) {
      var leg = legs[i];
      final mode = leg['mode'] ?? 'transport';
      
      final depStr = leg['departure'] as String?;
      final arrStr = leg['arrival'] as String?;
      if (depStr == null || arrStr == null) continue;

      DateTime dep = DateTime.parse(depStr);
      DateTime arr = DateTime.parse(arrStr);
      
      int legDurationMin = arr.difference(dep).inMinutes;
      
      String lineName = 'Transport';
      String instruction = '';
      String type = 'ride';

      String destName = 'Destination';
      if (leg['direction'] != null) {
        destName = leg['direction'].toString();
      } else if (leg['destination'] != null && leg['destination']['name'] != null) {
        destName = leg['destination']['name'].toString();
      }
      
      String originName = '';
      if (leg['origin'] != null && leg['origin']['name'] != null) {
        originName = leg['origin']['name'].toString();
      }

      String durationDisplay = "$legDurationMin min";
      if (legDurationMin > 60) {
        int h = legDurationMin ~/ 60;
        int m = legDurationMin % 60;
        durationDisplay = "${h}h ${m}min";
      }

      if (leg['line'] != null && leg['line']['name'] != null) {
        lineName = leg['line']['name'].toString();
        instruction = "$lineName → $destName"; 
      } else {
          // Handle Transfers/Walking/Waits
          if (mode == 'walking') {
            type = 'wait'; // Using 'wait' type for orange border
            lineName = 'Wait'; // "Wait" appears on left
            
            // Calculate WAIT time (Gap until NEXT leg starts)
            int waitMin = 0;
            if (i + 1 < legs.length) {
              var nextLeg = legs[i+1];
              // Fallback priority: real departure -> planned departure -> arrival
              String? nextDepStr = nextLeg['departure'] ?? nextLeg['plannedDeparture'];
              
              if (nextDepStr != null) {
                DateTime nextDep = DateTime.parse(nextDepStr);
                // Difference between next leg departure and current leg arrival
                waitMin = nextDep.difference(arr).inMinutes;
              }
            }
            
            // Ensure wait time is non-negative
            if (waitMin < 0) waitMin = 0;

            instruction = "Transfer to $destName";
            
            // "Transfer 3 min • Wait 6 min"
            durationDisplay = "Transfer $legDurationMin min • Wait $waitMin min";
            
          } else {
            // Pure Wait logic (Origin == Dest)
            if (originName == destName) {
              type = 'wait';
              lineName = 'Wait';
              instruction = "Wait at $originName";
              
              if (i + 1 < legs.length) {
                var nextLeg = legs[i+1];
                String? nextDepStr = nextLeg['departure'] ?? nextLeg['plannedDeparture'];
                if (nextDepStr != null) {
                  DateTime nextDep = DateTime.parse(nextDepStr);
                  int nextWait = nextDep.difference(arr).inMinutes;
                  if (nextWait > 0) durationDisplay = "Wait • $nextWait min";
                }
              }
            } else {
              String rawMode = mode.toString().toUpperCase();
              if (rawMode == 'TRANSPORT') {
                  type = 'wait'; 
                  lineName = 'Transfer';
                  instruction = 'Transfer to $destName';
              } else {
                  lineName = rawMode;
                  instruction = "$lineName to $destName";
              }
            }
          }
      }

      String? platform;
      if (leg['platform'] != null) platform = "Plat ${leg['platform']}";
      else if (leg['departurePlatform'] != null) platform = "Plat ${leg['departurePlatform']}";

      String? startStationId;
      if (leg['origin'] != null && leg['origin']['id'] != null) {
        startStationId = leg['origin']['id'];
      }

      String depTime = "${dep.hour.toString().padLeft(2, '0')}:${dep.minute.toString().padLeft(2, '0')}";
      String arrTime = "${arr.hour.toString().padLeft(2, '0')}:${arr.minute.toString().padLeft(2, '0')}";

      steps.add(JourneyStep(
        type: type,
        line: lineName,
        instruction: instruction,
        duration: durationDisplay,
        departureTime: depTime,
        arrivalTime: arrTime,
        chatCount: (type == 'ride') ? random.nextInt(15) + 1 : null,
        startStationId: startStationId,
        platform: platform,
      ));
    }
    return steps;
  }

  Future<void> _findRoutes() async {
    Station? from = _fromStation;
    
    if (from == null && widget.currentPosition != null) {
       setState(() => _isLoadingRoute = true); 
       try {
         final nearby = await TransportApi.getNearbyStops(
           widget.currentPosition!.latitude, 
           widget.currentPosition!.longitude
         );
         if (nearby.isNotEmpty) {
           from = nearby.first;
         } else {
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
      searchTime = DateTime(
        _selectedDate!.year, 
        _selectedDate!.month, 
        _selectedDate!.day,
        _selectedTime!.hour,
        _selectedTime!.minute
      );
    }

    try {
      final journeyData = await TransportApi.searchJourney(
          from.id, 
          _toStation!.id, 
          nahverkehrOnly: widget.onlyNahverkehr,
          when: searchTime,
          isArrival: _isArrival
      );

      if (journeyData != null && journeyData['legs'] != null) {
        final List legs = journeyData['legs'];
        final List<JourneyStep> steps = _processLegs(legs);
        
        // Calculate Total Duration
        String totalDurationStr = "";
        if (legs.isNotEmpty) {
           var firstLeg = legs.first;
           var lastLeg = legs.last;
           if (firstLeg['departure'] != null && lastLeg['arrival'] != null) {
             DateTime routeStart = DateTime.parse(firstLeg['departure']);
             DateTime routeEnd = DateTime.parse(lastLeg['arrival']);
             int totalMin = routeEnd.difference(routeStart).inMinutes;
             int hrs = totalMin ~/ 60;
             int mins = totalMin % 60;
             if (hrs > 0) {
               totalDurationStr = "${hrs}h ${mins}min";
             } else {
               totalDurationStr = "${mins}min";
             }
           }
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
          subtitle: "${from.name} → ${_toStation!.name}",
          eta: eta,
          totalDuration: totalDurationStr, 
          destinationId: _toStation!.id, 
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

  // UPDATED: Opens a NEW tab instead of updating inline
  Future<void> _openNewRouteTab(DateTime newDepartureTime, String startStationId, String finalDestId) async {
    Navigator.pop(context); // Close alternatives sheet first
    setState(() => _isLoadingRoute = true);
    
    try {
      final journeyData = await TransportApi.searchJourney(
        startStationId,
        finalDestId,
        nahverkehrOnly: widget.onlyNahverkehr,
        when: newDepartureTime,
        isArrival: false
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
             int hrs = totalMin ~/ 60;
             int mins = totalMin % 60;
             totalDurationStr = hrs > 0 ? "${hrs}h ${mins}min" : "${mins}min";
           }
        }

        final newTabId = DateTime.now().millisecondsSinceEpoch.toString();
        String eta = "--:--";
        if (journeyData['arrival'] != null) {
          final arr = DateTime.parse(journeyData['arrival']);
          eta = "${arr.hour.toString().padLeft(2, '0')}:${arr.minute.toString().padLeft(2, '0')}";
        }
        
        // Find destination name properly (this assumes we know the ID, name lookup would be better but ID works for logic)
        // For title, we can try to fetch name or just use "New Route" if name unavailable instantly
        // A clean way is to re-use _toStation name if ID matches, or just "Alternative"
        String title = "Alternative Route";
        if (_toStation != null && _toStation!.id == finalDestId) {
          title = _toStation!.name;
        }

        final newTab = RouteTab(
          id: newTabId,
          title: title, 
          subtitle: "Alternative from ${newDepartureTime.hour}:${newDepartureTime.minute.toString().padLeft(2,'0')}",
          eta: eta,
          totalDuration: totalDurationStr, 
          destinationId: finalDestId, 
          steps: steps,
        );

        setState(() {
          _tabs.add(newTab);
          _activeTabId = newTabId;
          _isLoadingRoute = false;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Alternative route opened in new tab")));
        }

      } else {
        setState(() => _isLoadingRoute = false);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not find route from selected departure.")));
      }
    } catch (e) {
      setState(() => _isLoadingRoute = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to open alternative: $e")));
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
                    if (!snapshot.hasData || snapshot.data!.isEmpty) return Center(child: Text("No messages yet.", style: TextStyle(color: Colors.grey.shade600)));
                    return ListView.builder(
                      itemCount: snapshot.data!.length,
                      itemBuilder: (context, index) {
                        final msg = snapshot.data![index];
                        final user = msg['user_id'].toString().substring(0, 4);
                        return ListTile(
                          leading: CircleAvatar(child: Text(user[0])),
                          title: Text(user, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          subtitle: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                            child: Text(msg['content']),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              Row(
                children: [
                  Expanded(child: TextField(controller: msgController, decoration: const InputDecoration(hintText: "Message..."))),
                  IconButton(icon: const Icon(Icons.send), onPressed: () { if (msgController.text.isNotEmpty) { SupabaseService.sendMessage(lineName, msgController.text); msgController.clear(); } })
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  void _showGuide(BuildContext context, String? startStationId) {
    if (startStationId == null) return;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            backgroundColor: Theme.of(ctx).cardColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Station Guide", style: TextStyle(color: Theme.of(ctx).textTheme.bodyLarge?.color)),
                IconButton(
                  icon: const Icon(Icons.add_a_photo, color: Colors.blue),
                  onPressed: () async {
                    final picker = ImagePicker();
                    final picked = await picker.pickImage(
                      source: ImageSource.camera,
                      maxWidth: 1024,
                      maxHeight: 1024,
                      imageQuality: 80,
                    );
                    
                    if (picked != null) {
                       try {
                         dynamic imageFile;
                         if (kIsWeb) {
                           imageFile = await picked.readAsBytes();
                         } else {
                           imageFile = File(picked.path);
                         }
                         
                         if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Uploading...")));
                         
                         await SupabaseService.uploadStationImage(imageFile, startStationId);
                         
                         setStateDialog(() {}); 
                         if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Guide updated!")));
                       } catch (e) {
                         if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
                       }
                    }
                  },
                )
              ],
            ),
            content: FutureBuilder<String?>(
              future: SupabaseService.getStationImage(startStationId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()));
                final imageUrl = snapshot.data;
                if (imageUrl == null) return const Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.image_not_supported, size: 40), Text("No guide image found.")]);
                return ClipRRect(
                  borderRadius: BorderRadius.circular(16), 
                  child: Image.network(
                    imageUrl, 
                    fit: BoxFit.cover, 
                    height: 200,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
                    },
                  ),
                );
              },
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close"))],
          );
        }
      ),
    );
  }

  void _showAlternatives(BuildContext context, String stationId, int stepIndex, String finalDestinationId) {
     showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      builder: (ctx) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: TransportApi.getDepartures(stationId, nahverkehrOnly: widget.onlyNahverkehr),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (!snapshot.hasData || snapshot.data!.isEmpty) return Center(child: Text("No alternatives found.", style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)));
            
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: snapshot.data!.length,
              itemBuilder: (ctx, idx) {
                final dep = snapshot.data![idx];
                final line = dep['line']['name'] ?? 'Unknown';
                final dir = dep['direction'] ?? 'Unknown';
                final planned = DateTime.parse(dep['plannedWhen']);
                final time = "${planned.hour.toString().padLeft(2,'0')}:${planned.minute.toString().padLeft(2,'0')}";
                
                return ListTile(
                  leading: const Icon(Icons.directions_bus), 
                  title: Text("$line to $dir"), 
                  trailing: Text(time),
                  onTap: () {
                    // NEW: Open new tab instead of update
                    _openNewRouteTab(planned, stationId, finalDestinationId);
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _triggerVibration() async {
    if (kIsWeb) return; 
    if (await Vibration.hasVibrator() ?? false) {
      final prefs = await SharedPreferences.getInstance();
      final intensity = prefs.getInt('vibration_intensity') ?? 128;
      Vibration.vibrate(pattern: [0, 200, 100, 200], intensities: [0, intensity, 0, intensity]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool canSearch = (_fromStation != null || widget.currentPosition != null) && _toStation != null && !_isLoadingRoute;
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                    decoration: BoxDecoration(color: isActive ? const Color(0xFF4F46E5) : Theme.of(context).cardColor, borderRadius: BorderRadius.circular(20)),
                    child: Row(children: [Icon(Icons.directions, size: 16, color: isActive ? Colors.white : Colors.grey), const SizedBox(width: 6), Text(tab.title, style: TextStyle(color: isActive ? Colors.white : Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)), const SizedBox(width: 4), GestureDetector(onTap: () => _closeTab(tab.id), child: Icon(Icons.close, size: 14, color: isActive ? Colors.white70 : Colors.grey))]),
                  ),
                );
              },
            ),
          ),
        Expanded(child: _activeTabId == null ? _buildSearchView(canSearch, isDark) : _buildActiveRouteView(_tabs.firstWhere((t) => t.id == _activeTabId))),
      ],
    );
  }

  Widget _buildSearchView(bool canSearch, bool isDark) {
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
                  Row(children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.2), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.search, color: Colors.indigoAccent)), const SizedBox(width: 12), Text("Plan Journey", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor))]),
                  const SizedBox(height: 20),
                  _buildTextField("From", _fromController, _fromStation != null, 'from', hint: (_fromStation == null && widget.currentPosition != null) ? "Current Location" : "Station..."),
                  if (_activeSearchField == 'from') _buildSuggestionsList(),
                  const SizedBox(height: 12),
                  _buildTextField("To", _toController, _toStation != null, 'to'),
                  if (_activeSearchField == 'to') _buildSuggestionsList(),
                  const SizedBox(height: 20),
                  Text("Trip Time", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: isDark ? const Color(0xFF1F2937) : Colors.grey.shade200, borderRadius: BorderRadius.circular(16)),
                    child: Row(
                      children: [
                        GestureDetector(onTap: () => setState(() => _isArrival = !_isArrival), child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.indigoAccent, borderRadius: BorderRadius.circular(12)), child: Text(_isArrival ? "Arrive by" : "Depart at", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)))),
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
                         return GestureDetector(onTap: () => _onFavoriteTap(fav), onLongPress: () => _showEditFavoriteDialog(fav), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Container(width: 48, height: 48, decoration: BoxDecoration(color: (fav.type == 'friend' ? Colors.green : Colors.indigo).withOpacity(0.1), shape: BoxShape.circle), child: Icon(fav.type == 'friend' ? Icons.person : (fav.label.toLowerCase() == 'home' ? Icons.home : (fav.label.toLowerCase() == 'work' ? Icons.work : Icons.star)), color: fav.type == 'friend' ? Colors.green : Colors.indigo, size: 20)), const SizedBox(height: 4), Text(fav.label, style: TextStyle(fontSize: 10, color: textColor))]));
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(width: double.infinity, height: 56, child: ElevatedButton(onPressed: canSearch ? _findRoutes : null, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: _isLoadingRoute ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text("Find Routes", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)))),
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
                final item = _suggestions[idx];
                if (item is Favorite) return ListTile(leading: const Icon(Icons.star, size: 16, color: Colors.orange), title: Text(item.label, style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.bold)), onTap: () => _selectItem(item));
                final station = item as Station;
                return ListTile(leading: const Icon(Icons.place, size: 16, color: Colors.grey), title: Text(station.name, style: TextStyle(color: textColor, fontSize: 14)), onTap: () => _selectItem(station));
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, bool isSelected, String fieldKey, {String hint = "Station..."}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Color iconColor = Colors.grey;
    if (isSelected) iconColor = Colors.greenAccent; else if (fieldKey == 'from' && hint == "Current Location") iconColor = Colors.blue;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Padding(padding: const EdgeInsets.only(left: 4, bottom: 4), child: Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold))), TextField(controller: controller, onChanged: (val) => _onSearchChanged(val, fieldKey), onTap: () => setState(() => _activeSearchField = fieldKey), style: TextStyle(color: isDark ? Colors.white : Colors.black), decoration: InputDecoration(filled: true, fillColor: isDark ? const Color(0xFF1F2937) : Colors.grey.shade200, prefixIcon: Icon(fieldKey == 'from' ? Icons.my_location : Icons.location_on, color: iconColor, size: 20), hintText: hint, hintStyle: TextStyle(color: hint == "Current Location" ? Colors.blue.withOpacity(0.5) : Colors.grey), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)))]);
  }

  Widget _buildActiveRouteView(RouteTab route) {
    final textColor = Theme.of(context).textTheme.bodyLarge?.color;
    final cardColor = Theme.of(context).cardColor;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(route.title, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor)),
                  Text(route.subtitle, style: const TextStyle(color: Colors.grey)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.green.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                   const Icon(Icons.timer_outlined, size: 16, color: Colors.green),
                   const SizedBox(width: 4),
                   Text(route.totalDuration, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                ],
              ),
            )
          ],
        ),
        const SizedBox(height: 20),
        
        for (int i = 0; i < route.steps.length; i++) ...[
          (() {
            final step = route.steps[i];
            final isWait = step.type == 'wait';
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isWait ? Colors.orange.withOpacity(0.1) : cardColor, 
                borderRadius: BorderRadius.circular(16),
                border: isWait ? Border.all(color: Colors.orange.withOpacity(0.3)) : null
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Expanded(child: Text(step.instruction, style: TextStyle(fontWeight: FontWeight.bold, color: textColor))), 
                  // HIDE TIME for wait/transfer steps
                  if (!isWait)
                    Text("${step.departureTime} - ${step.arrivalTime}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigoAccent))
                ]),
                const SizedBox(height: 4),
                
                // Show duration subtitle
                if (step.line == 'Wait' && isWait)
                  Text(step.duration, style: const TextStyle(color: Colors.orange))
                else
                  Text("${step.line} • ${step.duration}", style: TextStyle(color: isWait ? Colors.orange : Colors.grey)),
                
                if (step.platform != null) Text(step.platform!, style: const TextStyle(color: Colors.greenAccent, fontSize: 12)),
                
                if (!isWait)
                  Padding(padding: const EdgeInsets.only(top: 12), child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
                    GestureDetector(onTap: () => _showChat(context, step.line), child: _buildActionChip(Icons.chat_bubble_outline, "Chat")),
                    const SizedBox(width: 8),
                    if (!step.line.toLowerCase().contains('bus')) ...[GestureDetector(onTap: () => _showGuide(context, step.startStationId), child: _buildActionChip(Icons.camera_alt_outlined, "Guide")), const SizedBox(width: 8)],
                    GestureDetector(onTap: () { setState(() => _isWakeAlarmSet = !_isWakeAlarmSet); ScaffoldMessenger.of(context).clearSnackBars(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_isWakeAlarmSet ? "Alarm ON" : "Alarm OFF"), action: _isWakeAlarmSet ? SnackBarAction(label: "TEST", onPressed: _triggerVibration) : null)); }, child: _buildActionChip(Icons.vibration, _isWakeAlarmSet ? "Alarm ON" : "Wake Me", isActive: _isWakeAlarmSet)),
                    const SizedBox(width: 8),
                    if (step.startStationId != null) GestureDetector(onTap: () => _showAlternatives(context, step.startStationId!, i, route.destinationId), child: _buildActionChip(Icons.alt_route, "Alternatives")),
                  ])))
              ]),
            );
          }())
        ]
      ],
    );
  }

  Widget _buildActionChip(IconData icon, String label, {bool isActive = false}) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: isActive ? Colors.indigoAccent : Colors.grey.withOpacity(0.2), borderRadius: BorderRadius.circular(20)), child: Row(children: [Icon(icon, size: 14, color: isActive ? Colors.white : Colors.grey), const SizedBox(width: 6), Text(label, style: TextStyle(color: isActive ? Colors.white : Colors.grey, fontSize: 12))]));
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
            Text("Edit Favorite", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
            const SizedBox(height: 20),
            
            // LABEL INPUT
            TextField(controller: _labelCtrl, decoration: const InputDecoration(labelText: "Label (e.g. Home, Bestie)")),
            const SizedBox(height: 10),
            
            // TYPE SELECTOR
            Row(children: [
              Expanded(child: RadioListTile<String>(title: const Text("Station"), value: 'station', groupValue: _currentType, contentPadding: EdgeInsets.zero, onChanged: (val) => setState(() => _currentType = val!))),
              Expanded(child: RadioListTile<String>(title: const Text("Friend"), value: 'friend', groupValue: _currentType, contentPadding: EdgeInsets.zero, onChanged: (val) => setState(() => _currentType = val!))),
            ]),
            
            const SizedBox(height: 10),

            // CONTENT AREA 
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
                        if (_labelCtrl.text.isEmpty || _labelCtrl.text == widget.favorite.label) {
                           _labelCtrl.text = res.first['username'];
                        }
                      });
                    }
                  },
               ),
               if (_selectedFriendId != null) const Padding(padding: EdgeInsets.only(top: 8), child: Text("Friend Selected", style: TextStyle(color: Colors.green))),
            ],

            const SizedBox(height: 20),
            
            // ACTION BUTTONS
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () async {
                    await FavoritesManager.deleteFavorite(widget.favorite.id);
                    if (mounted) Navigator.pop(context, true); // Return TRUE
                  },
                  child: const Text("Delete", style: TextStyle(color: Colors.red)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    if (_labelCtrl.text.isNotEmpty) {
                      final newFav = Favorite(
                        id: widget.favorite.id,
                        label: _labelCtrl.text,
                        type: _currentType,
                        station: _selectedStation,
                        friendId: _selectedFriendId
                      );
                      await FavoritesManager.saveFavorite(newFav);
                      if (mounted) Navigator.pop(context, true); // Return TRUE
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