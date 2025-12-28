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
        'poi': 'true',       
        'addresses': 'true', 
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
        'results': '10',    
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
        'polylines': 'true', // Request actual geometry
      };

      // HANDLING START POINT
      if (from.id.contains(',') || from.type == 'address' || from.type == 'location') {
        params['from.latitude'] = from.latitude.toString();
        params['from.longitude'] = from.longitude.toString();
        // FIX: Send coordinates as string if no address name (prevents 503/500 errors)
        params['from.address'] = (from.type == 'address' && from.name != "Current Location") 
            ? from.name 
            : "${from.latitude},${from.longitude}"; 
      } else {
        params['from'] = from.id;
      }

      // HANDLING DESTINATION
      if (to.id.contains(',') || to.type == 'address' || to.type == 'location') {
        params['to.latitude'] = to.latitude.toString();
        params['to.longitude'] = to.longitude.toString();
        params['to.address'] = (to.type == 'address' && to.name != "Current Location") 
            ? to.name 
            : "${to.latitude},${to.longitude}";
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
          // Add polyline decoding logic here before returning
          List<Map<String, dynamic>> journeys = List<Map<String, dynamic>>.from(data['journeys']);
          
          for (var journey in journeys) {
            for (var leg in journey['legs']) {
              if (leg['polyline'] != null) {
                // Manually decode if backend sends encoded string, 
                // but transport.rest usually sends GeoJSON-like object or google encoded string.
                // Assuming Google Encoded Polyline for simplicity with 'polylines=true' defaults
                // transport.rest v6 usually needs decoding if it returns a string.
                if (leg['polyline'] is Map) {
                   // GeoJSON format sometimes returned
                   // We ignore complex geojson for now, assuming string for google algo
                } else if (leg['polyline'] is String) {
                   leg['decodedPath'] = _decodePolyline(leg['polyline']);
                }
              }
            }
          }
          return journeys;
        }
      } else {
        debugPrint('TransportApi Error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint("Error fetching journeys: $e");
    }
    return [];
  }

  // Google Polyline Algorithm Decoder
  static List<List<double>> _decodePolyline(String encoded) {
    List<List<double>> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add([lat / 1E5, lng / 1E5]);
    }
    return points;
  }
}