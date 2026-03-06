// lib/services/favorites_manager.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/favorite.dart';
import 'supabase_service.dart';

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

    // Sync to Supabase
    await _syncToSupabase(current);
  }

  static Future<void> deleteFavorite(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await getFavorites();

    current.removeWhere((f) => f.id == id);

    final encoded = current.map((f) => json.encode(f.toJson())).toList();
    await prefs.setStringList(_key, encoded);

    // Sync to Supabase
    await _syncToSupabase(current);
  }

  static Future<void> _syncToSupabase(List<Favorite> favorites) async {
    try {
      final List<Map<String, dynamic>> favsData =
          favorites.map((f) => f.toJson()).toList();
      await SupabaseService.updateFavoritesInfo(favsData);
    } catch (e) {
      // Fail silently or log
      debugPrint("Error syncing favorites: $e");
    }
  }
}
