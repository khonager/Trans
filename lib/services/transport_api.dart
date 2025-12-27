import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:trans/models/station.dart';

class TransportApi {
  static const String _baseUrl = 'https://v6.db.transport.rest';

  static Future<List<Station>> searchStations(String query, {double? lat, double? lng}) async {
    if (query.length < 2) return [];
    try {
      final Map<String, String> params = {
        'query': query,
        'results': '10',
        'poi': 'false',      
        'addresses': 'false' 
      };
      if (lat != null && lng != null) {
        params['latitude'] = lat.toString();
        params['longitude'] = lng.toString();
      }

      final uri = Uri.parse('$_baseUrl/locations').replace(queryParameters: params);
      final response = await http.get(uri);
      
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
      final uri = Uri.parse('$_baseUrl/stops/nearby').replace(queryParameters: {
        'latitude': lat.toString(),
        'longitude': lng.toString(),
        'results': '5',
        'distance': '2000',
      });
      
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        return data.map((json) => Station.fromJson(json)).toList();
      }
    } catch (e) {
      debugPrint("Error fetching nearby: $e");
    }
    return [];
  }

  static Future<List<Map<String, dynamic>>> searchJourneys(
    String fromId, 
    String toId, 
    {
      bool nahverkehrOnly = false,
      DateTime? when,      
      bool isArrival = false,
      int results = 3 
    }
  ) async {
    try {
      final Map<String, String> params = {
        'from': fromId,
        'to': toId,
        'results': results.toString(),
        'stopovers': 'true',
      };

      if (when != null) {
        final iso = when.toIso8601String().split('.').first;
        if (isArrival) {
          params['arrival'] = iso;
        } else {
          params['departure'] = iso;
        }
      }

      // Exact match to your working request:
      // nationalExpress=false&national=false
      if (nahverkehrOnly) {
        params['nationalExpress'] = 'false';
        params['national'] = 'false';
        // params['regional'] = 'true'; // Optional, but usually implied by removing others
      }

      final uri = Uri.parse('$_baseUrl/journeys').replace(queryParameters: params);
      debugPrint('TransportApi Calling: $uri');

      final response = await http.get(uri);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['journeys'] != null) {
          return List<Map<String, dynamic>>.from(data['journeys']);
        }
      } else {
        debugPrint('TransportApi Error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint("Error fetching journeys: $e");
    }
    return [];
  }
}