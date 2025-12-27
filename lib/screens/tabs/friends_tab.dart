import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/supabase_service.dart';

class FriendsTab extends StatefulWidget {
  final Position? currentPosition;

  const FriendsTab({super.key, required this.currentPosition});

  @override
  State<FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<FriendsTab> {
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;

  StreamSubscription? _friendsSub;
  StreamSubscription? _requestsSub;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _friendsSub?.cancel();
    _requestsSub?.cancel();
    super.dispose();
  }

  void _initData() async {
    // 1. FAST INITIAL FETCH (Removes spinner immediately)
    try {
      final friends = await SupabaseService.getFriendsWithLocation();
      final requests = await SupabaseService.getPendingRequests();
      if (mounted) {
        setState(() {
          _friends = friends;
          _requests = requests;
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Initial friends fetch failed: $e");
      if (mounted) setState(() => _isLoading = false);
    }

    // 2. LISTEN FOR LIVE UPDATES
    _friendsSub = SupabaseService.streamFriendsWithLocation().listen((data) {
      if (mounted) setState(() => _friends = data);
    });

    _requestsSub = SupabaseService.streamPendingRequests().listen((data) {
      if (mounted) setState(() => _requests = data);
    });
  }

  void _showAddFriendSheet(BuildContext context) async {
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
                  Text("Add New Friend", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
                  const SizedBox(height: 16),
                  
                  TextField(
                    controller: searchCtrl,
                    decoration: InputDecoration(
                      hintText: "Search by username...",
                      filled: true,
                      fillColor: Theme.of(context).scaffoldBackgroundColor,
                      prefixIcon: const Icon(Icons.search),
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
                        if (user['id'] == SupabaseService.currentUser?.id) return const SizedBox.shrink();
                        
                        return ListTile(
                          leading: CircleAvatar(
                             backgroundImage: user['avatar_url'] != null ? NetworkImage(user['avatar_url']) : null,
                             child: user['avatar_url'] == null ? Text(user['username'][0].toUpperCase()) : null
                          ),
                          title: Text(user['username']),
                          trailing: IconButton(
                            icon: const Icon(Icons.person_add, color: Colors.blue),
                            onPressed: () async {
                              try {
                                await SupabaseService.sendFriendRequest(user['id']);
                                if (context.mounted) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Request sent to @${user['username']}")));
                                }
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e")));
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

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).textTheme.bodyLarge?.color;
    
    // --- SORTING LOGIC ---
    final now = DateTime.now();
    final activeFriends = <Map<String, dynamic>>[];
    final inactiveFriends = <Map<String, dynamic>>[];

    for (var f in _friends) {
      final updated = DateTime.tryParse(f['updated_at'] ?? '') ?? DateTime(2000);
      final isActive = now.difference(updated).inHours < 12;
      if (isActive) {
        activeFriends.add(f);
      } else {
        inactiveFriends.add(f);
      }
    }

    activeFriends.sort((a, b) => (a['username'] as String).compareTo(b['username'] as String));
    _requests.sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String));
    inactiveFriends.sort((a, b) => (a['username'] as String).compareTo(b['username'] as String));

    final combinedList = [...activeFriends, ..._requests, ...inactiveFriends];

    return Column(
      children: [
        const SizedBox(height: 100),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Friends", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor)),
              IconButton(
                icon: const Icon(Icons.person_add, color: Colors.blue),
                onPressed: () => _showAddFriendSheet(context),
              )
            ],
          ),
        ),
        
        Expanded(
          child: _isLoading 
            ? const Center(child: CircularProgressIndicator()) 
            : combinedList.isEmpty 
                ? Center(child: Text("No friends yet.", style: TextStyle(color: Colors.grey.shade600)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: combinedList.length,
                    itemBuilder: (ctx, idx) {
                      final item = combinedList[idx];
                      final bool isRequest = item.containsKey('sender_id');

                      if (isRequest) {
                        return _buildRequestCard(item, textColor);
                      } else {
                        final bool isActive = activeFriends.contains(item);
                        return _buildFriendCard(item, isActive, textColor);
                      }
                    },
                  ),
        ),
      ],
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> req, Color? textColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.indigo.withOpacity(0.1), 
        borderRadius: BorderRadius.circular(16), 
        border: Border.all(color: Colors.indigo.withOpacity(0.3))
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundImage: req['sender_avatar'] != null ? NetworkImage(req['sender_avatar']) : null,
            child: req['sender_avatar'] == null ? Text((req['sender_username'] ?? "?")[0].toUpperCase()) : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(req['sender_username'] ?? "User", style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                const Text("Sent a friend request", style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.check_circle, color: Colors.green),
            onPressed: () => SupabaseService.acceptFriendRequest(req['sender_id']),
          ),
          IconButton(
            icon: const Icon(Icons.cancel, color: Colors.red),
            onPressed: () => SupabaseService.rejectFriendRequest(req['sender_id']),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendCard(Map<String, dynamic> friend, bool isActive, Color? textColor) {
    final String? currentLine = friend['current_line'];
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isActive ? Theme.of(context).cardColor.withOpacity(0.9) : Theme.of(context).cardColor.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isActive ? Colors.green.withOpacity(0.3) : Colors.white10)
      ),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                backgroundImage: friend['avatar_url'] != null ? NetworkImage(friend['avatar_url']) : null,
                child: friend['avatar_url'] == null ? Text((friend['username'] ?? "?")[0].toUpperCase()) : null,
              ),
              if (isActive)
                Positioned(right: 0, bottom: 0, child: Container(width: 12, height: 12, decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle, border: Border.all(color: Theme.of(context).cardColor, width: 2))))
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, 
              children: [
                Text(friend['username'] ?? "Unknown", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)), 
                const SizedBox(height: 2), 
                if (currentLine != null && currentLine.isNotEmpty && isActive)
                  Row(
                    children: [
                      const Icon(Icons.directions_bus, size: 12, color: Colors.blue),
                      const SizedBox(width: 4),
                      Text("On $currentLine", style: const TextStyle(fontSize: 12, color: Colors.blue)),
                    ],
                  )
                else
                  Text(isActive ? "Active recently" : "Inactive", style: TextStyle(fontSize: 12, color: isActive ? Colors.green : Colors.grey))
              ]
            ),
          ),
        ],
      ),
    );
  }
}