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
  static const Duration _syntheticTransferSlack = Duration(seconds: 15);
  static const int _syntheticOnwardResultsPerDeparture = 1;
  static const int _syntheticProgressBatchSize = 4;
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
      if (_advancedMinTransferTimeMinutes !=
          defaultAdvancedMinTransferTimeMinutes) {
        params['minTransferTime'] = _advancedMinTransferTimeMinutes.toString();
      }
      if (_advancedAdditionalTransferTimeMinutes !=
          defaultAdvancedAdditionalTransferTimeMinutes) {
        params['additionalTransferTime'] =
            _advancedAdditionalTransferTimeMinutes.toString();
      }
      if ((_advancedTransferTimeFactor - defaultAdvancedTransferTimeFactor)
              .abs() >
          0.0001) {
        params['transferTimeFactor'] =
            _advancedTransferTimeFactor.toStringAsFixed(2);
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
      pedestrianSpeedKmhOverride: pedestrianSpeedKmhOverride,
      maxWalkingTimeMinutesOverride: maxWalkingTimeMinutesOverride,
    );

    final response = await _fetch(_getMotisPlanUri(params));
    final data = json.decode(response.body);
    return decodeMotisPlanJourneys(data);
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
    bool allowDirectFallback = true,
  }) async {
    final primary = await _searchJourneysMotis(
      from,
      to,
      nahverkehrOnly: nahverkehrOnly,
      when: when,
      isArrival: isArrival,
      results: results,
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
    if (usesOnlyDbV6) {
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

    if (!isDbV6Enabled) {
      _stationCache[cacheKey] = _CacheEntry(
        rankedMotis,
        const Duration(hours: 1),
      );
      return rankedMotis;
    }

    // In auto mode, Transitous is the primary source.
    // Only fall back to v6 when Transitous returns no station results.
    if (rankedMotis.isNotEmpty) {
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
    final ranked = rankStationsForQuery(v6Results, query, lat: lat, lng: lng);
    _stationCache[cacheKey] = _CacheEntry(ranked, const Duration(hours: 1));
    return ranked;
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

  static Future<Map<String, dynamic>?> _fetchTripItineraryCached(
    String tripId,
  ) async {
    final normalizedTripId = tripId.trim();
    if (normalizedTripId.isEmpty) return null;

    final cached = _tripItineraryCache[normalizedTripId];
    if (cached != null && !cached.isExpired) {
      return cached.data;
    }

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
      _tripItineraryCache[normalizedTripId] = _CacheEntry(
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

    final lineKey = _normalizeTransitKey(_journeyLegLineName(firstRide));
    if (lineKey.isEmpty) return null;

    final directionKey = _normalizeTransitKey(firstRide['direction']);
    final transferStopId = _stringOrNull(transfer['id']) ?? '';
    final transferStopName = _stringOrNull(transfer['name']) ?? '';
    if (transferStopId.isEmpty && transferStopName.isEmpty) return null;
    final secondLineKey =
        _normalizeTransitKey(_journeyLegLineName(transferRide));
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
    void Function(Set<String> activePhases)? onLoadStateChanged,
    bool Function()? shouldContinue,
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
        );
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
          allowDirectFallback: false,
        ).then((res) => res).catchError((e) {
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
            onPartialResults(baseResults);
          }
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
          if (finalResults.length > baseResults.length) {
            onPartialResults(finalResults);
          }
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
    debugPrint('TransportApi cache cleared');
  }
}
