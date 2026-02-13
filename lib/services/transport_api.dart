import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';
import '../models/station.dart';
import 'motis_adapters.dart';

/// Simple cache entry with TTL
class _CacheEntry<T> {
  final T data;
  final DateTime expiry;

  _CacheEntry(this.data, Duration ttl) : expiry = DateTime.now().add(ttl);

  bool get isExpired => DateTime.now().isAfter(expiry);
}

class TransportApi {
  // API endpoints
  static const String _motisUrl = 'https://api.transitous.org';
  static const String _v6Url = 'https://v6.db.transport.rest';

  /// API Mode: 'auto', 'motis', or 'v6'
  static String apiMode = 'auto';

  // In-memory caches with TTL
  static final Map<String, _CacheEntry<List<Station>>> _stationCache = {};
  static final Map<String, _CacheEntry<List<Station>>> _nearbyCache = {};

  // Cache the User-Agent
  static String? _userAgent;

  // ============================================================
  // CORE FETCH HELPERS
  // ============================================================

  static Future<String> _getUserAgent() async {
    if (_userAgent == null) {
      try {
        final info = await PackageInfo.fromPlatform();
        final sessionId = const Uuid().v4().substring(0, 8);
        _userAgent =
            '${info.appName}/${info.version} (${info.packageName}; session-$sessionId)';
      } catch (e) {
        _userAgent = 'TransApp/2.0 (github.com/your-repo)';
      }
    }
    return _userAgent!;
  }

