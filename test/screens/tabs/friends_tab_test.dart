import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trans/screens/tabs/friends_tab.dart';

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
  });
}
