import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

T? _readCache<T>(Map<String, _CacheEntry<T>> cache, String key) {
  final cached = cache[key];
  if (cached == null) return null;
  if (cached.isExpired) {
    cache.remove(key);
    return null;
  }
  return cached.data;
}

void _writeCache<T>(
  Map<String, _CacheEntry<T>> cache,
  String key,
  T data,
  Duration ttl,
) {
  cache[key] = _CacheEntry<T>(data, ttl);
}

void _pruneExpiredCache<T>(Map<String, _CacheEntry<T>> cache) {
  cache.removeWhere((_, entry) => entry.isExpired);
}

class _SyntheticSeed {
  final Map<String, dynamic> journey;
  final Map<String, dynamic> firstRide;
  final Map<String, dynamic> transferRide;
  final bool supportsSharedFamilyExpansion;
  final DateTime firstDeparture;
  final String originStopId;
  final String originStopName;
  final String lineKey;
  final String directionKey;
  final String? baseTripId;
  final String transferStopId;
  final String transferStopName;
  final double? transferLat;
  final double? transferLng;
  final String secondLineKey;
  final String secondDirectionKey;
  final String secondDestinationStopId;
  final String secondDestinationStopName;
  final List<Map<String, dynamic>> trailingLegs;
  final String dedupeKey;

  const _SyntheticSeed({
    required this.journey,
    required this.firstRide,
    required this.transferRide,
    required this.supportsSharedFamilyExpansion,
    required this.firstDeparture,
    required this.originStopId,
    required this.originStopName,
    required this.lineKey,
    required this.directionKey,
    required this.baseTripId,
    required this.transferStopId,
    required this.transferStopName,
    required this.transferLat,
    required this.transferLng,
    required this.secondLineKey,
    required this.secondDirectionKey,
    required this.secondDestinationStopId,
    required this.secondDestinationStopName,
    required this.trailingLegs,
    required this.dedupeKey,
  });
}

class TransportApi {
  static const String enabledApiSourcesPreferenceKey = 'enabled_api_sources';
  static const String advancedSettingsEnabledPreferenceKey =
      'advanced_settings_enabled_device';
  // Legacy keys kept for migration from slider-based advanced settings.
  static const String advancedTransferComfortPreferenceKey =
      'advanced_transfer_comfort';
  static const String advancedBikePreferenceKey = 'advanced_bike_preference';
  static const String advancedBikeTogglePreferenceKey =
      'advanced_bike_toggle_enabled_device';
  static const String advancedMinTransferTimeMinutesPreferenceKey =
      'advanced_min_transfer_time_minutes';
  static const String advancedAdditionalTransferTimeMinutesPreferenceKey =
      'advanced_additional_transfer_time_minutes';
  static const String advancedTransferTimeFactorPreferenceKey =
      'advanced_transfer_time_factor';
  static const String advancedPreTransitWalkEnabledPreferenceKey =
      'advanced_pre_transit_walk_enabled';
  static const String advancedPreTransitBikeEnabledPreferenceKey =
      'advanced_pre_transit_bike_enabled';
  static const String advancedPostTransitWalkEnabledPreferenceKey =
      'advanced_post_transit_walk_enabled';
  static const String advancedPostTransitBikeEnabledPreferenceKey =
      'advanced_post_transit_bike_enabled';
  static const String advancedCyclingSpeedKmhPreferenceKey =
      'advanced_cycling_speed_kmh';
  static const String advancedPedestrianSpeedKmhPreferenceKey =
      'advanced_pedestrian_speed_kmh';
  static const String advancedMaxWalkingTimeMinutesPreferenceKey =
      'advanced_max_walking_time_minutes';
  static const int defaultAdvancedMinTransferTimeMinutes = 0;
  static const int defaultAdvancedAdditionalTransferTimeMinutes = 0;
  static const double defaultAdvancedTransferTimeFactor = 1.0;
  static const double defaultAdvancedPedestrianSpeedKmh = 5.0;
  static const int defaultAdvancedMaxWalkingTimeMinutes = 60;
  static const double defaultAdvancedCyclingSpeedKmh = 16.0;

  // API endpoints
  static const String _motisUrl = 'https://api.transitous.org';
  static const String _v6Url = 'https://v6.db.transport.rest';
  static const String _bahnWebUrl = 'https://www.bahn.de';
  static const String loadPhaseMotis = 'motis';
  static const String loadPhaseV6 = 'v6';
  static const String loadPhaseSynthetic = 'synthetic';
  static const String sourceTransitous = 'transitous';
  static const String sourceSyntheticTransitous = 'synthetic_transitous';
  static const String sourceDbV6 = 'db_v6';
  static const List<String> defaultEnabledSources = <String>[
    sourceTransitous,
    sourceSyntheticTransitous,
  ];

  static Set<String> enabledSources = Set<String>.from(defaultEnabledSources);

  // In-memory caches with TTL
  static final Map<String, _CacheEntry<List<Station>>> _stationCache = {};
  static final Map<String, _CacheEntry<List<Station>>> _nearbyCache = {};
  static final Map<String, Future<List<Station>>> _stationSearchInFlight = {};
  static final Map<String, _CacheEntry<List<Map<String, dynamic>>>>
      _syntheticStopDeparturesCache = {};
  static final Map<String, _CacheEntry<Map<String, dynamic>?>>
      _tripItineraryCache = {};
  static final Map<String, Future<Map<String, dynamic>?>>
      _tripItineraryInFlight = {};
  static final Map<String, _CacheEntry<List<Map<String, dynamic>>>>
      _stopEventsCache = {};
  static final Map<String, _CacheEntry<List<Map<String, dynamic>>>>
      _bahnBoardCache = {};
  static final Map<String, _CacheEntry<String?>> _bahnEvaCache = {};
  static final List<String> _syntheticDebugBuffer = <String>[];

  // Cache the User-Agent
  static String? _userAgent;
  static bool _advancedSettingsLoaded = false;
  static bool _advancedSettingsEnabledForDevice = false;
  static int _advancedMinTransferTimeMinutes =
      defaultAdvancedMinTransferTimeMinutes;
  static int _advancedAdditionalTransferTimeMinutes =
      defaultAdvancedAdditionalTransferTimeMinutes;
  static double _advancedTransferTimeFactor = defaultAdvancedTransferTimeFactor;
  static bool _advancedPreTransitWalkEnabled = true;
  static bool _advancedPreTransitBikeEnabled = false;
  static bool _advancedPostTransitWalkEnabled = true;
  static bool _advancedPostTransitBikeEnabled = false;
  static double _advancedCyclingSpeedKmh = defaultAdvancedCyclingSpeedKmh;
  static double _advancedPedestrianSpeedKmh = defaultAdvancedPedestrianSpeedKmh;
  static int _advancedMaxWalkingTimeMinutes =
      defaultAdvancedMaxWalkingTimeMinutes;
  static bool _advancedBikeToggleEnabledForDevice = false;
  static DateTime? _v6StationsCooldownUntil;
  static const Duration _syntheticStopDeparturesCacheTtl = Duration(minutes: 2);
  static const Duration _tripItineraryCacheTtl = Duration(minutes: 10);
  static const Duration _stopEventsCacheTtl = Duration(minutes: 2);
  static const Duration _bahnBoardCacheTtl = Duration(minutes: 2);
  static const Duration _bahnEvaCacheTtl = Duration(days: 7);
  static const Duration _syntheticTransferSlack = Duration(seconds: 15);
  static const int _syntheticOnwardResultsPerDeparture = 1;
  static const int _syntheticProgressBatchSize = 4;
  static const int _defaultStationSearchLimit = 20;
  static const int _expandedStationSearchLimit = 60;
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
  // Transitous defaults first/last street legs to 15 minutes (900s).
  // Use 60 minutes so routes requiring longer access/egress walks are found.
  static const int _motisMaxPreTransitTimeSeconds = 3600;
  static const int _motisMaxPostTransitTimeSeconds = 3600;
  static const int _motisDirectFallbackMaxMinutes = 120;

  static void configureEnabledSources(Iterable<String> sources) {
    final normalized = Set<String>.from(sources);
    if (!normalized.contains(sourceTransitous)) {
      normalized.remove(sourceSyntheticTransitous);
    }
    if (normalized.isEmpty) {
      normalized.add(sourceTransitous);
      normalized.add(sourceSyntheticTransitous);
    }
    enabledSources = normalized;
  }

  static Set<String> enabledSourcesFromPreferences(SharedPreferences prefs) {
    final stored = prefs.getStringList(enabledApiSourcesPreferenceKey);
    if (stored != null) {
      final normalized = Set<String>.from(stored);
      if (!normalized.contains(sourceTransitous)) {
        normalized.remove(sourceSyntheticTransitous);
      }
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }

    final legacyMode = prefs.getString('api_mode');
    if (legacyMode == 'v6') {
      return <String>{sourceDbV6};
    }

    return Set<String>.from(defaultEnabledSources);
  }

  static bool get isTransitousEnabled =>
      enabledSources.contains(sourceTransitous);

  static bool get isSyntheticTransitousEnabled =>
      isTransitousEnabled && enabledSources.contains(sourceSyntheticTransitous);

  static bool get isDbV6Enabled => enabledSources.contains(sourceDbV6);

  static bool get usesOnlyDbV6 =>
      isDbV6Enabled && !isTransitousEnabled && !isSyntheticTransitousEnabled;

  static Future<void> _ensureAdvancedSettingsLoaded() async {
    if (_advancedSettingsLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    _advancedSettingsEnabledForDevice =
        prefs.getBool(advancedSettingsEnabledPreferenceKey) ?? false;
    final hasLegacyTransferComfort =
        prefs.containsKey(advancedTransferComfortPreferenceKey);
    final legacyTransferComfort = hasLegacyTransferComfort
        ? (prefs.getDouble(advancedTransferComfortPreferenceKey) ?? 0.5)
            .clamp(0.0, 1.0)
        : null;
    final hasLegacyBikePreference =
        prefs.containsKey(advancedBikePreferenceKey);
    final legacyBikePreference = hasLegacyBikePreference
        ? (prefs.getDouble(advancedBikePreferenceKey) ?? 0.0).clamp(0.0, 1.0)
        : null;
    _advancedMinTransferTimeMinutes =
        prefs.getInt(advancedMinTransferTimeMinutesPreferenceKey) ??
            (legacyTransferComfort != null
                ? (2 + (legacyTransferComfort * 5)).round()
                : defaultAdvancedMinTransferTimeMinutes);
    _advancedAdditionalTransferTimeMinutes =
        prefs.getInt(advancedAdditionalTransferTimeMinutesPreferenceKey) ??
            (legacyTransferComfort != null
                ? (legacyTransferComfort * 4).round()
                : defaultAdvancedAdditionalTransferTimeMinutes);
    _advancedTransferTimeFactor = (prefs.getDouble(
              advancedTransferTimeFactorPreferenceKey,
            ) ??
            (legacyTransferComfort != null
                ? (0.8 + (legacyTransferComfort * 1.0))
                : defaultAdvancedTransferTimeFactor))
        .clamp(0.7, 2.5);
    _advancedPreTransitWalkEnabled =
        prefs.getBool(advancedPreTransitWalkEnabledPreferenceKey) ?? true;
    _advancedPreTransitBikeEnabled =
        prefs.getBool(advancedPreTransitBikeEnabledPreferenceKey) ??
            (legacyBikePreference != null && legacyBikePreference > 0.01);
    _advancedPostTransitWalkEnabled =
        prefs.getBool(advancedPostTransitWalkEnabledPreferenceKey) ?? true;
    _advancedPostTransitBikeEnabled =
        prefs.getBool(advancedPostTransitBikeEnabledPreferenceKey) ??
            (legacyBikePreference != null && legacyBikePreference > 0.01);
    _advancedCyclingSpeedKmh = (prefs.getDouble(
              advancedCyclingSpeedKmhPreferenceKey,
            ) ??
            (legacyBikePreference != null
                ? ((3.2 + (legacyBikePreference * 2.4)) * 3.6)
                : defaultAdvancedCyclingSpeedKmh))
        .clamp(8.0, 30.0);
    _advancedPedestrianSpeedKmh = (prefs.getDouble(
              advancedPedestrianSpeedKmhPreferenceKey,
            ) ??
            defaultAdvancedPedestrianSpeedKmh)
        .clamp(2.0, 10.0);
    _advancedMaxWalkingTimeMinutes =
        prefs.getInt(advancedMaxWalkingTimeMinutesPreferenceKey) ??
            defaultAdvancedMaxWalkingTimeMinutes;
    _advancedBikeToggleEnabledForDevice =
        prefs.getBool(advancedBikeTogglePreferenceKey) ?? false;
    _advancedSettingsLoaded = true;
  }

  static void configureAdvancedSearchSettings({
    required bool enabledForDevice,
    required int minTransferTimeMinutes,
    required int additionalTransferTimeMinutes,
    required double transferTimeFactor,
    required bool preTransitWalkEnabled,
    required bool preTransitBikeEnabled,
    required bool postTransitWalkEnabled,
    required bool postTransitBikeEnabled,
    required double cyclingSpeedKmh,
    required double pedestrianSpeedKmh,
    required int maxWalkingTimeMinutes,
  }) {
    _advancedSettingsEnabledForDevice = enabledForDevice;
    _advancedMinTransferTimeMinutes = minTransferTimeMinutes.clamp(0, 30);
    _advancedAdditionalTransferTimeMinutes =
        additionalTransferTimeMinutes.clamp(0, 30);
    _advancedTransferTimeFactor = transferTimeFactor.clamp(0.7, 2.5);
    _advancedPreTransitWalkEnabled = preTransitWalkEnabled;
    _advancedPreTransitBikeEnabled = preTransitBikeEnabled;
    _advancedPostTransitWalkEnabled = postTransitWalkEnabled;
    _advancedPostTransitBikeEnabled = postTransitBikeEnabled;
    _advancedCyclingSpeedKmh = cyclingSpeedKmh.clamp(8.0, 30.0);
    _advancedPedestrianSpeedKmh = pedestrianSpeedKmh.clamp(2.0, 10.0);
    _advancedMaxWalkingTimeMinutes = maxWalkingTimeMinutes.clamp(5, 120);
    _advancedSettingsLoaded = true;
  }

  static void setBikeToggleEnabledForDevice(bool enabled) {
    _advancedBikeToggleEnabledForDevice = enabled;
    _advancedSettingsLoaded = true;
  }

  static void _pruneExpiredCaches() {
    _pruneExpiredCache(_stationCache);
    _pruneExpiredCache(_nearbyCache);
    _pruneExpiredCache(_syntheticStopDeparturesCache);
    _pruneExpiredCache(_tripItineraryCache);
    _pruneExpiredCache(_stopEventsCache);
    _pruneExpiredCache(_bahnBoardCache);
    _pruneExpiredCache(_bahnEvaCache);
  }

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
    final uri = Uri.parse('$_v6Url$endpoint');
    if (params == null || params.isEmpty) return uri;

    return uri.replace(
      queryParameters: {
        for (final entry in params.entries)
          if (entry.value != null) entry.key: entry.value.toString(),
      },
    );
  }

  static Future<List<Station>> _searchStationsV6(
    String query, {
    double? lat,
    double? lng,
    int limit = _defaultStationSearchLimit,
  }) async {
    final Map<String, dynamic> params = {
      'query': query,
      'results': limit.clamp(1, _expandedStationSearchLimit),
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
      for (final journey in journeys) {
        attachV6LegPaths(journey);
      }
      // Post-filter: remove FlixBus/FlixTrain/IC Bus etc. when Deutschlandticket mode
      if (nahverkehrOnly) {
        journeys = _filterForDeutschlandticket(journeys);
      }
      return journeys;
    }
    return [];
  }

  /// Decodes the GeoJSON polyline v6.db returns for a leg (already requested
  /// via `polylines=true`, so this costs no extra round-trip) into the same
  /// `[[lat, lng], ...]` shape the MOTIS adapter produces.
  @visibleForTesting
  static List<List<double>>? decodeV6LegPath(Map<String, dynamic> leg) {
    final features = (leg['polyline'] as Map?)?['features'];
    if (features is! List) return null;

    final points = <List<double>>[];
    for (final feature in features) {
      if (feature is! Map) continue;
      final coordinates = (feature['geometry'] as Map?)?['coordinates'];
      if (coordinates is! List || coordinates.length < 2) continue;
      final lng = coordinates[0];
      final lat = coordinates[1];
      if (lat is! num || lng is! num) continue;
      points.add([lat.toDouble(), lng.toDouble()]);
    }
    return points.length < 2 ? null : points;
  }

