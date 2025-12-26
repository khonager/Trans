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
  // --- SHOW ADD FRIEND SHEET ---
  void _showAddFriendSheet(BuildContext context) async {
    final profile = await SupabaseService.getCurrentProfile();
    final myUsername = profile != null ? profile['username'] : 'Unknown';
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
              height: 600, // Increased height for requests
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade600, borderRadius: BorderRadius.circular(2)), margin: const EdgeInsets.only(bottom: 20)),
                  Text("Add Friends", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
                  const SizedBox(height: 16),
                  
                  // INVITE LINK SECTION
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Theme.of(context).primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Your Username", style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodyLarge?.color?.withOpacity(0.7))),
                              Text("@$myUsername", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, color: Colors.blue),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: "Add me on Trans App! My username is @$myUsername"));
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invite text copied!")));
                          },
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // PENDING REQUESTS SECTION
                  Text("Friend Requests", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
                  const SizedBox(height: 10),
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: SupabaseService.getPendingRequests(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 20.0),
                          child: Text("No pending requests.", style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                        );
                      }
                      return Container(
                        height: 100, // Fixed height for requests list
                        margin: const EdgeInsets.only(bottom: 20),
                        child: ListView.builder(
                          itemCount: snapshot.data!.length,
                          itemBuilder: (ctx, idx) {
                            final reqUser = snapshot.data![idx];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundImage: reqUser['avatar_url'] != null ? NetworkImage(reqUser['avatar_url']) : null,
                                child: reqUser['avatar_url'] == null ? Text(reqUser['username'][0].toUpperCase()) : null,
                              ),
                              title: Text(reqUser['username'], style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.check, color: Colors.green),
                                    onPressed: () async {
                                      await SupabaseService.acceptFriendRequest(reqUser['id']);
                                      if (context.mounted) {
                                        setSheetState(() {}); // Refresh
                                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Accepted ${reqUser['username']}!")));
                                      }
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, color: Colors.red),
                                    onPressed: () async {
                                      await SupabaseService.rejectFriendRequest(reqUser['id']);
                                      if (context.mounted) setSheetState(() {}); // Refresh
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                  
                  // SEARCH SECTION
                  TextField(
                    controller: searchCtrl,
                    style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
                    decoration: InputDecoration(
                      hintText: "Search by username...",
                      hintStyle: TextStyle(color: Colors.grey.shade600),
                      filled: true,
                      fillColor: Theme.of(context).scaffoldBackgroundColor,
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
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
                        // Don't show myself
                        if (user['id'] == SupabaseService.currentUser?.id) return const SizedBox.shrink();
                        
                        return ListTile(
                          leading: CircleAvatar(
                             backgroundImage: user['avatar_url'] != null ? NetworkImage(user['avatar_url']) : null,
                             child: user['avatar_url'] == null ? Text(user['username'][0].toUpperCase()) : null
                          ),
                          title: Text(user['username'], style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
                          trailing: IconButton(
                            icon: const Icon(Icons.person_add_alt_1, color: Colors.blue),
                            onPressed: () async {
                              try {
                                await SupabaseService.sendFriendRequest(user['id']);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Request sent to @${user['username']}!")));
                                  Navigator.pop(context);
                                }
                              } catch (e) {
                                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
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

  void _blockUser(BuildContext context, String userId, String username) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).cardColor,
        title: Text("Block @$username?", style: TextStyle(color: Theme.of(ctx).textTheme.bodyLarge?.color)),
        content: const Text("They will no longer see your location or profile. This action can be undone in Settings."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await SupabaseService.blockUser(userId);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Blocked @$username")));
            },
            child: const Text("Block", style: TextStyle(color: Colors.red)),
          ),
        ],
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
              Text("Friends Live", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor)),
              if (SupabaseService.currentUser != null)
                IconButton(
                  icon: const Icon(Icons.person_add, color: Colors.blue),
                  onPressed: () => _showAddFriendSheet(context),
                )
            ],
          ),
        ),
        
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: SupabaseService.streamUsersLocations(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              
              final locations = snapshot.data!;
              if (locations.isEmpty) {
                 return Center(child: Text("No friends active.", style: TextStyle(color: Colors.grey.shade600)));
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: locations.length,
                itemBuilder: (ctx, idx) {
                  final loc = locations[idx];
                  final userId = loc['user_id'];
                  // Don't show myself
                  if (userId == SupabaseService.currentUser?.id) return const SizedBox.shrink();

                  double dist = 0;
                  if (widget.currentPosition != null) {
                    dist = Geolocator.distanceBetween(widget.currentPosition!.latitude, widget.currentPosition!.longitude, loc['latitude'], loc['longitude']);
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10)
                    ),
                    child: Row(
                      children: [
                        Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.blue.withOpacity(0.2), shape: BoxShape.circle), child: const Center(child: Icon(Icons.person, color: Colors.blue))),
                        const SizedBox(width: 16),
                        Expanded(
                          child: FutureBuilder<String?>(
                            future: SupabaseService.getUsername(userId),
                            builder: (context, snap) {
                              final name = snap.data ?? "User ${userId.toString().substring(0,4)}";
                              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)), 
                                const SizedBox(height: 2), 
                                Text("${(dist/1000).toStringAsFixed(1)} km away", style: const TextStyle(fontSize: 12, color: Colors.grey))
                              ]);
                            }
                          ),
                        ),
                        // More Options (Block)
                        PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert, color: textColor),
                          color: Theme.of(context).cardColor,
                          onSelected: (val) async {
                             if (val == 'block') {
                               final name = await SupabaseService.getUsername(userId) ?? "User";
                               if (mounted) _blockUser(context, userId, name);
                             }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'block',
                              child: Row(children: [Icon(Icons.block, color: Colors.red, size: 18), SizedBox(width: 8), Text("Block", style: TextStyle(color: Colors.red))]),
                            )
                          ],
                        )
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