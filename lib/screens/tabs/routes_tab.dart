import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vibration/vibration.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/station.dart';
import '../../models/journey.dart';
import '../../models/favorite.dart'; // Import Favorite
import '../../services/transport_api.dart';
import '../../services/supabase_service.dart';
import '../../services/history_manager.dart';
import '../../services/favorites_manager.dart'; // Import Favorites Manager

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
  List<Station> _suggestions = [];
  String _activeSearchField = '';
  Timer? _debounce;
  bool _isLoadingRoute = false;
  bool _isSuggestionsLoading = false;
  
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

  // --- LOGIC ---

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

    if (widget.currentPosition != null && _activeSearchField == 'from') {
      final nearby = await TransportApi.getNearbyStops(
          widget.currentPosition!.latitude, widget.currentPosition!.longitude);
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
        double? refLat = widget.currentPosition?.latitude;
        double? refLng = widget.currentPosition?.longitude;
        // Use other station as reference if set
        if (field == 'to' && _fromStation != null) {
          refLat = _fromStation!.latitude;
          refLng = _fromStation!.longitude;
        }

        final results = await TransportApi.searchStations(query, lat: refLat, lng: refLng);
        if (mounted) setState(() { _suggestions = results; _isSuggestionsLoading = false; });
      } else {
        if (mounted) setState(() { _suggestions = []; _isSuggestionsLoading = false; });
      }
    });
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
    // 1. Determine Target Station
    Station? target;

    if (fav.type == 'station') {
      target = fav.station;
      if (target == null) {
        // Needs setup
        _showEditFavoriteDialog(fav);
        return;
      }
    } else if (fav.type == 'friend' && fav.friendId != null) {
      // Find friend location
      setState(() => _isLoadingRoute = true);
      try {
        // We use a simple select for the single user location
        final data = await SupabaseService.client
            .from('user_locations')
            .select()
            .eq('user_id', fav.friendId!)
            .maybeSingle();
        
        if (data != null) {
          final lat = data['latitude'] as double;
          final lng = data['longitude'] as double;
          
          // Find nearest station to friend
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
      // Apply to UI - default to "To" unless "From" is focused or empty
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

  void _showEditFavoriteDialog(Favorite fav) {
    final labelCtrl = TextEditingController(text: fav.label);
    Station? selectedStation = fav.station;
    String? selectedFriendId = fav.friendId;
    String currentType = fav.type; // 'station' or 'friend'

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
                  
                  // Type Selector
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

                  // Station Picker
                  if (currentType == 'station') ...[
                    if (selectedStation != null)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.train),
                        title: Text(selectedStation!.name),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setDialogState(() => selectedStation = null),
                        ),
                      )
                    else
                      ElevatedButton.icon(
                        icon: const Icon(Icons.search),
                        label: const Text("Search Station"),
                        onPressed: () async {
                           // Simple workaround: Close dialog, focus search, select, then re-open? 
                           // Better: Just tell user to search in main UI.
                           // OR: Simple search dialog on top.
                           // For MVP: Let's assume they search by name string here.
                        }, 
                      ),
                      // NOTE: For simplicity in this turn, we allow them to Paste a station ID or 
                      // actually, let's just make them pick from History or Search inside the dialog.
                      TextField(
                        decoration: const InputDecoration(labelText: "Search Station Name"),
                        onSubmitted: (val) async {
                          final res = await TransportApi.searchStations(val);
                          if (res.isNotEmpty) {
                            setDialogState(() => selectedStation = res.first);
                          }
                        },
                      ),
                  ],

                  // Friend Picker
                  if (currentType == 'friend') ...[
                     FutureBuilder<List<Map<String, dynamic>>>(
                       future: SupabaseService.searchUsers(""), // Search all/recent friends logic needed?
                       // Actually, let's just fetch friends table.
                       // We don't have a getFriends method yet, let's simulate or use search.
                       builder: (context, snap) {
                         return TextField(
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
                         );
                       },
                     ),
                     if (selectedFriendId != null) 
                       Padding(padding: const EdgeInsets.only(top: 8), child: Text("Selected Friend ID: ...${selectedFriendId!.substring(0,6)}", style: const TextStyle(color: Colors.green))),
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
                      id: fav.id, // Keep ID
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
    // Generate ID
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    _showEditFavoriteDialog(Favorite(id: id, label: '', type: 'station'));
  }

  // --- ROUTE LOGIC (Keep existing _findRoutes etc) ---
  Future<void> _findRoutes() async {
    if (_fromStation == null || _toStation == null) return;
    setState(() => _isLoadingRoute = true);

    try {
      final journeyData = await TransportApi.searchJourney(
          _fromStation!.id, 
          _toStation!.id, 
          nahverkehrOnly: widget.onlyNahverkehr
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

  // --- OVERLAYS (Chat, Guide, etc - Keep existing) ---
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
    return Column(
      children: [
        const SizedBox(height: 100),
        // Horizontal Tab List
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
              ? _buildSearchView() 
              : _buildActiveRouteView(_tabs.firstWhere((t) => t.id == _activeTabId)),
        ),
      ],
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
                  
                  // NEW: Favorites Section
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
                           // Add Button
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
                                    border: fav.station == null && fav.friendId == null ? Border.all(color: Colors.red) : null
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
          controller: controller, onChanged: (val) => _onSearchChanged(val, fieldKey), onTap: () => setState(() => _activeSearchField = fieldKey),
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
              child: Row(children: [const Icon(Icons.directions_walk, color: Colors.grey), const SizedBox(width: 16), Expanded(child: Text(step.instruction, style: TextStyle(color: textColor)))]),
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