  /// Adds `decodedPath` to every leg of a v6.db journey so the UI can read leg
  /// geometry the same way it does for MOTIS journeys.
  @visibleForTesting
  static void attachV6LegPaths(Map<String, dynamic> journey) {
    final legs = journey['legs'];
    if (legs is! List) return;
    for (final leg in legs) {
      if (leg is! Map<String, dynamic>) continue;
      if (leg['decodedPath'] != null) continue;
      final path = decodeV6LegPath(leg);
      if (path != null) leg['decodedPath'] = path;
    }
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

  static bool get _hasAdvancedSearchOverrides {
    if (!_advancedSettingsEnabledForDevice) return false;
    if (_advancedMinTransferTimeMinutes !=
        defaultAdvancedMinTransferTimeMinutes) {
      return true;
    }
    if (_advancedAdditionalTransferTimeMinutes !=
        defaultAdvancedAdditionalTransferTimeMinutes) {
      return true;
    }
    if ((_advancedTransferTimeFactor - defaultAdvancedTransferTimeFactor)
            .abs() >
        0.0001) {
      return true;
    }
    if ((_advancedPedestrianSpeedKmh - defaultAdvancedPedestrianSpeedKmh)
            .abs() >
        0.0001) {
      return true;
    }
    if (_advancedMaxWalkingTimeMinutes !=
        defaultAdvancedMaxWalkingTimeMinutes) {
      return true;
    }
    final usesBikeForThisSearch = _usesPreTransitBike || _usesPostTransitBike;
    return !_advancedPreTransitWalkEnabled ||
        !_advancedPostTransitWalkEnabled ||
        usesBikeForThisSearch;
  }

  static bool get _usesPreTransitBike =>
      _advancedSettingsEnabledForDevice &&
      _advancedPreTransitBikeEnabled &&
      _advancedBikeToggleEnabledForDevice;

  static bool get _usesPostTransitBike =>
      _advancedSettingsEnabledForDevice &&
      _advancedPostTransitBikeEnabled &&
      _advancedBikeToggleEnabledForDevice;

  static List<String> _motisDirectModesForCurrentSettings() {
    if (!_advancedSettingsEnabledForDevice) {
      return const <String>['WALK'];
    }

    final modes = <String>[];
    if (_advancedPreTransitWalkEnabled || _advancedPostTransitWalkEnabled) {
      modes.add('WALK');
    }
    if (_usesPreTransitBike || _usesPostTransitBike) {
      modes.add('BIKE');
    }

    if (modes.isEmpty) return const <String>['WALK'];
    return modes;
  }

  static Map<String, dynamic> _buildMotisJourneySearchParams(
    Station from,
    Station to, {
    bool nahverkehrOnly = false,
    DateTime? when,
    bool isArrival = false,
    int results = 3,
    int? minTransferTimeMinutesOverride,
    int? additionalTransferTimeMinutesOverride,
    double? transferTimeFactorOverride,
    double? pedestrianSpeedKmhOverride,
    int? maxWalkingTimeMinutesOverride,
  }) {
    final Map<String, dynamic> params = {
      'numItineraries': results.toString(),
      'detailedTransfers': 'true',
      'showIntermediateStops': 'true',
      'maxPreTransitTime': _motisMaxPreTransitTimeSeconds.toString(),
      'maxPostTransitTime': _motisMaxPostTransitTimeSeconds.toString(),
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

    if (_advancedSettingsEnabledForDevice) {
      final minTransferTimeMinutes =
          minTransferTimeMinutesOverride ?? _advancedMinTransferTimeMinutes;
      if (minTransferTimeMinutes != defaultAdvancedMinTransferTimeMinutes) {
        params['minTransferTime'] = minTransferTimeMinutes.toString();
      }
      final additionalTransferTimeMinutes =
          additionalTransferTimeMinutesOverride ??
              _advancedAdditionalTransferTimeMinutes;
      if (additionalTransferTimeMinutes !=
          defaultAdvancedAdditionalTransferTimeMinutes) {
        params['additionalTransferTime'] =
            additionalTransferTimeMinutes.toString();
      }
      final transferTimeFactor =
          transferTimeFactorOverride ?? _advancedTransferTimeFactor;
      if ((transferTimeFactor - defaultAdvancedTransferTimeFactor).abs() >
          0.0001) {
        params['transferTimeFactor'] = transferTimeFactor.toStringAsFixed(2);
      }

      final pedestrianSpeedKmh =
          pedestrianSpeedKmhOverride ?? _advancedPedestrianSpeedKmh;
      if ((pedestrianSpeedKmh - defaultAdvancedPedestrianSpeedKmh).abs() >
          0.0001) {
        final pedestrianSpeedMps = (pedestrianSpeedKmh / 3.6).clamp(0.55, 2.8);
        params['pedestrianSpeed'] = pedestrianSpeedMps.toStringAsFixed(2);
      }

      final maxWalkingTimeMinutes =
          maxWalkingTimeMinutesOverride ?? _advancedMaxWalkingTimeMinutes;
      if (maxWalkingTimeMinutes != defaultAdvancedMaxWalkingTimeMinutes) {
        final maxWalkingTimeSeconds =
            (maxWalkingTimeMinutes.clamp(5, 120) * 60);
        params['maxPreTransitTime'] = maxWalkingTimeSeconds.toString();
        params['maxPostTransitTime'] = maxWalkingTimeSeconds.toString();
      }

      final useBikeForThisSearch = _usesPreTransitBike || _usesPostTransitBike;
      final hasModeOverride = !_advancedPreTransitWalkEnabled ||
          !_advancedPostTransitWalkEnabled ||
          useBikeForThisSearch;
      if (hasModeOverride) {
        final preModes = <String>[];
        final postModes = <String>[];

        if (_advancedPreTransitWalkEnabled) preModes.add('WALK');
        if (_advancedPostTransitWalkEnabled) postModes.add('WALK');
        if (_usesPreTransitBike) {
          preModes.add('BIKE');
        }
        if (_usesPostTransitBike) {
          postModes.add('BIKE');
        }

        // Avoid invalid empty mode sets. If all options are off, fall back to WALK.
        if (preModes.isEmpty) preModes.add('WALK');
        if (postModes.isEmpty) postModes.add('WALK');

        params['preTransitModes'] = preModes.join(',');
        params['postTransitModes'] = postModes.join(',');

        if (useBikeForThisSearch) {
          final cyclingSpeedMps =
              (_advancedCyclingSpeedKmh / 3.6).clamp(1.5, 8.5);
          params['cyclingSpeed'] = cyclingSpeedMps.toStringAsFixed(2);
        }
      }
    }

    return params;
  }

  static Map<String, dynamic> _buildMotisDirectJourneySearchParams(
    Station from,
    Station to, {
    DateTime? when,
    bool isArrival = false,
    int results = 3,
  }) {
    final params = _buildMotisJourneySearchParams(
      from,
      to,
      when: when,
      isArrival: isArrival,
      results: results,
    );

    if (from.latitude != null && from.longitude != null) {
      params['fromPlace'] = '${from.latitude},${from.longitude}';
    }
    if (to.latitude != null && to.longitude != null) {
      params['toPlace'] = '${to.latitude},${to.longitude}';
    }

    final directModes = _motisDirectModesForCurrentSettings();

    params
      ..remove('transitModes')
      ..remove('preTransitModes')
      ..remove('postTransitModes')
      ..remove('maxPreTransitTime')
      ..remove('maxPostTransitTime')
      ..remove('minTransferTime')
      ..remove('additionalTransferTime')
      ..remove('transferTimeFactor')
      ..remove('pedestrianSpeed')
      ..remove('cyclingSpeed')
      ..['directModes'] = directModes.join(',')
      ..['maxDirectTime'] = (_motisDirectFallbackMaxMinutes * 60).toString()
      ..addAll({
        if (directModes.contains('WALK'))
          'pedestrianSpeed': (_advancedPedestrianSpeedKmh / 3.6)
              .clamp(0.55, 2.8)
              .toStringAsFixed(2),
        if (directModes.contains('BIKE'))
          'cyclingSpeed': (_advancedCyclingSpeedKmh / 3.6)
              .clamp(1.5, 8.5)
              .toStringAsFixed(2),
      });

    return params;
  }

  static Future<List<Station>> _searchStationsMotis(
    String query, {
    double? lat,
    double? lng,
    int limit = _defaultStationSearchLimit,
  }) async {
    final Map<String, dynamic> params = {
      'text': query,
      'limit': limit.clamp(1, _expandedStationSearchLimit),
    };

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
    int? minTransferTimeMinutesOverride,
    int? additionalTransferTimeMinutesOverride,
    double? transferTimeFactorOverride,
    double? pedestrianSpeedKmhOverride,
    int? maxWalkingTimeMinutesOverride,
  }) async {
    await _ensureAdvancedSettingsLoaded();
    final params = _buildMotisJourneySearchParams(
      from,
      to,
      nahverkehrOnly: nahverkehrOnly,
      when: when,
      isArrival: isArrival,
      results: results,
      minTransferTimeMinutesOverride: minTransferTimeMinutesOverride,
      additionalTransferTimeMinutesOverride:
          additionalTransferTimeMinutesOverride,
      transferTimeFactorOverride: transferTimeFactorOverride,
      pedestrianSpeedKmhOverride: pedestrianSpeedKmhOverride,
      maxWalkingTimeMinutesOverride: maxWalkingTimeMinutesOverride,
    );

    final response = await _fetch(_getMotisPlanUri(params));
    final data = json.decode(response.body);
    final journeys = decodeMotisPlanJourneys(data);
    return journeys;
  }

  static Future<List<Map<String, dynamic>>> _searchDirectJourneysMotis(
    Station from,
    Station to, {
    DateTime? when,
    bool isArrival = false,
    int results = 3,
  }) async {
    await _ensureAdvancedSettingsLoaded();
    final params = _buildMotisDirectJourneySearchParams(
      from,
      to,
      when: when,
      isArrival: isArrival,
      results: results,
    );

    final response = await _fetch(_getMotisPlanUri(params));
    final data = json.decode(response.body);
    final directJourneys = decodeMotisDirectPlanJourneys(data);
    _syntheticLog('direct fallback result: routes=${directJourneys.length}');
    return directJourneys;
  }

  /// Retry empty MOTIS search with safer walking parameters for edge-case
  /// combinations where high walking speed / short pre-post windows can
  /// suppress otherwise valid itineraries.
  static Future<List<Map<String, dynamic>>> _searchJourneysMotisWithFallback({
    required Station from,
    required Station to,
    required bool nahverkehrOnly,
    required DateTime? when,
    required bool isArrival,
    required int results,
    int? minTransferTimeMinutesOverride,
    int? additionalTransferTimeMinutesOverride,
    double? transferTimeFactorOverride,
    double? pedestrianSpeedKmhOverride,
    int? maxWalkingTimeMinutesOverride,
    bool allowDirectFallback = true,
  }) async {
    final primary = await _searchJourneysMotis(
      from,
      to,
      nahverkehrOnly: nahverkehrOnly,
      when: when,
      isArrival: isArrival,
      results: results,
      minTransferTimeMinutesOverride: minTransferTimeMinutesOverride,
      additionalTransferTimeMinutesOverride:
          additionalTransferTimeMinutesOverride,
      transferTimeFactorOverride: transferTimeFactorOverride,
      pedestrianSpeedKmhOverride: pedestrianSpeedKmhOverride,
      maxWalkingTimeMinutesOverride: maxWalkingTimeMinutesOverride,
    );
    if (primary.isNotEmpty) return primary;

    await _ensureAdvancedSettingsLoaded();
    if (_hasAdvancedSearchOverrides) {
      // Some provider/network combinations are unstable in narrow speed bands.
      // Retry using conservative, known-stable walking speeds and wider
      // first/last-mile windows before giving up.
      final retries = <(double speedKmh, int walkMinutes)>[
        (4.3, math.max(_advancedMaxWalkingTimeMinutes, 60)),
        (4.5, math.max(_advancedMaxWalkingTimeMinutes, 60)),
        (4.3, math.max(_advancedMaxWalkingTimeMinutes, 120)),
      ];
      final attemptedKeys = <String>{};

      for (final retry in retries) {
        final key = '${retry.$1.toStringAsFixed(1)}:${retry.$2.toString()}';
        if (!attemptedKeys.add(key)) continue;

        _syntheticLog(
          'motis retry: empty primary, fallback pedestrianSpeed='
          '${retry.$1.toStringAsFixed(1)}km/h '
          'maxWalk=${retry.$2}min',
        );

        final fallback = await _searchJourneysMotis(
          from,
          to,
          nahverkehrOnly: nahverkehrOnly,
          when: when,
          isArrival: isArrival,
          results: results,
          minTransferTimeMinutesOverride: minTransferTimeMinutesOverride,
          additionalTransferTimeMinutesOverride:
              additionalTransferTimeMinutesOverride,
          transferTimeFactorOverride: transferTimeFactorOverride,
          pedestrianSpeedKmhOverride: retry.$1,
          maxWalkingTimeMinutesOverride: retry.$2,
        );
        _syntheticLog(
          'motis retry result: speed=${retry.$1.toStringAsFixed(1)} '
          'maxWalk=${retry.$2}min itineraries=${fallback.length}',
        );
        if (fallback.isNotEmpty) return fallback;
      }
    }

    if (allowDirectFallback) {
      _syntheticLog('direct fallback: empty public transport results');
      final direct = await _searchDirectJourneysMotis(
        from,
        to,
        when: when,
        isArrival: isArrival,
        results: results,
      );
      if (direct.isNotEmpty) return direct;
    }

    return primary;
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
    int limit = _defaultStationSearchLimit,
  }) async {
    _pruneExpiredCaches();
    final sanitizedQuery = _sanitizeStationQuery(query);
    if (sanitizedQuery.isEmpty) return [];

    // Check cache first
    final cacheKey = 'stations:$sanitizedQuery:$lat:$lng:$limit';
    final cached = _readCache(_stationCache, cacheKey);
    if (cached != null) {
      debugPrint('Cache hit for stations: $sanitizedQuery');
      return cached;
    }

    final inFlight = _stationSearchInFlight[cacheKey];
    if (inFlight != null) return inFlight;

    final future = _searchStationsInternal(
      sanitizedQuery,
      cacheKey,
      lat: lat,
      lng: lng,
      limit: limit,
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
    int limit = _defaultStationSearchLimit,
  }) async {
    if (usesOnlyDbV6) {
      final result = await _searchStationsV6(
        query,
        lat: lat,
        lng: lng,
        limit: limit,
      );
      final ranked = rankStationsForQuery(result, query, lat: lat, lng: lng);
      _writeCache(_stationCache, cacheKey, ranked, const Duration(hours: 1));
      return ranked;
    }

    List<Station> motisResults = [];
    try {
      motisResults = await _searchStationsMotisExpanded(
        query,
        lat: lat,
        lng: lng,
        limit: limit,
      );
    } catch (error) {
      debugPrint('Transitous searchStations failed: $error');
    }

    final rankedMotis = rankStationsForQuery(
      motisResults,
      query,
      lat: lat,
      lng: lng,
    );

    if (!isDbV6Enabled) {
      _writeCache(
        _stationCache,
        cacheKey,
        rankedMotis,
        const Duration(hours: 1),
      );
      return rankedMotis;
    }

    // Keep v6 as an empty-result fallback only. Synthetic expansion stays on
    // Transitous by combining biased and unbiased result pools.
    if (rankedMotis.isNotEmpty) {
      _writeCache(
        _stationCache,
        cacheKey,
        rankedMotis,
        const Duration(hours: 1),
      );
      return rankedMotis;
    }

    final v6Results = await _searchStationsV6WithCooldown(
      query,
      lat: lat,
      lng: lng,
      limit: limit,
    );
    final ranked = rankStationsForQuery(v6Results, query, lat: lat, lng: lng);
    _writeCache(_stationCache, cacheKey, ranked, const Duration(hours: 1));
    return ranked;
  }

  static Future<List<Station>> _searchStationsMotisExpanded(
    String query, {
    double? lat,
    double? lng,
    required int limit,
  }) async {
    var results = await _searchStationsMotisQuerySet(
      query,
      lat: lat,
      lng: lng,
      limit: limit,
    );

    final shouldTryWithoutBias = shouldSupplementSparseStationResults(
      query,
      currentCount: results.length,
      requestedLimit: limit,
      hasLocationBias: lat != null && lng != null,
    );

    if (shouldTryWithoutBias) {
      final unbiasedResults = await _searchStationsMotisQuerySet(
        query,
        limit: limit,
      );
      results = _mergeStationSearchResults(results, unbiasedResults);
    }

    return results;
  }

  static Future<List<Station>> _searchStationsMotisQuerySet(
    String query, {
    double? lat,
    double? lng,
    required int limit,
  }) async {
    var results = await _searchStationsMotis(
      query,
      lat: lat,
      lng: lng,
      limit: limit,
    );
    for (final alternateQuery in _alternateStationQueries(query)) {
      final alternateResults = await _searchStationsMotis(
        alternateQuery,
        lat: lat,
        lng: lng,
        limit: limit,
      );
      results = _mergeStationSearchResults(results, alternateResults);
    }
    return results;
  }

