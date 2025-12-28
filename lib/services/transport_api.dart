import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart'; // For kIsWeb
import '../models/station.dart';

class TransportApi {
  static const String baseUrl = 'https://v6.db.transport.rest';

  static Uri _getUri(String endpoint, [Map<String, dynamic>? params]) {
    String url = "$baseUrl$endpoint";
    if (params != null) {
      url += "?";
      params.forEach((key, value) {
        if (value != null) url += "$key=${Uri.encodeComponent(value.toString())}&";
      });
    }
    return Uri.parse(url);
  }

  // Helper to handle Web CORS if direct call fails
  static Future<http.Response> _fetch(Uri uri) async {
    try {
      // 1. Try Direct
      final response = await http.get(uri);
      if (response.statusCode == 200) return response;
    } catch (e) {
      // Direct failed (likely CORS on Web)
    }

    if (kIsWeb) {
      try {
        // 2. Fallback: allorigins (reliable JSON proxy)
        final proxyUrl = "https://api.allorigins.win/raw?url=${Uri.encodeComponent(uri.toString())}";
        return await http.get(Uri.parse(proxyUrl));
      } catch (e) {
        debugPrint("Proxy failed: $e");
      }
    }
    
    // Return empty 400 if all fails
    return http.Response('{}', 400); 
  }

  static Future<List<Station>> searchStations(String query, {double? lat, double? lng}) async {
    if (query.isEmpty) return [];
    
    final Map<String, dynamic> params = {
      'query': query,
      'results': 10,
      'poi': 'true',
      'addresses': 'true',
    };
    
    if (lat != null && lng != null) {
      params['latitude'] = lat;
      params['longitude'] = lng;
      params['distance'] = 2000;
    }

    try {
      final response = await _fetch(_getUri('/locations', params));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Station.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      debugPrint("API Exception: $e");
      return [];
    }
  }

  static Future<List<Station>> getNearbyStops(double lat, double lng) async {
    try {
      final response = await _fetch(_getUri('/stops/nearby', {
        'latitude': lat, 
        'longitude': lng, 
        'results': 5, 
        'distance': 1000
      }));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Station.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> searchJourneys(
    Station from, 
    Station to, 
    {bool nahverkehrOnly = false, DateTime? when, bool isArrival = false, int results = 3}
  ) async {
    
    final Map<String, dynamic> params = {
      'results': results,
      'stopovers': 'true',
      'polylines': 'true',
    };

    if (from.id == 'gps' || from.type == 'location') {
      params['from.latitude'] = from.latitude;
      params['from.longitude'] = from.longitude;
      params['from.address'] = "${from.latitude},${from.longitude}";
    } else {
      params['from'] = from.id;
    }

    if (to.id == 'gps' || to.type == 'location') {
      params['to.latitude'] = to.latitude;
      params['to.longitude'] = to.longitude;
    } else {
      params['to'] = to.id;
    }

    if (when != null) {
      params[isArrival ? 'arrival' : 'departure'] = when.toIso8601String();
    }

    if (nahverkehrOnly) {
      params['loyaltyCard'] = 'none';
      params['class'] = 2;
      params['nationalExpress'] = false;
      params['national'] = false;
    }

    try {
      final uri = _getUri('/journeys', params);
      final response = await _fetch(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['journeys'] != null) {
          return List<Map<String, dynamic>>.from(data['journeys']);
        }
      }
      return [];
    } catch (e) {
      debugPrint("Journey Exception: $e");
      return [];
    }
  }
}