import 'package:flutter_test/flutter_test.dart';
import 'package:trans/models/joint_plan_friend.dart';
import 'package:trans/models/station.dart';

Map<String, dynamic> _row({
  required String id,
  String username = 'Alex',
  double? latitude,
  double? longitude,
  String? updatedAt,
  int level = 7,
}) =>
    {
      'id': id,
      'username': username,
      'latitude': latitude,
      'longitude': longitude,
      'updated_at': updatedAt,
      'visible_privacy_level': level,
      'theme_color': 0xFF00FF00,
      'avatar_emoji': '🐝',
    };

void main() {
  final now = DateTime.utc(2026, 8, 30, 12);

  group('selectable friends', () {
    test('keeps only friends whose position is available', () {
      final friends = JointPlanFriend.selectableFrom([
        _row(id: 'a', latitude: 50, longitude: 8),
        _row(id: 'b'),
        _row(id: 'c', latitude: 50, longitude: null),
      ]);

      expect(friends.map((friend) => friend.id), ['a']);
    });

    test('drops rows without an id', () {
      final friends = JointPlanFriend.selectableFrom([
        _row(id: '', latitude: 50, longitude: 8),
      ]);

      expect(friends, isEmpty);
    });

    test('shows the freshest position first', () {
      final friends = JointPlanFriend.selectableFrom([
        _row(
          id: 'old',
          latitude: 50,
          longitude: 8,
          updatedAt: now.subtract(const Duration(hours: 2)).toIso8601String(),
        ),
        _row(
          id: 'fresh',
          latitude: 50,
          longitude: 8,
          updatedAt: now.subtract(const Duration(minutes: 2)).toIso8601String(),
        ),
        _row(id: 'unknown', latitude: 50, longitude: 8),
      ]);

      expect(friends.map((friend) => friend.id), ['fresh', 'old', 'unknown']);
    });
  });

  group('freshness', () {
    test('treats a missing timestamp as stale', () {
      final friend =
          JointPlanFriend.fromRow(_row(id: 'a', latitude: 50, longitude: 8));
      expect(friend.isStale(now: now), isTrue);
      expect(friend.locationAge(now: now), isNull);
    });

    test('is fresh inside the sharing window', () {
      final friend = JointPlanFriend.fromRow(_row(
        id: 'a',
        latitude: 50,
        longitude: 8,
        updatedAt: now.subtract(const Duration(minutes: 12)).toIso8601String(),
      ));

      expect(friend.isStale(now: now), isFalse);
      expect(friend.locationAge(now: now), const Duration(minutes: 12));
    });

    test('is stale once the position outlives the window', () {
      final friend = JointPlanFriend.fromRow(_row(
        id: 'a',
        latitude: 50,
        longitude: 8,
        updatedAt: now.subtract(const Duration(minutes: 31)).toIso8601String(),
      ));

      expect(friend.isStale(now: now), isTrue);
    });
  });

  group('as a search result', () {
    test('round trips the friend id through the station', () {
      final friend = JointPlanFriend.fromRow(
          _row(id: 'friend-7', latitude: 50.1, longitude: 8.7));
      final station = friend.toOriginStation()!;

      expect(station.latitude, 50.1);
      expect(station.longitude, 8.7);
      expect(station.name, 'Alex');
      expect(JointPlanFriend.isFriendStation(station), isTrue);
      expect(JointPlanFriend.friendIdFromStation(station), 'friend-7');
    });

    test('leaves ordinary stations alone', () {
      final station = Station(id: 'stop:123', name: 'Central');
      expect(JointPlanFriend.isFriendStation(station), isFalse);
      expect(JointPlanFriend.friendIdFromStation(station), isNull);
    });

    test('has no station without a shared position', () {
      expect(JointPlanFriend.fromRow(_row(id: 'a')).toOriginStation(), isNull);
    });
  });

  test('matches by name, ignoring case and empty queries', () {
    final friend = JointPlanFriend.fromRow(
        _row(id: 'a', username: 'Mara', latitude: 50, longitude: 8));

    expect(friend.matches('mar'), isTrue);
    expect(friend.matches('  '), isTrue);
    expect(friend.matches('jo'), isFalse);
  });
}
