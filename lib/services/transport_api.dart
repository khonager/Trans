import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
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

  static Future<http.Response> _fetch(Uri uri) async {
    try {
      debugPrint("Fetching: $uri");
      final response = await http.get(uri);
      if (response.statusCode == 200) return response;
      
      debugPrint("API Error ${response.statusCode}: ${response.body}");
      return response; // Return to let caller handle status
    } catch (e) {
      debugPrint("Network Error: $e");
      // Rethrow so the UI knows it failed (and stops the spinner)
      throw Exception("Network Error: $e");
    }
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
      'tickets': 'false',
    };

    // FROM: Use coordinates for GPS, locations (POIs), and addresses
    if (from.id == 'gps' || from.type == 'location' || from.type == 'address') {
      params['from.latitude'] = from.latitude;
      params['from.longitude'] = from.longitude;
      // Address param seems required by v6 API when using coordinates
      params['from.address'] = from.name;
    } else {
      params['from'] = from.id;
    }

    // TO: Use coordinates for GPS, locations (POIs), and addresses
    if (to.id == 'gps' || to.type == 'location' || to.type == 'address') {
      params['to.latitude'] = to.latitude;
      params['to.longitude'] = to.longitude;
      params['to.address'] = to.name;
    } else {
      params['to'] = to.id;
    }

    // TIME
    if (when != null) {
      params[isArrival ? 'arrival' : 'departure'] = when.toIso8601String();
    }

    // FILTERS
    if (nahverkehrOnly) {
      // Exclude high-speed
      params['nationalExpress'] = 'false';
      params['national'] = 'false';
      // We don't need to strictly enable the others (default is true), 
      // but setting exclusion is critical.
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
      return [];
    }
  }
}