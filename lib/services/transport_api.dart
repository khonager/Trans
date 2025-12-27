import 'dart:convert';
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:http/http.dart' as http;
import '../models/station.dart';

class TransportApi {
  static const String _baseUrl = 'https://v6.db.transport.rest';

  static Future<dynamic> _get(String endpoint, {Map<String, String>? queryParams}) async {
    final uri = Uri.parse('$_baseUrl$endpoint').replace(queryParameters: queryParams);
    Uri finalUri = uri;
    
    if (kIsWeb) {
      final String encodedUrl = Uri.encodeComponent(uri.toString());
      finalUri = Uri.parse('https://corsproxy.io/?$encodedUrl');
    }

    try {
      final response = await http.get(
        finalUri,
        headers: {
          'User-Agent': 'TransApp/1.0 (flutter-web)',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes));
      } else {
        debugPrint("Server returned ${response.statusCode}: ${response.body}");
        return []; 
      }
    } catch (e) {
      debugPrint("API Error on $endpoint: $e");
      return []; 
    }
  }

  // 1. Search Stations
  static Future<List<Station>> searchStations(String query, {double? lat, double? lng}) async {
    if (query.trim().isEmpty) return [];

    final params = {
      'query': query,
      'results': '10', 
      'language': 'en',
    };

    if (lat != null && lng != null) {
      params['latitude'] = lat.toString();
      params['longitude'] = lng.toString();
      params['distance'] = '2000';
    }

    try {
      final data = await _get('/locations', queryParams: params);
      if (data is List) {
        return data
            .where((item) => item['type'] == 'stop' || item['type'] == 'station')
            .map((json) => Station.fromJson(json))
            .toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // 2. Get Nearby Stops (GPS)
  static Future<List<Station>> getNearbyStops(double lat, double lng) async {
    final params = {
      'latitude': lat.toString(),
      'longitude': lng.toString(),
      'distance': '1500', 
      'results': '5',
      'stops': 'true',
      'linesOfStops': 'true',
    };

    try {
      final data = await _get('/stops/nearby', queryParams: params);
      if (data is List) {
        return data.map((json) => Station.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // 3. Search Journey (Routes)
  static Future<Map<String, dynamic>?> searchJourney(String fromId, String toId, {
    bool nahverkehrOnly = false,
    DateTime? when,
    bool isArrival = false,
  }) async {
    final params = {
      'from': fromId,
      'to': toId,
      'results': '3', 
      'language': 'en',
      'transfers': '5',
      'stopovers': 'true', // FIX: Crucial for fetching intermediate stops!
    };

    if (nahverkehrOnly) {
      params['nationalExpress'] = 'false';
      params['national'] = 'false';
    }

    if (when != null) {
      params[isArrival ? 'arrival' : 'departure'] = when.toIso8601String();
    }

    try {
      final data = await _get('/journeys', queryParams: params);
      if (data is Map<String, dynamic> && data.containsKey('journeys')) {
        final List journeys = data['journeys'];
        if (journeys.isNotEmpty) {
          return journeys.first; 
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // 4. Get Departures (Alternatives)
  static Future<List<Map<String, dynamic>>> getDepartures(String stationId, {bool nahverkehrOnly = false}) async {
    final params = {
      'duration': '60', 
      'results': '15',
      'language': 'en',
    };

    if (nahverkehrOnly) {
      params['nationalExpress'] = 'false';
      params['national'] = 'false';
    }

    try {
      final data = await _get('/stops/$stationId/departures', queryParams: params);
      if (data is List) {
        return data.where((d) => d['line'] != null).map((d) => d as Map<String, dynamic>).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }
}