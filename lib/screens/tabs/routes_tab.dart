import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vibration/vibration.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  
  // Suggestions now hold either Station objects or Favorite objects
  List<dynamic> _suggestions = []; 
  
  String _activeSearchField = '';
  Timer? _debounce;
  bool _isLoadingRoute = false;
  bool _isSuggestionsLoading = false;
  
  // Time Planning State
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

    // 1. Add matching favorites (Fix 3: Typing favorite name works like station)
    if (query.isNotEmpty) {
      final matchingFavs = _favorites.where((f) => f.label.toLowerCase().contains(query.toLowerCase())).toList();
      results.addAll(matchingFavs);
    }

    // 2. Add history (filtered by query if present)
    final history = await SearchHistoryManager.getHistory();
    if (history.isNotEmpty) {
       if (query.isNotEmpty) {
         // Avoid duplicates if favorite matches history item (simple name check)
         results.addAll(history.where((s) => s.name.toLowerCase().contains(query.toLowerCase())));
       } else {
         results.addAll(history);
       }
    }

    // 3. Add Nearby if "From" is focused and empty
    if (widget.currentPosition != null && _activeSearchField == 'from' && query.isEmpty) {
      final nearby = await TransportApi.getNearbyStops(
          widget.currentPosition!.latitude, widget.currentPosition!.longitude);
      for (var s in nearby) {
        // Prevent duplicates from history
        if (!results.any((h) => h is Station && h.id == s.id)) results.insert(0, s);
      }
    }

    if (mounted) setState(() { _suggestions = results; _isSuggestionsLoading = false; });
  }

  void _onSearchChanged(String query, String field) {
    setState(() => _activeSearchField = field);
    
    // Immediate local search (Favorites/History)
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
            // Append API results to existing local suggestions
            // Simple check to avoid duplicates with existing items
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
    // Hide suggestions
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

  // FIX 2: Enhanced Edit Favorite Dialog
  void _showEditFavoriteDialog(Favorite fav) {
    final labelCtrl = TextEditingController(text: fav.label);
    
    // We use a dedicated controller for the search field in the dialog
    // to prevent state loss on rebuilds
    final searchCtrl = TextEditingController();
    
    Station? selectedStation = fav.station;
    String? selectedFriendId = fav.friendId;
    String currentType = fav.type;
    
    // Dialog Search State
    List<Station> dialogSuggestions = [];
    Timer? dialogDebounce;
    bool dialogLoading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: Theme.of(context).cardColor,
            title: Text("Edit Favorite", style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: labelCtrl,
                    decoration: const InputDecoration(labelText: "Label (e.g. Home, Bestie)"),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text("Station"),
                          value: 'station',
                          groupValue: currentType,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (val) => setDialogState(() => currentType = val!),
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text("Friend"),
                          value: 'friend',
                          groupValue: currentType,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (val) => setDialogState(() => currentType = val!),
                        ),
                      ),
                    ],
                  ),
                  
                  if (currentType == 'station') ...[
                    if (selectedStation != null)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.train, color: Colors.indigo),
                        title: Text(selectedStation!.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setDialogState(() {
                            selectedStation = null;
                            searchCtrl.clear(); // Clear search so we can type again
                          }),
                        ),
                      )
                    else ...[
                      // SEARCH FIELD
                      TextField(
                        controller: searchCtrl, // Added Controller
                        decoration: InputDecoration(
                          labelText: "Search Station Name",
                          prefixIcon: const Icon(Icons.search),
                          suffix: dialogLoading ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)) : null,
                        ),
                        onChanged: (val) {
                           if (dialogDebounce?.isActive ?? false) dialogDebounce!.cancel();
                           if (val.isEmpty) {
                             setDialogState(() => dialogSuggestions = []);
                             return;
                           }
                           dialogDebounce = Timer(const Duration(milliseconds: 400), () async {
                             setDialogState(() => dialogLoading = true);
                             final res = await TransportApi.searchStations(val);
                             setDialogState(() {
                               dialogSuggestions = res;
                               dialogLoading = false;
                             });
                           });
                        },
                      ),
                      // SUGGESTIONS LIST
                      if (dialogSuggestions.isNotEmpty)
                        Container(
                          height: 150,
                          margin: const EdgeInsets.only(top: 8),
                          decoration: BoxDecoration(border: Border.all(color: Colors.white10), borderRadius: BorderRadius.circular(8)),
                          child: ListView.builder(
                            itemCount: dialogSuggestions.length,
                            itemBuilder: (context, idx) {
                              final s = dialogSuggestions[idx];
                              return ListTile(
                                dense: true,
                                title: Text(s.name),
                                onTap: () {
                                  setDialogState(() {
                                    selectedStation = s;
                                    dialogSuggestions = [];
                                    // Auto-fill label if empty
                                    if (labelCtrl.text.isEmpty) labelCtrl.text = s.name;
                                  });
                                },
                              );
                            },
                          ),
                        )
                    ]
                  ],
                  if (currentType == 'friend') ...[
                     TextField(
                        decoration: const InputDecoration(labelText: "Search Friend Username"),
                        onSubmitted: (val) async {
                          final res = await SupabaseService.searchUsers(val);
                          if (res.isNotEmpty) {
                            setDialogState(() => selectedFriendId = res.first['id']);
                            if (labelCtrl.text.isEmpty || labelCtrl.text == fav.label) {
                               labelCtrl.text = res.first['username'];
                            }
                          }
                        },
                     ),
                     if (selectedFriendId != null) 
                       Padding(padding: const EdgeInsets.only(top: 8), child: Text("Friend Selected", style: const TextStyle(color: Colors.green))),
                  ]
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await FavoritesManager.deleteFavorite(fav.id);
                  _loadFavorites();
                  Navigator.pop(context);
                },
                child: const Text("Delete", style: TextStyle(color: Colors.red)),
              ),
              TextButton(
                onPressed: () async {
                  if (labelCtrl.text.isNotEmpty) {
                    final newFav = Favorite(
                      id: fav.id,
                      label: labelCtrl.text,
                      type: currentType,
                      station: selectedStation,
                      friendId: selectedFriendId
                    );
                    await FavoritesManager.saveFavorite(newFav);
                    _loadFavorites();
                    Navigator.pop(context);
                  }
                },
                child: const Text("Save"),
              )
            ],
          );
        },
      ),
    );
  }
  
  void _addNewFavorite() {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    _showEditFavoriteDialog(Favorite(id: id, label: '', type: 'station'));
  }

  // --- ROUTE LOGIC ---

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

          // Format times for display
          String depTime = "${dep.hour.toString().padLeft(2, '0')}:${dep.minute.toString().padLeft(2, '0')}";
          String arrTime = "${arr.hour.toString().padLeft(2, '0')}:${arr.minute.toString().padLeft(2, '0')}";

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
            departureTime: depTime,
            arrivalTime: arrTime, // Added
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
          subtitle: "${from.name} → ${_toStation!.name}",
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

  // --- OVERLAYS ---
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
                    
                    final msgs = snapshot.data!;
                    return ListView.builder(
                      itemCount: msgs.length,
                      itemBuilder: (context, index) {
                        final msg = msgs[index];
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
                  IconButton(
                    icon: const Icon(Icons.send),
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
              return const Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.image_not_supported, size: 40), Text("No guide image found.")]);
            }
            return ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(imageUrl, fit: BoxFit.cover, height: 200),
            );
          },
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close"))],
      ),
    );
  }

  void _showAlternatives(BuildContext context, String stationId) {
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
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _triggerVibration() async {
    if (await Vibration.hasVibrator() ?? false) {
      final prefs = await SharedPreferences.getInstance();
      final patternName = prefs.getString('vibration_pattern') ?? 'standard';
      final intensity = prefs.getInt('vibration_intensity') ?? 128;

      List<int> pattern = [0, 500, 200, 500];
      if (patternName == 'heartbeat') pattern = [0, 200, 100, 200];
      if (patternName == 'tick') pattern = [0, 50];

      if (await Vibration.hasAmplitudeControl() ?? false) {
        Vibration.vibrate(pattern: pattern, intensities: pattern.map((_) => intensity).toList());
      } else {
        Vibration.vibrate(pattern: pattern);
      }
    }
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    final bool canSearch = (_fromStation != null || widget.currentPosition != null) && 
                           _toStation != null && 
                           !_isLoadingRoute;

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
          child: _activeTabId == null 
              ? _buildSearchView(canSearch, isDark) 
              : _buildActiveRouteView(_tabs.firstWhere((t) => t.id == _activeTabId)),
        ),
      ],
    );
  }

  // FIX 1: Added Padding at bottom to prevent obstruction by Ticket Sheet
  Widget _buildSearchView(bool canSearch, bool isDark) {
    final textColor = Theme.of(context).textTheme.bodyLarge?.color;
    final cardColor = Theme.of(context).cardColor;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 100), // PADDING ADDED HERE
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
                  
                  // FROM Field
                  _buildTextField(
                    "From", 
                    _fromController, 
                    _fromStation != null, 
                    'from',
                    hint: (_fromStation == null && widget.currentPosition != null) ? "Current Location" : "Station..."
                  ),
                  
                  if (_activeSearchField == 'from') _buildSuggestionsList(),
                  const SizedBox(height: 12),
                  
                  // TO Field
                  _buildTextField("To", _toController, _toStation != null, 'to'),
                  if (_activeSearchField == 'to') _buildSuggestionsList(),
                  
                  const SizedBox(height: 20),

                  // TIME & DATE SELECTION
                  Text("Trip Time", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1F2937) : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(16)
                    ),
                    child: Row(
                      children: [
                        // Dep/Arr Toggle
                        GestureDetector(
                          onTap: () => setState(() => _isArrival = !_isArrival),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.indigoAccent,
                              borderRadius: BorderRadius.circular(12)
                            ),
                            child: Text(
                              _isArrival ? "Arrive by" : "Depart at",
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        
                        // Time Display/Picker
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              final now = DateTime.now();
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _selectedDate ?? now,
                                firstDate: now.subtract(const Duration(days: 30)),
                                lastDate: now.add(const Duration(days: 90)),
                              );
                              if (picked != null) {
                                setState(() {
                                  _selectedDate = picked;
                                  _selectedTime ??= TimeOfDay.now();
                                });
                                // Chain Time Picker
                                final t = await showTimePicker(context: context, initialTime: _selectedTime!);
                                if (t != null) setState(() => _selectedTime = t);
                              }
                            },
                            child: Row(
                              children: [
                                Icon(Icons.calendar_today, size: 16, color: Colors.grey.shade600),
                                const SizedBox(width: 6),
                                Text(
                                  _selectedDate == null 
                                    ? "Now" 
                                    : "${_selectedDate!.day}.${_selectedDate!.month}  ${_selectedTime?.format(context) ?? ''}",
                                  style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Clear Button
                        if (_selectedDate != null)
                          IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () => setState(() {
                              _selectedDate = null;
                              _selectedTime = null;
                            }),
                          )
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // FAVORITES
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
                           return GestureDetector(
                             onTap: _addNewFavorite,
                             child: Column(
                               mainAxisAlignment: MainAxisAlignment.center,
                               children: [
                                 Container(
                                   width: 48, height: 48,
                                   decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), shape: BoxShape.circle),
                                   child: const Icon(Icons.add, color: Colors.blue),
                                 ),
                                 const SizedBox(height: 4),
                                 const Text("Add", style: TextStyle(fontSize: 10))
                               ],
                             ),
                           );
                         }
                         final fav = _favorites[idx];
                         final isFriend = fav.type == 'friend';
                         return GestureDetector(
                           onTap: () => _onFavoriteTap(fav),
                           onLongPress: () => _showEditFavoriteDialog(fav),
                           child: Column(
                             mainAxisAlignment: MainAxisAlignment.center,
                             children: [
                               Container(
                                 width: 48, height: 48,
                                 decoration: BoxDecoration(
                                    color: (isFriend ? Colors.green : Colors.indigo).withOpacity(0.1), 
                                    shape: BoxShape.circle,
                                 ),
                                 child: Icon(
                                   isFriend ? Icons.person : (fav.label.toLowerCase() == 'home' ? Icons.home : (fav.label.toLowerCase() == 'work' ? Icons.work : Icons.star)),
                                   color: isFriend ? Colors.green : Colors.indigo,
                                   size: 20,
                                 ),
                               ),
                               const SizedBox(height: 4),
                               Text(fav.label, style: TextStyle(fontSize: 10, color: textColor))
                             ],
                           ),
                         );
                      },
                    ),
                  ),

                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: canSearch ? _findRoutes : null,
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                      child: _isLoadingRoute 
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) 
                        : const Text("Find Routes", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                final item = _suggestions[idx];
                
                // Render differently if it's a Favorite or a Station
                if (item is Favorite) {
                   return ListTile(
                    leading: const Icon(Icons.star, size: 16, color: Colors.orange),
                    title: Text(item.label, style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.bold)),
                    subtitle: Text(item.type == 'station' ? (item.station?.name ?? '') : 'Friend', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    onTap: () => _selectItem(item),
                  );
                }

                final station = item as Station;
                return ListTile(
                  leading: const Icon(Icons.place, size: 16, color: Colors.grey),
                  title: Text(station.name, style: TextStyle(color: textColor, fontSize: 14)),
                  onTap: () => _selectItem(station),
                );
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
    if (isSelected) iconColor = Colors.greenAccent;
    else if (fieldKey == 'from' && hint == "Current Location") iconColor = Colors.blue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(left: 4, bottom: 4), child: Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold))),
        TextField(
          controller: controller, onChanged: (val) => _onSearchChanged(val, fieldKey), onTap: () => setState(() => _activeSearchField = fieldKey),
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
          decoration: InputDecoration(
            filled: true, fillColor: isDark ? const Color(0xFF1F2937) : Colors.grey.shade200,
            prefixIcon: Icon(fieldKey == 'from' ? Icons.my_location : Icons.location_on, color: iconColor, size: 20),
            hintText: hint,
            hintStyle: TextStyle(
              color: hint == "Current Location" ? Colors.blue.withOpacity(0.5) : Colors.grey
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }

  // FIX 1 & 5: Added Padding to bottom & Displaying Times
  Widget _buildActiveRouteView(RouteTab route) {
    final textColor = Theme.of(context).textTheme.bodyLarge?.color;
    final cardColor = Theme.of(context).cardColor;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), // BOTTOM PADDING ADDED
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
              child: Row(children: [const Icon(Icons.directions_walk, color: Colors.grey), const SizedBox(width: 16), Expanded(child: Text(step.instruction, style: TextStyle(color: textColor)))]),
            );
          }
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // FIX 5: SHOW TIMES
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(step.instruction, style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                  Text("${step.departureTime} - ${step.arrivalTime}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigoAccent)),
                ],
              ),
              const SizedBox(height: 4),
              Text("${step.line} • ${step.duration}", style: const TextStyle(color: Colors.grey)),
              if (step.platform != null) Text(step.platform!, style: const TextStyle(color: Colors.greenAccent, fontSize: 12)),
              
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => _showChat(context, step.line),
                        child: _buildActionChip(Icons.chat_bubble_outline, "Chat"),
                      ),
                      const SizedBox(width: 8),
                      if (!step.line.toLowerCase().contains('bus')) ...[
                        GestureDetector(
                          onTap: () => _showGuide(context, step.startStationId),
                          child: _buildActionChip(Icons.camera_alt_outlined, "Guide"),
                        ),
                        const SizedBox(width: 8),
                      ],
                      GestureDetector(
                        onTap: () {
                          setState(() => _isWakeAlarmSet = !_isWakeAlarmSet);
                          ScaffoldMessenger.of(context).clearSnackBars();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(_isWakeAlarmSet 
                                ? "Alarm ON. We will vibrate when you are close." 
                                : "Alarm OFF."
                              ),
                              action: _isWakeAlarmSet ? SnackBarAction(
                                label: "TEST",
                                onPressed: _triggerVibration,
                              ) : null,
                            )
                          );
                        },
                        child: _buildActionChip(
                          Icons.vibration, 
                          _isWakeAlarmSet ? "Alarm ON" : "Wake Me",
                          isActive: _isWakeAlarmSet
                        ),
                      ),
                      const SizedBox(width: 8),
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

  Widget _buildActionChip(IconData icon, String label, {bool isActive = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isActive ? Colors.indigoAccent : Colors.grey.withOpacity(0.2), 
        borderRadius: BorderRadius.circular(20)
      ),
      child: Row(children: [
        Icon(icon, size: 14, color: isActive ? Colors.white : Colors.grey), 
        const SizedBox(width: 6), 
        Text(label, style: TextStyle(color: isActive ? Colors.white : Colors.grey, fontSize: 12))
      ]),
    );
  }
}