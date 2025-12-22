import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/station.dart';

class TransportApi {
  static const String _baseUrl = 'https://v6.db.transport.rest';

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

  static Future<Map<String, dynamic>?> searchJourney(String fromId, String toId) async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/journeys?from=$fromId&to=$toId&results=1'));
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

  static Future<List<Map<String, dynamic>>> getDepartures(String stationId) async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/stops/$stationId/departures?results=5&duration=20'));
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