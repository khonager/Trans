import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/station.dart';
import 'supabase_service.dart';

class SearchHistoryManager {
  static const _keyParams = 'recent_stations';
  static const _keyJourneys = 'frequent_journeys';

  // --- STATIONS (Previous Searches) ---

  static Future<void> saveStation(Station station) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList(_keyParams) ?? [];

    String jsonStr = json.encode(station.toJson());

    // Remove duplicate IDs
    history.removeWhere((item) {
      final existing = json.decode(item);
      return existing['id'] == station.id;
    });

    // Insert at top, keep max 10
    history.insert(0, jsonStr);
    if (history.length > 10) history = history.sublist(0, 10);

    await prefs.setStringList(_keyParams, history);
    
    // Sync to Cloud
    _syncStationsToCloud(history);
  }

  static Future<List<Station>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyParams) ?? [];
    return list.map((item) => Station.fromJson(json.decode(item))).toList();
  }

  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyParams);
    _syncStationsToCloud([]);
  }
  
  static Future<void> _syncStationsToCloud(List<String> historyJson) async {
    // Convert back to List<Map> for Supabase JSONB
    final list = historyJson.map((s) => json.decode(s)).toList();
    await SupabaseService.updatePreviousSearches(list);
  }
  
  // --- JOURNEYS (Frequent Routes) ---

  static Future<void> saveJourney(Station from, Station to) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> journeys = prefs.getStringList(_keyJourneys) ?? [];
    
    final newEntry = {
      'from': from.toJson(),
      'to': to.toJson(),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'count': 1
    };

    // Check if exists
    int index = -1;
    for (int i = 0; i < journeys.length; i++) {
        final existing = json.decode(journeys[i]);
        if (existing['from']['id'] == from.id && existing['to']['id'] == to.id) {
            index = i;
            // Increment count
            newEntry['count'] = (existing['count'] ?? 1) + 1;
            break;
        }
    }

    if (index != -1) {
      journeys.removeAt(index);
    }
    
    journeys.insert(0, json.encode(newEntry));
    if (journeys.length > 10) journeys = journeys.sublist(0, 10); // Keep top 10

    await prefs.setStringList(_keyJourneys, journeys);
    
    // Sync
    _syncJourneysToCloud(journeys);
  }

  static Future<List<Map<String, dynamic>>> getFrequentJourneys() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyJourneys) ?? [];
    return list.map((e) => json.decode(e) as Map<String, dynamic>).toList();
  }
  
  static Future<void> clearJourneys() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyJourneys);
    _syncJourneysToCloud([]);
  }

  static Future<void> _syncJourneysToCloud(List<String> journeysJson) async {
    final list = journeysJson.map((s) => json.decode(s)).toList();
    await SupabaseService.updateFrequentJourneys(list);
  }
}