  static Future<List<Station>> _searchStationsV6WithCooldown(
    String query, {
    double? lat,
    double? lng,
    int limit = _defaultStationSearchLimit,
  }) async {
    final cooldownUntil = _v6StationsCooldownUntil;
    if (cooldownUntil != null && DateTime.now().isBefore(cooldownUntil)) {
      debugPrint(
        'Skipping v6 station search during cooldown for query: $query',
      );
      return const <Station>[];
    }

    try {
      return await _searchStationsV6(query, lat: lat, lng: lng, limit: limit);
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
    final cityTokens = _searchTokens(station.city ?? '');
    final regionTokens = _searchTokens(station.region ?? '');
    final countryTokens = _searchTokens(station.country ?? '');
    final categoryTokens = _searchTokens(station.category ?? '');
    final typeTokens = _searchTokens(station.type);
    final metadataTokens = <String>{
      ...cityTokens,
      ...regionTokens,
      ...countryTokens,
      ...categoryTokens,
      ...typeTokens,
    }.toList(growable: false);
    final isTransitStop = station.type == 'station' || station.type == 'stop';
    final isAirportQuery = _isAirportLikeQuery(queryTokens);
    final hasLocationBias = lat != null && lng != null;
    final isSingleTokenQuery = queryTokens.length == 1;
    final wantsSpecificAirportDetail =
        _queryRequestsSpecificAirportDetail(queryTokens);
    final expandedQueryTokens = _expandEquivalentSearchTokens(queryTokens);
    final queryLooksLikeStation = _isStationLikeQuery(queryTokens);

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
      final equivalentTokens = expandedQueryTokens[token] ?? <String>{token};
      final exactNameMatch = equivalentTokens.any(nameTokens.contains);
      final prefixNameMatch = equivalentTokens.any(
        (variant) => nameTokens.any(
          (nameToken) =>
              nameToken.startsWith(variant) || variant.startsWith(nameToken),
        ),
      );
      final exactCityMatch = equivalentTokens.any(cityTokens.contains);
      final prefixCityMatch = equivalentTokens.any(
        (variant) => cityTokens.any(
          (cityToken) =>
              cityToken.startsWith(variant) || variant.startsWith(cityToken),
        ),
      );
      final categoryMatch = equivalentTokens.any(categoryTokens.contains) ||
          equivalentTokens.any(typeTokens.contains) ||
          equivalentTokens.any(countryTokens.contains);
      final weakRegionMatch = equivalentTokens.any(regionTokens.contains);

      if (exactNameMatch) {
        matchedQueryTokens++;
        score += equivalentTokens.length > 1 ? 60 : 55;
      } else if (prefixNameMatch) {
        matchedQueryTokens++;
        score += 24;
      } else if (exactCityMatch) {
        matchedQueryTokens++;
        score += 42;
      } else if (prefixCityMatch) {
        matchedQueryTokens++;
        score += 18;
      } else if (categoryMatch) {
        matchedQueryTokens++;
        score += 10;
      } else if (weakRegionMatch) {
        score += 3;
      }
    }

    if (matchedQueryTokens == queryTokens.length) {
      score += 75;
    }

    if (isTransitStop) {
      score += 105;
      if (queryLooksLikeStation) score += 55;
    } else {
      if (station.type == 'location') score -= 25;
      if (station.type == 'address') score -= 55;
      if (queryLooksLikeStation) {
        if (station.type == 'location') score -= 95;
        if (station.type == 'address') score -= 120;
      }
    }

    if (_looksLikeTransitHub(normalizedName, nameTokens)) {
      score += 95;
    }
    if (station.searchImportance != null) {
      score += (station.searchImportance! * 140).round();
    }
    if (station.searchScore != null) {
      score += (-station.searchScore!).round();
    }
    if (queryLooksLikeStation &&
        !isTransitStop &&
        _looksLikeCommercialPoi(categoryTokens, nameTokens)) {
      score -= 140;
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
      if (_looksLikeAirportRailHub(normalizedName, nameTokens)) {
        score += 260;
      }
      if (station.type == 'address') score -= 140;
      if (_isGenericAirportLabel(normalizedName)) score -= 110;
      if (_looksLikeRoadOrNeighborhood(nameTokens)) score -= 95;
      if (!wantsSpecificAirportDetail &&
          _looksLikeOverSpecificAirportResult(normalizedName, nameTokens) &&
          !_looksLikeAirportRailHub(normalizedName, nameTokens)) {
        score -= 170;
      }
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

  static bool _looksLikeAirportRailHub(
    String normalizedName,
    List<String> nameTokens,
  ) {
    if (!_looksLikeAirport(nameTokens, nameTokens)) return false;
    return normalizedName.contains('bahnhof') ||
        normalizedName.contains('regionalbf') ||
        normalizedName.contains('fernbf') ||
        nameTokens.contains('bf') ||
        nameTokens.contains('hbf');
  }

  static bool _looksLikeOverSpecificAirportResult(
    String normalizedName,
    List<String> nameTokens,
  ) {
    if (RegExp(r'\bp\d{1,3}\b').hasMatch(normalizedName)) return true;
    if (RegExp(r'\bterminal\s*[0-9a-z]+\b').hasMatch(normalizedName)) {
      return true;
    }

    const detailTokens = {
      'gate',
      'pier',
      'stand',
      'parking',
      'park',
    };
    return nameTokens.any(detailTokens.contains);
  }

  static bool _queryRequestsSpecificAirportDetail(List<String> queryTokens) {
    if (queryTokens.any((token) => RegExp(r'^p\d{1,3}$').hasMatch(token))) {
      return true;
    }
    if (queryTokens.any((token) => RegExp(r'^[0-9]+[a-z]?$').hasMatch(token))) {
      return true;
    }
    return queryTokens.contains('terminal') ||
        queryTokens.contains('gate') ||
        queryTokens.contains('pier');
  }

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

  static bool _isStationLikeQuery(List<String> queryTokens) => queryTokens.any(
        (token) => _stationEquivalentTokens(token).length > 1,
      );

  @visibleForTesting
  static bool shouldSupplementSparseStationResults(
    String query, {
    required int currentCount,
    required int requestedLimit,
    bool hasLocationBias = true,
  }) {
    return _shouldSupplementSparseStationResults(
      _searchTokens(query),
      currentCount: currentCount,
      requestedLimit: requestedLimit,
      hasLocationBias: hasLocationBias,
    );
  }

  static bool _shouldSupplementSparseStationResults(
    List<String> queryTokens, {
    required int currentCount,
    required int requestedLimit,
    required bool hasLocationBias,
  }) {
    if (!hasLocationBias) return false;
    if (currentCount <= 0) return true;
    if (currentCount >= requestedLimit) return false;
    if (queryTokens.isEmpty) return false;

    final stationLike = _isStationLikeQuery(queryTokens);
    final broadQuery = queryTokens.length <= 2;
    if (!stationLike && !broadQuery) return false;

    final minimumUsefulResults = math.min(12, requestedLimit);
    return currentCount < minimumUsefulResults;
  }

  static Map<String, Set<String>> _expandEquivalentSearchTokens(
    List<String> tokens,
  ) {
    return {
      for (final token in tokens) token: _stationEquivalentTokens(token),
    };
  }

  static Set<String> _stationEquivalentTokens(String token) {
    switch (token) {
      case 'hbf':
      case 'hauptbahnhof':
        return {'hbf', 'hauptbahnhof'};
      case 'bf':
      case 'bahnhof':
        return {'bf', 'bahnhof'};
      default:
        return {token};
    }
  }

  static bool _looksLikeCommercialPoi(
    List<String> categoryTokens,
    List<String> nameTokens,
  ) {
    const commercialTokens = {
      'shop',
      'mall',
      'retail',
      'supermarket',
      'commercial',
      'einkaufsbahnhof',
    };
    return categoryTokens.any(commercialTokens.contains) ||
        nameTokens.any(commercialTokens.contains);
  }

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

  static List<String> _alternateStationQueries(String query) {
    final sanitized = _sanitizeStationQuery(query);
    if (sanitized.isEmpty) return const <String>[];

    final lower = sanitized.toLowerCase();
    final alternates = <String>{};
    if (lower.contains('airport')) {
      alternates.add(
        sanitized.replaceAll(
          RegExp('airport', caseSensitive: false),
          'Flughafen',
        ),
      );
    }
    if (lower.contains('flughafen')) {
      alternates.add(
        sanitized.replaceAll(
          RegExp('flughafen', caseSensitive: false),
          'Airport',
        ),
      );
    }
    alternates.removeWhere((value) => value.trim().toLowerCase() == lower);
    return alternates.toList(growable: false);
  }

  static List<Station> _mergeStationSearchResults(
    List<Station> primary,
    List<Station> secondary,
  ) {
    if (primary.isEmpty) return secondary;
    if (secondary.isEmpty) return primary;

    final merged = <Station>[...primary];
    final seen = <String>{
      for (final station in primary) _stationDedupKey(station),
    };
    for (final station in secondary) {
      if (seen.add(_stationDedupKey(station))) {
        merged.add(station);
      }
    }
    return merged;
  }

  static String _stationDedupKey(Station station) {
    final id = station.id.trim();
    if (id.isNotEmpty) return 'id:$id';

    final lat =
        station.latitude != null ? station.latitude!.toStringAsFixed(4) : '';
    final lng =
        station.longitude != null ? station.longitude!.toStringAsFixed(4) : '';
    final city = _normalizeSearchText(station.city ?? '');
    final name = _normalizeSearchText(station.name);
    return 'name:$name|city:$city|lat:$lat|lng:$lng';
  }

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

  static String? _platformFromPlace(Map<String, dynamic>? place) {
    final platform =
        place?['track'] ?? place?['scheduledTrack'] ?? place?['platform'];
    final normalized = platform?.toString().trim();
    if (normalized == null || normalized.isEmpty) return null;
    return normalized;
  }

  /// Matches a label that names several tracks at once ("Gleis1/11").
  static final RegExp _multiTrackLabelPattern = RegExp(r'\d+\s*[/&+-]\s*\d+');

  /// Some feeds (DELFI at Mainz Hbf, for example) model a whole platform area
  /// as one stop and pin every trip to it, so the track we get names one
  /// arbitrary track of that area rather than the one the train uses. Such a
  /// track is worth a second opinion.
  static bool _platformLooksLikeTrackArea(Map<String, dynamic>? place) {
    final platform = _platformFromPlace(place);
    if (platform == null) return false;
    final label = _stringOrNull(place?['description']) ??
        _stringOrNull(place?['stopLabel']);
    if (label == null || !_multiTrackLabelPattern.hasMatch(label)) return false;
    return RegExp(r'[A-Za-z0-9]+')
        .allMatches(label)
        .map((match) => match.group(0)!.toLowerCase())
        .contains(platform.toLowerCase());
  }

  static String? _stopLabelFromPlace(Map<String, dynamic>? place) {
    final description = place?['description']?.toString().trim();
    if (description != null && description.isNotEmpty) {
      final normalizedName = place?['name']?.toString().trim();
      if (normalizedName == null || normalizedName != description) {
        return description;
      }
    }

    final stopLabel = place?['stopLabel']?.toString().trim();
    if (stopLabel == null || stopLabel.isEmpty) return null;
    return stopLabel;
  }

  static String? _platformFromStopEvent(Map<String, dynamic> dep) {
    final place = (dep['place'] as Map?)?.cast<String, dynamic>();
    final platform = _platformFromPlace(place) ??
        dep['platform']?.toString().trim() ??
        dep['plannedPlatform']?.toString().trim();
    if (platform == null || platform.isEmpty) return null;
    return platform;
  }

  static DateTime? _journeyLegTimeLocal(
    Map<String, dynamic> leg,
    String plannedKey,
    String realtimeKey,
  ) {
    final raw = leg[plannedKey] ?? leg[realtimeKey];
    if (raw == null) return null;
    try {
      return DateTime.parse(raw.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }

  static String _journeyLegLineDisplayName(Map<String, dynamic> leg) {
    final line = (leg['line'] as Map?)?.cast<String, dynamic>();
    final name = line?['name']?.toString().trim();
    if (name != null && name.isNotEmpty) return name;
    return '';
  }

  static String _journeyLegHeadsign(Map<String, dynamic> leg) {
    final headsign = leg['direction']?.toString().trim();
    if (headsign != null && headsign.isNotEmpty) return headsign;
    return '';
  }

  static DateTime? _stopEventBestTimeLocal(Map<String, dynamic> dep) {
    final departure = dep['departure'];
    if (departure is Map<String, dynamic>) {
      final raw = departure['scheduledTime'] ?? departure['time'];
      if (raw is String && raw.isNotEmpty) {
        try {
          return DateTime.parse(raw).toLocal();
        } catch (_) {}
      }
    }

    final arrival = dep['arrival'];
    if (arrival is Map<String, dynamic>) {
      final raw = arrival['scheduledTime'] ?? arrival['time'];
      if (raw is String && raw.isNotEmpty) {
        try {
          return DateTime.parse(raw).toLocal();
        } catch (_) {}
      }
    }

    return _stopDepartureDateTimeLocal(dep);
  }

  static DateTime? _stopEventTime(
    Map<String, dynamic> event, {
    required bool arrival,
  }) {
    final place = (event['place'] as Map?)?.cast<String, dynamic>();
    final timing = (event[arrival ? 'arrival' : 'departure'] as Map?)
        ?.cast<String, dynamic>();
    final candidates = arrival
        ? <Object?>[
            place?['scheduledArrival'],
            place?['arrival'],
            timing?['scheduledTime'],
            timing?['time'],
          ]
        : <Object?>[
            place?['scheduledDeparture'],
            place?['departure'],
            timing?['scheduledTime'],
            timing?['time'],
          ];
    for (final candidate in candidates) {
      final parsed = _parseJourneyTimeLocal(candidate);
      if (parsed != null) return parsed;
    }
    return null;
  }

  static String _stopEventLineName(Map<String, dynamic> event) {
    final displayName = _stringOrNull(event['displayName']);
    if (displayName != null) return displayName;
    final routeShortName = _stringOrNull(event['routeShortName']);
    if (routeShortName != null) return routeShortName;
    return _stringOrNull(
          (event['line'] as Map<String, dynamic>?)?['name'],
        ) ??
        '';
  }

  static String _stopEventRouteKey(Map<String, dynamic> event) {
    final routeShortName = _stringOrNull(event['routeShortName']);
    if (routeShortName != null) return _normalizeTransitKey(routeShortName);
    return _normalizeTransitKey(
      _stopEventLineName(event).replaceAll(RegExp(r'\s*\(\d+\)'), ''),
    );
  }

  static String _namedPlaceKey(Object? value) {
    if (value is! Map) return '';
    final place = value.cast<dynamic, dynamic>();
    final id = _stringOrNull(place['stopId']) ?? _stringOrNull(place['id']);
    if (id != null) return 'id:$id';
    return _normalizeTransitKey(place['name']);
  }

  static bool _samePresentText(Object? left, Object? right) {
    final a = _normalizeTransitKey(left);
    final b = _normalizeTransitKey(right);
    return a.isEmpty || b.isEmpty || a == b;
  }

  static String? _coupledLineDisplayNameFromStopEvents(
    Iterable<Map<String, dynamic>> events, {
    required Map<String, dynamic> leg,
    required DateTime? expectedTime,
  }) {
    final eventList = events.toList();
    final selected = _matchStopEventForLeg(
      eventList,
      leg: leg,
      expectedTime: expectedTime,
    );
    if (selected == null) return null;

    final selectedDeparture = _stopEventTime(selected, arrival: false);
    if (selectedDeparture == null) return null;
    final selectedArrival = _stopEventTime(selected, arrival: true);
    final selectedRouteKey = _stopEventRouteKey(selected);
    final selectedTripTo = _namedPlaceKey(selected['tripTo']);
    final selectedTripFrom = _namedPlaceKey(selected['tripFrom']);
    final selectedPlatform = _platformFromStopEvent(selected);

    final companionNames = <String>[];
    final seenRouteKeys = <String>{selectedRouteKey};
    for (final candidate in eventList) {
      if (identical(candidate, selected)) continue;
      final candidateRouteKey = _stopEventRouteKey(candidate);
      if (candidateRouteKey.isEmpty ||
          seenRouteKeys.contains(candidateRouteKey)) {
        continue;
      }
      if (_stopEventTime(candidate, arrival: false) != selectedDeparture) {
        continue;
      }
      if (!_samePresentText(candidate['headsign'], selected['headsign']) ||
          !_samePresentText(candidate['agencyName'], selected['agencyName']) ||
          !_samePresentText(candidate['mode'], selected['mode'])) {
        continue;
      }

      final candidateTripTo = _namedPlaceKey(candidate['tripTo']);
      if (selectedTripTo.isEmpty ||
          candidateTripTo.isEmpty ||
          candidateTripTo != selectedTripTo) {
        continue;
      }

      final candidateArrival = _stopEventTime(candidate, arrival: true);
      if (selectedArrival != null) {
        // Two service numbers arriving and departing together are the strong
        // signal that they are portions of the same physical train.
        if (candidateArrival != selectedArrival) continue;
      } else {
        final candidateTripFrom = _namedPlaceKey(candidate['tripFrom']);
        if (selectedTripFrom.isEmpty ||
            candidateTripFrom.isEmpty ||
            candidateTripFrom != selectedTripFrom) {
          continue;
        }
      }

      final candidatePlatform = _platformFromStopEvent(candidate);
      if (selectedPlatform != null &&
          candidatePlatform != null &&
          candidatePlatform != selectedPlatform) {
        continue;
      }

      final candidateName = _stopEventLineName(candidate);
      if (candidateName.isNotEmpty) {
        seenRouteKeys.add(candidateRouteKey);
        companionNames.add(candidateName);
      }
    }

    if (companionNames.isEmpty) return null;
    final selectedName = _stopEventLineName(selected);
    if (selectedName.isEmpty) return null;
    // Put the companion first: this is often the number shown on the front of
    // the coupled train, while the selected journey uses the other portion.
    return [...companionNames, selectedName].join(' / ');
  }

  @visibleForTesting
  static String? coupledLineDisplayNameFromStopEventsForTesting(
    Iterable<Map<String, dynamic>> events, {
    required Map<String, dynamic> leg,
    required DateTime? expectedTime,
  }) =>
      _coupledLineDisplayNameFromStopEvents(
        events,
        leg: leg,
        expectedTime: expectedTime,
      );

  static Duration? _eventTimeDistance(
    Map<String, dynamic> dep,
    DateTime? expectedTime,
  ) {
    if (expectedTime == null) return null;
    final eventTime = _stopEventBestTimeLocal(dep);
    if (eventTime == null) return null;
    return eventTime.difference(expectedTime).abs();
  }

  static bool _transitLineKeysMatch(String left, String right) {
    if (left.isEmpty || right.isEmpty) return false;
    if (left == right) return true;
    return left.startsWith('$right ') || right.startsWith('$left ');
  }

  static Set<String> _transitLineNumberTokens(String value) {
    return RegExp(r'\d+[A-Z]?')
        .allMatches(value)
        .map((match) => match.group(0) ?? '')
        .where((token) => token.isNotEmpty)
        .toSet();
  }

  static bool _transitLineKeysLikelyMatch(String left, String right) {
    if (_transitLineKeysMatch(left, right)) return true;
    final leftNumbers = _transitLineNumberTokens(left);
    if (leftNumbers.isEmpty) return false;
    final rightNumbers = _transitLineNumberTokens(right);
    return rightNumbers.any(leftNumbers.contains);
  }

  static bool _journeyLegLooksRail(Map<String, dynamic> leg) {
    final mode = normalizeServiceText(leg['mode']);
    const railModes = {
      'HIGHSPEED RAIL',
      'LONG DISTANCE',
      'NIGHT RAIL',
      'REGIONAL FAST RAIL',
      'REGIONAL RAIL',
      'SUBURBAN',
    };
    if (railModes.contains(mode)) return true;

    final line = (leg['line'] as Map?)?.cast<String, dynamic>();
    final productName = normalizeServiceText(line?['productName']);
    final product =
        normalizeServiceText(line?['product'] is Map ? null : line?['product']);
    final lineName = normalizeServiceText(line?['name']);
    const railTokens = ['ICE', 'IC', 'EC', 'ECE', 'RE', 'RB', 'S', 'IR'];
    return _containsAnyServiceToken(productName, railTokens) ||
        _containsAnyServiceToken(product, railTokens) ||
        _containsAnyServiceToken(lineName, railTokens);
  }

  static String? _matchPlatformFromStopEvents(
    Iterable<Map<String, dynamic>> events, {
    required Map<String, dynamic> leg,
    required DateTime? expectedTime,
  }) {
    final tripId = _journeyLegTripId(leg)?.trim();
    final lineKey = _normalizeTransitKey(_journeyLegLineDisplayName(leg));
    final directionKey = _normalizeTransitKey(_journeyLegHeadsign(leg));

    Map<String, dynamic>? bestLineMatch;
    Duration? bestLineDistance;

    for (final event in events) {
      final platform = _platformFromStopEvent(event);
      if (platform == null) continue;

      final eventTripId = _stopDepartureTripId(event)?.trim();
      if (tripId != null && tripId.isNotEmpty && eventTripId == tripId) {
        return platform;
      }

      final eventLineKey = _normalizeTransitKey(_stopDepartureLineKey(event));
      if (!_transitLineKeysLikelyMatch(lineKey, eventLineKey)) continue;

      final eventDirectionKey =
          _normalizeTransitKey(_stopDepartureDirectionKey(event));
      if (directionKey.isNotEmpty &&
          eventDirectionKey.isNotEmpty &&
          eventDirectionKey != directionKey) {
        continue;
      }

      final distance = _eventTimeDistance(event, expectedTime);
      if (distance != null && distance > const Duration(minutes: 5)) {
        continue;
      }

      if (bestLineMatch == null ||
          distance == null ||
          bestLineDistance == null ||
          distance < bestLineDistance) {
        bestLineMatch = event;
        bestLineDistance = distance;
      }
    }

    if (bestLineMatch == null) return null;
    return _platformFromStopEvent(bestLineMatch);
  }

  static Map<String, dynamic>? _matchStopEventForLeg(
    Iterable<Map<String, dynamic>> events, {
    required Map<String, dynamic> leg,
    required DateTime? expectedTime,
  }) {
    final tripId = _journeyLegTripId(leg)?.trim();
    final lineKey = _normalizeTransitKey(_journeyLegLineDisplayName(leg));
    final directionKey = _normalizeTransitKey(_journeyLegHeadsign(leg));

    Map<String, dynamic>? bestLineMatch;
    Duration? bestLineDistance;
    Map<String, dynamic>? exactTripWithoutPlatform;

    for (final event in events) {
      final eventPlace = (event['place'] as Map?)?.cast<String, dynamic>();
      if (eventPlace == null) continue;

      final eventTripId = _stopDepartureTripId(event)?.trim();
      if (tripId != null && tripId.isNotEmpty && eventTripId == tripId) {
        if (_platformFromStopEvent(event) != null ||
            _stopLabelFromPlace(eventPlace) != null) {
          return event;
        }
        exactTripWithoutPlatform ??= event;
        continue;
      }

      final eventLineKey = _normalizeTransitKey(_stopDepartureLineKey(event));
      if (!_transitLineKeysLikelyMatch(lineKey, eventLineKey)) continue;

      final eventDirectionKey =
          _normalizeTransitKey(_stopDepartureDirectionKey(event));
      if (directionKey.isNotEmpty &&
          eventDirectionKey.isNotEmpty &&
          eventDirectionKey != directionKey) {
        continue;
      }

      final distance = _eventTimeDistance(event, expectedTime);
      if (distance != null && distance > const Duration(minutes: 5)) {
        continue;
      }

      if (bestLineMatch == null ||
          distance == null ||
          bestLineDistance == null ||
          distance < bestLineDistance) {
        bestLineMatch = event;
        bestLineDistance = distance;
      }
    }

    return bestLineMatch ?? exactTripWithoutPlatform;
  }

  @visibleForTesting
  static String? matchPlatformFromStopEventsForTesting(
    Iterable<Map<String, dynamic>> events, {
    required Map<String, dynamic> leg,
    required DateTime? expectedTime,
  }) =>
      _matchPlatformFromStopEvents(
        events,
        leg: leg,
        expectedTime: expectedTime,
      );

  @visibleForTesting
  static ({
    String? platform,
    String? stopLabel,
    String? stopId,
    String? parentId,
  }) matchStopEventDetailsForTesting(
    Iterable<Map<String, dynamic>> events, {
    required Map<String, dynamic> leg,
    required DateTime? expectedTime,
  }) {
    final event = _matchStopEventForLeg(
      events,
      leg: leg,
      expectedTime: expectedTime,
    );
    final place = (event?['place'] as Map?)?.cast<String, dynamic>();
    return (
      platform: event == null ? null : _platformFromStopEvent(event),
      stopLabel: _stopLabelFromPlace(place),
      stopId: _stringOrNull(place?['stopId']),
      parentId: _stringOrNull(place?['parentId']),
    );
  }

  static DateTime? _tripStopBestTimeLocal(
    Map<String, dynamic> stop,
    DateTime? expectedTime,
  ) {
    final times = <DateTime>[
      if (_parseJourneyTimeLocal(stop['scheduledDeparture']) case final time?)
        time,
      if (_parseJourneyTimeLocal(stop['departure']) case final time?) time,
      if (_parseJourneyTimeLocal(stop['scheduledArrival']) case final time?)
        time,
      if (_parseJourneyTimeLocal(stop['arrival']) case final time?) time,
    ];
    if (times.isEmpty) return null;
    if (expectedTime == null) return times.first;

    times.sort(
      (a, b) => a
          .difference(expectedTime)
          .abs()
          .compareTo(b.difference(expectedTime).abs()),
    );
    return times.first;
  }

  static Duration? _tripStopTimeDistance(
    Map<String, dynamic> stop,
    DateTime? expectedTime,
  ) {
    if (expectedTime == null) return null;
    final stopTime = _tripStopBestTimeLocal(stop, expectedTime);
    if (stopTime == null) return null;
    return stopTime.difference(expectedTime).abs();
  }

  static ({
    String? platform,
    String? stopLabel,
    String? stopId,
    String? parentId,
  })? _stopDetailsFromTripPlace(Map<String, dynamic>? place) {
    if (place == null) return null;

    final platform = _platformFromPlace(place);
    final stopLabel = _stopLabelFromPlace(place);
    final stopId = _stringOrNull(place['stopId']) ?? _stringOrNull(place['id']);
    final parentId = _stringOrNull(place['parentId']);
    if (platform == null &&
        stopLabel == null &&
        stopId == null &&
        parentId == null) {
      return null;
    }

    return (
      platform: platform,
      stopLabel: stopLabel,
      stopId: stopId,
      parentId: parentId,
    );
  }

  static ({
    String? platform,
    String? stopLabel,
    String? stopId,
    String? parentId,
  })? _matchStopDetailsFromTripItinerary(
    Map<String, dynamic> tripItinerary, {
    required Map<String, dynamic> targetPlace,
    required DateTime? expectedTime,
  }) {
    final stopId = _stringOrNull(targetPlace['exactStopId']) ??
        _stringOrNull(targetPlace['stopId']) ??
        _stringOrNull(targetPlace['id']);
    final stopName = _stringOrNull(targetPlace['name']) ?? '';
    if ((stopId == null || stopId.isEmpty) && stopName.isEmpty) return null;

    ({
      String? platform,
      String? stopLabel,
      String? stopId,
      String? parentId
    })? bestDetails;
    Duration? bestDistance;
    var bestHasPlatform = false;

    final tripLegs =
        (tripItinerary['legs'] as List?)?.whereType<Map>().toList() ??
            const <Map>[];
    for (final rawTripLeg in tripLegs) {
      final tripLeg = rawTripLeg.cast<String, dynamic>();
      final sequence = _tripLegStopSequence(tripLeg);
      for (final stop in sequence) {
        final tripPlace =
            (stop['place'] as Map?)?.cast<String, dynamic>() ?? const {};
        if (!_tripPlaceMatchesTarget(tripPlace, stopId ?? '', stopName)) {
          continue;
        }

        final distance = _tripStopTimeDistance(stop, expectedTime);
        if (distance != null && distance > const Duration(minutes: 15)) {
          continue;
        }

        final details = _stopDetailsFromTripPlace(tripPlace);
        if (details == null) continue;

        final hasPlatform =
            details.platform != null && details.platform!.isNotEmpty;
        final isBetter = bestDetails == null ||
            (hasPlatform && !bestHasPlatform) ||
            (hasPlatform == bestHasPlatform &&
                distance != null &&
                (bestDistance == null || distance < bestDistance));

        if (isBetter) {
          bestDetails = details;
          bestDistance = distance;
          bestHasPlatform = hasPlatform;
        }
      }
    }

    return bestDetails;
  }

  @visibleForTesting
  static ({
    String? platform,
    String? stopLabel,
    String? stopId,
    String? parentId,
  })? matchStopDetailsFromTripItineraryForTesting(
    Map<String, dynamic> tripItinerary, {
    required Map<String, dynamic> targetPlace,
    required DateTime? expectedTime,
  }) =>
      _matchStopDetailsFromTripItinerary(
        tripItinerary,
        targetPlace: targetPlace,
        expectedTime: expectedTime,
      );

  static Future<
      ({
        String? platform,
        String? stopLabel,
        String? stopId,
        String? parentId,
      })?> _backfillStopDetailsFromTripItinerary(
    Map<String, dynamic> leg,
    Map<String, dynamic> place, {
    required DateTime? expectedTime,
  }) async {
    final tripId = _journeyLegTripId(leg);
    if (tripId == null || tripId.isEmpty) return null;

    final tripItinerary = await _fetchTripItineraryCached(tripId);
    if (tripItinerary == null) return null;

    return _matchStopDetailsFromTripItinerary(
      tripItinerary,
      targetPlace: place,
      expectedTime: expectedTime,
    );
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');

  static String _bahnDate(DateTime time) =>
      '${time.year}-${_twoDigits(time.month)}-${_twoDigits(time.day)}';

  static String _bahnTime(DateTime time) =>
      '${_twoDigits(time.hour)}:${_twoDigits(time.minute)}:00';

  static Uri _getBahnWebUri(
    String endpoint,
    Map<String, List<String>> queryParameters,
  ) {
    final query = queryParameters.entries
        .expand(
          (entry) => entry.value.map(
            (value) =>
                '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(value)}',
          ),
        )
        .join('&');
    return Uri.parse('$_bahnWebUrl$endpoint?$query');
  }

  static String? _bahnEvaFromText(Object? value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;
    final match = RegExp(r'(?<!\d)8\d{6}(?!\d)').firstMatch(text);
    return match?.group(0);
  }

  static String? _bahnEvaFromPlace(Map<String, dynamic> place) {
    final candidates = <Object?>[
      place['exactStopId'],
      place['id'],
      place['stopId'],
      place['parentId'],
    ];
    for (final candidate in candidates) {
      final eva = _bahnEvaFromText(candidate);
      if (eva != null) return eva;
    }
    return null;
  }

  static double? _placeLatitude(Map<String, dynamic> place) =>
      (place['location'] as Map?)?['latitude'] is num
          ? ((place['location'] as Map)['latitude'] as num).toDouble()
          : (place['latitude'] is num
              ? (place['latitude'] as num).toDouble()
              : null);

  static double? _placeLongitude(Map<String, dynamic> place) =>
      (place['location'] as Map?)?['longitude'] is num
          ? ((place['location'] as Map)['longitude'] as num).toDouble()
          : (place['longitude'] is num
              ? (place['longitude'] as num).toDouble()
              : null);

  static bool _bahnPlaceHasRailProducts(Map<String, dynamic> place) {
    final products = place['products'];
    if (products is! List) return false;
    const railProducts = {'ICE', 'EC_IC', 'IR', 'REGIONAL', 'SBAHN'};
    return products
        .map((product) => product.toString())
        .any(railProducts.contains);
  }

  static Future<String?> _resolveBahnEvaForPlace(
    Map<String, dynamic> place,
  ) async {
    final existing = _bahnEvaFromPlace(place);
    if (existing != null) return existing;

    final name = _stringOrNull(place['name']);
    if (name == null) return null;

    final cacheKey = _normalizeTransitKey(name);
    final cached = _bahnEvaCache[cacheKey];
    if (cached != null && !cached.isExpired) return cached.data;

    try {
      final response = await _fetch(
        _getBahnWebUri('/web/api/reiseloesung/orte', {
          'suchbegriff': [name],
        }),
      );
      final data = json.decode(response.body);
      if (data is! List) return null;

      final targetLat = _placeLatitude(place);
      final targetLng = _placeLongitude(place);
      Map<String, dynamic>? best;
      var bestScore = -1.0;

      for (final raw in data.whereType<Map>()) {
        final candidate = raw.cast<String, dynamic>();
        final extId = _stringOrNull(candidate['extId']);
        if (extId == null || _bahnEvaFromText(extId) == null) continue;

        var score = 0.0;
        if (extId.startsWith('8')) score += 100;
        if (_bahnPlaceHasRailProducts(candidate)) score += 50;
        final candidateName = _normalizeTransitKey(candidate['name']);
        if (candidateName == cacheKey) {
          score += 40;
        } else if (candidateName.contains(cacheKey) ||
            cacheKey.contains(candidateName)) {
          score += 20;
        }

        final candidateLat = (candidate['lat'] as num?)?.toDouble();
        final candidateLng = (candidate['lon'] as num?)?.toDouble();
        if (targetLat != null &&
            targetLng != null &&
            candidateLat != null &&
            candidateLng != null) {
          final distanceMeters = _distanceKm(
                targetLat,
                targetLng,
                candidateLat,
                candidateLng,
              ) *
              1000;
          if (distanceMeters < 250) {
            score += 25;
          } else if (distanceMeters < 1000) {
            score += 10;
          }
        }

        if (score > bestScore) {
          best = candidate;
          bestScore = score;
        }
      }

      final eva = _stringOrNull(best?['extId']);
      _bahnEvaCache[cacheKey] = _CacheEntry(eva, _bahnEvaCacheTtl);
      return eva;
    } catch (error) {
      debugPrint('bahn.de station lookup failed for $name: $error');
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> _fetchBahnBoardEvents(
    String evaNumber, {
    required DateTime expectedTime,
    required bool arrivals,
  }) async {
    final queryTime = expectedTime.subtract(const Duration(minutes: 15));
    final cacheKey =
        '$evaNumber|${arrivals ? 'arr' : 'dep'}|${_bahnDate(queryTime)}|${_bahnTime(queryTime)}';
    final cached = _bahnBoardCache[cacheKey];
    if (cached != null && !cached.isExpired) return cached.data;

    final endpoint = arrivals
        ? '/web/api/reiseloesung/ankuenfte'
        : '/web/api/reiseloesung/abfahrten';
    final response = await _fetch(
      _getBahnWebUri(endpoint, {
        'datum': [_bahnDate(queryTime)],
        'zeit': [_bahnTime(queryTime)],
        'ortExtId': [evaNumber],
        'verkehrsMittel[]': ['ICE', 'INTERCITY', 'REGIONAL'],
      }),
    );
    final data = json.decode(response.body);
    final entries = (data is Map ? data['entries'] : null) as List?;
    final result = entries
            ?.whereType<Map>()
            .map((entry) => entry.cast<String, dynamic>())
            .toList() ??
        const <Map<String, dynamic>>[];
    _bahnBoardCache[cacheKey] = _CacheEntry(result, _bahnBoardCacheTtl);
    return result;
  }

  static Duration? _bahnBoardTimeDistance(
    Map<String, dynamic> entry,
    DateTime expectedTime,
  ) {
    final times = <DateTime>[
      if (_parseJourneyTimeLocal(entry['zeit']) case final time?) time,
      if (_parseJourneyTimeLocal(entry['ezZeit']) case final time?) time,
    ];
    if (times.isEmpty) return null;
    times.sort(
      (a, b) => a
          .difference(expectedTime)
          .abs()
          .compareTo(b.difference(expectedTime).abs()),
    );
    return times.first.difference(expectedTime).abs();
  }

  static String _bahnBoardLineKey(Map<String, dynamic> entry) {
    final vehicle = (entry['verkehrmittel'] as Map?)?.cast<String, dynamic>();
    return _normalizeTransitKey(
      vehicle?['mittelText'] ?? vehicle?['name'] ?? vehicle?['linienNummer'],
    );
  }

  /// bahn.de reports a live track change in `ezGleis`, falling back to the
  /// planned `gleis`.
  static String? _bahnBoardPlatform(Map<String, dynamic>? entry) {
    if (entry == null) return null;
    return _stringOrNull(entry['ezGleis']) ?? _stringOrNull(entry['gleis']);
  }

  static bool _bahnBoardDirectionMatches(
    Map<String, dynamic> entry,
    String headsign,
  ) {
    final legDirection = _normalizeTransitKey(headsign);
    final entryDirection = _normalizeTransitKey(
      entry['richtung'] ?? entry['terminus'],
    );
    if (legDirection.isEmpty || entryDirection.isEmpty) return false;
    return legDirection.contains(entryDirection) ||
        entryDirection.contains(legDirection);
  }

  static String? _matchPlatformFromBahnBoardEvents(
    Iterable<Map<String, dynamic>> entries, {
    required Map<String, dynamic> leg,
    required DateTime expectedTime,
    bool strict = false,
    bool matchDirection = false,
  }) {
    final lineKey = _normalizeTransitKey(_journeyLegLineDisplayName(leg));
    final maxDistance =
        strict ? const Duration(minutes: 4) : const Duration(minutes: 12);
    Map<String, dynamic>? best;
    Duration? bestDistance;

    for (final entry in entries) {
      final platform = _bahnBoardPlatform(entry);
      if (platform == null) continue;

      final entryLineKey = _bahnBoardLineKey(entry);
      if (!_transitLineKeysLikelyMatch(lineKey, entryLineKey)) continue;

      // Overriding a track the feed already gave us is only safe on an
      // unmistakable match, so require the direction to line up as well.
      if (matchDirection &&
          !_bahnBoardDirectionMatches(entry, _journeyLegHeadsign(leg))) {
        continue;
      }

      final distance = _bahnBoardTimeDistance(entry, expectedTime);
      if (distance == null || distance > maxDistance) continue;

      if (best == null || bestDistance == null || distance < bestDistance) {
        best = entry;
        bestDistance = distance;
      }
    }

    return _bahnBoardPlatform(best);
  }

  @visibleForTesting
  static String? matchPlatformFromBahnBoardEventsForTesting(
    Iterable<Map<String, dynamic>> entries, {
    required Map<String, dynamic> leg,
    required DateTime expectedTime,
    bool strict = false,
    bool matchDirection = false,
  }) =>
      _matchPlatformFromBahnBoardEvents(
        entries,
        leg: leg,
        expectedTime: expectedTime,
        strict: strict,
        matchDirection: matchDirection,
      );

  @visibleForTesting
  static bool platformLooksLikeTrackAreaForTesting(
    Map<String, dynamic>? place,
  ) =>
      _platformLooksLikeTrackArea(place);

  static Future<Map<String, dynamic>> debugLookupBahnPlatform({
    required String stationName,
    required String lineName,
    required DateTime expectedTime,
    required bool arrivals,
  }) async {
    final place = <String, dynamic>{'name': stationName};
    final leg = <String, dynamic>{
      'line': <String, dynamic>{'name': lineName},
    };
    final evaNumber = await _resolveBahnEvaForPlace(place);
    if (evaNumber == null) {
      return <String, dynamic>{
        'station': stationName,
        'line': lineName,
        'time': expectedTime.toIso8601String(),
        'arrivals': arrivals,
        'error': 'No bahn.de EVA station id found',
      };
    }

    final events = await _fetchBahnBoardEvents(
      evaNumber,
      expectedTime: expectedTime,
      arrivals: arrivals,
    );
    final platform = _matchPlatformFromBahnBoardEvents(
      events,
      leg: leg,
      expectedTime: expectedTime,
    );

    Map<String, dynamic> simplifyEntry(Map<String, dynamic> entry) {
      final vehicle = (entry['verkehrmittel'] as Map?)?.cast<String, dynamic>();
      final line = vehicle?['mittelText'] ??
          vehicle?['name'] ??
          vehicle?['linienNummer'];
      return <String, dynamic>{
        'time': entry['zeit']?.toString(),
        'realtimeTime': entry['ezZeit']?.toString(),
        'line': line?.toString(),
        'direction': entry['richtung']?.toString(),
        'platform': entry['gleis']?.toString(),
        'lineKey': _bahnBoardLineKey(entry),
        'minutesFromExpected':
            _bahnBoardTimeDistance(entry, expectedTime)?.inMinutes.toString(),
      };
    }

    final lineKey = _normalizeTransitKey(lineName);
    final relevantEntries = events
        .where((entry) =>
            _transitLineKeysLikelyMatch(lineKey, _bahnBoardLineKey(entry)) ||
            (_bahnBoardTimeDistance(entry, expectedTime) != null &&
                _bahnBoardTimeDistance(entry, expectedTime)! <=
                    const Duration(minutes: 20)))
        .map(simplifyEntry)
        .take(20)
        .toList();

    return <String, dynamic>{
      'station': stationName,
      'eva': evaNumber,
      'line': lineName,
      'lineKey': lineKey,
      'time': expectedTime.toIso8601String(),
      'arrivals': arrivals,
      'platform': platform,
      'entriesReturned': events.length,
      'entries': relevantEntries,
    };
  }

  static Future<Map<String, dynamic>> enrichJourneyWithPlatforms(
    Map<String, dynamic> journey, {
    void Function(Map<String, dynamic> enrichedSoFar)? onProgress,
    bool preferBahnForRail = false,
    bool fastBahnRailOnly = false,
  }) async {
    await _enrichJourneyWithCoupledLineAliases(
      journey,
      onProgress: onProgress,
    );
    final journeys = <Map<String, dynamic>>[journey];
    await _enrichJourneysWithPlatforms(
      journeys,
      onProgress: onProgress == null
          ? null
          : (enrichedSoFar) => onProgress(enrichedSoFar.first),
      preferBahnForRail: preferBahnForRail,
      fastBahnRailOnly: fastBahnRailOnly,
    );
    return journeys.first;
  }

  static Future<void> _enrichJourneyWithCoupledLineAliases(
    Map<String, dynamic> journey, {
    void Function(Map<String, dynamic> enrichedSoFar)? onProgress,
  }) async {
    if (journey['source'] != 'motis') return;
    final legs = (journey['legs'] as List?)?.whereType<Map>().toList();
    if (legs == null) return;

    for (final rawLeg in legs) {
      final leg = rawLeg.cast<String, dynamic>();
      if (leg['line'] == null || !_journeyLegLooksRail(leg)) continue;
      final origin = (leg['origin'] as Map?)?.cast<String, dynamic>();
      final stopId =
          _stringOrNull(origin?['id']) ?? _stringOrNull(origin?['stopId']);
      final departureTime =
          _journeyLegTimeLocal(leg, 'plannedDeparture', 'departure');
      if (stopId == null || departureTime == null) continue;

      try {
        final events = await _fetchMotisStopEvents(
          stopId,
          timeLocal: departureTime.subtract(const Duration(minutes: 3)),
          direction: 'LATER',
          maxResults: 40,
        );
        final combinedName = _coupledLineDisplayNameFromStopEvents(
          events,
          leg: leg,
          expectedTime: departureTime,
        );
        if (combinedName == null) continue;
        final line = (leg['line'] as Map).cast<String, dynamic>();
        if (line['name']?.toString() == combinedName) continue;
        line['primaryName'] ??= line['name'];
        line['name'] = combinedName;
        onProgress?.call(journey);
      } catch (error) {
        _syntheticLog(
          'coupled line lookup failed: ${_journeyLegLineDisplayName(leg)} '
          'at ${origin?['name'] ?? stopId}: $error',
        );
      }
    }
  }

  static Future<void> _enrichJourneysWithCoupledLineAliases(
    Iterable<Map<String, dynamic>> journeys,
  ) async {
    await Future.wait(
      journeys.map(
        (journey) => _enrichJourneyWithCoupledLineAliases(journey),
      ),
    );
  }

  static void _setIfBlankMapValue(
    Map<String, dynamic> map,
    String key,
    String value,
  ) {
    final current = map[key]?.toString().trim();
    if (current == null || current.isEmpty) {
      map[key] = value;
    }
  }

  @visibleForTesting
  static void setIfBlankMapValueForTesting(
    Map<String, dynamic> map,
    String key,
    String value,
  ) =>
      _setIfBlankMapValue(map, key, value);

  static Future<
      ({
        String? platform,
        String? stopLabel,
        String? stopId,
        String? parentId,
      })?> _backfillStopDetailsFromBahnBoard(
    Map<String, dynamic> leg,
    Map<String, dynamic> place, {
    required DateTime? expectedTime,
    required bool arrivals,
    bool strict = false,
  }) async {
    if (expectedTime == null || !_journeyLegLooksRail(leg)) return null;

    final evaNumber = await _resolveBahnEvaForPlace(place);
    final placeName = _stringOrNull(place['name']) ?? 'unknown stop';
    final lineName = _journeyLegLineDisplayName(leg);
    if (evaNumber == null) {
      _syntheticLog('bahn platform skipped: no EVA for $placeName');
      return null;
    }

    try {
      _syntheticLog(
        'bahn platform lookup: $placeName eva=$evaNumber '
        '${arrivals ? 'arr' : 'dep'} $lineName',
      );
      final events = await _fetchBahnBoardEvents(
        evaNumber,
        expectedTime: expectedTime,
        arrivals: arrivals,
      );
      final platform = _matchPlatformFromBahnBoardEvents(
        events,
        leg: leg,
        expectedTime: expectedTime,
        strict: strict,
        // Arrival boards name the origin, not the direction of travel, so the
        // direction check only applies to departures.
        matchDirection: strict && !arrivals,
      );
      if (platform == null) {
        _syntheticLog(
          'bahn platform no match: $placeName eva=$evaNumber '
          '${arrivals ? 'arr' : 'dep'} $lineName events=${events.length}',
        );
        return null;
      }

      _syntheticLog(
        'bahn platform match: $placeName ${arrivals ? 'arr' : 'dep'} '
        '$lineName -> Gl. $platform',
      );

      return (
        platform: platform,
        stopLabel: null,
        stopId: null,
        parentId: null,
      );
    } catch (error) {
      debugPrint('bahn.de platform lookup failed for $evaNumber: $error');
      return null;
    }
  }

  static void _applyBackfilledStopDetails(
    Map<String, dynamic> place, {
    required String? platform,
    required String? stopLabel,
    required String? stopId,
    required String? parentId,
    bool overwritePlatform = false,
  }) {
    if (platform != null && platform.isNotEmpty) {
      if (overwritePlatform) {
        place['platform'] = platform;
        place['scheduledPlatform'] = platform;
      } else {
        _setIfBlankMapValue(place, 'platform', platform);
        _setIfBlankMapValue(place, 'scheduledPlatform', platform);
      }
    }
    if (stopLabel != null && stopLabel.isNotEmpty) {
      _setIfBlankMapValue(place, 'stopLabel', stopLabel);
    }
    if (stopId != null && stopId.isNotEmpty) {
      _setIfBlankMapValue(place, 'exactStopId', stopId);
    }
    if (parentId != null && parentId.isNotEmpty) {
      _setIfBlankMapValue(place, 'parentId', parentId);
    }
  }

  static Future<void> _enrichJourneyRailPlatformsFromBahnBoardFast(
    Map<String, dynamic> journey, {
    void Function()? onProgress,
  }) async {
    final legs = (journey['legs'] as List?)?.whereType<Map>().toList();
    if (legs == null || legs.isEmpty) return;

    final tasks = <Future<void>>[];
    for (final rawLeg in legs) {
      final leg = rawLeg.cast<String, dynamic>();
      if (leg['walking'] == true ||
          leg['line'] == null ||
          !_journeyLegLooksRail(leg)) {
        continue;
      }

      void addLookup(
        Map<String, dynamic>? place, {
        required DateTime? expectedTime,
        required bool arrivals,
      }) {
        if (place == null) return;
        final isTrackArea = _platformLooksLikeTrackArea(place);
        if (_platformFromPlace(place) != null && !isTrackArea) return;
        tasks.add(() async {
          final details = await _backfillStopDetailsFromBahnBoard(
            leg,
            place,
            expectedTime: expectedTime,
            arrivals: arrivals,
            strict: isTrackArea,
          );
          if (details == null || details.platform == null) return;
          _applyBackfilledStopDetails(
            place,
            platform: details.platform,
            stopLabel: details.stopLabel,
            stopId: details.stopId,
            parentId: details.parentId,
            overwritePlatform: isTrackArea,
          );
          onProgress?.call();
        }());
      }

      addLookup(
        (leg['origin'] as Map?)?.cast<String, dynamic>(),
        expectedTime: _journeyLegTimeLocal(
          leg,
          'plannedDeparture',
          'departure',
        ),
        arrivals: false,
      );
      addLookup(
        (leg['destination'] as Map?)?.cast<String, dynamic>(),
        expectedTime: _journeyLegTimeLocal(
          leg,
          'plannedArrival',
          'arrival',
        ),
        arrivals: true,
      );
    }

    await Future.wait(tasks);
  }

  static Future<List<Map<String, dynamic>>> _fetchMotisStopEvents(
    String stationId, {
    required DateTime timeLocal,
    required String direction,
    int maxResults = 80,
  }) async {
    final cacheKey =
        '$stationId|$direction|${timeLocal.toIso8601String()}|$maxResults';
    final cached = _stopEventsCache[cacheKey];
    if (cached != null && !cached.isExpired) {
      return cached.data;
    }

    final response = await _fetch(
      _getMotisUri('/api/v5/stoptimes', {
        'stopId': stationId,
        'time': timeLocal.toUtc().toIso8601String(),
        'direction': direction,
        'n': maxResults.toString(),
      }),
    );
    final data = json.decode(response.body);
    final events = decodeStopDeparturesResponse(data);
    _stopEventsCache[cacheKey] = _CacheEntry(events, _stopEventsCacheTtl);
    return events;
  }

  static Future<
      ({
        String? platform,
        String? stopLabel,
        String? stopId,
        String? parentId,
      })?> _backfillStopDetailsForLegPlace(
    Map<String, dynamic> leg,
    Map<String, dynamic> place, {
    required DateTime? expectedTime,
    required bool arrivals,
    bool preferBahnForRail = false,
  }) async {
    final existingPlatform = _platformFromPlace(place);
    final existingStopLabel = _stopLabelFromPlace(place);
    final existingStopId = _stringOrNull(place['exactStopId']);
    final existingParentId = _stringOrNull(place['parentId']);
    final existingIsTrackArea = _platformLooksLikeTrackArea(place);
    if (existingPlatform != null && !existingIsTrackArea) {
      return (
        platform: existingPlatform,
        stopLabel: existingStopLabel,
        stopId: existingStopId,
        parentId: existingParentId,
      );
    }

    // The feed only knows the platform area, so ask bahn.de for the actual
    // track and keep the area as a fallback if nothing matches exactly.
    if (existingIsTrackArea) {
      final bahnDetails = expectedTime == null || !_journeyLegLooksRail(leg)
          ? null
          : await _backfillStopDetailsFromBahnBoard(
              leg,
              place,
              expectedTime: expectedTime,
              arrivals: arrivals,
              strict: true,
            );
      return (
        platform: bahnDetails?.platform ?? existingPlatform,
        stopLabel: existingStopLabel,
        stopId: existingStopId,
        parentId: existingParentId,
      );
    }

    if (preferBahnForRail &&
        expectedTime != null &&
        _journeyLegLooksRail(leg)) {
      final bahnDetails = await _backfillStopDetailsFromBahnBoard(
        leg,
        place,
        expectedTime: expectedTime,
        arrivals: arrivals,
      );
      if (bahnDetails != null && bahnDetails.platform != null) {
        return (
          platform: bahnDetails.platform,
          stopLabel: bahnDetails.stopLabel ?? existingStopLabel,
          stopId: bahnDetails.stopId ?? existingStopId,
          parentId: bahnDetails.parentId ?? existingParentId,
        );
      }
    }

    final stopId = _stringOrNull(place['id']) ??
        _stringOrNull(place['stopId']) ??
        existingStopId;
    if (stopId == null || stopId.isEmpty) {
      final bahnDetails = await _backfillStopDetailsFromBahnBoard(
        leg,
        place,
        expectedTime: expectedTime,
        arrivals: arrivals,
      );
      if (bahnDetails != null) {
        return (
          platform: bahnDetails.platform,
          stopLabel: bahnDetails.stopLabel ?? existingStopLabel,
          stopId: bahnDetails.stopId,
          parentId: bahnDetails.parentId ?? existingParentId,
        );
      }
      if (existingStopLabel != null) {
        return (
          platform: null,
          stopLabel: existingStopLabel,
          stopId: null,
          parentId: existingParentId,
        );
      }
      return null;
    }

    if (expectedTime != null) {
      final beforeTime = expectedTime.subtract(const Duration(minutes: 3));
      final requests = <Future<List<Map<String, dynamic>>>>[
        _fetchMotisStopEvents(
          stopId,
          timeLocal: beforeTime,
          direction: 'LATER',
        ),
        _fetchMotisStopEvents(
          stopId,
          timeLocal: expectedTime,
          direction: 'EARLIER',
        ),
      ];

      final results = await Future.wait(requests);
      for (final events in results) {
        final matchedEvent = _matchStopEventForLeg(
          events,
          leg: leg,
          expectedTime: expectedTime,
        );
        final matchedPlace =
            (matchedEvent?['place'] as Map?)?.cast<String, dynamic>();
        if (matchedPlace == null) continue;

        final platform = _platformFromStopEvent(matchedEvent!);
        final stopLabel = _stopLabelFromPlace(matchedPlace);
        final exactStopId = _stringOrNull(matchedPlace['stopId']);
        final parentId = _stringOrNull(matchedPlace['parentId']);
        if (platform != null || stopLabel != null) {
          return (
            platform: platform,
            stopLabel: stopLabel,
            stopId: exactStopId,
            parentId: parentId,
          );
        }
      }
    }

    final tripDetails = await _backfillStopDetailsFromTripItinerary(
      leg,
      place,
      expectedTime: expectedTime,
    );
    if (tripDetails != null &&
        (tripDetails.platform != null || tripDetails.stopLabel != null)) {
      return tripDetails;
    }

    final bahnDetails = await _backfillStopDetailsFromBahnBoard(
      leg,
      place,
      expectedTime: expectedTime,
      arrivals: arrivals,
    );
    if (bahnDetails != null) {
      return (
        platform: bahnDetails.platform,
        stopLabel: bahnDetails.stopLabel ??
            tripDetails?.stopLabel ??
            existingStopLabel,
        stopId: bahnDetails.stopId ?? tripDetails?.stopId ?? existingStopId,
        parentId:
            bahnDetails.parentId ?? tripDetails?.parentId ?? existingParentId,
      );
    }

    if (existingStopLabel != null) {
      return (
        platform: null,
        stopLabel: existingStopLabel,
        stopId: null,
        parentId: existingParentId,
      );
    }
    return null;
  }

  static Future<List<Map<String, dynamic>>> _enrichJourneysWithPlatforms(
    List<Map<String, dynamic>> journeys, {
    void Function(List<Map<String, dynamic>> enrichedSoFar)? onProgress,
    bool preferBahnForRail = false,
    bool fastBahnRailOnly = false,
  }) async {
    for (var journeyIndex = 0; journeyIndex < journeys.length; journeyIndex++) {
      final journey = journeys[journeyIndex];
      final source = journey['source']?.toString();
      if (source != 'motis' &&
          source != 'motis_synthetic' &&
          source != 'v6' &&
          source != sourceDbV6) {
        continue;
      }

      final legs = (journey['legs'] as List?)?.whereType<Map>().toList();
      if (legs == null || legs.isEmpty) continue;

      if (fastBahnRailOnly) {
        await _enrichJourneyRailPlatformsFromBahnBoardFast(
          journey,
          onProgress: () =>
              onProgress?.call(List<Map<String, dynamic>>.from(journeys)),
        );
        onProgress?.call(List<Map<String, dynamic>>.from(journeys));
        continue;
      }

      for (final rawLeg in legs) {
        final leg = rawLeg.cast<String, dynamic>();
        if (leg['walking'] == true || leg['line'] == null) continue;

        final origin = (leg['origin'] as Map?)?.cast<String, dynamic>();
        final destination =
            (leg['destination'] as Map?)?.cast<String, dynamic>();
        final departureTime =
            _journeyLegTimeLocal(leg, 'plannedDeparture', 'departure');
        final arrivalTime =
            _journeyLegTimeLocal(leg, 'plannedArrival', 'arrival');

        if (origin != null) {
          final originIsTrackArea = _platformLooksLikeTrackArea(origin);
          final details = await _backfillStopDetailsForLegPlace(
            leg,
            origin,
            expectedTime: departureTime,
            arrivals: false,
            preferBahnForRail: preferBahnForRail,
          );
          if (details != null) {
            _applyBackfilledStopDetails(
              origin,
              platform: details.platform,
              stopLabel: details.stopLabel,
              stopId: details.stopId,
              parentId: details.parentId,
              overwritePlatform: originIsTrackArea,
            );
            onProgress?.call(List<Map<String, dynamic>>.from(journeys));
          }
        }

        if (destination != null) {
          final destinationIsTrackArea =
              _platformLooksLikeTrackArea(destination);
          final details = await _backfillStopDetailsForLegPlace(
            leg,
            destination,
            expectedTime: arrivalTime,
            arrivals: true,
            preferBahnForRail: preferBahnForRail,
          );
          if (details != null) {
            _applyBackfilledStopDetails(
              destination,
              platform: details.platform,
              stopLabel: details.stopLabel,
              stopId: details.stopId,
              parentId: details.parentId,
              overwritePlatform: destinationIsTrackArea,
            );
            onProgress?.call(List<Map<String, dynamic>>.from(journeys));
          }
        }
      }

      onProgress?.call(List<Map<String, dynamic>>.from(journeys));
    }

    return journeys;
  }

  static Future<List<Map<String, dynamic>>> _fetchMotisStopDepartures(
    String stationId, {
    required DateTime startLocal,
    required DateTime endLocal,
    required int maxResults,
  }) async {
    final pageSize = math.min(math.max(maxResults, 1), 100);
    final baseParams = <String, dynamic>{
      'stopId': stationId,
      'direction': 'LATER',
      'n': pageSize.toString(),
    };

    final departures = <Map<String, dynamic>>[];
    final seenKeys = <String>{};
    var requestTime = startLocal;
    String? pageCursor;
    final maxPages = math.max(1, (maxResults / pageSize).ceil() + 4);

    for (var page = 0;
        page < maxPages && departures.length < maxResults;
        page++) {
      final response = await _fetch(
        _getMotisUri('/api/v5/stoptimes', {
          ...baseParams,
          'time': requestTime.toUtc().toIso8601String(),
          if (pageCursor != null) 'pageCursor': pageCursor,
        }),
      );
      final data = json.decode(response.body);
      final pageDepartures = decodeStopDeparturesResponse(data);
      if (pageDepartures.isEmpty) break;

      var reachedNextDay = false;
      DateTime? lastDepartureTime;
      for (final dep in pageDepartures) {
        final departureTime = _stopDepartureDateTimeLocal(dep);
        if (departureTime == null) continue;
        if (lastDepartureTime == null ||
            departureTime.isAfter(lastDepartureTime)) {
          lastDepartureTime = departureTime;
        }
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
      if (nextPageCursor != null && nextPageCursor != pageCursor) {
        pageCursor = nextPageCursor;
        continue;
      }

      if (lastDepartureTime == null ||
          !lastDepartureTime.isAfter(requestTime)) {
        break;
      }
      requestTime = lastDepartureTime.add(const Duration(seconds: 1));
      pageCursor = null;
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

  @visibleForTesting
  static Uri buildMotisPlanUri(Map<String, dynamic> params) =>
      _getMotisPlanUri(params);

  static Uri _getMotisPlanUri(Map<String, dynamic> params) =>
      _getMotisUri('/api/v5/plan', params);

  @visibleForTesting
  static Map<String, dynamic> buildMotisJourneySearchParamsForTesting(
    Station from,
    Station to, {
    bool nahverkehrOnly = false,
    DateTime? when,
    bool isArrival = false,
    int results = 3,
    double? pedestrianSpeedKmhOverride,
    int? maxWalkingTimeMinutesOverride,
  }) =>
      _buildMotisJourneySearchParams(
        from,
        to,
        nahverkehrOnly: nahverkehrOnly,
        when: when,
        isArrival: isArrival,
        results: results,
        pedestrianSpeedKmhOverride: pedestrianSpeedKmhOverride,
        maxWalkingTimeMinutesOverride: maxWalkingTimeMinutesOverride,
      );

  @visibleForTesting
  static Map<String, dynamic> buildMotisDirectJourneySearchParamsForTesting(
    Station from,
    Station to, {
    DateTime? when,
    bool isArrival = false,
    int results = 3,
  }) =>
      _buildMotisDirectJourneySearchParams(
        from,
        to,
        when: when,
        isArrival: isArrival,
        results: results,
      );

  /// Decodes a MOTIS `/api/v5/plan` response into normalized journeys.
  ///
  /// Transitous data quality can vary by provider/country; this parser is
  /// intentionally defensive so one malformed itinerary does not discard all
  /// other valid results.
  @visibleForTesting
  static List<Map<String, dynamic>> decodeMotisPlanJourneys(dynamic data) {
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Unsupported MOTIS plan response');
    }

    final rawItineraries = data['itineraries'];
    if (rawItineraries is! List) return const <Map<String, dynamic>>[];

    final journeys = <Map<String, dynamic>>[];
    for (final raw in rawItineraries) {
      if (raw is! Map) continue;
      try {
        final journey = journeyFromMotisItinerary(raw.cast<String, dynamic>());
        journey['source'] = 'motis';
        journeys.add(journey);
      } catch (error) {
        debugPrint('Skipping malformed MOTIS itinerary: $error');
      }
    }
    return journeys;
  }

  @visibleForTesting
  static List<Map<String, dynamic>> decodeMotisDirectPlanJourneys(
    dynamic data,
  ) {
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Unsupported MOTIS plan response');
    }

    final rawDirect = data['direct'];
    if (rawDirect is! List) return const <Map<String, dynamic>>[];

    final journeys = <Map<String, dynamic>>[];
    for (final raw in rawDirect) {
      if (raw is! Map) continue;
      try {
        final journey = journeyFromMotisItinerary(raw.cast<String, dynamic>());
        journey['source'] = 'motis';
        journey['direct'] = true;
        journeys.add(journey);
      } catch (error) {
        debugPrint('Skipping malformed MOTIS direct itinerary: $error');
      }
    }
    return journeys;
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
        'startTime': _motisMapTime(startTime),
        'endTime': _motisMapTime(endTime),
        'zoom': zoom.toStringAsFixed(2),
      });

  static String _motisMapTime(DateTime time) {
    final utc = time.toUtc();
    return DateTime.utc(
      utc.year,
      utc.month,
      utc.day,
      utc.hour,
      utc.minute,
      utc.second,
      utc.millisecond,
    ).toIso8601String();
  }

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

  /// Fetches one MOTIS trip without using the itinerary cache.
  ///
  /// Route searches are snapshots and can omit a selected service in busy
  /// result windows. A trip id addresses that exact vehicle, so route-detail
  /// refreshes use this as their realtime-first path and retain plan search as
  /// a fallback for providers that do not expose MOTIS trip ids.
  static Future<Map<String, dynamic>?> fetchLiveTripJourney(
    String tripId,
  ) async {
    final normalizedTripId = tripId.trim();
    if (normalizedTripId.isEmpty) return null;

    try {
      final itinerary = await fetchTripItinerary(
        normalizedTripId,
        withScheduledSkippedStops: true,
        joinInterlinedLegs: true,
      );
      if (itinerary == null) return null;
      final journey = journeyFromMotisItinerary(itinerary);
      journey['source'] = 'motis';
      return journey;
    } catch (error) {
      // A v6 trip id is not necessarily understood by MOTIS. Callers fall
      // back to a route search in that case, rather than failing refresh.
      _syntheticLog(
          'live trip refresh unavailable trip=$normalizedTripId error=$error');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> _fetchTripItineraryCached(
    String tripId,
  ) async {
    _pruneExpiredCaches();
    final normalizedTripId = tripId.trim();
    if (normalizedTripId.isEmpty) return null;

    final cached = _readCache(_tripItineraryCache, normalizedTripId);
    if (cached != null) return cached;

    final inFlight = _tripItineraryInFlight[normalizedTripId];
    if (inFlight != null) return inFlight;

    final future = fetchTripItinerary(
      normalizedTripId,
      withScheduledSkippedStops: true,
      joinInterlinedLegs: true,
    );
    _tripItineraryInFlight[normalizedTripId] = future;

    try {
      final itinerary = await future;
      _writeCache(
        _tripItineraryCache,
        normalizedTripId,
        itinerary,
        _tripItineraryCacheTtl,
      );
      return itinerary;
    } finally {
      _tripItineraryInFlight.remove(normalizedTripId);
    }
  }

  static String _normalizeTransitKey(Object? value) =>
      normalizeServiceText(value);

  static void _syntheticLog(String message) {
    final line = '[synthetic] $message';
    _syntheticDebugBuffer.add(line);
    if (_syntheticDebugBuffer.length > 250) {
      _syntheticDebugBuffer.removeRange(0, _syntheticDebugBuffer.length - 250);
    }
    if (kDebugMode) {
      debugPrint(line);
    }
  }

  static void addSyntheticDebugLog(String message) {
    _syntheticLog(message);
  }

  static void clearSyntheticDebugLog() {
    _syntheticDebugBuffer.clear();
  }

  static String syntheticDebugLogText() {
    if (_syntheticDebugBuffer.isEmpty) {
      return '[synthetic] no synthetic debug logs captured yet';
    }
    return _syntheticDebugBuffer.join('\n');
  }

  static String _formatDebugTime(DateTime? time) {
    if (time == null) return '??:??';
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  static String _journeyLegLineName(Map<String, dynamic> leg) =>
      (leg['line'] as Map<String, dynamic>?)?['name']?.toString().trim() ?? '';

  static String _journeyLegPrimaryLineName(Map<String, dynamic> leg) {
    final line = leg['line'] as Map<String, dynamic>?;
    return line?['primaryName']?.toString().trim() ??
        line?['name']?.toString().trim() ??
        '';
  }

  static String? _journeyLegTripId(Map<String, dynamic> leg) {
    final line = leg['line'] as Map<String, dynamic>?;
    final candidates = <Object?>[
      leg['tripId'],
      line?['tripId'],
      line?['fahrtNr'],
      line?['fahrtnr'],
    ];
    for (final candidate in candidates) {
      final text = candidate?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  static DateTime? _parseJourneyTimeLocal(Object? value) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    try {
      return DateTime.parse(raw).toLocal();
    } catch (_) {
      return null;
    }
  }

  static String? _stringOrNull(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  static List<Map<String, dynamic>> _copyLegList(List? rawLegs) =>
      rawLegs
          ?.whereType<Map>()
          .map((leg) => Map<String, dynamic>.from(leg))
          .toList() ??
      const <Map<String, dynamic>>[];

  static double? _locationLat(Map<String, dynamic>? location) {
    final loc = location?['location'] as Map<String, dynamic>?;
    return (loc?['latitude'] as num?)?.toDouble() ??
        (location?['latitude'] as num?)?.toDouble();
  }

  static double? _locationLng(Map<String, dynamic>? location) {
    final loc = location?['location'] as Map<String, dynamic>?;
    return (loc?['longitude'] as num?)?.toDouble() ??
        (location?['longitude'] as num?)?.toDouble();
  }

  static _SyntheticSeed? _syntheticSeedFromJourney(
    Map<String, dynamic> journey,
  ) {
    if (journey['source'] != 'motis' || journey['synthetic'] == true) {
      return null;
    }

    final rawLegs = journey['legs'] as List?;
    if (rawLegs == null || rawLegs.isEmpty) return null;

    final mappedRawLegs = _copyLegList(rawLegs);
    final rideIndices = <int>[];
    for (var index = 0; index < mappedRawLegs.length; index++) {
      if (mappedRawLegs[index]['line'] != null) {
        rideIndices.add(index);
      }
    }
    final rideLegs = rideIndices
        .map((index) => mappedRawLegs[index])
        .toList(growable: false);
    if (rideLegs.length < 2) return null;

    final firstRide = rideLegs.first;
    final transferRide = rideLegs[1];
    final origin = (firstRide['origin'] as Map?)?.cast<String, dynamic>();
    final transfer = (transferRide['origin'] as Map?)?.cast<String, dynamic>();
    final secondDestination =
        (transferRide['destination'] as Map?)?.cast<String, dynamic>();
    if (origin == null || transfer == null) return null;

    final firstDeparture = _parseJourneyTimeLocal(
      firstRide['plannedDeparture'] ?? firstRide['departure'],
    );
    if (firstDeparture == null) return null;

    final originStopId = _stringOrNull(origin['id']);
    if (originStopId == null) return null;

    final lineKey = _normalizeTransitKey(_journeyLegPrimaryLineName(firstRide));
    if (lineKey.isEmpty) return null;

    final directionKey = _normalizeTransitKey(firstRide['direction']);
    final transferStopId = _stringOrNull(transfer['id']) ?? '';
    final transferStopName = _stringOrNull(transfer['name']) ?? '';
    if (transferStopId.isEmpty && transferStopName.isEmpty) return null;
    final secondLineKey =
        _normalizeTransitKey(_journeyLegPrimaryLineName(transferRide));
    final secondDirectionKey = _normalizeTransitKey(transferRide['direction']);
    final secondDestinationStopId =
        _stringOrNull(secondDestination?['id']) ?? '';
    final secondDestinationStopName =
        _stringOrNull(secondDestination?['name']) ?? '';
    final secondRideIndex = rideIndices[1];
    final trailingLegs = secondRideIndex + 1 < mappedRawLegs.length
        ? mappedRawLegs.sublist(secondRideIndex + 1)
        : const <Map<String, dynamic>>[];
    final supportsSharedFamilyExpansion = rideLegs.length == 2 &&
        secondLineKey.isNotEmpty &&
        secondDirectionKey.isNotEmpty &&
        (secondDestinationStopId.isNotEmpty ||
            secondDestinationStopName.isNotEmpty) &&
        trailingLegs.every((leg) => leg['line'] == null);

    return _SyntheticSeed(
      journey: journey,
      firstRide: firstRide,
      transferRide: transferRide,
      supportsSharedFamilyExpansion: supportsSharedFamilyExpansion,
      firstDeparture: firstDeparture,
      originStopId: originStopId,
      originStopName: _stringOrNull(origin['name']) ?? '',
      lineKey: lineKey,
      directionKey: directionKey,
      baseTripId: _journeyLegTripId(firstRide),
      transferStopId: transferStopId,
      transferStopName: transferStopName,
      transferLat: _locationLat(transfer),
      transferLng: _locationLng(transfer),
      secondLineKey: secondLineKey,
      secondDirectionKey: secondDirectionKey,
      secondDestinationStopId: secondDestinationStopId,
      secondDestinationStopName: secondDestinationStopName,
      trailingLegs: trailingLegs,
      dedupeKey:
          '$originStopId|$lineKey|$directionKey|$transferStopId|$transferStopName'
          '|$secondLineKey|$secondDirectionKey|$secondDestinationStopId|$secondDestinationStopName',
    );
  }

  static String _stopDepartureLineKey(Map<String, dynamic> departure) =>
      _normalizeTransitKey(
        departure['routeShortName'] ??
            departure['displayName'] ??
            (departure['line'] as Map<String, dynamic>?)?['name'],
      );

  static String _stopDepartureDirectionKey(Map<String, dynamic> departure) {
    final tripTo = departure['tripTo'] as Map<String, dynamic>?;
    return _normalizeTransitKey(
      departure['headsign'] ?? tripTo?['name'] ?? departure['direction'],
    );
  }

  static String? _stopDepartureTripId(Map<String, dynamic> departure) {
    final trip = departure['trip'];
    final trips = departure['trips'] as List?;
    final depObj = departure['departure'] as Map<String, dynamic>?;
    final line = departure['line'] as Map<String, dynamic>?;
    final candidates = <Object?>[
      departure['tripId'],
      depObj?['tripId'],
      depObj?['id'],
      line?['tripId'],
      if (trip is Map<String, dynamic>) trip['tripId'],
      if (trip is Map<String, dynamic>) trip['id'],
      if (trip is String) trip,
      if (trips != null && trips.isNotEmpty && trips.first is Map)
        (trips.first as Map)['tripId'],
      if (trips != null && trips.isNotEmpty && trips.first is Map)
        (trips.first as Map)['id'],
    ];
    for (final candidate in candidates) {
      final text = candidate?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  static Future<List<Map<String, dynamic>>> _fetchMotisStopDeparturesWindow(
    String stationId, {
    required DateTime startLocal,
    required DateTime endLocal,
    int maxResults = 40,
  }) async {
    final cacheKey =
        '$stationId|${startLocal.toIso8601String()}|${endLocal.toIso8601String()}|$maxResults';
    final cached = _syntheticStopDeparturesCache[cacheKey];
    if (cached != null && !cached.isExpired) {
      return cached.data;
    }

    final departures = await _fetchMotisStopDepartures(
      stationId,
      startLocal: startLocal,
      endLocal: endLocal,
      maxResults: maxResults,
    );
    _syntheticStopDeparturesCache[cacheKey] = _CacheEntry(
      departures,
      _syntheticStopDeparturesCacheTtl,
    );
    return departures;
  }

  static List<Map<String, dynamic>> _tripLegStopSequence(
    Map<String, dynamic> leg,
  ) {
    final sequence = <Map<String, dynamic>>[];
    final from = (leg['from'] as Map?)?.cast<String, dynamic>();
    final to = (leg['to'] as Map?)?.cast<String, dynamic>();

    if (from != null) {
      sequence.add({
        'place': from,
        'arrival': leg['startTime'],
        'departure': leg['startTime'],
        'scheduledArrival': leg['scheduledStartTime'],
        'scheduledDeparture': leg['scheduledStartTime'],
      });
    }

    final intermediates = (leg['intermediateStops'] as List?)
            ?.whereType<Map>()
            .map((stop) => Map<String, dynamic>.from(stop))
            .toList() ??
        const <Map<String, dynamic>>[];
    for (final stop in intermediates) {
      sequence.add({
        'place': stop,
        'arrival': stop['arrival'],
        'departure': stop['departure'],
        'scheduledArrival': stop['scheduledArrival'],
        'scheduledDeparture': stop['scheduledDeparture'],
      });
    }

    if (to != null) {
      sequence.add({
        'place': to,
        'arrival': leg['endTime'],
        'departure': leg['endTime'],
        'scheduledArrival': leg['scheduledEndTime'],
        'scheduledDeparture': leg['scheduledEndTime'],
      });
    }

    return sequence;
  }

  static bool _tripPlaceMatchesTarget(
    Map<String, dynamic> place,
    String stopId,
    String stopName,
  ) {
    final placeId =
        _stringOrNull(place['stopId']) ?? _stringOrNull(place['id']);
    if (stopId.isNotEmpty && placeId == stopId) return true;

    if (stopName.isEmpty) return false;
    final normalizedName = _normalizeTransitKey(place['name']);
    return normalizedName.isNotEmpty &&
        normalizedName == _normalizeTransitKey(stopName);
  }

  static int _tripStopIndex(
    List<Map<String, dynamic>> sequence,
    String stopId,
    String stopName,
  ) {
    for (var index = 0; index < sequence.length; index++) {
      final place =
          (sequence[index]['place'] as Map?)?.cast<String, dynamic>() ??
              const {};
      if (_tripPlaceMatchesTarget(place, stopId, stopName)) return index;
    }
    return -1;
  }

  static Map<String, dynamic> _journeyLocationFromTripPlace(
    Map<String, dynamic> place,
  ) {
    final platform = place['track'] ?? place['scheduledTrack'];
    return {
      'id': place['stopId'] ?? place['id'] ?? '',
      'name': place['name'] ?? '',
      'type': 'stop',
      'location': {
        'latitude': place['lat'],
        'longitude': place['lon'],
      },
      if (platform != null) 'platform': platform,
      if (place['scheduledTrack'] != null)
        'scheduledPlatform': place['scheduledTrack'],
      if (place['description'] != null) 'stopLabel': place['description'],
      if (place['parentId'] != null) 'parentId': place['parentId'],
    };
  }

  static int? _delaySecondsFromStrings(String? scheduled, String? actual) {
    if (scheduled == null || actual == null) return null;
    try {
      return DateTime.parse(actual)
          .difference(DateTime.parse(scheduled))
          .inSeconds;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _journeyStopoverFromTripStop(
    Map<String, dynamic> stop,
  ) {
    final place = (stop['place'] as Map?)?.cast<String, dynamic>() ?? const {};
    final platform = place['track'] ?? place['scheduledTrack'];
    return {
      'stop': _journeyLocationFromTripPlace(place),
      'arrival': stop['arrival'],
      'departure': stop['departure'],
      'plannedArrival': stop['scheduledArrival'],
      'plannedDeparture': stop['scheduledDeparture'],
      'arrivalDelay': _delaySecondsFromStrings(
        stop['scheduledArrival']?.toString(),
        stop['arrival']?.toString(),
      ),
      'departureDelay': _delaySecondsFromStrings(
        stop['scheduledDeparture']?.toString(),
        stop['departure']?.toString(),
      ),
      if (platform != null) 'platform': platform,
    };
  }

  static Map<String, dynamic>? _buildSyntheticFirstRide(
    _SyntheticSeed seed,
    Map<String, dynamic> tripItinerary,
    String tripId,
  ) =>
      _buildSyntheticRideSegment(
        templateRide: seed.firstRide,
        tripItinerary: tripItinerary,
        tripId: tripId,
        fromStopId: seed.originStopId,
        fromStopName: seed.originStopName,
        toStopId: seed.transferStopId,
        toStopName: seed.transferStopName,
      );

  static Map<String, dynamic>? _buildSyntheticRideSegment({
    required Map<String, dynamic> templateRide,
    required Map<String, dynamic> tripItinerary,
    required String tripId,
    required String fromStopId,
    required String fromStopName,
    required String toStopId,
    required String toStopName,
  }) {
    final legs = (tripItinerary['legs'] as List?)
            ?.whereType<Map>()
            .map((leg) => Map<String, dynamic>.from(leg))
            .toList() ??
        const <Map<String, dynamic>>[];
    if (legs.isEmpty) return null;

    for (final tripLeg in legs) {
      final sequence = _tripLegStopSequence(tripLeg);
      final fromIndex = _tripStopIndex(sequence, fromStopId, fromStopName);
      final toIndex = _tripStopIndex(sequence, toStopId, toStopName);
      if (fromIndex == -1 || toIndex == -1 || toIndex <= fromIndex) {
        continue;
      }

      final originStop = sequence[fromIndex];
      final transferStop = sequence[toIndex];
      final departure = _stringOrNull(
        originStop['departure'] ??
            originStop['scheduledDeparture'] ??
            originStop['arrival'] ??
            originStop['scheduledArrival'],
      );
      final arrival = _stringOrNull(
        transferStop['arrival'] ??
            transferStop['scheduledArrival'] ??
            transferStop['departure'] ??
            transferStop['scheduledDeparture'],
      );
      if (departure == null || arrival == null) continue;

      final line =
          (templateRide['line'] as Map?)?.cast<String, dynamic>() != null
              ? Map<String, dynamic>.from(
                  (templateRide['line'] as Map).cast<String, dynamic>(),
                )
              : <String, dynamic>{'name': _journeyLegLineName(templateRide)};
      if (tripId.isNotEmpty) {
        line['tripId'] = tripId;
      }

      final intermediateStopovers = sequence
          .sublist(fromIndex + 1, toIndex)
          .map(_journeyStopoverFromTripStop)
          .toList();
      final originPlace =
          (originStop['place'] as Map?)?.cast<String, dynamic>() ?? const {};
      final transferPlace =
          (transferStop['place'] as Map?)?.cast<String, dynamic>() ?? const {};

      return {
        'origin': _journeyLocationFromTripPlace(originPlace),
        'destination': _journeyLocationFromTripPlace(transferPlace),
        'departure': departure,
        'arrival': arrival,
        'plannedDeparture': originStop['scheduledDeparture'] ??
            originStop['departure'] ??
            originStop['scheduledArrival'] ??
            originStop['arrival'],
        'plannedArrival': transferStop['scheduledArrival'] ??
            transferStop['arrival'] ??
            transferStop['scheduledDeparture'] ??
            transferStop['departure'],
        'departureDelay': _delaySecondsFromStrings(
          (originStop['scheduledDeparture'] ?? originStop['scheduledArrival'])
              ?.toString(),
          (originStop['departure'] ?? originStop['arrival'])?.toString(),
        ),
        'arrivalDelay': _delaySecondsFromStrings(
          (transferStop['scheduledArrival'] ??
                  transferStop['scheduledDeparture'])
              ?.toString(),
          (transferStop['arrival'] ?? transferStop['departure'])?.toString(),
        ),
        'reachable': true,
        'line': line,
        'direction': templateRide['direction'],
        if (intermediateStopovers.isNotEmpty)
          'stopovers': intermediateStopovers,
        if (templateRide['polyline'] != null)
          'polyline': templateRide['polyline'],
        if (templateRide['decodedPath'] != null)
          'decodedPath': templateRide['decodedPath'],
        'tripId': tripId,
      };
    }

    return null;
  }

  static String? _shiftIsoTimeString(Object? value, Duration delta) {
    final parsed = _parseJourneyTimeLocal(value);
    if (parsed == null) return value?.toString();
    return parsed.add(delta).toIso8601String();
  }

  static Map<String, dynamic> _shiftLegTimes(
    Map<String, dynamic> leg,
    Duration delta,
  ) {
    final shifted = Map<String, dynamic>.from(leg);
    for (final key in const [
      'departure',
      'arrival',
      'plannedDeparture',
      'plannedArrival',
    ]) {
      if (shifted.containsKey(key)) {
        shifted[key] = _shiftIsoTimeString(shifted[key], delta);
      }
    }

    final rawStopovers = shifted['stopovers'] as List?;
    if (rawStopovers != null) {
      shifted['stopovers'] = rawStopovers.whereType<Map>().map((stopover) {
        final mapped = Map<String, dynamic>.from(stopover);
        for (final key in const [
          'arrival',
          'departure',
          'plannedArrival',
          'plannedDeparture',
        ]) {
          if (mapped.containsKey(key)) {
            mapped[key] = _shiftIsoTimeString(mapped[key], delta);
          }
        }
        return mapped;
      }).toList();
    }

    return shifted;
  }

  static String _journeyKey(Map<String, dynamic> journey) {
    final departure = _stringOrNull(
          journey['plannedDeparture'] ?? journey['departure'],
        ) ??
        '';
    final arrival =
        _stringOrNull(journey['plannedArrival'] ?? journey['arrival']) ?? '';
    String firstLine = '';
    final legs = journey['legs'] as List?;
    if (legs != null) {
      for (final leg in legs.whereType<Map>()) {
        final mapped = leg.cast<String, dynamic>();
        if (mapped['line'] != null) {
          firstLine = _journeyLegLineName(mapped);
          break;
        }
      }
    }
    return '$departure|$arrival|$firstLine';
  }

  static Map<String, dynamic>? _firstRideLegFromJourney(
    Map<String, dynamic> journey,
  ) {
    final legs = journey['legs'] as List?;
    if (legs == null) return null;
    for (final leg in legs.whereType<Map>()) {
      final mapped = leg.cast<String, dynamic>();
      if (mapped['line'] != null) return mapped;
    }
    return null;
  }

  static String? _journeyFirstRideKey(Map<String, dynamic> journey) {
    final firstRide = _firstRideLegFromJourney(journey);
    if (firstRide == null) return null;

    final origin = (firstRide['origin'] as Map?)?.cast<String, dynamic>();
    final originStopId = _stringOrNull(origin?['id']) ?? '';
    final lineKey = _normalizeTransitKey(_journeyLegLineName(firstRide));
    final directionKey = _normalizeTransitKey(firstRide['direction']);
    final tripId = _journeyLegTripId(firstRide) ?? '';
    final departure = _stringOrNull(
          firstRide['plannedDeparture'] ?? firstRide['departure'],
        ) ??
        '';

    if (originStopId.isEmpty &&
        lineKey.isEmpty &&
        directionKey.isEmpty &&
        tripId.isEmpty &&
        departure.isEmpty) {
      return null;
    }

    return '$originStopId|$lineKey|$directionKey|$tripId|$departure';
  }

  static int _journeySyntheticPreferenceScore(Map<String, dynamic> journey) {
    final source = journey['source']?.toString();
    if (source == 'motis_synthetic') return 1;
    return 0;
  }

  static int _compareJourneyPreference(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final sourceScore = _journeySyntheticPreferenceScore(a).compareTo(
      _journeySyntheticPreferenceScore(b),
    );
    if (sourceScore != 0) return sourceScore;

    final arrivalA = _parseJourneyTimeLocal(
      a['plannedArrival'] ?? a['arrival'],
    );
    final arrivalB = _parseJourneyTimeLocal(
      b['plannedArrival'] ?? b['arrival'],
    );
    if (arrivalA != null && arrivalB != null) {
      final arrivalCompare = arrivalA.compareTo(arrivalB);
      if (arrivalCompare != 0) return arrivalCompare;
    }

    final departureA = _parseJourneyTimeLocal(
      a['plannedDeparture'] ?? a['departure'],
    );
    final departureB = _parseJourneyTimeLocal(
      b['plannedDeparture'] ?? b['departure'],
    );
    if (departureA != null && departureB != null) {
      return departureA.compareTo(departureB);
    }

    return 0;
  }

  static DateTime? _journeyFirstRideDepartureLocal(
    Map<String, dynamic> journey,
  ) {
    final firstRide = _firstRideLegFromJourney(journey);
    if (firstRide == null) return null;
    return _parseJourneyTimeLocal(
      firstRide['plannedDeparture'] ?? firstRide['departure'],
    );
  }

  static List<Map<String, dynamic>> _limitSyntheticToBaseRideWindow(
    List<Map<String, dynamic>> journeys,
  ) {
    final baseJourneys = journeys
        .where((journey) => journey['source']?.toString() != 'motis_synthetic')
        .toList();
    if (baseJourneys.isEmpty) return journeys;

    DateTime? minBaseDeparture;
    DateTime? maxBaseDeparture;
    for (final journey in baseJourneys) {
      final departure = _journeyFirstRideDepartureLocal(journey);
      if (departure == null) continue;
      if (minBaseDeparture == null || departure.isBefore(minBaseDeparture)) {
        minBaseDeparture = departure;
      }
      if (maxBaseDeparture == null || departure.isAfter(maxBaseDeparture)) {
        maxBaseDeparture = departure;
      }
    }

    if (minBaseDeparture == null || maxBaseDeparture == null) {
      return journeys;
    }
    final minDeparture = minBaseDeparture;
    final maxDeparture = maxBaseDeparture;

    return journeys.where((journey) {
      if (journey['source']?.toString() != 'motis_synthetic') {
        return true;
      }
      final departure = _journeyFirstRideDepartureLocal(journey);
      if (departure == null) return false;
      return !departure.isBefore(minDeparture) &&
          !departure.isAfter(maxDeparture);
    }).toList();
  }

  static ({DateTime? minDeparture, DateTime? maxDeparture})
      _baseRideDepartureWindow(List<Map<String, dynamic>> journeys) {
    DateTime? minDeparture;
    DateTime? maxDeparture;
    for (final journey in journeys) {
      if (journey['source']?.toString() == 'motis_synthetic') continue;
      final departure = _journeyFirstRideDepartureLocal(journey);
      if (departure == null) continue;
      if (minDeparture == null || departure.isBefore(minDeparture)) {
        minDeparture = departure;
      }
      if (maxDeparture == null || departure.isAfter(maxDeparture)) {
        maxDeparture = departure;
      }
    }
    return (minDeparture: minDeparture, maxDeparture: maxDeparture);
  }

  static List<Map<String, dynamic>> _dedupeAndSortJourneys(
    List<Map<String, dynamic>> journeys,
  ) {
    final deduped = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final journey in journeys) {
      final key = _journeyKey(journey);
      if (seen.add(key)) deduped.add(journey);
    }

    final firstRideDeduped = <Map<String, dynamic>>[];
    final firstRideIndex = <String, int>{};
    for (final journey in deduped) {
      final firstRideKey = _journeyFirstRideKey(journey);
      if (firstRideKey == null) {
        firstRideDeduped.add(journey);
        continue;
      }

      final existingIndex = firstRideIndex[firstRideKey];
      if (existingIndex == null) {
        firstRideIndex[firstRideKey] = firstRideDeduped.length;
        firstRideDeduped.add(journey);
        continue;
      }

      final existing = firstRideDeduped[existingIndex];
      if (_compareJourneyPreference(journey, existing) < 0) {
        firstRideDeduped[existingIndex] = journey;
      }
    }

    firstRideDeduped.sort((a, b) {
      final depA = _parseJourneyTimeLocal(
        a['plannedDeparture'] ?? a['departure'],
      );
      final depB = _parseJourneyTimeLocal(
        b['plannedDeparture'] ?? b['departure'],
      );
      if (depA == null || depB == null) return 0;
      return depA.compareTo(depB);
    });
    return firstRideDeduped;
  }

  static Map<String, dynamic> _buildSyntheticJourney(
    _SyntheticSeed seed,
    Map<String, dynamic> firstRide,
    Map<String, dynamic> onwardJourney,
    String tripId,
  ) {
    final onwardLegs = (onwardJourney['legs'] as List?)
            ?.whereType<Map>()
            .map((leg) => Map<String, dynamic>.from(leg))
            .toList() ??
        const <Map<String, dynamic>>[];

    return {
      'type': 'journey',
      'legs': [firstRide, ...onwardLegs],
      'departure': firstRide['departure'],
      'arrival': onwardJourney['arrival'] ??
          onwardJourney['plannedArrival'] ??
          (onwardLegs.isNotEmpty
              ? onwardLegs.last['arrival'] ?? onwardLegs.last['plannedArrival']
              : null),
      'plannedDeparture':
          firstRide['plannedDeparture'] ?? firstRide['departure'],
      'plannedArrival': onwardJourney['plannedArrival'] ??
          onwardJourney['arrival'] ??
          (onwardLegs.isNotEmpty
              ? onwardLegs.last['plannedArrival'] ?? onwardLegs.last['arrival']
              : null),
      'source': 'motis_synthetic',
      'synthetic': true,
      'syntheticBaseDeparture': seed.firstDeparture.toUtc().toIso8601String(),
      'syntheticTripId': tripId,
    };
  }

  static Map<String, dynamic> _buildSyntheticJourneyFromLegs(
    _SyntheticSeed seed,
    List<Map<String, dynamic>> legs, {
    required String firstTripId,
    String? secondTripId,
  }) {
    final firstLeg = legs.first;
    final lastLeg = legs.last;
    return {
      'type': 'journey',
      'legs': legs,
      'departure': firstLeg['departure'] ?? firstLeg['plannedDeparture'],
      'arrival': lastLeg['arrival'] ??
          lastLeg['plannedArrival'] ??
          lastLeg['departure'] ??
          lastLeg['plannedDeparture'],
      'plannedDeparture': firstLeg['plannedDeparture'] ?? firstLeg['departure'],
      'plannedArrival': lastLeg['plannedArrival'] ??
          lastLeg['arrival'] ??
          lastLeg['plannedDeparture'] ??
          lastLeg['departure'],
      'source': 'motis_synthetic',
      'synthetic': true,
      'syntheticBaseDeparture': seed.firstDeparture.toUtc().toIso8601String(),
      'syntheticTripId': firstTripId,
      if (secondTripId != null) 'syntheticTransferTripId': secondTripId,
    };
  }

  static Future<List<Map<String, dynamic>>> _expandSyntheticSeedViaSharedFamily(
    _SyntheticSeed seed,
    List<Map<String, dynamic>> matchingFirstDepartures, {
    DateTime? minSyntheticDeparture,
    DateTime? maxSyntheticDeparture,
    void Function(List<Map<String, dynamic>> syntheticSoFar)? onProgress,
    bool Function()? shouldContinue,
  }) async {
    if (!seed.supportsSharedFamilyExpansion || seed.transferStopId.isEmpty) {
      return const <Map<String, dynamic>>[];
    }

    final dayStart = DateTime(
      seed.firstDeparture.year,
      seed.firstDeparture.month,
      seed.firstDeparture.day,
    );
    final dayEnd = DateTime(
      seed.firstDeparture.year,
      seed.firstDeparture.month,
      seed.firstDeparture.day,
      23,
      59,
      59,
    );

    final secondDepartures = await _fetchMotisStopDeparturesWindow(
      seed.transferStopId,
      startLocal: dayStart,
      endLocal: dayEnd,
      maxResults: 400,
    );
    final matchingSecondDepartures = secondDepartures.where((departure) {
      final time = _stopDepartureDateTimeLocal(departure);
      if (time == null) return false;
      if (_stopDepartureLineKey(departure) != seed.secondLineKey) return false;
      final directionKey = _stopDepartureDirectionKey(departure);
      if (seed.secondDirectionKey.isNotEmpty &&
          directionKey.isNotEmpty &&
          directionKey != seed.secondDirectionKey) {
        return false;
      }
      return _stopDepartureTripId(departure)?.isNotEmpty == true;
    }).toList()
      ..sort((a, b) {
        final timeA = _stopDepartureDateTimeLocal(a);
        final timeB = _stopDepartureDateTimeLocal(b);
        if (timeA == null || timeB == null) return 0;
        return timeA.compareTo(timeB);
      });

    if (matchingSecondDepartures.isEmpty) {
      _syntheticLog(
        'shared family unavailable: ${seed.dedupeKey} second departures=0',
      );
      return const <Map<String, dynamic>>[];
    }

    _syntheticLog(
      'shared family ready: ${seed.dedupeKey} secondDepartures=${matchingSecondDepartures.length}',
    );

    final synthetic = <Map<String, dynamic>>[];
    var lastProgressCount = 0;
    final baseSecondArrival = _parseJourneyTimeLocal(
      seed.transferRide['arrival'] ?? seed.transferRide['plannedArrival'],
    );

    for (final departure in matchingFirstDepartures) {
      if (!(shouldContinue?.call() ?? true)) {
        _syntheticLog('shared family aborted: ${seed.dedupeKey}');
        break;
      }

      final firstTripId = _stopDepartureTripId(departure);
      if (firstTripId == null || firstTripId.isEmpty) continue;

      final firstDepartureTime = _stopDepartureDateTimeLocal(departure);
      if (firstDepartureTime == null) continue;
      if (minSyntheticDeparture != null &&
          firstDepartureTime.isBefore(minSyntheticDeparture)) {
        continue;
      }
      if (maxSyntheticDeparture != null &&
          firstDepartureTime.isAfter(maxSyntheticDeparture)) {
        continue;
      }
      final firstTripItinerary = await _fetchTripItineraryCached(firstTripId);
      if (firstTripItinerary == null) {
        continue;
      }

      final syntheticFirstRide = _buildSyntheticFirstRide(
        seed,
        firstTripItinerary,
        firstTripId,
      );
      if (syntheticFirstRide == null) {
        continue;
      }

      final firstRideArrival = _parseJourneyTimeLocal(
        syntheticFirstRide['arrival'] ?? syntheticFirstRide['plannedArrival'],
      );
      if (firstRideArrival == null) {
        continue;
      }

      final earliestSecondDeparture =
          firstRideArrival.add(_syntheticTransferSlack);
      Map<String, dynamic>? secondDeparture;
      for (final candidate in matchingSecondDepartures) {
        final candidateTime = _stopDepartureDateTimeLocal(candidate);
        if (candidateTime == null ||
            candidateTime.isBefore(earliestSecondDeparture)) {
          continue;
        }
        secondDeparture = candidate;
        break;
      }
      if (secondDeparture == null) {
        _syntheticLog(
          'shared family trip $firstTripId ${_formatDebugTime(firstDepartureTime)} '
          'skipped: no matching second departure after ${_formatDebugTime(firstRideArrival)}',
        );
        continue;
      }

      final secondTripId = _stopDepartureTripId(secondDeparture);
      if (secondTripId == null || secondTripId.isEmpty) continue;
      final secondTripItinerary = await _fetchTripItineraryCached(secondTripId);
      if (secondTripItinerary == null) {
        continue;
      }

      final syntheticSecondRide = _buildSyntheticRideSegment(
        templateRide: seed.transferRide,
        tripItinerary: secondTripItinerary,
        tripId: secondTripId,
        fromStopId: seed.transferStopId,
        fromStopName: seed.transferStopName,
        toStopId: seed.secondDestinationStopId,
        toStopName: seed.secondDestinationStopName,
      );
      if (syntheticSecondRide == null) {
        _syntheticLog(
          'shared family trip $firstTripId -> $secondTripId skipped: '
          'second trip does not map ${seed.transferStopName} -> ${seed.secondDestinationStopName}',
        );
        continue;
      }

      final legs = <Map<String, dynamic>>[
        syntheticFirstRide,
        syntheticSecondRide,
      ];
      final syntheticSecondArrival = _parseJourneyTimeLocal(
        syntheticSecondRide['arrival'] ?? syntheticSecondRide['plannedArrival'],
      );
      if (baseSecondArrival != null &&
          syntheticSecondArrival != null &&
          seed.trailingLegs.isNotEmpty) {
        final delta = syntheticSecondArrival.difference(baseSecondArrival);
        legs.addAll(
          seed.trailingLegs.map((leg) => _shiftLegTimes(leg, delta)),
        );
      }

      synthetic.add(
        _buildSyntheticJourneyFromLegs(
          seed,
          legs,
          firstTripId: firstTripId,
          secondTripId: secondTripId,
        ),
      );

      final shouldEmitProgress =
          synthetic.length - lastProgressCount >= _syntheticProgressBatchSize;
      if ((shouldContinue?.call() ?? true) && shouldEmitProgress) {
        lastProgressCount = synthetic.length;
        onProgress?.call(List<Map<String, dynamic>>.from(synthetic));
      }
    }

    if ((shouldContinue?.call() ?? true) &&
        synthetic.length > lastProgressCount) {
      onProgress?.call(List<Map<String, dynamic>>.from(synthetic));
    }

    return synthetic;
  }

  static bool _journeyMatchesQueryWindow(
    Map<String, dynamic> journey, {
    required DateTime? when,
    required bool isArrival,
  }) {
    if (when == null) return true;

    final reference = when.toLocal();
    final departure = _parseJourneyTimeLocal(
      journey['plannedDeparture'] ?? journey['departure'],
    );
    final arrival = _parseJourneyTimeLocal(
      journey['plannedArrival'] ?? journey['arrival'],
    );

    if (isArrival) {
      return arrival == null || !arrival.isAfter(reference);
    }

    return departure == null || !departure.isBefore(reference);
  }

  static Future<List<Map<String, dynamic>>> _expandSyntheticSeed(
    _SyntheticSeed seed,
    Station destination, {
    required bool nahverkehrOnly,
    DateTime? minSyntheticDeparture,
    DateTime? maxSyntheticDeparture,
    void Function(List<Map<String, dynamic>> syntheticSoFar)? onProgress,
    bool Function()? shouldContinue,
  }) async {
    _syntheticLog(
      'seed start: ${seed.originStopName} ${_formatDebugTime(seed.firstDeparture)} '
      '${_journeyLegLineName(seed.firstRide)} -> ${seed.firstRide['direction'] ?? '?'} '
      'transfer=${seed.transferStopName}',
    );

    final dayStart = DateTime(
      seed.firstDeparture.year,
      seed.firstDeparture.month,
      seed.firstDeparture.day,
    );
    final dayEnd = DateTime(
      seed.firstDeparture.year,
      seed.firstDeparture.month,
      seed.firstDeparture.day,
      23,
      59,
      59,
    );

    final departures = await _fetchMotisStopDeparturesWindow(
      seed.originStopId,
      startLocal: dayStart,
      endLocal: dayEnd,
      maxResults: 400,
    );
    if (departures.isEmpty) return const <Map<String, dynamic>>[];

    var missingTime = 0;
    var tooEarly = 0;
    var lineMismatch = 0;
    var directionMismatch = 0;
    var missingTripId = 0;
    var sameBaseTrip = 0;

    final matchingDepartures = departures.where((departure) {
      final time = _stopDepartureDateTimeLocal(departure);
      if (time == null) {
        missingTime++;
        return false;
      }
      if (!time.isAfter(seed.firstDeparture.add(const Duration(seconds: 30)))) {
        tooEarly++;
        return false;
      }
      if (minSyntheticDeparture != null &&
          time.isBefore(minSyntheticDeparture)) {
        tooEarly++;
        return false;
      }
      if (maxSyntheticDeparture != null &&
          time.isAfter(maxSyntheticDeparture)) {
        return false;
      }
      if (_stopDepartureLineKey(departure) != seed.lineKey) {
        lineMismatch++;
        return false;
      }
      final directionKey = _stopDepartureDirectionKey(departure);
      if (seed.directionKey.isNotEmpty &&
          directionKey.isNotEmpty &&
          directionKey != seed.directionKey) {
        directionMismatch++;
        return false;
      }
      final tripId = _stopDepartureTripId(departure);
      if (tripId == null || tripId.isEmpty) {
        missingTripId++;
        return false;
      }
      if (seed.baseTripId != null && seed.baseTripId == tripId) {
        sameBaseTrip++;
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) {
        final timeA = _stopDepartureDateTimeLocal(a);
        final timeB = _stopDepartureDateTimeLocal(b);
        if (timeA == null || timeB == null) return 0;
        return timeA.compareTo(timeB);
      });

    _syntheticLog(
      'seed departures: raw=${departures.length} matching=${matchingDepartures.length} '
      'missingTime=$missingTime tooEarly=$tooEarly lineMismatch=$lineMismatch '
      'directionMismatch=$directionMismatch missingTripId=$missingTripId sameBaseTrip=$sameBaseTrip',
    );

    if (seed.supportsSharedFamilyExpansion) {
      final sharedSynthetic = await _expandSyntheticSeedViaSharedFamily(
        seed,
        matchingDepartures,
        minSyntheticDeparture: minSyntheticDeparture,
        maxSyntheticDeparture: maxSyntheticDeparture,
        onProgress: onProgress,
        shouldContinue: shouldContinue,
      );
      if (sharedSynthetic.isNotEmpty) {
        _syntheticLog(
          'seed done: generated=${sharedSynthetic.length} '
          'shared family for ${_journeyLegLineName(seed.firstRide)} -> '
          '${_journeyLegLineName(seed.transferRide)}',
        );
        return sharedSynthetic;
      }
      _syntheticLog('shared family fallback: ${seed.dedupeKey}');
    }

    final synthetic = <Map<String, dynamic>>[];
    final seenTrips = <String>{};
    var lastProgressCount = 0;

    for (final departure in matchingDepartures) {
      if (!(shouldContinue?.call() ?? true)) {
        _syntheticLog('seed aborted: ${seed.dedupeKey}');
        break;
      }
      final tripId = _stopDepartureTripId(departure);
      if (tripId == null || !seenTrips.add(tripId)) continue;

      final departureTime = _stopDepartureDateTimeLocal(departure);

      final tripItinerary = await _fetchTripItineraryCached(tripId);
      if (tripItinerary == null) {
        _syntheticLog(
          'trip $tripId ${_formatDebugTime(departureTime)} skipped: no trip itinerary',
        );
        continue;
      }

      final syntheticFirstRide = _buildSyntheticFirstRide(
        seed,
        tripItinerary,
        tripId,
      );
      if (syntheticFirstRide == null) {
        _syntheticLog(
          'trip $tripId ${_formatDebugTime(departureTime)} skipped: '
          'trip does not map ${seed.originStopName} -> ${seed.transferStopName}',
        );
        continue;
      }

      final firstRideArrival = _parseJourneyTimeLocal(
        syntheticFirstRide['arrival'] ?? syntheticFirstRide['plannedArrival'],
      );
      if (firstRideArrival == null) {
        _syntheticLog(
          'trip $tripId ${_formatDebugTime(departureTime)} skipped: no forced-arrival time',
        );
        continue;
      }
      if (seed.transferStopId.isEmpty &&
          (seed.transferLat == null || seed.transferLng == null)) {
        _syntheticLog(
          'trip $tripId ${_formatDebugTime(departureTime)} skipped: transfer station lacks id/coords',
        );
        continue;
      }

      final transferStation = Station(
        id: seed.transferStopId,
        name: seed.transferStopName,
        type: 'stop',
        latitude: seed.transferLat,
        longitude: seed.transferLng,
      );

      final onwardJourneys = await _searchJourneysMotis(
        transferStation,
        destination,
        nahverkehrOnly: nahverkehrOnly,
        when: firstRideArrival.add(_syntheticTransferSlack),
        isArrival: false,
        results: _syntheticOnwardResultsPerDeparture,
      );
      if (onwardJourneys.isEmpty) {
        _syntheticLog(
          'trip $tripId ${_formatDebugTime(departureTime)} -> ${seed.transferStopName} '
          '${_formatDebugTime(firstRideArrival)} skipped: onward search returned 0',
        );
        continue;
      }

      final onwardJourney = onwardJourneys.first;
      _syntheticLog(
        'trip $tripId ${_formatDebugTime(departureTime)} -> ${seed.transferStopName} '
        '${_formatDebugTime(firstRideArrival)} onward=1/${onwardJourneys.length}',
      );

      synthetic.add(
        _buildSyntheticJourney(
          seed,
          syntheticFirstRide,
          onwardJourney,
          tripId,
        ),
      );
      final shouldEmitProgress =
          synthetic.length - lastProgressCount >= _syntheticProgressBatchSize;
      if ((shouldContinue?.call() ?? true) && shouldEmitProgress) {
        lastProgressCount = synthetic.length;
        onProgress?.call(List<Map<String, dynamic>>.from(synthetic));
      }
    }

    if ((shouldContinue?.call() ?? true) &&
        synthetic.length > lastProgressCount) {
      onProgress?.call(List<Map<String, dynamic>>.from(synthetic));
    }

    _syntheticLog(
      'seed done: generated=${synthetic.length} '
      'for ${_journeyLegLineName(seed.firstRide)} -> ${seed.transferStopName}',
    );

    return synthetic;
  }

  static Future<List<Map<String, dynamic>>> _augmentJourneysWithSynthetic(
    Station from,
    Station to,
    List<Map<String, dynamic>> journeys, {
    required DateTime? when,
    required bool nahverkehrOnly,
    required bool isArrival,
    void Function(List<Map<String, dynamic>> mergedJourneys)? onProgress,
    bool Function()? shouldContinue,
  }) async {
    if (!isSyntheticTransitousEnabled || journeys.isEmpty) {
      return journeys;
    }

    var motisJourneys = 0;
    var transferCandidates = 0;
    final seeds = <_SyntheticSeed>[];
    final seenSeedKeys = <String>{};
    for (final journey in journeys) {
      if (journey['source'] == 'motis') {
        motisJourneys++;
        final rawLegs = journey['legs'] as List?;
        final rideCount = rawLegs
                ?.whereType<Map>()
                .where((leg) => leg['line'] != null)
                .length ??
            0;
        if (rideCount >= 2) transferCandidates++;
      }
      final seed = _syntheticSeedFromJourney(journey);
      if (seed == null || !seenSeedKeys.add(seed.dedupeKey)) continue;
      seeds.add(seed);
    }
    _syntheticLog(
      'augment ${from.name} -> ${to.name}: base=${journeys.length} '
      'motis=$motisJourneys transferCandidates=$transferCandidates seeds=${seeds.length}',
    );
    if (seeds.isEmpty) return journeys;
    final rideWindow = _baseRideDepartureWindow(journeys);

    final synthetic = <Map<String, dynamic>>[];
    for (final seed in seeds) {
      if (!(shouldContinue?.call() ?? true)) {
        _syntheticLog('augment aborted before seed ${seed.dedupeKey}');
        break;
      }
      try {
        final expanded = await _expandSyntheticSeed(
          seed,
          to,
          nahverkehrOnly: nahverkehrOnly,
          minSyntheticDeparture: rideWindow.minDeparture,
          maxSyntheticDeparture: rideWindow.maxDeparture,
          onProgress: (seedSyntheticSoFar) {
            if (onProgress == null) return;
            final merged = _dedupeAndSortJourneys([
              ...journeys,
              ...synthetic,
              ...seedSyntheticSoFar,
            ]);
            final bounded = _limitSyntheticToBaseRideWindow(merged);
            final visible = bounded.where((journey) {
              return _journeyMatchesQueryWindow(
                journey,
                when: when,
                isArrival: isArrival,
              );
            }).toList();
            _syntheticLog(
              'augment progress ${from.name} -> ${to.name}: '
              'seedPartial=${seedSyntheticSoFar.length} visible=${visible.length}',
            );
            onProgress(visible);
          },
          shouldContinue: shouldContinue,
        );
        synthetic.addAll(expanded);
      } catch (error) {
        debugPrint('Synthetic expansion skipped for ${seed.dedupeKey}: $error');
      }
    }

    _syntheticLog(
      'augment result ${from.name} -> ${to.name}: synthetic=${synthetic.length}',
    );

    if (synthetic.isEmpty) return journeys;
    final merged = _dedupeAndSortJourneys([...journeys, ...synthetic]);
    final bounded = _limitSyntheticToBaseRideWindow(merged);
    final visible = bounded.where((journey) {
      return _journeyMatchesQueryWindow(
        journey,
        when: when,
        isArrival: isArrival,
      );
    }).toList();
    _syntheticLog(
      'augment merged ${from.name} -> ${to.name}: final=${visible.length}',
    );
    return visible;
  }

  /// Get nearby stops by coordinates
  /// Uses in-memory cache, tries Transitous first, falls back to v6.db
  static Future<List<Station>> getNearbyStops(double lat, double lng) async {
    _pruneExpiredCaches();
    // Check cache (with rounded coords for better hit rate)
    final roundedLat = (lat * 1000).round() / 1000;
    final roundedLng = (lng * 1000).round() / 1000;
    final cacheKey = 'nearby:$roundedLat:$roundedLng';

    final cached = _readCache(_nearbyCache, cacheKey);
    if (cached != null) {
      debugPrint('Cache hit for nearby stops');
      return cached;
    }

    try {
      // Try MOTIS/Transitous first
      final result = await _getNearbyStopsMotis(lat, lng);
      _writeCache(_nearbyCache, cacheKey, result, const Duration(minutes: 30));
      return result;
    } catch (e) {
      debugPrint('Transitous getNearbyStops failed: $e, trying v6.db...');
      try {
        // Fallback to v6.db
        final result = await _getNearbyStopsV6(lat, lng);
        _writeCache(
          _nearbyCache,
          cacheKey,
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
    int? minTransferTimeMinutesOverride,
    int? additionalTransferTimeMinutesOverride,
    double? transferTimeFactorOverride,
    double? pedestrianSpeedKmhOverride,
    int? maxWalkingTimeMinutesOverride,
    Function(List<Map<String, dynamic>>)? onPartialResults,
    void Function(Set<String> activePhases)? onLoadStateChanged,
    bool Function()? shouldContinue,

    /// Callers that do not display platforms can skip the expensive per-stop
    /// platform lookups. Coupled train names are controlled separately below.
    bool enrichPlatforms = true,
    bool enrichCoupledLines = true,
  }) async {
    final activePhases = <String>{};
    void setPhase(String phase, bool active) {
      if (active) {
        activePhases.add(phase);
      } else {
        activePhases.remove(phase);
      }
      onLoadStateChanged?.call(Set<String>.from(activePhases));
    }

    _syntheticLog(
      'search start: sources=${enabledSources.join(",")} from=${from.name} to=${to.name} '
      'when=${when?.toIso8601String() ?? 'now'} arriveBy=$isArrival results=$results',
    );

    // 1. DB-ONLY MODE
    if (usesOnlyDbV6) {
      setPhase(loadPhaseV6, true);
      try {
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
        _syntheticLog('search done: db-only returned=${mapped.length}');
        return mapped;
      } finally {
        setPhase(loadPhaseV6, false);
      }
    }

    // 2. TRANSITOUS-ONLY MODE
    if (isTransitousEnabled && !isDbV6Enabled) {
      setPhase(loadPhaseMotis, true);
      try {
        final res = await _searchJourneysMotisWithFallback(
          from: from,
          to: to,
          nahverkehrOnly: nahverkehrOnly,
          when: when,
          isArrival: isArrival,
          results: results,
          minTransferTimeMinutesOverride: minTransferTimeMinutesOverride,
          additionalTransferTimeMinutesOverride:
              additionalTransferTimeMinutesOverride,
          transferTimeFactorOverride: transferTimeFactorOverride,
          pedestrianSpeedKmhOverride: pedestrianSpeedKmhOverride,
          maxWalkingTimeMinutesOverride: maxWalkingTimeMinutesOverride,
        );
        if (enrichCoupledLines) {
          await _enrichJourneysWithCoupledLineAliases(res);
        }
        if (onPartialResults != null) onPartialResults(res);
        List<Map<String, dynamic>> finalResults = res;
        if (isSyntheticTransitousEnabled) {
          setPhase(loadPhaseMotis, false);
          setPhase(loadPhaseSynthetic, true);
          finalResults = await _augmentJourneysWithSynthetic(
            from,
            to,
            res,
            when: when,
            nahverkehrOnly: nahverkehrOnly,
            isArrival: isArrival,
            onProgress: onPartialResults,
            shouldContinue: shouldContinue,
          );
          if (onPartialResults != null && finalResults.length > res.length) {
            onPartialResults(finalResults);
          }
        }
        if (enrichPlatforms) {
          finalResults = await _enrichJourneysWithPlatforms(
            finalResults,
            onProgress: onPartialResults,
          );
        }
        _syntheticLog(
          'search done: transitous-only base=${res.length} final=${finalResults.length}',
        );
        return finalResults;
      } catch (e) {
        debugPrint('Transitous searchJourneys failed (strict mode): $e');
        _syntheticLog('search fail: transitous-only error=$e');
        rethrow;
      } finally {
        setPhase(loadPhaseMotis, false);
        setPhase(loadPhaseSynthetic, false);
      }
    }

    // 3. HYBRID MODE
    try {
      Future<List<Map<String, dynamic>>> motisFuture =
          Future<List<Map<String, dynamic>>>.value(
        <Map<String, dynamic>>[],
      );
      if (isTransitousEnabled) {
        setPhase(loadPhaseMotis, true);
        motisFuture = _searchJourneysMotisWithFallback(
          from: from,
          to: to,
          nahverkehrOnly: nahverkehrOnly,
          when: when,
          isArrival: isArrival,
          results: results,
          minTransferTimeMinutesOverride: minTransferTimeMinutesOverride,
          additionalTransferTimeMinutesOverride:
              additionalTransferTimeMinutesOverride,
          transferTimeFactorOverride: transferTimeFactorOverride,
          pedestrianSpeedKmhOverride: pedestrianSpeedKmhOverride,
          maxWalkingTimeMinutesOverride: maxWalkingTimeMinutesOverride,
          allowDirectFallback: false,
        ).then((res) async {
          if (enrichCoupledLines) {
            await _enrichJourneysWithCoupledLineAliases(res);
          }
          return res;
        }).catchError((e) {
          debugPrint('Hybrid: Transitous failed: $e');
          return <Map<String, dynamic>>[];
        }).whenComplete(() => setPhase(loadPhaseMotis, false));
      }

      Future<List<Map<String, dynamic>>> v6Future =
          Future<List<Map<String, dynamic>>>.value(<Map<String, dynamic>>[]);
      if (isDbV6Enabled) {
        setPhase(loadPhaseV6, true);
        v6Future = _searchJourneysV6(
          from,
          to,
          nahverkehrOnly: nahverkehrOnly,
          when: when,
          isArrival: isArrival,
          results: results,
        ).then((res) => res).catchError((e) {
          debugPrint('Hybrid: v6 failed: $e');
          return <Map<String, dynamic>>[];
        }).whenComplete(() => setPhase(loadPhaseV6, false));
      }

      if (onPartialResults != null) {
        bool motisDone = !isTransitousEnabled;

        motisFuture.then((motisResults) {
          motisDone = true;
          if (motisResults.isNotEmpty) {
            _syntheticLog('partial: motis=${motisResults.length}');
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
              _syntheticLog('partial: v6=${v6Results.length} before motis');
              onPartialResults(v6Results);
            } else {
              // Motis is done, we need to merge DB with Motis results.
              motisFuture.then((motisResults) {
                final merged = mergeResults(motisResults, v6Results);
                _syntheticLog(
                  'partial: merged motis=${motisResults.length} v6=${v6Results.length} total=${merged.length}',
                );
                onPartialResults(merged);
              });
            }
          }
        });

        // Wait for both to formally complete the function call
        final resultsList = await Future.wait([motisFuture, v6Future]);
        final merged = mergeResults(resultsList[0], resultsList[1]);
        var baseResults = merged.isEmpty ? resultsList[0] : merged;
        if (baseResults.isEmpty && isTransitousEnabled) {
          baseResults = await _searchDirectJourneysMotis(
            from,
            to,
            when: when,
            isArrival: isArrival,
            results: results,
          );
          if (baseResults.isNotEmpty) {
            if (enrichCoupledLines) {
              await _enrichJourneysWithCoupledLineAliases(baseResults);
            }
            onPartialResults(baseResults);
          }
        }
        var finalResults = baseResults;
        if (baseResults.isNotEmpty) {
          onPartialResults(baseResults);
        }
        if (isSyntheticTransitousEnabled) {
          setPhase(loadPhaseSynthetic, true);
          finalResults = await _augmentJourneysWithSynthetic(
            from,
            to,
            baseResults,
            when: when,
            nahverkehrOnly: nahverkehrOnly,
            isArrival: isArrival,
            onProgress: onPartialResults,
            shouldContinue: shouldContinue,
          );
          if (finalResults.length > baseResults.length) {
            onPartialResults(finalResults);
          }
        }
        if (enrichPlatforms) {
          finalResults = await _enrichJourneysWithPlatforms(
            finalResults,
            onProgress: onPartialResults,
          );
        }
        _syntheticLog(
          'search done: hybrid(partial) motis=${resultsList[0].length} '
          'v6=${resultsList[1].length} base=${baseResults.length} final=${finalResults.length}',
        );
        return finalResults;
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

        var baseResults = merged;
        if (baseResults.isEmpty && isTransitousEnabled) {
          baseResults = await _searchDirectJourneysMotis(
            from,
            to,
            when: when,
            isArrival: isArrival,
            results: results,
          );
          if (enrichCoupledLines && baseResults.isNotEmpty) {
            await _enrichJourneysWithCoupledLineAliases(baseResults);
          }
        }

        if (baseResults.isEmpty) {
          _syntheticLog('search done: hybrid merged empty');
          throw Exception("No routes found on either API");
        }

        var finalResults = baseResults;
        if (isSyntheticTransitousEnabled) {
          setPhase(loadPhaseSynthetic, true);
          finalResults = await _augmentJourneysWithSynthetic(
            from,
            to,
            baseResults,
            when: when,
            nahverkehrOnly: nahverkehrOnly,
            isArrival: isArrival,
            onProgress: onPartialResults,
            shouldContinue: shouldContinue,
          );
        }
        if (enrichPlatforms) {
          finalResults = await _enrichJourneysWithPlatforms(
            finalResults,
            onProgress: onPartialResults,
          );
        }
        _syntheticLog(
          'search done: hybrid motis=${motisResults.length} v6=${v6Results.length} '
          'base=${baseResults.length} final=${finalResults.length}',
        );
        return finalResults;
      }
    } catch (e) {
      debugPrint('Hybrid searchJourneys critical failure: $e');
      _syntheticLog('search fail: hybrid error=$e');
      return [];
    } finally {
      setPhase(loadPhaseMotis, false);
      setPhase(loadPhaseV6, false);
      setPhase(loadPhaseSynthetic, false);
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
    if (isTransitousEnabled) {
      try {
        return await _fetchMotisStopDepartures(
          stationId,
          startLocal: startLocal,
          endLocal: endLocal,
          maxResults: maxResults,
        );
      } catch (e) {
        debugPrint('MOTIS fetchStopDepartures failed: $e');
        if (!isDbV6Enabled) rethrow;
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
    _syntheticStopDeparturesCache.clear();
    _tripItineraryCache.clear();
    _tripItineraryInFlight.clear();
    _stopEventsCache.clear();
    _bahnBoardCache.clear();
    _bahnEvaCache.clear();
    debugPrint('TransportApi cache cleared');
  }
}