  static Future<http.Response> _fetch(Uri uri, {int retries = 2}) async {
    final userAgent = await _getUserAgent();

    for (int attempt = 0; attempt <= retries; attempt++) {
      try {
        debugPrint("Fetching: $uri");
        final response = await http.get(uri, headers: {
          'User-Agent': userAgent,
          'Accept': 'application/json',
        }).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) return response;

        // Retry on 503 (Service Unavailable) with backoff
        if (response.statusCode == 503 && attempt < retries) {
          final delay = Duration(milliseconds: 500 * (attempt + 1));
          debugPrint(
              "API returned 503, retrying in ${delay.inMilliseconds}ms...");
          await Future.delayed(delay);
          continue;
        }

        debugPrint("API Error ${response.statusCode}: ${response.body}");
        throw Exception("API Error ${response.statusCode}");
      } catch (e) {
        if (attempt < retries) {
          final delay = Duration(milliseconds: 500 * (attempt + 1));
          debugPrint(
              "Network Error: $e, retrying in ${delay.inMilliseconds}ms...");
          await Future.delayed(delay);
          continue;
        }
        rethrow;
      }
    }
    throw Exception("Max retries exceeded");
  }

  // ============================================================
  // V6.DB (FALLBACK) IMPLEMENTATIONS
  // ============================================================

  static Uri _getV6Uri(String endpoint, [Map<String, dynamic>? params]) {
    String url = "$_v6Url$endpoint";
    if (params != null && params.isNotEmpty) {
      url += "?";
      params.forEach((key, value) {
        if (value != null) {
          url += "$key=${Uri.encodeComponent(value.toString())}&";
        }
      });
    }
    return Uri.parse(url);
  }

  static Future<List<Station>> _searchStationsV6(String query,
      {double? lat, double? lng}) async {
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

    final response = await _fetch(_getV6Uri('/locations', params));
    final List<dynamic> data = json.decode(response.body);
    return data.map((json) => Station.fromJson(json)).toList();
  }

  static Future<List<Station>> _getNearbyStopsV6(double lat, double lng) async {
    final response = await _fetch(_getV6Uri('/stops/nearby', {
      'latitude': lat,
      'longitude': lng,
      'results': 5,
      'distance': 1000,
    }));
    final List<dynamic> data = json.decode(response.body);
    return data.map((json) => Station.fromJson(json)).toList();
  }

  static Future<List<Map<String, dynamic>>> _searchJourneysV6(
    Station from,
    Station to, {
    bool nahverkehrOnly = false,
    DateTime? when,
    bool isArrival = false,
    int results = 3,
  }) async {
    final Map<String, dynamic> params = {
      'results': results,
      'stopovers': 'true',
      'polylines': 'true',
      'tickets': 'false',
    };

    // FROM: Use coordinates for GPS, locations (POIs), addresses, OR non-numeric IDs
    final fromIsNumeric = RegExp(r'^[0-9]+$').hasMatch(from.id);
    if (from.id == 'gps' || from.type == 'location' || from.type == 'address' || !fromIsNumeric) {
      params['from.latitude'] = from.latitude;
      params['from.longitude'] = from.longitude;
      params['from.address'] = from.name;
    } else {
      params['from'] = from.id;
    }

    // TO: Use coordinates for GPS, locations (POIs), addresses, OR non-numeric IDs
    final toIsNumeric = RegExp(r'^[0-9]+$').hasMatch(to.id);
    if (to.id == 'gps' || to.type == 'location' || to.type == 'address' || !toIsNumeric) {
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
      params['nationalExpress'] = 'false';
      params['national'] = 'false';
    }

    final response = await _fetch(_getV6Uri('/journeys', params));
    final data = json.decode(response.body);
    if (data['journeys'] != null) {
      return List<Map<String, dynamic>>.from(data['journeys']);
    }
    return [];
  }

  // ============================================================
  // MOTIS/TRANSITOUS (PRIMARY) IMPLEMENTATIONS
  // ============================================================

  static Uri _getMotisUri(String endpoint, [Map<String, dynamic>? params]) {
    final uri = Uri.parse('$_motisUrl$endpoint');
    if (params == null || params.isEmpty) return uri;

    return uri.replace(
        queryParameters:
            params.map((k, v) => MapEntry(k, v?.toString() ?? '')));
  }

  static Future<List<Station>> _searchStationsMotis(String query,
      {double? lat, double? lng}) async {
    final Map<String, dynamic> params = {
      'text': query,
    };

    // Add location bias if coordinates provided
    // User requested to REMOVE bias for typed queries, so we comment this out.
    // The query 'text' should be the primary filter.
    /*
    if (lat != null && lng != null) {
      params['place'] = '$lat,$lng';
      params['placeBias'] = '2'; // Higher bias towards user location
    }
    */

    final response = await _fetch(_getMotisUri('/api/v1/geocode', params));
    final List<dynamic> data = json.decode(response.body);

    // Convert MOTIS Match format to Station
    return data.map((match) => stationFromMotisMatch(match)).toList();
  }

  static Future<List<Station>> _getNearbyStopsMotis(
      double lat, double lng) async {
    final response = await _fetch(_getMotisUri('/api/v1/reverse-geocode', {
      'place': '$lat,$lng',
      'type': 'STOP', // Only return transit stops
    }));
    final List<dynamic> data = json.decode(response.body);
    return data.map((match) => stationFromMotisMatch(match)).toList();
  }

  static Future<List<Map<String, dynamic>>> _searchJourneysMotis(
    Station from,
    Station to, {
    bool nahverkehrOnly = false,
    DateTime? when,
    bool isArrival = false,
    int results = 3,
  }) async {
    final Map<String, dynamic> params = {
      'numItineraries': results.toString(),
      'detailedTransfers': 'true',
      'showIntermediateStops': 'true',
    };

    // FROM: Use coordinates if ID is GPS, location, address, empty, or a v6.db numeric ID
    // MOTIS uses IDs like "de:11000:900003200", v6.db uses numeric IDs like "8005220"
    final fromIsNumericId = RegExp(r'^[0-9]+$').hasMatch(from.id);
    if (from.id == 'gps' ||
        from.type == 'location' ||
        from.type == 'address' ||
        from.id.isEmpty ||
        (fromIsNumericId && from.latitude != null && from.longitude != null)) {
      params['fromPlace'] = '${from.latitude},${from.longitude}';
    } else {
      params['fromPlace'] = from.id;
    }

    // TO: Use coordinates if ID is GPS, location, address, empty, or a v6.db numeric ID
    final toIsNumericId = RegExp(r'^[0-9]+$').hasMatch(to.id);
    if (to.id == 'gps' ||
        to.type == 'location' ||
        to.type == 'address' ||
        to.id.isEmpty ||
        (toIsNumericId && to.latitude != null && to.longitude != null)) {
      params['toPlace'] = '${to.latitude},${to.longitude}';
    } else {
      params['toPlace'] = to.id;
    }

    // TIME
    if (when != null) {
      // MOTIS expects ISO8601 without microseconds
      params['time'] = when.toUtc().toIso8601String().split('.').first + 'Z';
      params['arriveBy'] = isArrival.toString();
    }

    // TRANSIT MODES - filter for local transit if requested
    // Must include WALK to allow walking to/from stations!
    if (nahverkehrOnly) {
      params['transitModes'] =
          'REGIONAL_RAIL,REGIONAL_FAST_RAIL,SUBURBAN,SUBWAY,TRAM,BUS,WALK';
    }

    final response = await _fetch(_getMotisUri('/api/v5/plan', params));
    final data = json.decode(response.body);

    final itineraries = data['itineraries'] as List? ?? [];

    // Convert MOTIS itineraries to v6.db journey format and tag source
    return itineraries.map<Map<String, dynamic>>((it) {
      final j = journeyFromMotisItinerary(it as Map<String, dynamic>);
      j['source'] = 'motis';
      return j;
    }).toList();
  }

  // ============================================================
  // PUBLIC API WITH FALLBACK
  // ============================================================

  /// Search for stations/addresses by query
  /// Uses in-memory cache, tries Transitous first, falls back to v6.db
  static Future<List<Station>> searchStations(String query,
      {double? lat, double? lng}) async {
    if (query.isEmpty) return [];

    // Check cache first
    final cacheKey = 'stations:$query:$lat:$lng';
    final cached = _stationCache[cacheKey];
    if (cached != null && !cached.isExpired) {
      debugPrint('Cache hit for stations: $query');
      return cached.data;
    }

    try {
      // Try MOTIS/Transitous first
      final result = await _searchStationsMotis(query, lat: lat, lng: lng);
      _stationCache[cacheKey] = _CacheEntry(result, const Duration(hours: 1));
      return result;
    } catch (e) {
      debugPrint('Transitous searchStations failed: $e, trying v6.db...');
      try {
        // Fallback to v6.db
        final result = await _searchStationsV6(query, lat: lat, lng: lng);
        _stationCache[cacheKey] = _CacheEntry(result, const Duration(hours: 1));
        return result;
      } catch (e2) {
        debugPrint('v6.db searchStations also failed: $e2');
        return [];
      }
    }
  }

  /// Get nearby stops by coordinates
  /// Uses in-memory cache, tries Transitous first, falls back to v6.db
  static Future<List<Station>> getNearbyStops(double lat, double lng) async {
    // Check cache (with rounded coords for better hit rate)
    final roundedLat = (lat * 1000).round() / 1000;
    final roundedLng = (lng * 1000).round() / 1000;
    final cacheKey = 'nearby:$roundedLat:$roundedLng';

    final cached = _nearbyCache[cacheKey];
    if (cached != null && !cached.isExpired) {
      debugPrint('Cache hit for nearby stops');
      return cached.data;
    }

    try {
      // Try MOTIS/Transitous first
      final result = await _getNearbyStopsMotis(lat, lng);
      _nearbyCache[cacheKey] =
          _CacheEntry(result, const Duration(minutes: 30));
      return result;
    } catch (e) {
      debugPrint('Transitous getNearbyStops failed: $e, trying v6.db...');
      try {
        // Fallback to v6.db
        final result = await _getNearbyStopsV6(lat, lng);
        _nearbyCache[cacheKey] =
            _CacheEntry(result, const Duration(minutes: 30));
        return result;
      } catch (e2) {
        debugPrint('v6.db getNearbyStops also failed: $e2');
        return [];
      }
    }
  }

  /// Search for journeys between two stations
  /// Tries Transitous first, falls back to v6.db
  /// No caching - journeys are time-sensitive
  static Future<List<Map<String, dynamic>>> searchJourneys(
    Station from,
    Station to, {
    bool nahverkehrOnly = false,
    DateTime? when,
    bool isArrival = false,
    int results = 7,
  }) async {
    if (apiMode == 'v6') {
      final res = await _searchJourneysV6(
        from,
        to,
        nahverkehrOnly: nahverkehrOnly,
        when: when,
        isArrival: isArrival,
        results: results,
      );
      // Filter out past journeys and tag with source
      final now = DateTime.now();
      final filtered = res;

      return filtered.map((j) { j['source'] = 'v6'; return j; }).toList();
    }

    try {
      // Try MOTIS/Transitous (unless disabled)
      final motisResults = await _searchJourneysMotis(
        from,
        to,
        nahverkehrOnly: nahverkehrOnly,
        when: when,
        isArrival: isArrival,
        results: results,
      );
      
      // Filter out journeys with past departure times (unless searching by arrival time)
      final now = DateTime.now();
      final filteredResults = motisResults;

      
      if (filteredResults.isNotEmpty || apiMode == 'motis') return filteredResults;
      
      debugPrint("Transitous returned 0 routes and mode is auto. Trying fallback...");
      throw Exception("No routes found on primary API");
    } catch (e) {
      if (apiMode == 'motis') rethrow; // Don't fallback in strict mode
      
      debugPrint('Transitous searchJourneys failed: $e, trying v6.db...');
      try {
        // Fallback to v6.db
        final res = await _searchJourneysV6(
          from,
          to,
          nahverkehrOnly: nahverkehrOnly,
          when: when,
          isArrival: isArrival,
          results: results,
        );
        
        // Filter out past journeys and tag with source
        final now = DateTime.now();
        final filtered = res;

        
        return filtered.map((j) {
           j['source'] = 'v6';
           return j;
        }).toList();
      } catch (e2) {
        debugPrint('v6.db searchJourneys also failed: $e2');
        return [];
      }
    }
  }

  /// Get walking route between two points
  /// Still uses OSRM - MOTIS handles walking in journey legs but not standalone
  static Future<List<List<double>>> getWalkingRoute(
      double startLat, double startLng, double endLat, double endLng) async {
    final uri = Uri.parse(
        'http://router.project-osrm.org/route/v1/foot/$startLng,$startLat;$endLng,$endLat?overview=full&geometries=geojson');

    try {
      final response = await _fetch(uri);
      final data = json.decode(response.body);
      if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
        final coordinates =
            data['routes'][0]['geometry']['coordinates'] as List;
        return coordinates.map<List<double>>((point) {
          return [
            (point[1] as num).toDouble(),
            (point[0] as num).toDouble()
          ];
        }).toList();
      }
    } catch (e) {
      debugPrint("OSRM Error: $e");
    }
    return [
      [startLat, startLng],
      [endLat, endLng]
    ];
  }

  /// Test API connectivity (checks both endpoints)
  static Future<bool> testConnection() async {
    try {
      // Test Transitous
      final motisUri =
          Uri.parse('$_motisUrl/api/v1/geocode?text=Berlin&limit=1');
      await _fetch(motisUri);
      return true;
    } catch (e) {
      debugPrint("Transitous connection test failed: $e");
      try {
        // Try v6.db
        final v6Uri = Uri.parse('$_v6Url/locations?query=Berlin&results=1');
        await _fetch(v6Uri);
        return true;
      } catch (e2) {
        debugPrint("v6.db connection test also failed: $e2");
        return false;
      }
    }
  }

  /// Clear all in-memory caches
  static void clearCache() {
    _stationCache.clear();
    _nearbyCache.clear();
    debugPrint('TransportApi cache cleared');
  }
}