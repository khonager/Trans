import 'dart:convert';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/station.dart';
import 'supabase_service.dart';

class SearchHistoryManager {
  static const _keyParams = 'recent_stations';
  static const _keyJourneys = 'frequent_journeys';
  static const _keyRecentJourneys = 'recent_journeys';
  static const _keySavedJourneys = 'saved_journeys';

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

  static double _calculateScore(Map<String, dynamic> journey) {
    final int count = journey['count'] ?? 1;
    final int timestamp =
        journey['timestamp'] ?? DateTime.now().millisecondsSinceEpoch;
    final int daysOld = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(timestamp))
        .inDays;
    // Half-life of 21 days: value halves every 3 weeks
    return (count * math.pow(0.5, daysOld / 21.0)).toDouble();
  }

  static Future<void> saveJourney(Station from, Station to) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> journeysStr = prefs.getStringList(_keyJourneys) ?? [];

    List<Map<String, dynamic>> journeys =
        journeysStr.map((e) => json.decode(e) as Map<String, dynamic>).toList();

    final newEntry = {
      'from': from.toJson(),
      'to': to.toJson(),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'count': 1
    };

    // Check if exists
    int index = -1;
    for (int i = 0; i < journeys.length; i++) {
      final existing = journeys[i];
      if (existing['from']['id'] == from.id && existing['to']['id'] == to.id) {
        index = i;
        // Increment count and reset timestamp
        newEntry['count'] = (existing['count'] ?? 1) + 1;
        break;
      }
    }

    if (index != -1) {
      journeys.removeAt(index);
    }

    journeys.add(newEntry);

    // Sort by frecency score descending
    journeys.sort((a, b) => _calculateScore(b).compareTo(_calculateScore(a)));

    if (journeys.length > 30) {
      journeys = journeys.sublist(0, 30); // Keep top 30 in long term cache
    }

    List<String> jsonList = journeys.map((e) => json.encode(e)).toList();
    await prefs.setStringList(_keyJourneys, jsonList);

    // Sync
    _syncJourneysToCloud(jsonList);
  }

  static Future<List<Map<String, dynamic>>> getFrequentJourneys() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyJourneys) ?? [];
    List<Map<String, dynamic>> journeys =
        list.map((e) => json.decode(e) as Map<String, dynamic>).toList();

    // Re-calculate and sort dynamically based on modern current time
    journeys.sort((a, b) => _calculateScore(b).compareTo(_calculateScore(a)));

    if (journeys.length > 5) {
      return journeys.sublist(0, 5); // Return only top 5 relevant to display
    }
    return journeys;
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

  // --- JOURNEYS (Recent Route Searches) ---

  static Map<String, dynamic> _buildJourneyEntry(Station from, Station to) {
    return {
      'from': from.toJson(),
      'to': to.toJson(),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }

  static bool _sameJourney(Map<String, dynamic> a, Station from, Station to) {
    return a['from']?['id'] == from.id && a['to']?['id'] == to.id;
  }

  static Future<void> saveRecentJourney(Station from, Station to) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> journeysStr = prefs.getStringList(_keyRecentJourneys) ?? [];

    List<Map<String, dynamic>> journeys =
        journeysStr.map((e) => json.decode(e) as Map<String, dynamic>).toList();

    journeys.removeWhere((entry) => _sameJourney(entry, from, to));
    journeys.insert(0, _buildJourneyEntry(from, to));

    if (journeys.length > 30) {
      journeys = journeys.sublist(0, 30);
    }

    final jsonList = journeys.map((e) => json.encode(e)).toList();
    await prefs.setStringList(_keyRecentJourneys, jsonList);
    _syncRecentJourneysToCloud(jsonList);
  }

  static Future<List<Map<String, dynamic>>> getRecentJourneys() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyRecentJourneys) ?? [];
    final journeys =
        list.map((e) => json.decode(e) as Map<String, dynamic>).toList();

    if (journeys.length > 5) {
      return journeys.sublist(0, 5);
    }
    return journeys;
  }

  static Future<void> _syncRecentJourneysToCloud(
      List<String> journeysJson) async {
    final list = journeysJson.map((s) => json.decode(s)).toList();
    await SupabaseService.updateRecentJourneys(list);
  }

  // --- JOURNEYS (Saved Routes) ---

  static Future<bool> toggleSavedJourney(Station from, Station to) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> journeysStr = prefs.getStringList(_keySavedJourneys) ?? [];

    List<Map<String, dynamic>> journeys =
        journeysStr.map((e) => json.decode(e) as Map<String, dynamic>).toList();

    final existingIndex =
        journeys.indexWhere((entry) => _sameJourney(entry, from, to));

    bool isSaved;
    if (existingIndex != -1) {
      journeys.removeAt(existingIndex);
      isSaved = false;
    } else {
      journeys.insert(0, _buildJourneyEntry(from, to));
      isSaved = true;
    }

    if (journeys.length > 30) {
      journeys = journeys.sublist(0, 30);
    }

    final jsonList = journeys.map((e) => json.encode(e)).toList();
    await prefs.setStringList(_keySavedJourneys, jsonList);
    _syncSavedJourneysToCloud(jsonList);
    return isSaved;
  }

  static Future<List<Map<String, dynamic>>> getSavedJourneys() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keySavedJourneys) ?? [];
    return list.map((e) => json.decode(e) as Map<String, dynamic>).toList();
  }

  static Future<void> _syncSavedJourneysToCloud(
      List<String> journeysJson) async {
    final list = journeysJson.map((s) => json.decode(s)).toList();
    await SupabaseService.updateSavedJourneys(list);
  }
}
