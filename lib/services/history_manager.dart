import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/station.dart';

class SearchHistoryManager {
  static const _key = 'recent_stations';

  static Future<void> saveStation(Station station) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList(_key) ?? [];

    String jsonStr = json.encode(station.toJson());

    // Remove duplicate IDs
    history.removeWhere((item) {
      final existing = json.decode(item);
      return existing['id'] == station.id;
    });

    // Insert at top, keep max 10
    history.insert(0, jsonStr);
    if (history.length > 10) history = history.sublist(0, 10);

    await prefs.setStringList(_key, history);
  }

  static Future<List<Station>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    return list.map((item) => Station.fromJson(json.decode(item))).toList();
  }

  // NEW: Clear history
  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}