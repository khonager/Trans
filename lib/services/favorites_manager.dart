// lib/services/favorites_manager.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/favorite.dart';
import 'favorites_policy.dart';
import 'supabase_service.dart';

class FavoritesManager {
  static const _key = 'saved_favorites';
  static Future<void> _pendingUsageWrite = Future.value();

  static List<Favorite> _sortByUsage(List<Favorite> favorites) {
    favorites.sort((a, b) {
      final usageComparison = b.usageCount.compareTo(a.usageCount);
      if (usageComparison != 0) return usageComparison;
      final labelComparison =
          a.label.toLowerCase().compareTo(b.label.toLowerCase());
      if (labelComparison != 0) return labelComparison;
      return a.id.compareTo(b.id);
    });
    return favorites;
  }

  static List<Favorite> _defaultFavorites() {
    return [
      Favorite(id: 'home', label: 'Home', type: 'station'),
      Favorite(id: 'work', label: 'Work', type: 'station'),
    ];
  }

  static Future<List<Favorite>> getFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key);

    if (list == null || list.isEmpty) {
      return _sortByUsage(_defaultFavorites());
    }

    final favorites =
        list.map((item) => Favorite.fromJson(json.decode(item))).toList();
    final sanitized = sanitizeFavorites(favorites);

    if (sanitized.length != favorites.length) {
      final encoded = sanitized.map((f) => json.encode(f.toJson())).toList();
      await prefs.setStringList(_key, encoded);
      await _syncToSupabase(sanitized);
    }

    if (sanitized.isEmpty) {
      return _sortByUsage(_defaultFavorites());
    }

    return _sortByUsage(sanitized.toList());
  }

  static Future<void> saveFavorite(Favorite favorite) async {
    if (!isSupportedFavorite(favorite)) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final current = (await getFavorites()).toList();

    // Remove existing if id matches (editing/overwriting)
    current.removeWhere((f) => f.id == favorite.id);
    current.add(favorite);

    final encoded = current.map((f) => json.encode(f.toJson())).toList();
    await prefs.setStringList(_key, encoded);

    // Sync to Supabase
    await _syncToSupabase(current);
  }

  static Future<List<Favorite>> recordFavoriteUse(String id) {
    final write = _pendingUsageWrite.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final current = (await getFavorites()).toList();
      final index = current.indexWhere((favorite) => favorite.id == id);
      if (index == -1) return current;

      final favorite = current[index];
      current[index] = Favorite(
        id: favorite.id,
        label: favorite.label,
        type: favorite.type,
        station: favorite.station,
        friendId: favorite.friendId,
        iconCode: favorite.iconCode,
        usageCount: favorite.usageCount + 1,
      );
      await prefs.setStringList(
        _key,
        current.map((item) => json.encode(item.toJson())).toList(),
      );
      await _syncToSupabase(current);
      return _sortByUsage(current);
    });
    _pendingUsageWrite =
        write.then((_) {}, onError: (Object _, StackTrace __) {});
    return write;
  }

  static Future<void> deleteFavorite(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final current = (await getFavorites()).toList();

    current.removeWhere((f) => f.id == id);

    final encoded = current.map((f) => json.encode(f.toJson())).toList();
    await prefs.setStringList(_key, encoded);

    // Sync to Supabase
    await _syncToSupabase(current);
  }

  static Future<void> _syncToSupabase(List<Favorite> favorites) async {
    try {
      final List<Map<String, dynamic>> favsData =
          sanitizeFavoritePayloads(favorites.map((f) => f.toJson()));
      await SupabaseService.updateFavoritesInfo(favsData);
    } catch (e) {
      // Fail silently or log
      debugPrint("Error syncing favorites: $e");
    }
  }
}
