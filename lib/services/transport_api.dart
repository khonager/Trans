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
        'poi': 'true',       // Allow Points of Interest
        'addresses': 'true', // Allow Addresses
      };
      if (lat != null && lng != null) {
        params['latitude'] = lat.toString();
        params['longitude'] = lng.toString();
      }

      final uri = Uri.parse('$_baseUrl/locations').replace(queryParameters: params);
      final response = await http.get(uri);
      
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        return data.map((json) => Station.fromJson(json)).toList();
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
        'results': '10',    // Fetch more results to filter bad ones
        'distance': '2000', // Standard 2km walking distance
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
    Station from, 
    Station to, 
    {
      bool nahverkehrOnly = false,
      DateTime? when,      
      bool isArrival = false,
      int results = 3 
    }
  ) async {
    try {
      final Map<String, String> params = {
        'results': results.toString(),
        'stopovers': 'true',
      };

      // HANDLING ADDRESSES: If ID contains comma (our coordinate hack) or it's an address, use lat/long
      if (from.id.contains(',') || from.type == 'address') {
        params['from.latitude'] = from.latitude.toString();
        params['from.longitude'] = from.longitude.toString();
        params['from.address'] = from.name;
      } else {
        params['from'] = from.id;
      }

      if (to.id.contains(',') || to.type == 'address') {
        params['to.latitude'] = to.latitude.toString();
        params['to.longitude'] = to.longitude.toString();
        params['to.address'] = to.name;
      } else {
        params['to'] = to.id;
      }

      if (when != null) {
        final iso = when.toIso8601String().split('.').first;
        if (isArrival) {
          params['arrival'] = iso;
        } else {
          params['departure'] = iso;
        }
      }

      if (nahverkehrOnly) {
        params['nationalExpress'] = 'false';
        params['national'] = 'false';
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