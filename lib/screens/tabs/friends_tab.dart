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
              height: 500,
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
                        return ListTile(
                          leading: CircleAvatar(
                             backgroundImage: user['avatar_url'] != null ? NetworkImage(user['avatar_url']) : null,
                             child: user['avatar_url'] == null ? Text(user['username'][0].toUpperCase()) : null
                          ),
                          title: Text(user['username'], style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
                          trailing: IconButton(
                            icon: const Icon(Icons.person_add, color: Colors.green),
                            onPressed: () async {
                              try {
                                await SupabaseService.addFriend(user['id']);
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Added @${user['username']}!")));
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
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
                  double dist = 0;
                  if (widget.currentPosition != null) {
                    dist = Geolocator.distanceBetween(widget.currentPosition!.latitude, widget.currentPosition!.longitude, loc['latitude'], loc['longitude']);
                  }

                  // RESTORED: Styled Container for friends
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
                        FutureBuilder<String?>(
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