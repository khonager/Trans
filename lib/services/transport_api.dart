import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/station.dart';

class TransportApi {
  static const String _baseUrl = 'https://v6.db.transport.rest';

  // HELPER: Appends filters to exclude high-speed trains if Nahverkehr is requested
  static String _addFilters(String url, bool useNahverkehrOnly) {
    if (useNahverkehrOnly) {
      return '$url&nationalExpress=false&national=false';
    }
    return url;
  }

  static Future<List<Station>> searchStations(String query, {double? lat, double? lng}) async {
    if (query.length < 2) return [];
    try {
      String url = '$_baseUrl/locations?query=${Uri.encodeComponent(query)}&results=10';
      if (lat != null && lng != null) {
        url += '&latitude=$lat&longitude=$lng';
      }
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        return data
            .where((d) => d['type'] == 'station' || d['type'] == 'stop')
            .map((json) => Station.fromJson(json))
            .toList();
      }
    } catch (e) {
      debugPrint("Error fetching stations: $e");
    }
    return [];
  }

  static Future<List<Station>> getNearbyStops(double lat, double lng) async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/stops/nearby?latitude=$lat&longitude=$lng&results=5'));
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        return data.map((json) => Station.fromJson(json)).toList();
      }
    } catch (e) {
      debugPrint("Error fetching nearby: $e");
    }
    return [];
  }

  // UPDATED: Added &stopovers=true to URL
  static Future<Map<String, dynamic>?> searchJourney(
    String fromId, 
    String toId, 
    {
      bool nahverkehrOnly = false,
      DateTime? when,      
      bool isArrival = false 
    }
  ) async {
    try {
      // NEW: stopovers=true ensures we get the list of stops for Issue 5
      String url = '$_baseUrl/journeys?from=$fromId&to=$toId&results=3&stopovers=true';
      
      if (when != null) {
        final iso = when.toIso8601String();
        if (isArrival) {
          url += '&arrival=$iso';
        } else {
          url += '&departure=$iso';
        }
      }

      url = _addFilters(url, nahverkehrOnly);
      
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['journeys'] != null && (data['journeys'] as List).isNotEmpty) {
          return data['journeys'][0];
        }
      }
    } catch (e) {
      debugPrint("Error fetching journey: $e");
    }
    return null;
  }

  static Future<List<Map<String, dynamic>>> getDepartures(String stationId, {bool nahverkehrOnly = false}) async {
    try {
      String url = '$_baseUrl/stops/$stationId/departures?results=10&duration=60';
      url = _addFilters(url, nahverkehrOnly);

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['departures'] != null) {
          return List<Map<String, dynamic>>.from(data['departures']);
        }
      }
    } catch (e) {
      debugPrint("Error fetching departures: $e");
    }
    return [];
  }
}