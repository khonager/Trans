import 'dart:convert';
import 'dart:math' as math;
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
  static final Map<String, Future<List<Station>>> _stationSearchInFlight = {};

  // Cache the User-Agent
  static String? _userAgent;
  static DateTime? _v6StationsCooldownUntil;
  static const List<String> _nonDeutschlandticketServiceTokens = [
    'ICE',
    'IC',
    'EC',
    'ECE',
    'TGV',
    'RJ',
    'RJX',
    'WESTBAHN',
  ];

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
        final response = await http.get(
          uri,
          headers: {'User-Agent': userAgent, 'Accept': 'application/json'},
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) return response;

        // Retry on 503 (Service Unavailable) with backoff
        if (response.statusCode == 503 && attempt < retries) {
          final delay = Duration(milliseconds: 500 * (attempt + 1));
          debugPrint(
            "API returned 503, retrying in ${delay.inMilliseconds}ms...",
          );
          await Future.delayed(delay);
          continue;
        }

        debugPrint("API Error ${response.statusCode}: ${response.body}");
        throw Exception("API Error ${response.statusCode}");
      } catch (e) {
        if (attempt < retries) {
          final delay = Duration(milliseconds: 500 * (attempt + 1));
          debugPrint(
            "Network Error: $e, retrying in ${delay.inMilliseconds}ms...",
          );
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

  static Future<List<Station>> _searchStationsV6(
    String query, {
    double? lat,
    double? lng,
  }) async {
    final Map<String, dynamic> params = {
      'query': query,
      'results': 20,
      'poi': 'true',
      'addresses': 'true',
    };

    if (lat != null && lng != null) {
      params['latitude'] = lat;
      params['longitude'] = lng;
    }

    final response = await _fetch(_getV6Uri('/locations', params));
    final List<dynamic> data = json.decode(response.body);
    return data.map((json) => Station.fromJson(json)).toList();
  }

  static Future<List<Station>> _getNearbyStopsV6(double lat, double lng) async {
    final response = await _fetch(
      _getV6Uri('/stops/nearby', {
        'latitude': lat,
        'longitude': lng,
        'results': 5,
        'distance': 1000,
      }),
    );
    final List<dynamic> data = json.decode(response.body);
    return data.map((json) => Station.fromJson(json)).toList();
  }

  /// Checks if a v6 journey leg is a non-Deutschlandticket service
  /// (e.g. FlixBus, FlixTrain, IC Bus, or other long-distance coaches)
  @visibleForTesting
  static String normalizeServiceText(Object? value) {
    if (value == null) return '';
    // Keep separators as spaces so patterns like "IC-BUS" and "IC/BUS"
    // still become tokenizable as "IC BUS".
    return value
        .toString()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), ' ')
        .trim();
  }

  @visibleForTesting
  static bool containsServiceToken(String text, String token) {
    return RegExp('(^| )${RegExp.escape(token)}( |\$)').hasMatch(text);
  }

  static bool _containsAnyServiceToken(String text, List<String> tokens) {
    for (final token in tokens) {
      if (containsServiceToken(text, token)) return true;
    }
    return false;
  }

  static String _lineNumberText(Map<String, dynamic> line) {
    // Some providers expose line numbers as `fahrtNr` (v6-style) while others
    // return `fahrtnr`; normalize both for robust filtering.
    return normalizeServiceText(line['fahrtNr'] ?? line['fahrtnr']);
  }

  @visibleForTesting
  static bool isNonDeutschlandticketLegForTesting(Map<String, dynamic> leg) =>
      _isNonDeutschlandticketLeg(leg);

  static bool _isNonDeutschlandticketLeg(Map<String, dynamic> leg) {
    final line = leg['line'] as Map<String, dynamic>?;
    if (line == null) return false;

    // Check product type — nationalExpress/national are not covered
    final product = (line['product'] as String?)?.toLowerCase() ?? '';
    if (product == 'nationalexpress' || product == 'national') return true;

    // Check productName for FlixBus/FlixTrain/IC Bus patterns
    final productName = normalizeServiceText(line['productName']);
    if (productName == 'FLX' ||
        productName == 'FLIXBUS' ||
        productName == 'FLIXTRAIN') {
      return true;
    }
    if (productName == 'IC BUS' || productName == 'ICB') {
      return true;
    }
    if (_containsAnyServiceToken(
      productName,
      _nonDeutschlandticketServiceTokens,
    )) {
      return true;
    }

    // Check line name for Flix patterns
    final lineName = normalizeServiceText(line['name']);
    if (lineName.contains('FLX') || lineName.contains('FLIX')) return true;
    if (_containsAnyServiceToken(
      lineName,
      _nonDeutschlandticketServiceTokens,
    )) {
      return true;
    }

    final lineNumber = _lineNumberText(line);
    if (_containsAnyServiceToken(
      lineNumber,
      _nonDeutschlandticketServiceTokens,
    )) {
      return true;
    }

    // Check operator name
    final operator = line['operator'] as Map<String, dynamic>?;
    if (operator != null) {
      final opName = normalizeServiceText(operator['name']);
      if (opName.contains('FLIX') || opName.contains('FLIXMOBILITY')) {
        return true;
      }
    }

    return false;
  }

  /// Filters out journeys that contain non-Deutschlandticket legs
  static List<Map<String, dynamic>> _filterForDeutschlandticket(
    List<Map<String, dynamic>> journeys,
  ) {
    return journeys.where((journey) {
      final legs = journey['legs'] as List?;
      if (legs == null) return true;
      // Keep journey only if NO leg is a non-Deutschlandticket service
      return !legs.any(
        (leg) => leg is Map<String, dynamic> && _isNonDeutschlandticketLeg(leg),
      );
    }).toList();
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
    if (from.id == 'gps' ||
        from.type == 'location' ||
        from.type == 'address' ||
        !fromIsNumeric) {
      params['from.latitude'] = from.latitude;
      params['from.longitude'] = from.longitude;
      params['from.address'] = from.name;
    } else {
      params['from'] = from.id;
    }

    // TO: Use coordinates for GPS, locations (POIs), addresses, OR non-numeric IDs
    final toIsNumeric = RegExp(r'^[0-9]+$').hasMatch(to.id);
    if (to.id == 'gps' ||
        to.type == 'location' ||
        to.type == 'address' ||
        !toIsNumeric) {
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
      var journeys = List<Map<String, dynamic>>.from(data['journeys']);
      // Post-filter: remove FlixBus/FlixTrain/IC Bus etc. when Deutschlandticket mode
      if (nahverkehrOnly) {
        journeys = _filterForDeutschlandticket(journeys);
      }
      return journeys;
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
      queryParameters: params.map((k, v) => MapEntry(k, v?.toString() ?? '')),
    );
  }

  static Future<List<Station>> _searchStationsMotis(
    String query, {
    double? lat,
    double? lng,
  }) async {
    final Map<String, dynamic> params = {'text': query};

    if (lat != null && lng != null) {
      params['place'] = '$lat,$lng';
      // Bias ranking toward nearby matches without restricting the search area.
      params['placeBias'] = '2';
    }

    final response = await _fetch(_getMotisUri('/api/v1/geocode', params));
    final List<dynamic> data = json.decode(response.body);

    // Convert MOTIS Match format to Station
    return data.map((match) => stationFromMotisMatch(match)).toList();
  }

  static Future<List<Station>> _getNearbyStopsMotis(
    double lat,
    double lng,
  ) async {
    final response = await _fetch(
      _getMotisUri('/api/v1/reverse-geocode', {
        'place': '$lat,$lng',
        'type': 'STOP', // Only return transit stops
      }),
    );
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
      params['time'] = '${when.toUtc().toIso8601String().split('.').first}Z';
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
  static Future<List<Station>> searchStations(
    String query, {
    double? lat,
    double? lng,
  }) async {
    final sanitizedQuery = _sanitizeStationQuery(query);
    if (sanitizedQuery.isEmpty) return [];

    // Check cache first
    final cacheKey = 'stations:$sanitizedQuery:$lat:$lng';
    final cached = _stationCache[cacheKey];
    if (cached != null && !cached.isExpired) {
      debugPrint('Cache hit for stations: $sanitizedQuery');
      return cached.data;
    }

    final inFlight = _stationSearchInFlight[cacheKey];
    if (inFlight != null) return inFlight;

    final future = _searchStationsInternal(
      sanitizedQuery,
      cacheKey,
      lat: lat,
      lng: lng,
    );
    _stationSearchInFlight[cacheKey] = future;
    future.whenComplete(() => _stationSearchInFlight.remove(cacheKey));
    return future;
  }

  static Future<List<Station>> _searchStationsInternal(
    String query,
    String cacheKey, {
    double? lat,
    double? lng,
  }) async {
    if (apiMode == 'v6') {
      final result = await _searchStationsV6(query, lat: lat, lng: lng);
      final ranked = rankStationsForQuery(result, query, lat: lat, lng: lng);
      _stationCache[cacheKey] = _CacheEntry(ranked, const Duration(hours: 1));
      return ranked;
    }

    List<Station> motisResults = [];
    try {
      motisResults = await _searchStationsMotis(query, lat: lat, lng: lng);
    } catch (error) {
      debugPrint('Transitous searchStations failed: $error');
    }

    final rankedMotis = rankStationsForQuery(
      motisResults,
      query,
      lat: lat,
      lng: lng,
    );

    if (apiMode == 'motis') {
      _stationCache[cacheKey] = _CacheEntry(
        rankedMotis,
        const Duration(hours: 1),
      );
      return rankedMotis;
    }

    if (!_shouldAugmentStationResultsWithV6(
      rankedMotis,
      query,
      lat: lat,
      lng: lng,
    )) {
      _stationCache[cacheKey] = _CacheEntry(
        rankedMotis,
        const Duration(hours: 1),
      );
      return rankedMotis;
    }

    final v6Results = await _searchStationsV6WithCooldown(
      query,
      lat: lat,
      lng: lng,
    );
    if (v6Results.isEmpty) {
      _stationCache[cacheKey] = _CacheEntry(
        rankedMotis,
        const Duration(hours: 1),
      );
      return rankedMotis;
    }

    final merged = _mergeStations(rankedMotis, v6Results);
    final ranked = rankStationsForQuery(merged, query, lat: lat, lng: lng);
    _stationCache[cacheKey] = _CacheEntry(ranked, const Duration(hours: 1));
    return ranked;
  }

  static List<Station> _mergeStations(
    List<Station> primary,
    List<Station> secondary,
  ) {
    final merged = <Station>[];
    final seen = <String>{};

    void addStation(Station station) {
      final key = _stationDedupKey(station);
      if (seen.add(key)) {
        merged.add(station);
      }
    }

    for (final station in primary) {
      addStation(station);
    }
    for (final station in secondary) {
      addStation(station);
    }

    return merged;
  }

  static String _stationDedupKey(Station station) {
    final id = station.id.trim();
    if (id.isNotEmpty) return id;

    final lat = station.latitude?.toStringAsFixed(5) ?? '';
    final lng = station.longitude?.toStringAsFixed(5) ?? '';
    return '${station.name.trim().toLowerCase()}|$lat|$lng';
  }

  static Future<List<Station>> _searchStationsV6WithCooldown(
    String query, {
    double? lat,
    double? lng,
  }) async {
    final cooldownUntil = _v6StationsCooldownUntil;
    if (cooldownUntil != null && DateTime.now().isBefore(cooldownUntil)) {
      debugPrint(
        'Skipping v6 station search during cooldown for query: $query',
      );
      return const <Station>[];
    }

    try {
      return await _searchStationsV6(query, lat: lat, lng: lng);
    } catch (error) {
      debugPrint('v6.db searchStations failed: $error');
      _v6StationsCooldownUntil = DateTime.now().add(
        _looksLikeServiceUnavailable(error)
            ? const Duration(minutes: 3)
            : const Duration(minutes: 1),
      );
      return const <Station>[];
    }
  }

  static bool _shouldAugmentStationResultsWithV6(
    List<Station> motisResults,
    String query, {
    double? lat,
    double? lng,
  }) {
    if (motisResults.isEmpty) return true;

    final queryTokens = _searchTokens(query);
    final topResults = motisResults.take(5).toList();
    final transitResults =
        topResults.where((station) => _isTransitStation(station)).toList();

    if (_isAirportLikeQuery(queryTokens)) {
      return transitResults.isEmpty ||
          !topResults.any((station) => _looksLikeAirportStation(station));
    }

    if (transitResults.isEmpty) return true;
    if (motisResults.length < 5) return true;

    final hasLocationBias = lat != null && lng != null;
    final isSingleTokenQuery = queryTokens.length == 1;
    if (!hasLocationBias &&
        isSingleTokenQuery &&
        !_looksLikeTransitHubStation(topResults.first)) {
      return true;
    }

    return false;
  }

  @visibleForTesting
  static List<Station> rankStationsForQuery(
    List<Station> stations,
    String query, {
    double? lat,
    double? lng,
  }) {
    if (stations.length < 2) return stations;

    final normalizedQuery = _normalizeSearchText(query);
    final queryTokens = _searchTokens(query);
    if (normalizedQuery.isEmpty || queryTokens.isEmpty) return stations;

    final indexedStations = stations.asMap().entries.toList();
    indexedStations.sort((a, b) {
      final scoreA = _stationSearchScore(
        a.value,
        normalizedQuery,
        queryTokens,
        lat: lat,
        lng: lng,
      );
      final scoreB = _stationSearchScore(
        b.value,
        normalizedQuery,
        queryTokens,
        lat: lat,
        lng: lng,
      );
      final scoreCompare = scoreB.compareTo(scoreA);
      if (scoreCompare != 0) return scoreCompare;
      return a.key.compareTo(b.key);
    });

    return indexedStations.map((entry) => entry.value).toList();
  }

  static int _stationSearchScore(
    Station station,
    String normalizedQuery,
    List<String> queryTokens, {
    double? lat,
    double? lng,
  }) {
    final normalizedName = _normalizeSearchText(station.name);
    final nameTokens = _splitSearchTokens(normalizedName);
    final metadataTokens = _splitSearchTokens(
      _normalizeSearchText(
        [
          station.city,
          station.region,
          station.country,
          station.category,
          station.type,
        ].whereType<String>().join(' '),
      ),
    );
    final isTransitStop = station.type == 'station' || station.type == 'stop';
    final isAirportQuery = _isAirportLikeQuery(queryTokens);
    final hasLocationBias = lat != null && lng != null;
    final isSingleTokenQuery = queryTokens.length == 1;

    var score = 0;

    if (normalizedName == normalizedQuery) {
      score += 300;
    } else if (normalizedName.startsWith('$normalizedQuery ')) {
      score += 240;
    } else if (normalizedName.contains(normalizedQuery)) {
      score += 170;
    }

    var matchedQueryTokens = 0;
    for (final token in queryTokens) {
      final exactNameMatch = nameTokens.contains(token);
      final prefixNameMatch = nameTokens.any(
        (nameToken) =>
            nameToken.startsWith(token) || token.startsWith(nameToken),
      );
      final metadataMatch = metadataTokens.contains(token);

      if (exactNameMatch) {
        matchedQueryTokens++;
        score += 55;
      } else if (prefixNameMatch) {
        matchedQueryTokens++;
        score += 24;
      } else if (metadataMatch) {
        matchedQueryTokens++;
        score += 10;
      }
    }

    if (matchedQueryTokens == queryTokens.length) {
      score += 75;
    }

    if (isTransitStop) score += 65;
    if (station.type == 'address') score -= 20;

    if (_looksLikeTransitHub(normalizedName, nameTokens)) {
      score += 95;
    }

    if (!hasLocationBias &&
        isSingleTokenQuery &&
        station.type == 'location' &&
        normalizedName == normalizedQuery) {
      // In route planning, exact city/place names are useful, but the main
      // station is usually the more actionable result when we have no location.
      score -= 90;
    }

    if (isAirportQuery) {
      if (_looksLikeAirport(nameTokens, metadataTokens)) {
        score += 180;
      }
      if (isTransitStop) score += 120;
      if (station.type == 'address') score -= 140;
      if (_isGenericAirportLabel(normalizedName)) score -= 110;
      if (_looksLikeRoadOrNeighborhood(nameTokens)) score -= 95;
      if (normalizedName.contains('bahnhof') ||
          normalizedName.contains('regionalbf') ||
          normalizedName.contains('fernbf') ||
          normalizedName.contains('terminal')) {
        score += 45;
      }
    }

    if (lat != null &&
        lng != null &&
        station.latitude != null &&
        station.longitude != null) {
      final distanceKm = _distanceKm(
        lat,
        lng,
        station.latitude!,
        station.longitude!,
      );
      score += math.max(0, 120 - distanceKm.round());
    }

    return score;
  }

  static bool _looksLikeAirport(
    List<String> nameTokens,
    List<String> metadataTokens,
  ) {
    const airportTokens = {
      'airport',
      'flughafen',
      'aerodrome',
      'aerodrom',
      'airfield',
      'terminal',
    };

    final allTokens = [...nameTokens, ...metadataTokens];
    return allTokens.any(
      (token) =>
          airportTokens.contains(token) ||
          token.startsWith('flughaf') ||
          token.startsWith('airport'),
    );
  }

  static bool _looksLikeAirportStation(Station station) {
    final normalizedName = _normalizeSearchText(station.name);
    final nameTokens = _splitSearchTokens(normalizedName);
    final metadataTokens = _splitSearchTokens(
      _normalizeSearchText(
        [
          station.city,
          station.region,
          station.country,
          station.category,
          station.type,
        ].whereType<String>().join(' '),
      ),
    );
    return _looksLikeAirport(nameTokens, metadataTokens);
  }

  static bool _looksLikeTransitHub(
    String normalizedName,
    List<String> nameTokens,
  ) {
    if (normalizedName.contains('hauptbahnhof') ||
        normalizedName.contains('main station') ||
        normalizedName.contains('central station') ||
        normalizedName.contains('regionalbf') ||
        normalizedName.contains('fernbf')) {
      return true;
    }

    const hubTokens = {
      'bahnhof',
      'busbahnhof',
      'central',
      'centrum',
      'centre',
      'hbf',
      'terminal',
      'zob',
      'zentrum',
    };

    return nameTokens.any(hubTokens.contains);
  }

  static bool _looksLikeTransitHubStation(Station station) =>
      _looksLikeTransitHub(
        _normalizeSearchText(station.name),
        _splitSearchTokens(_normalizeSearchText(station.name)),
      );

  static bool _isTransitStation(Station station) =>
      station.type == 'station' || station.type == 'stop';

  static bool _isGenericAirportLabel(String normalizedName) =>
      normalizedName == 'airport' || normalizedName == 'flughafen';

  static bool _looksLikeRoadOrNeighborhood(List<String> tokens) {
    const roadSuffixes = [
      'allee',
      'gasse',
      'ring',
      'schneise',
      'strasse',
      'street',
      'weg',
    ];
    return tokens.any(
      (token) => roadSuffixes.any(
        (suffix) => token.endsWith(suffix) && token != suffix,
      ),
    );
  }

  static bool _isAirportLikeQuery(List<String> queryTokens) => queryTokens.any(
        (token) =>
            token.startsWith('flughaf') ||
            token.startsWith('airport') ||
            token.startsWith('airpor') ||
            token.startsWith('aerodrom'),
      );

  static List<String> _searchTokens(String text) => _splitSearchTokens(
        _normalizeSearchText(text),
      ).where(_isMeaningfulSearchToken).toList();

  static List<String> _splitSearchTokens(String text) => text
      .split(RegExp(r'\s+'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();

  static bool _isMeaningfulSearchToken(String token) {
    const ignoredTokens = {
      'am',
      'an',
      'bei',
      'closest',
      'der',
      'die',
      'ein',
      'eine',
      'im',
      'in',
      'nahe',
      'naher',
      'near',
      'nearby',
      'nearest',
      'the',
      'zum',
      'zur',
    };
    return token.isNotEmpty && !ignoredTokens.contains(token);
  }

  static String _sanitizeStationQuery(String query) =>
      query.trim().replaceAll(RegExp(r'\s+'), ' ');

  static String _normalizeSearchText(String text) {
    const replacements = {
      'ä': 'a',
      'ö': 'o',
      'ü': 'u',
      'ß': 'ss',
      'à': 'a',
      'á': 'a',
      'â': 'a',
      'ã': 'a',
      'å': 'a',
      'ç': 'c',
      'è': 'e',
      'é': 'e',
      'ê': 'e',
      'ë': 'e',
      'ì': 'i',
      'í': 'i',
      'î': 'i',
      'ï': 'i',
      'ñ': 'n',
      'ò': 'o',
      'ó': 'o',
      'ô': 'o',
      'õ': 'o',
      'ù': 'u',
      'ú': 'u',
      'û': 'u',
      'ý': 'y',
      'ÿ': 'y',
    };

    final buffer = StringBuffer();
    for (final rune in text.toLowerCase().runes) {
      final char = String.fromCharCode(rune);
      buffer.write(replacements[char] ?? char);
    }

    return buffer.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  static double _distanceKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadiusKm = 6371.0;
    final lat1Rad = _degreesToRadians(lat1);
    final lat2Rad = _degreesToRadians(lat2);
    final latDelta = _degreesToRadians(lat2 - lat1);
    final lngDelta = _degreesToRadians(lng2 - lng1);

    final a = math.sin(latDelta / 2) * math.sin(latDelta / 2) +
        math.cos(lat1Rad) *
            math.cos(lat2Rad) *
            math.sin(lngDelta / 2) *
            math.sin(lngDelta / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double _degreesToRadians(double degrees) => degrees * math.pi / 180;

  static bool _looksLikeServiceUnavailable(Object error) =>
      error.toString().contains('503');

  @visibleForTesting
  static List<Map<String, dynamic>> decodeStopDeparturesResponse(dynamic data) {
    if (data is List) {
      return data.whereType<Map<String, dynamic>>().toList();
    }

    if (data is Map<String, dynamic>) {
      final nestedList =
          data['stopTimes'] ?? data['stoptimes'] ?? data['departures'];
      if (nestedList is List) {
        return nestedList.whereType<Map<String, dynamic>>().toList();
      }

      if (data.containsKey('place') || data.containsKey('line')) {
        return [data];
      }
    }

    throw FormatException(
      'Unsupported stop departures response: ${data.runtimeType}',
    );
  }

  static String? _nextStopTimesPageCursor(dynamic data) {
    if (data is! Map<String, dynamic>) return null;
    final cursor = data['nextPageCursor']?.toString().trim();
    if (cursor == null || cursor.isEmpty) return null;
    return cursor;
  }

  static DateTime? _stopDepartureDateTimeLocal(Map<String, dynamic> dep) {
    final motisDepObj = dep['departure'] as Map<String, dynamic>?;
    final motisPlaceObj = dep['place'] as Map<String, dynamic>?;
    final rawTime = (motisDepObj?['scheduledTime'] as String?) ??
        (motisDepObj?['time'] as String?) ??
        (motisPlaceObj?['scheduledDeparture'] as String?) ??
        (motisPlaceObj?['departure'] as String?) ??
        (motisPlaceObj?['scheduledArrival'] as String?) ??
        (motisPlaceObj?['arrival'] as String?) ??
        (dep['plannedWhen'] as String?) ??
        (dep['when'] as String?);
    if (rawTime == null || rawTime.isEmpty) return null;

    try {
      return DateTime.parse(rawTime).toLocal();
    } catch (_) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> _fetchMotisStopDepartures(
    String stationId, {
    required DateTime startLocal,
    required DateTime endLocal,
    required int maxResults,
  }) async {
    final baseParams = <String, dynamic>{
      'stopId': stationId,
      'time': startLocal.toUtc().toIso8601String(),
      'direction': 'LATER',
      'n': math.min(maxResults, 100).toString(),
    };

    final departures = <Map<String, dynamic>>[];
    final seenKeys = <String>{};
    String? pageCursor;

    for (var page = 0; page < 8 && departures.length < maxResults; page++) {
      final response = await _fetch(
        _getMotisUri('/api/v5/stoptimes', {
          ...baseParams,
          if (pageCursor != null) 'pageCursor': pageCursor,
        }),
      );
      final data = json.decode(response.body);
      final pageDepartures = decodeStopDeparturesResponse(data);
      if (pageDepartures.isEmpty) break;

      var reachedNextDay = false;
      for (final dep in pageDepartures) {
        final departureTime = _stopDepartureDateTimeLocal(dep);
        if (departureTime == null) continue;
        if (departureTime.isAfter(endLocal)) {
          reachedNextDay = true;
          break;
        }
        if (departureTime.isBefore(startLocal)) continue;

        final dedupeKey = [
          departureTime.toIso8601String(),
          dep['routeShortName'] ?? dep['displayName'] ?? '',
          dep['headsign'] ?? dep['direction'] ?? '',
          (dep['place'] as Map<String, dynamic>?)?['track'] ?? '',
        ].join('|');
        if (!seenKeys.add(dedupeKey)) continue;

        departures.add(dep);
        if (departures.length >= maxResults) break;
      }

      if (departures.length >= maxResults || reachedNextDay) break;

      final nextPageCursor = _nextStopTimesPageCursor(data);
      if (nextPageCursor == null || nextPageCursor == pageCursor) break;
      pageCursor = nextPageCursor;
    }

    return departures;
  }

  /// Decodes a JSON response body and returns the result only when it is a
  /// JSON object (i.e. `Map<String, dynamic>`); returns `null` otherwise.
  ///
  /// Extracted so that the Map-or-null contract can be unit-tested without an
  /// HTTP round-trip.
  @visibleForTesting
  static Map<String, dynamic>? decodeJsonMap(String body) {
    final data = json.decode(body);
    return data is Map<String, dynamic> ? data : null;
  }

  /// Builds the MOTIS URI for `/api/v5/map/trips` with the required query
  /// parameters.  Exposed for unit-testing of parameter serialisation.
  @visibleForTesting
  static Uri buildLiveMapTripsUri({
    required String min,
    required String max,
    required DateTime startTime,
    required DateTime endTime,
    required double zoom,
  }) =>
      _getMotisUri('/api/v5/map/trips', {
        'min': min,
        'max': max,
        'startTime': startTime.toUtc().toIso8601String(),
        'endTime': endTime.toUtc().toIso8601String(),
        'zoom': zoom.toStringAsFixed(2),
      });

  /// Builds the MOTIS URI for `/api/v5/trip` with the required query
  /// parameters.  Exposed for unit-testing of parameter serialisation.
  /// Boolean flags are serialised as lowercase strings ('true'/'false').
  @visibleForTesting
  static Uri buildTripItineraryUri(
    String tripId, {
    bool withScheduledSkippedStops = true,
    bool joinInterlinedLegs = true,
  }) =>
      _getMotisUri('/api/v5/trip', {
        'tripId': tripId,
        'withScheduledSkippedStops': withScheduledSkippedStops.toString(),
        'joinInterlinedLegs': joinInterlinedLegs.toString(),
      });

  static Future<Map<String, dynamic>?> fetchMapInitial() async {
    final response = await _fetch(_getMotisUri('/api/v1/map/initial'));
    return decodeJsonMap(response.body);
  }

  static Future<String> fetchLiveMapTrips({
    required String min,
    required String max,
    required DateTime startTime,
    required DateTime endTime,
    required double zoom,
  }) async {
    final response = await _fetch(
      buildLiveMapTripsUri(
        min: min,
        max: max,
        startTime: startTime,
        endTime: endTime,
        zoom: zoom,
      ),
    );
    return response.body;
  }

  static Future<Map<String, dynamic>?> fetchTripItinerary(
    String tripId, {
    bool withScheduledSkippedStops = true,
    bool joinInterlinedLegs = true,
  }) async {
    final response = await _fetch(
      buildTripItineraryUri(
        tripId,
        withScheduledSkippedStops: withScheduledSkippedStops,
        joinInterlinedLegs: joinInterlinedLegs,
      ),
    );
    return decodeJsonMap(response.body);
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
      _nearbyCache[cacheKey] = _CacheEntry(result, const Duration(minutes: 30));
      return result;
    } catch (e) {
      debugPrint('Transitous getNearbyStops failed: $e, trying v6.db...');
      try {
        // Fallback to v6.db
        final result = await _getNearbyStopsV6(lat, lng);
        _nearbyCache[cacheKey] = _CacheEntry(
          result,
          const Duration(minutes: 30),
        );
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
    Function(List<Map<String, dynamic>>)? onPartialResults,
  }) async {
    // 1. STRICT V6 MODE
    if (apiMode == 'v6') {
      final res = await _searchJourneysV6(
        from,
        to,
        nahverkehrOnly: nahverkehrOnly,
        when: when,
        isArrival: isArrival,
        results: results,
      );
      final mapped = res.map((j) {
        j['source'] = 'v6';
        return j;
      }).toList();
      if (onPartialResults != null) onPartialResults(mapped);
      return mapped;
    }

    // 2. STRICT MOTIS MODE
    if (apiMode == 'motis') {
      try {
        final res = await _searchJourneysMotis(
          from,
          to,
          nahverkehrOnly: nahverkehrOnly,
          when: when,
          isArrival: isArrival,
          results: results,
        );
        if (onPartialResults != null) onPartialResults(res);
        return res;
      } catch (e) {
        debugPrint('Transitous searchJourneys failed (strict mode): $e');
        rethrow;
      }
    }

    // 3. AUTO MODE: HYBRID FETCHING
    try {
      // Launch both requests in parallel
      final motisFuture = _searchJourneysMotis(
        from,
        to,
        nahverkehrOnly: nahverkehrOnly,
        when: when,
        isArrival: isArrival,
        results: results,
      ).then((res) => res).catchError((e) {
        debugPrint('Hybrid: Transitous failed: $e');
        return <Map<String, dynamic>>[];
      });

      final v6Future = _searchJourneysV6(
        from,
        to,
        nahverkehrOnly: nahverkehrOnly,
        when: when,
        isArrival: isArrival,
        results: results,
      ).then((res) => res).catchError((e) {
        debugPrint('Hybrid: v6 failed: $e');
        return <Map<String, dynamic>>[];
      });

      if (onPartialResults != null) {
        bool motisDone = false;

        motisFuture.then((motisResults) {
          motisDone = true;
          if (motisResults.isNotEmpty) {
            onPartialResults(motisResults);
          }
        });

        v6Future.then((v6Results) {
          if (v6Results.isNotEmpty) {
            for (var j in v6Results) {
              j['source'] = 'v6';
            }

            if (!motisDone) {
              // DB finished before Motis! Show DB results first.
              onPartialResults(v6Results);
            } else {
              // Motis is done, we need to merge DB with Motis results.
              motisFuture.then((motisResults) {
                final merged = mergeResults(motisResults, v6Results);
                onPartialResults(merged);
              });
            }
          }
        });

        // Wait for both to formally complete the function call
        final resultsList = await Future.wait([motisFuture, v6Future]);
        final merged = mergeResults(resultsList[0], resultsList[1]);
        if (merged.isEmpty) return resultsList[0];
        return merged;
      } else {
        // Wait for both to complete
        final resultsList = await Future.wait([motisFuture, v6Future]);
        final motisResults = resultsList[0];
        final v6Results = resultsList[1];

        // Tag v6 results (MOTIS results are already tagged)
        for (var j in v6Results) {
          j['source'] = 'v6';
        }

        // Merge results
        final merged = mergeResults(motisResults, v6Results);

        if (merged.isEmpty) {
          throw Exception("No routes found on either API");
        }

        return merged;
      }
    } catch (e) {
      debugPrint('Hybrid searchJourneys critical failure: $e');
      return [];
    }
  }

  /// Merges results from both APIs, preferring MOTIS for duplicates but including unique v6 trips
  @visibleForTesting
  static List<Map<String, dynamic>> mergeResults(
    List<Map<String, dynamic>> motis,
    List<Map<String, dynamic>> v6,
  ) {
    if (motis.isEmpty) return v6;
    if (v6.isEmpty) return motis;

    final List<Map<String, dynamic>> merged = List.from(motis);
    final existingKeys = <String>{};

    // Helper to generate unique key for a journey
    String generateKey(Map<String, dynamic> journey) {
      final dep = journey['departure'] ?? '';
      final arr = journey['arrival'] ?? '';

      // Extract first line name to distinguish different routes at same time
      String firstLine = '';
      final legs = journey['legs'] as List?;
      if (legs != null && legs.isNotEmpty) {
        for (var leg in legs) {
          if (leg['line'] != null) {
            firstLine = leg['line']['name'] ?? '';
            break;
          }
        }
      }
      return '${dep}_${arr}_$firstLine';
    }

    // Index MOTIS results
    for (var j in motis) {
      existingKeys.add(generateKey(j));
    }

    // Add unique v6 results
    for (var j in v6) {
      final key = generateKey(j);
      if (!existingKeys.contains(key)) {
        merged.add(j);
      }
    }

    // Sort by departure time
    merged.sort((a, b) {
      final depA = a['departure'];
      final depB = b['departure'];
      if (depA == null || depB == null) return 0;
      return depA.compareTo(depB);
    });

    return merged;
  }

  /// Get walking route between two points
  /// Still uses OSRM - MOTIS handles walking in journey legs but not standalone
  static Future<List<List<double>>> getWalkingRoute(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) async {
    final uri = Uri.parse(
      'http://router.project-osrm.org/route/v1/foot/$startLng,$startLat;$endLng,$endLat?overview=full&geometries=geojson',
    );

    try {
      final response = await _fetch(uri);
      final data = json.decode(response.body);
      if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
        final coordinates =
            data['routes'][0]['geometry']['coordinates'] as List;
        return coordinates.map<List<double>>((point) {
          return [(point[1] as num).toDouble(), (point[0] as num).toDouble()];
        }).toList();
      }
    } catch (e) {
      debugPrint("OSRM Error: $e");
    }
    return [
      [startLat, startLng],
      [endLat, endLng],
    ];
  }

  /// Test API connectivity (checks both endpoints)
  static Future<bool> testConnection() async {
    try {
      // Test Transitous
      final motisUri = Uri.parse(
        '$_motisUrl/api/v1/geocode?text=Berlin&limit=1',
      );
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

  /// Fetch all departures for a stop on a given day.
  /// Tries MOTIS `/api/v5/stoptimes` first, falls back to v6.db `/stops/{id}/departures`.
  static Future<List<Map<String, dynamic>>> fetchStopDepartures(
    String stationId, {
    DateTime? date,
    int maxResults = 250,
  }) async {
    final day = date ?? DateTime.now();

    // Build a window covering the full calendar day (00:00 – 23:59).
    final startLocal = DateTime(day.year, day.month, day.day, 0, 0, 0);
    final endLocal = DateTime(day.year, day.month, day.day, 23, 59, 59);
    final start = startLocal.toUtc();

    // ── MOTIS ───────────────────────────────────────────────────────────────
    if (apiMode != 'v6') {
      try {
        return await _fetchMotisStopDepartures(
          stationId,
          startLocal: startLocal,
          endLocal: endLocal,
          maxResults: maxResults,
        );
      } catch (e) {
        debugPrint('MOTIS fetchStopDepartures failed: $e');
        if (apiMode == 'motis') rethrow;
      }
    }

    // ── v6.db ────────────────────────────────────────────────────────────────
    try {
      final isNumeric = RegExp(r'^[0-9]+$').hasMatch(stationId);
      if (!isNumeric) {
        debugPrint('Skipping v6 stop departures for non-numeric id $stationId');
        return [];
      }
      final response = await _fetch(
        _getV6Uri('/stops/$stationId/departures', {
          'when': start.toIso8601String(),
          'duration': 1440, // minutes in a day
          'results': maxResults,
        }),
      );
      return decodeStopDeparturesResponse(json.decode(response.body));
    } catch (e) {
      debugPrint('v6 fetchStopDepartures failed: $e');
      return [];
    }
  }

  /// Clear all in-memory caches
  static void clearCache() {
    _stationCache.clear();
    _nearbyCache.clear();
    debugPrint('TransportApi cache cleared');
  }
}
