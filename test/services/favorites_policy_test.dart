import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:trans/models/favorite.dart';
import 'package:trans/services/favorites_policy.dart';
import 'package:trans/utils/favorite_icons.dart';

void main() {
  group('favorites policy', () {
    test('sanitizeFavorites keeps station favorites only', () {
      final favorites = [
        Favorite(id: 'home', label: 'Home', type: 'station'),
        Favorite(
          id: 'friend-alice',
          label: 'Alice',
          type: 'friend',
          friendId: 'alice-id',
        ),
        Favorite(id: 'work', label: 'Work', type: 'station'),
      ];

      final sanitized = sanitizeFavorites(favorites);

      expect(sanitized.map((favorite) => favorite.id), ['home', 'work']);
    });

    test('sanitizeFavoritePayloads drops non-station favorites', () {
      final sanitized = sanitizeFavoritePayloads([
        {
          'id': 'friend-alice',
          'label': 'Alice',
          'type': 'friend',
          'friendId': 'alice-id',
        },
        {
          'id': 'home',
          'label': 'Home',
          'type': 'station',
          'friendId': 'should-be-removed',
        },
      ]);

      expect(sanitized, [
        {
          'id': 'home',
          'label': 'Home',
          'type': 'station',
        },
      ]);
    });

    test('shared favorite icon codes survive JSON number and string formats',
        () {
      final numeric = Favorite.fromJson({
        'id': 'cafe',
        'label': 'Cafe',
        'type': 'station',
        'iconCode': Icons.local_cafe.codePoint,
      });
      final string = Favorite.fromJson({
        'id': 'school',
        'label': 'School',
        'type': 'station',
        'iconCode': Icons.school.codePoint.toString(),
      });

      expect(resolveFavoriteIcon(numeric), Icons.local_cafe);
      expect(resolveFavoriteIcon(string), Icons.school);
    });
  });
}
