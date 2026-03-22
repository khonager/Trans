import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/supabase_service.dart';
import '../../config/app_theme.dart';
import '../../widgets/private_chat_sheet.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/app_error.dart';

bool isAutoAddedFriend(Map<String, dynamic> friend) =>
    friend['is_auto_added'] == true;

bool isRecentlyJoinedFriend(Map<String, dynamic> friend, {DateTime? nowUtc}) {
  final createdAt = DateTime.tryParse(friend['created_at']?.toString() ?? '');
  if (createdAt == null) return false;
  final now = nowUtc ?? DateTime.now().toUtc();
  final createdUtc = createdAt.toUtc();
  if (createdUtc.isAfter(now)) return false;
  return now.difference(createdUtc).inDays < 7;
}

String newFriendBadgeLabel(Locale locale) =>
    locale.languageCode == 'de' ? 'Neu' : 'New';

String autoAddedSectionLabel(Locale locale) =>
    locale.languageCode == 'de' ? 'Automatisch hinzugefügt' : 'Auto Added';

int _usernameComparator(Map<String, dynamic> a, Map<String, dynamic> b) =>
    (a['username'] as String).compareTo(b['username'] as String);

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
    SupabaseService.friendsListRefresh.addListener(_initData);
  }

  @override
  void dispose() {
    _friendsSub?.cancel();
    _requestsSub?.cancel();
    SupabaseService.friendsListRefresh.removeListener(_initData);
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

    _friendsSub?.cancel();
    _friendsSub = SupabaseService.streamFriends().listen((data) {
      if (mounted) setState(() => _friends = data);
    });

    _requestsSub?.cancel();
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
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (context, setSheetState) {
        return Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            height: 500,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: colors.modalHandle,
                        borderRadius: BorderRadius.circular(2)),
                    margin: const EdgeInsets.only(bottom: 20)),
                Text(AppLocalizations.of(context)!.addNewFriend,
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary)),
                const SizedBox(height: 16),
                TextField(
                  controller: searchCtrl,
                  decoration: InputDecoration(
                      hintText: AppLocalizations.of(context)!.searchByUsername,
                      filled: true,
                      fillColor: colors.scaffoldBg,
                      prefixIcon:
                          Icon(Icons.search, color: colors.textSecondary),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none),
                      suffixIcon: IconButton(
                        icon:
                            const Icon(Icons.arrow_forward, color: Colors.blue),
                        onPressed: () async {
                          final res = await SupabaseService.searchUsers(
                              searchCtrl.text);
                          setSheetState(() => searchResults = res);
                        },
                      )),
                  onSubmitted: (val) async {
                    final res = await SupabaseService.searchUsers(val);
                    setSheetState(() => searchResults = res);
                  },
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.separated(
                    itemCount: searchResults.length,
                    separatorBuilder: (_, __) => Divider(color: colors.divider),
                    itemBuilder: (ctx, idx) {
                      final user = searchResults[idx];
                      if (user['id'] == SupabaseService.currentUser?.id) {
                        return const SizedBox.shrink();
                      }

                      return ListTile(
                        leading: _buildAvatarHelper(user),
                        title: Text(user['username'],
                            style: TextStyle(color: colors.textPrimary)),
                        trailing: IconButton(
                          icon:
                              const Icon(Icons.person_add, color: Colors.blue),
                          onPressed: () async {
                            try {
                              await SupabaseService.sendFriendRequest(
                                  user['id']);
                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(AppLocalizations.of(
                                                context)!
                                            .requestSentTo(user['username']))));
                              }
                            } catch (e, st) {
                              if (context.mounted) {
                                AppError.showSnackBar(
                                  context,
                                  error: e,
                                  stackTrace: st,
                                  source: 'send friend request',
                                );
                              }
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
      }),
    );
  }

  void _openPrivateChat(String friendId, String username) {
    showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) =>
            PrivateChatSheet(friendId: friendId, friendName: username));
  }

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    final topPadding = MediaQuery.of(context).padding.top + 10;

    final now = DateTime.now().toUtc();
    final activeFriends = <Map<String, dynamic>>[];
    final inactiveFriends = <Map<String, dynamic>>[];
    final autoAddedFriends = <Map<String, dynamic>>[];

    for (var f in _friends) {
      if (isAutoAddedFriend(f)) {
        autoAddedFriends.add(f);
        continue;
      }
      if (f['updated_at'] != null) {
        final updated = DateTime.tryParse(f['updated_at'])?.toUtc() ??
            DateTime(2000).toUtc();
        final isActive = now.difference(updated).inHours < 12;
        if (isActive) {
          activeFriends.add(f);
          continue;
        }
      }
      inactiveFriends.add(f);
    }

    activeFriends.sort(_usernameComparator);
    _requests.sort((a, b) =>
        (b['created_at'] as String).compareTo(a['created_at'] as String));
    inactiveFriends.sort(_usernameComparator);
    autoAddedFriends.sort(_usernameComparator);

    return Column(
      children: [
        // FIX: Dynamic Top Padding
        SizedBox(height: topPadding),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(AppLocalizations.of(context)!.friendsTitle,
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary)),
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
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                      16, 0, 16, 120), // ADDED BOTTOM PADDING FOR TICKET PANEL
                  children: [
                    if (activeFriends.isNotEmpty) ...[
                      _buildSectionHeader(
                          AppLocalizations.of(context)!.activeNow, colors),
                      ...activeFriends
                          .map((f) => _buildFriendCard(context, f, true)),
                    ],
                    if (_requests.isNotEmpty) ...[
                      _buildSectionHeader(
                          AppLocalizations.of(context)!.requests, colors),
                      ..._requests.map((r) => _buildRequestCard(context, r)),
                    ],
                    if (inactiveFriends.isNotEmpty) ...[
                      _buildSectionHeader(
                          AppLocalizations.of(context)!.offline, colors),
                      ...inactiveFriends
                          .map((f) => _buildFriendCard(context, f, false)),
                    ],
                    if (autoAddedFriends.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Divider(color: colors.divider),
                      _buildSectionHeader(
                          autoAddedSectionLabel(Localizations.localeOf(context)),
                          colors),
                      ...autoAddedFriends
                          .map((f) => _buildFriendCard(context, f, false)),
                    ],
                    if (activeFriends.isEmpty &&
                        _requests.isEmpty &&
                        inactiveFriends.isEmpty &&
                        autoAddedFriends.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 50),
                        child: Center(
                            child: Text(
                                AppLocalizations.of(context)!.noFriendsYet,
                                style: TextStyle(color: colors.textSecondary))),
                      )
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, TransColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
            color: colors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0),
      ),
    );
  }

  Widget _buildAvatarHelper(Map<String, dynamic> userData,
      {double radius = 20}) {
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
      child: url == null
          ? Text(username.isNotEmpty ? username[0].toUpperCase() : "?",
              style: const TextStyle(color: Colors.white))
          : null,
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
          border: Border.all(
              color: Colors.blue.withValues(alpha: 0.5), width: 1.5)),
      child: Row(
        children: [
          _buildAvatarHelper(req),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    req['sender_username'] ??
                        AppLocalizations.of(context)!.unknown,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary)),
                Text(AppLocalizations.of(context)!.sentFriendRequest,
                    style:
                        TextStyle(fontSize: 12, color: colors.textSecondary)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.check_circle, color: colors.actionIconSuccess),
            onPressed: () async {
              try {
                await SupabaseService.acceptFriendRequest(req['sender_id']);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(AppLocalizations.of(context)!
                          .friendRequestAccepted)));
                  setState(() {
                    _requests.removeWhere((r) => r['id'] == req['id']);
                  });
                }
              } catch (e, st) {
                if (context.mounted) {
                  AppError.showSnackBar(
                    context,
                    error: e,
                    stackTrace: st,
                    source: 'accept friend request',
                  );
                }
              }
            },
          ),
          IconButton(
            icon: Icon(Icons.cancel, color: colors.actionIconError),
            onPressed: () async {
              try {
                await SupabaseService.rejectFriendRequest(req['sender_id']);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                          AppLocalizations.of(context)!.friendRequestDenied)));
                  setState(() {
                    _requests.removeWhere((r) => r['id'] == req['id']);
                  });
                }
              } catch (e, st) {
                if (context.mounted) {
                  AppError.showSnackBar(
                    context,
                    error: e,
                    stackTrace: st,
                    source: 'reject friend request',
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFriendCard(
      BuildContext context, Map<String, dynamic> friend, bool isActive) {
    final colors = TransColors.of(context);
    final locale = Localizations.localeOf(context);
    final isNewUser = isRecentlyJoinedFriend(friend);
    final String? currentLine = friend['current_line'];
    final String friendId = friend['id'];
    final bool isExpanded = _expandedFriendId == friendId;
    final bool isGhost = friend['ghost_mode'] ?? false;

    String statusText = AppLocalizations.of(context)!.inactive;
    Color statusColor = colors.statusOffline;
    Widget? statusIcon;

    if (isActive) {
      statusText = AppLocalizations.of(context)!.activeRecently;
      statusColor = colors.statusActive;

      if (currentLine != null && currentLine.isNotEmpty) {
        final lastUpdate = DateTime.tryParse(friend['updated_at'])?.toUtc() ??
            DateTime(2000).toUtc();
        final diff = DateTime.now().toUtc().difference(lastUpdate);

        if (diff.inMinutes < 10) {
          statusText = AppLocalizations.of(context)!.onLine(currentLine);
          statusColor = colors.statusOnline;
          statusIcon =
              Icon(Icons.directions_bus, size: 12, color: colors.statusOnline);
        } else {
          statusText = AppLocalizations.of(context)!.lastOnLine(currentLine);
          statusColor = colors.textSecondary;
          statusIcon =
              Icon(Icons.history, size: 12, color: colors.textSecondary);
        }
      }
    }

    if (isGhost) {
      if (isActive && currentLine == null) {
        statusText = AppLocalizations.of(context)!.activeRecentlyGhost;
        statusColor = colors.textSecondary;
      }
    }

    return GestureDetector(
      onTap: () =>
          setState(() => _expandedFriendId = isExpanded ? null : friendId),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: isActive
                ? colors.friendCardActiveBg
                : colors.friendCardInactiveBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: isActive
                    ? colors.friendCardActiveBorder
                    : colors.friendCardInactiveBorder)),
        child: Column(
          children: [
            Row(
              children: [
                Stack(
                  children: [
                    _buildAvatarHelper(friend),
                    if (isActive)
                      Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                  color: colors.statusActive,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: colors.cardBg, width: 2))))
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            friend['username'] ??
                                AppLocalizations.of(context)!.unknown,
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: colors.textPrimary)),
                        if (isNewUser) ...[
                          const SizedBox(height: 4),
                          Text(
                            newFriendBadgeLabel(locale),
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.green),
                          ),
                        ],
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (statusIcon != null) ...[
                              statusIcon,
                              const SizedBox(width: 4)
                            ],
                            Text(statusText,
                                style: TextStyle(
                                    fontSize: 12, color: statusColor)),
                          ],
                        )
                      ]),
                ),
                Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: colors.textSecondary),
              ],
            ),
            if (isExpanded) ...[
              const SizedBox(height: 16),
              Divider(color: colors.divider),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildActionButton(
                      icon: Icons.chat_bubble_outline,
                      label: AppLocalizations.of(context)!.chat,
                      color: Colors.blue,
                      onTap: () => _openPrivateChat(
                          friend['id'],
                          friend['username'] ??
                              AppLocalizations.of(context)!.unknown)),
                  _buildActionButton(
                      icon: Icons.person_remove,
                      label: AppLocalizations.of(context)!.remove,
                      color: Colors.orange,
                      onTap: () async {
                        final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                                  title: Text(AppLocalizations.of(context)!
                                      .removeFriendTitle(friend['username'])),
                                  content: Text(AppLocalizations.of(context)!
                                      .removeFriendMessage),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: Text(
                                            AppLocalizations.of(context)!
                                                .cancel)),
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: Text(
                                            AppLocalizations.of(context)!
                                                .remove,
                                            style: const TextStyle(
                                                color: Colors.red))),
                                  ],
                                ));

                        if (confirm == true) {
                          await SupabaseService.removeFriend(friendId);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(AppLocalizations.of(context)!
                                    .removedFriend(friend['username']))));
                            setState(() => _expandedFriendId = null);
                          }
                        }
                      }),
                  _buildActionButton(
                      icon: Icons.block,
                      label: AppLocalizations.of(context)!.block,
                      color: Colors.red,
                      onTap: () async {
                        await SupabaseService.blockUser(friendId);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(AppLocalizations.of(context)!
                                  .blockedFriend(friend['username']))));
                          setState(() => _expandedFriendId = null);
                        }
                      }),
                ],
              )
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(
      {required IconData icon,
      required String label,
      required Color color,
      required VoidCallback onTap}) {
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
