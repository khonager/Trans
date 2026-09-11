import 'package:trans/models/station.dart';

/// A friend as the joint planner sees them.
///
/// Planning together never depends on location sharing: a start place can
/// always be typed in. A friend who does share a location simply becomes
/// selectable directly, with their last known position as the start.
class JointPlanFriend {
  /// Prefix for stations that stand for a friend's live position, so the rest
  /// of the search UI can recognise them again.
  static const String stationIdPrefix = 'joint-friend:';

  /// Beyond this the position is old enough to warn about before using it.
  static const Duration freshnessLimit = Duration(minutes: 30);

  final String id;
  final String name;
  final String? avatarEmoji;
  final String? avatarUrl;
  final int? themeColor;
  final double? latitude;
  final double? longitude;
  final DateTime? locationUpdatedAt;
  final int signalLevel;

  const JointPlanFriend({
    required this.id,
    required this.name,
    this.avatarEmoji,
    this.avatarUrl,
    this.themeColor,
    this.latitude,
    this.longitude,
    this.locationUpdatedAt,
    this.signalLevel = 0,
  });

  /// The backend only exposes coordinates a friend agreed to share, so their
  /// presence is the whole condition.
  bool get sharesLocation => latitude != null && longitude != null;

  bool isStale({DateTime? now}) {
    final updatedAt = locationUpdatedAt;
    if (updatedAt == null) return true;
    return (now ?? DateTime.now().toUtc())
            .toUtc()
            .difference(updatedAt.toUtc()) >
        freshnessLimit;
  }

  Duration? locationAge({DateTime? now}) {
    final updatedAt = locationUpdatedAt;
    if (updatedAt == null) return null;
    final age =
        (now ?? DateTime.now().toUtc()).toUtc().difference(updatedAt.toUtc());
    return age.isNegative ? Duration.zero : age;
  }

  bool matches(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return name.toLowerCase().contains(needle);
  }

  /// The friend's last known position as a search result the route planner can
  /// use like any other place.
  Station? toOriginStation() {
    if (!sharesLocation) return null;
    return Station(
      id: '$stationIdPrefix$id',
      name: name,
      type: 'location',
      latitude: latitude,
      longitude: longitude,
    );
  }

  static bool isFriendStation(Station station) =>
      station.id.startsWith(stationIdPrefix);

  static String? friendIdFromStation(Station station) =>
      isFriendStation(station)
          ? station.id.substring(stationIdPrefix.length)
          : null;

  factory JointPlanFriend.fromRow(Map<String, dynamic> row) {
    final latitude = row['latitude'];
    final longitude = row['longitude'];
    final themeColor = row['theme_color'];
    return JointPlanFriend(
      id: row['id']?.toString() ?? '',
      name: row['username']?.toString().trim().isNotEmpty == true
          ? row['username'].toString().trim()
          : '?',
      avatarEmoji: row['avatar_emoji']?.toString(),
      avatarUrl: row['avatar_url']?.toString(),
      themeColor: themeColor is num ? themeColor.toInt() : null,
      latitude: latitude is num ? latitude.toDouble() : null,
      longitude: longitude is num ? longitude.toDouble() : null,
      locationUpdatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? ''),
      signalLevel: row['visible_privacy_level'] is num
          ? (row['visible_privacy_level'] as num).toInt()
          : 0,
    );
  }

  /// Friends who can be picked directly, freshest position first.
  static List<JointPlanFriend> selectableFrom(
    List<Map<String, dynamic>> rows,
  ) {
    final friends = rows
        .map(JointPlanFriend.fromRow)
        .where((friend) => friend.id.isNotEmpty && friend.sharesLocation)
        .toList();
    friends.sort((a, b) {
      final left = a.locationUpdatedAt;
      final right = b.locationUpdatedAt;
      if (left == null && right == null) {
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      if (left == null) return 1;
      if (right == null) return -1;
      return right.compareTo(left);
    });
    return friends;
  }
}
