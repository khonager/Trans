import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trans/models/favorite.dart';
import 'package:trans/services/favorites_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('favorites sort by usage and older records start at zero', () async {
    SharedPreferences.setMockInitialValues({
      'saved_favorites': [
        json.encode({'id': 'z', 'label': 'Zebra', 'type': 'station'}),
        json.encode({'id': 'b', 'label': 'Beta', 'type': 'station', 'usageCount': 3}),
        json.encode({'id': 'a', 'label': 'Alpha', 'type': 'station', 'usageCount': 3}),
      ],
    });

    final favorites = await FavoritesManager.getFavorites();

    expect(favorites.map((favorite) => favorite.id), ['a', 'b', 'z']);
    expect(favorites.last.usageCount, 0);
  });

  test('rapid uses are all counted and persisted', () async {
    SharedPreferences.setMockInitialValues({
      'saved_favorites': [
        json.encode(Favorite(id: 'a', label: 'Alpha', type: 'station').toJson()),
        json.encode(Favorite(id: 'b', label: 'Beta', type: 'station').toJson()),
      ],
    });

    await Future.wait([
      FavoritesManager.recordFavoriteUse('b'),
      FavoritesManager.recordFavoriteUse('b'),
      FavoritesManager.recordFavoriteUse('b'),
    ]);

    final favorites = await FavoritesManager.getFavorites();
    expect(favorites.first.id, 'b');
    expect(favorites.first.usageCount, 3);
  });
}
