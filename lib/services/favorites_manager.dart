// lib/services/favorites_manager.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/favorite.dart';

class FavoritesManager {
  static const _key = 'saved_favorites';

  static Future<List<Favorite>> getFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key);

    if (list == null || list.isEmpty) {
      // Return defaults if empty
      return [
        Favorite(id: 'home', label: 'Home', type: 'station'),
        Favorite(id: 'work', label: 'Work', type: 'station'),
      ];
    }

    return list.map((item) => Favorite.fromJson(json.decode(item))).toList();
  }

  static Future<void> saveFavorite(Favorite favorite) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await getFavorites();
    
    // Remove existing if id matches (editing/overwriting)
    current.removeWhere((f) => f.id == favorite.id);
    current.add(favorite);

    final encoded = current.map((f) => json.encode(f.toJson())).toList();
    await prefs.setStringList(_key, encoded);
  }

  static Future<void> deleteFavorite(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await getFavorites();
    
    current.removeWhere((f) => f.id == id);
    
    final encoded = current.map((f) => json.encode(f.toJson())).toList();
    await prefs.setStringList(_key, encoded);
  }
}