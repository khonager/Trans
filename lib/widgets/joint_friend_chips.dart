import 'package:flutter/material.dart';
import 'package:trans/config/app_theme.dart';
import 'package:trans/models/joint_plan_friend.dart';

/// One-tap picks for friends who currently share a location, shown above the
/// free-text field so both ways of naming a starting point sit together.
class JointFriendChips extends StatelessWidget {
  final List<JointPlanFriend> friends;
  final String? selectedFriendId;
  final ValueChanged<JointPlanFriend> onSelected;
  final bool german;
  final DateTime? now;

  const JointFriendChips({
    super.key,
    required this.friends,
    required this.selectedFriendId,
    required this.onSelected,
    required this.german,
    this.now,
  });

  static String freshnessLabel(
    JointPlanFriend friend, {
    required bool german,
    DateTime? now,
  }) {
    final age = friend.locationAge(now: now);
    if (age == null) return german ? 'Standort' : 'Location';
    if (age.inMinutes < 1) return german ? 'gerade eben' : 'just now';
    if (age.inMinutes < 60) {
      return german ? 'vor ${age.inMinutes} Min.' : '${age.inMinutes} min ago';
    }
    if (age.inHours < 24) {
      return german ? 'vor ${age.inHours} Std.' : '${age.inHours} h ago';
    }
    return german ? 'vor ${age.inDays} T.' : '${age.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) {
    if (friends.isEmpty) return const SizedBox.shrink();
    final colors = TransColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          german ? 'TEILT STANDORT' : 'SHARING A LOCATION',
          style: TextStyle(
            fontSize: 10,
            color: colors.textSecondary,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          // Roomy enough for the two text lines at larger font scales.
          height: 52,
          child: ListView.separated(
            key: const ValueKey('joint-friend-chips'),
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: friends.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final friend = friends[index];
              final isSelected = friend.id == selectedFriendId;
              final stale = friend.isStale(now: now);
              return GestureDetector(
                key: ValueKey('joint-friend-chip-${friend.id}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelected(friend),
                child: Semantics(
                  button: true,
                  selected: isSelected,
                  label: friend.name,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? colors.effectiveSeed.withValues(alpha: 0.18)
                          : colors.chipBg,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: isSelected
                            ? colors.effectiveSeed
                            : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _FriendAvatar(friend: friend, radius: 16),
                        const SizedBox(width: 8),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              friend.name,
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 12.5,
                                height: 1.1,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              freshnessLabel(friend, german: german, now: now),
                              style: TextStyle(
                                color: stale
                                    ? Colors.orange
                                    : colors.textSecondary,
                                height: 1.1,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FriendAvatar extends StatelessWidget {
  final JointPlanFriend friend;
  final double radius;

  const _FriendAvatar({required this.friend, required this.radius});

  @override
  Widget build(BuildContext context) {
    final background =
        friend.themeColor != null ? Color(friend.themeColor!) : Colors.indigo;
    final emoji = friend.avatarEmoji;
    if (emoji != null && emoji.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: background,
        child: Text(emoji, style: TextStyle(fontSize: radius * 1.1)),
      );
    }
    final url = friend.avatarUrl;
    return CircleAvatar(
      radius: radius,
      backgroundColor: background,
      backgroundImage: url != null && url.isNotEmpty ? NetworkImage(url) : null,
      child: url == null || url.isEmpty
          ? Text(
              friend.name.isNotEmpty ? friend.name[0].toUpperCase() : '?',
              style: TextStyle(color: Colors.white, fontSize: radius * 0.9),
            )
          : null,
    );
  }
}
