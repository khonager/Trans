import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/supabase_service.dart';
import '../../config/app_theme.dart';
import '../../widgets/private_chat_sheet.dart'; 

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
  String? _expandedFriendId; 

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
    try {
      final friends = await SupabaseService.getFriends();
      final requests = await SupabaseService.getPendingRequests();
      if (mounted) {
        setState(() {
          _friends = friends;
          _requests = requests;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Friends init error: $e");
      if (mounted) setState(() => _isLoading = false);
    }

    _friendsSub = SupabaseService.streamFriends().listen((data) {
      if (mounted) setState(() => _friends = data);
    });

    _requestsSub = SupabaseService.streamPendingRequests().listen((data) {
      if (mounted) setState(() => _requests = data);
    });
  }

  void _showAddFriendSheet(BuildContext context) {
    final searchCtrl = TextEditingController();
    List<Map<String, dynamic>> searchResults = [];
    final colors = TransColors.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.cardBg,
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
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: colors.modalHandle, borderRadius: BorderRadius.circular(2)), margin: const EdgeInsets.only(bottom: 20)),
                  Text("Add New Friend", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: colors.textPrimary)),
                  const SizedBox(height: 16),
                  
                  TextField(
                    controller: searchCtrl,
                    decoration: InputDecoration(
                      hintText: "Search by username...",
                      filled: true,
                      fillColor: colors.scaffoldBg,
                      prefixIcon: Icon(Icons.search, color: colors.textSecondary),
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
                      separatorBuilder: (_,__) => Divider(color: colors.divider),
                      itemBuilder: (ctx, idx) {
                        final user = searchResults[idx];
                        if (user['id'] == SupabaseService.currentUser?.id) return const SizedBox.shrink();
                        
                        return ListTile(
                          leading: _buildAvatarHelper(user),
                          title: Text(user['username'], style: TextStyle(color: colors.textPrimary)),
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

  void _openPrivateChat(String friendId, String username) {
    showModalBottomSheet(
      context: context, 
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => PrivateChatSheet(friendId: friendId, friendName: username)
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    
    // Sorting Logic
    final now = DateTime.now().toUtc(); 
    final activeFriends = <Map<String, dynamic>>[];
    final inactiveFriends = <Map<String, dynamic>>[];

    for (var f in _friends) {
      if (f['updated_at'] != null) {
        final updated = DateTime.tryParse(f['updated_at'])?.toUtc() ?? DateTime(2000).toUtc();
        final isActive = now.difference(updated).inHours < 12;
        if (isActive) {
          activeFriends.add(f);
          continue;
        }
      }
      inactiveFriends.add(f);
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
              Text("Friends", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: colors.textPrimary)),
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
                ? Center(child: Text("No friends yet.", style: TextStyle(color: colors.textSecondary)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: combinedList.length,
                    itemBuilder: (ctx, idx) {
                      final item = combinedList[idx];
                      final bool isRequest = item.containsKey('sender_id');

                      if (isRequest) {
                        return _buildRequestCard(context, item);
                      } else {
                        final bool isActive = activeFriends.contains(item);
                        return _buildFriendCard(context, item, isActive);
                      }
                    },
                  ),
        ),
      ],
    );
  }

  Widget _buildAvatarHelper(Map<String, dynamic> userData, {double radius = 20}) {
    final emoji = userData['avatar_emoji'] ?? userData['sender_emoji'];
    final url = userData['avatar_url'] ?? userData['sender_avatar'];
    final username = userData['username'] ?? userData['sender_username'] ?? "?";
    
    final colorVal = userData['theme_color'];
    final Color bgColor = colorVal != null ? Color(colorVal) : Colors.indigo;

    if (emoji != null && emoji.isNotEmpty) {
       return CircleAvatar(
         radius: radius,
         backgroundColor: bgColor,
         child: Text(emoji, style: TextStyle(fontSize: radius * 1.2)),
       );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: bgColor,
      backgroundImage: url != null ? NetworkImage(url) : null,
      child: url == null ? Text(username.isNotEmpty ? username[0].toUpperCase() : "?", style: const TextStyle(color: Colors.white)) : null,
    );
  }

  Widget _buildRequestCard(BuildContext context, Map<String, dynamic> req) {
    final colors = TransColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.requestCardBg, 
        borderRadius: BorderRadius.circular(16), 
        border: Border.all(color: colors.requestCardBorder)
      ),
      child: Row(
        children: [
          _buildAvatarHelper(req),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(req['sender_username'] ?? "User", style: TextStyle(fontWeight: FontWeight.bold, color: colors.textPrimary)),
                Text("Sent a friend request", style: TextStyle(fontSize: 12, color: colors.textSecondary)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.check_circle, color: colors.actionIconSuccess),
            onPressed: () => SupabaseService.acceptFriendRequest(req['sender_id']),
          ),
          IconButton(
            icon: Icon(Icons.cancel, color: colors.actionIconError),
            onPressed: () => SupabaseService.rejectFriendRequest(req['sender_id']),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendCard(BuildContext context, Map<String, dynamic> friend, bool isActive) {
    final colors = TransColors.of(context);
    final String? currentLine = friend['current_line']; 
    final String friendId = friend['id'];
    final bool isExpanded = _expandedFriendId == friendId;
    final bool canSeeLoc = friend['can_see_location'] ?? true;
    final bool isGhost = friend['ghost_mode'] ?? false;
    
    return GestureDetector(
      onTap: () => setState(() => _expandedFriendId = isExpanded ? null : friendId),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isActive ? colors.friendCardActiveBg : colors.friendCardInactiveBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isActive ? colors.friendCardActiveBorder : colors.friendCardInactiveBorder)
        ),
        child: Column(
          children: [
            Row(
              children: [
                Stack(
                  children: [
                    _buildAvatarHelper(friend),
                    if (isActive)
                      Positioned(right: 0, bottom: 0, child: Container(width: 12, height: 12, decoration: BoxDecoration(color: colors.statusActive, shape: BoxShape.circle, border: Border.all(color: colors.cardBg, width: 2))))
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, 
                    children: [
                      Text(friend['username'] ?? "Unknown", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: colors.textPrimary)), 
                      const SizedBox(height: 2), 
                      
                      // Status Logic
                      if (!canSeeLoc)
                        Text("Location access required", style: TextStyle(fontSize: 12, color: Colors.orange))
                      else if (isGhost)
                        Text("Location hidden", style: TextStyle(fontSize: 12, color: colors.textSecondary))
                      else if (currentLine != null && currentLine.isNotEmpty && isActive)
                        Row(
                          children: [
                            Icon(Icons.directions_bus, size: 12, color: colors.statusOnline),
                            const SizedBox(width: 4),
                            Text("On $currentLine", style: TextStyle(fontSize: 12, color: colors.statusOnline)),
                          ],
                        )
                      else
                        Text(isActive ? "Active recently" : "Inactive", style: TextStyle(fontSize: 12, color: isActive ? colors.statusActive : colors.statusOffline))
                    ]
                  ),
                ),
                Icon(isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: colors.textSecondary),
              ],
            ),
            
            // Expanded Options
            if (isExpanded) ...[
              const SizedBox(height: 16),
              Divider(color: colors.divider),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                   _buildActionButton(
                     icon: Icons.chat_bubble_outline, 
                     label: "Chat", 
                     color: Colors.blue, 
                     onTap: () => _openPrivateChat(friend['id'], friend['username'] ?? "Friend")
                   ),
                   if (!canSeeLoc)
                     _buildActionButton(
                       icon: Icons.lock_open, 
                       label: "Request Access", 
                       color: Colors.orange, 
                       onTap: () {
                         SupabaseService.requestLocationAccess(friendId);
                         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Request sent (Simulated: Access Granted)")));
                         // Simulate immediate grant for demo
                         setState(() => _expandedFriendId = null);
                       }
                     ),
                   _buildActionButton(
                     icon: Icons.block, 
                     label: "Block", 
                     color: Colors.red, 
                     onTap: () async {
                       await SupabaseService.blockUser(friendId);
                       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Blocked ${friend['username']}")));
                       setState(() => _expandedFriendId = null);
                     }
                   ),
                ],
              )
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: color, fontSize: 12))
          ],
        ),
      ),
    );
  }
}