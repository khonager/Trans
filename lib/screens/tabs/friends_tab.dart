import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/supabase_service.dart';

class FriendsTab extends StatefulWidget {
  final Position? currentPosition;

  const FriendsTab({super.key, required this.currentPosition});

  @override
  State<FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<FriendsTab> {
  // --- ADD FRIEND SHEET ---
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
                  
                  // SEARCH
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
        
        // 1. PENDING REQUESTS SECTION
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: SupabaseService.streamPendingRequests(),
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();
            
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.indigo.withOpacity(0.3))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Pending Requests", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigoAccent)),
                  const SizedBox(height: 8),
                  ...snapshot.data!.map((req) {
                    // We need to fetch the sender's name. FutureBuilder is easiest here.
                    return FutureBuilder<String?>(
                      future: SupabaseService.getUsername(req['sender_id']),
                      builder: (context, nameSnap) {
                        final name = nameSnap.data ?? "...";
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text("@$name wants to add you", style: TextStyle(color: textColor)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
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
                    );
                  }).toList()
                ],
              ),
            );
          },
        ),

        // 2. ACTIVE FRIENDS LIST
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: SupabaseService.streamFriendsWithLocation(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              
              final friends = snapshot.data!;
              if (friends.isEmpty) {
                 return Center(child: Text("No friends yet. Add some!", style: TextStyle(color: Colors.grey.shade600)));
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: friends.length,
                itemBuilder: (ctx, idx) {
                  final loc = friends[idx];
                  final lastSeen = DateTime.parse(loc['updated_at']);
                  final isActive = DateTime.now().difference(lastSeen).inHours < 12;

                  double dist = 0;
                  if (widget.currentPosition != null) {
                    dist = Geolocator.distanceBetween(widget.currentPosition!.latitude, widget.currentPosition!.longitude, loc['latitude'], loc['longitude']);
                  }

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
                              backgroundImage: loc['avatar_url'] != null ? NetworkImage(loc['avatar_url']) : null,
                              child: loc['avatar_url'] == null ? Text(loc['username'][0].toUpperCase()) : null,
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
                              Text(loc['username'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)), 
                              const SizedBox(height: 2), 
                              Text(isActive ? "${(dist/1000).toStringAsFixed(1)} km away • Active" : "Inactive", style: TextStyle(fontSize: 12, color: isActive ? Colors.green : Colors.grey))
                            ]
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}