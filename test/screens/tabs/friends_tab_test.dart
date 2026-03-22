import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trans/screens/tabs/friends_tab.dart';
import 'package:trans/services/supabase_service.dart';

void main() {
  group('friends tab helpers', () {
    test('isAutoAddedFriend identifies auto-added users', () {
      expect(isAutoAddedFriend({'is_auto_added': true}), isTrue);
      expect(isAutoAddedFriend({'is_auto_added': false}), isFalse);
      expect(isAutoAddedFriend({}), isFalse);
    });

    test('isRecentlyJoinedFriend returns true only within last 7 days', () {
      final now = DateTime.utc(2026, 3, 22, 12);
      final recent = {'created_at': now.subtract(const Duration(days: 6)).toIso8601String()};
      final old = {'created_at': now.subtract(const Duration(days: 8)).toIso8601String()};
      final future = {'created_at': now.add(const Duration(days: 1)).toIso8601String()};

      expect(isRecentlyJoinedFriend(recent, nowUtc: now), isTrue);
      expect(isRecentlyJoinedFriend(old, nowUtc: now), isFalse);
      expect(isRecentlyJoinedFriend(future, nowUtc: now), isFalse);
      expect(isRecentlyJoinedFriend({'created_at': 'invalid'}, nowUtc: now), isFalse);
      expect(isRecentlyJoinedFriend({}, nowUtc: now), isFalse);
    });

    test('newFriendBadgeLabel localizes de and defaults to en', () {
      expect(newFriendBadgeLabel(const Locale('de')), 'Neu');
      expect(newFriendBadgeLabel(const Locale('en')), 'New');
      expect(newFriendBadgeLabel(const Locale('fr')), 'New');
    });

    test('autoAddedSectionLabel localizes de and defaults to en', () {
      expect(autoAddedSectionLabel(const Locale('de')), 'Automatisch hinzugefügt');
      expect(autoAddedSectionLabel(const Locale('en')), 'Auto Added');
      expect(autoAddedSectionLabel(const Locale('fr')), 'Auto Added');
    });

    test('friendAutoAddedMapForUser handles both relation directions', () {
      final map = SupabaseService.friendAutoAddedMapForUser(
        'me',
        friendRelations: const [
          {'user_id': 'me', 'friend_id': 'alice', 'is_auto_added': true},
          {'user_id': 'bob', 'friend_id': 'me', 'is_auto_added': false},
          // Legacy auto-added flag variants should stay supported.
          {'user_id': 'carol', 'friend_id': 'me', 'auto_added': true},
          {'user_id': 'me', 'friend_id': 'dave', 'added_automatically': true},
          {'friend_id': 'legacy-only'},
          {'user_id': 'x', 'friend_id': 'y', 'is_auto_added': true},
        ],
      );

      expect(map['alice'], isTrue);
      expect(map['bob'], isFalse);
      expect(map['carol'], isTrue);
      expect(map['dave'], isTrue);
      expect(map['legacy-only'], isFalse);
      expect(map.containsKey('x'), isFalse);
      expect(map.containsKey('y'), isFalse);
    });
  });
}
