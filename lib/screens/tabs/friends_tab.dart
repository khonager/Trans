import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/supabase_service.dart';

class FriendsTab extends StatelessWidget {
  final Position? currentPosition;

  const FriendsTab({super.key, required this.currentPosition});

  void _showAddFriendSheet(BuildContext context) async {
    final profile = await SupabaseService.getCurrentProfile();
    final myUsername = profile != null ? profile['username'] : 'Unknown';
    final searchCtrl = TextEditingController();
    
    // Using a ValueNotifier for simple state management inside the bottom sheet
    final resultsNotifier = ValueNotifier<List<Map<String, dynamic>>>([]);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          height: 500,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Text("Add Friends", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ListTile(
                tileColor: Theme.of(context).primaryColor.withOpacity(0.1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                title: Text("@$myUsername", style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text("Your Username"),
                trailing: const Icon(Icons.copy),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: "@$myUsername"));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Copied!")));
                },
              ),
              const SizedBox(height: 20),
              TextField(
                controller: searchCtrl,
                decoration: InputDecoration(
                  hintText: "Search username...",
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: () async {
                      resultsNotifier.value = await SupabaseService.searchUsers(searchCtrl.text);
                    },
                  )
                ),
                onSubmitted: (val) async {
                  resultsNotifier.value = await SupabaseService.searchUsers(val);
                },
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ValueListenableBuilder(
                  valueListenable: resultsNotifier,
                  builder: (context, results, _) {
                    return ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (ctx, idx) {
                        final user = results[idx];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: user['avatar_url'] != null ? NetworkImage(user['avatar_url']) : null,
                            child: user['avatar_url'] == null ? Text(user['username'][0]) : null,
                          ),
                          title: Text(user['username']),
                          trailing: IconButton(
                            icon: const Icon(Icons.person_add, color: Colors.green),
                            onPressed: () async {
                              try {
                                await SupabaseService.addFriend(user['id']);
                                Navigator.pop(context);
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e")));
                              }
                            },
                          ),
                        );
                      },
                    );
                  }
                ),
              )
            ],
          ),
        ),
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
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
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
              if (locations.isEmpty) return const Center(child: Text("No active friends."));

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: locations.length,
                itemBuilder: (ctx, idx) {
                  final loc = locations[idx];
                  double dist = 0;
                  if (currentPosition != null) {
                    dist = Geolocator.distanceBetween(
                      currentPosition!.latitude, currentPosition!.longitude, 
                      loc['latitude'], loc['longitude']
                    );
                  }
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: FutureBuilder<String?>(
                        future: SupabaseService.getUsername(loc['user_id']),
                        builder: (_, snap) => Text(snap.data ?? "Unknown"),
                      ),
                      subtitle: Text("${(dist/1000).toStringAsFixed(1)} km away"),
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