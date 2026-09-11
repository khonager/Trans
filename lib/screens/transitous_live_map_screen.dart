import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../services/favorites_manager.dart';
import '../services/supabase_service.dart';
import '../services/transport_api.dart';
import '../utils/app_error.dart';
import '../widgets/compass_icon.dart';
import '../widgets/favorite_map_markers.dart';
import '../widgets/friend_map_markers.dart';

class TransitousLiveMapScreen extends StatefulWidget {
  final Position? currentPosition;

  const TransitousLiveMapScreen({
    super.key,
    this.currentPosition,
  });

  @override
  State<TransitousLiveMapScreen> createState() =>
      _TransitousLiveMapScreenState();
}

class _TransitousLiveMapScreenState extends State<TransitousLiveMapScreen>
    with WidgetsBindingObserver {
  static const double _minLiveZoom = 9.5;
  static const Duration _lookBehind = Duration(minutes: 35);
  static const Duration _lookAhead = Duration(minutes: 45);
  static const Duration _fetchDebounceDuration = Duration(milliseconds: 350);
  static const Duration _refreshInterval = Duration(seconds: 5);
  static const Duration _animationInterval = Duration(milliseconds: 120);
  static const Duration _tripRetentionDuration = Duration(minutes: 2);
  static const double _retentionPaddingFactor = 0.8;

  final MapController _mapController = MapController();
  final ValueNotifier<DateTime> _clock = ValueNotifier(DateTime.now());

  LatLng _initialCenter = const LatLng(52.52, 13.405);
  double _initialZoom = 13;
  bool _isLoadingInitialView = true;
  bool _isFetchingTrips = false;
  bool _isFetchPipelineActive = false;
  bool _hasPendingViewportFetch = false;
  bool _pendingForceFetch = false;
  bool _isMapReady = false;
  String? _errorMessage;
  MapCamera? _latestCamera;
  _FetchedViewport? _lastFetchedViewport;
  List<_LiveBusTrip> _trips = const [];
  _SelectedBus? _selectedBus;
  List<_LiveBusTrip> _displayedTripsCache = const [];
  String? _displayedTripsCacheKey;
  List<Marker> _favoriteMarkers = const [];
  List<Marker> _friendMarkers = const [];
  Position? _liveCurrentPosition;
  bool _isStartingLiveLocationUpdates = false;
  bool _isCompassMode = false;

  Timer? _fetchDebounce;
  Timer? _refreshTimer;
  Timer? _animationTimer;
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<CompassEvent>? _compassStream;
  bool _forceNextFetch = false;
  int _selectedTripRouteRequestToken = 0;
  bool _appIsActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _liveCurrentPosition = widget.currentPosition;
    _bootstrap();
    _loadFavoriteMarkers();
    _startLiveLocationUpdates();
    _startTimers();
  }

  @override
  void didUpdateWidget(covariant TransitousLiveMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentPosition != null &&
        widget.currentPosition != oldWidget.currentPosition) {
      setState(() => _liveCurrentPosition = widget.currentPosition);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fetchDebounce?.cancel();
    _refreshTimer?.cancel();
    _animationTimer?.cancel();
    _positionStream?.cancel();
    _compassStream?.cancel();
    _clock.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasActive = _appIsActive;
    _appIsActive = state != AppLifecycleState.paused &&
        state != AppLifecycleState.detached;
    if (_appIsActive && !wasActive) {
      _startTimers();
      _scheduleFetch(force: true);
    } else if (!_appIsActive && wasActive) {
      _stopTimers();
    }
  }

  void _startTimers() {
    if (_animationTimer == null || !_animationTimer!.isActive) {
      _animationTimer = Timer.periodic(_animationInterval, (_) {
        if (!mounted) return;
        _clock.value = DateTime.now();
      });
    }
    if (_refreshTimer == null || !_refreshTimer!.isActive) {
      _refreshTimer = Timer.periodic(_refreshInterval, (_) {
        _scheduleFetch(force: true);
      });
    }
  }

  void _stopTimers() {
    _fetchDebounce?.cancel();
    _fetchDebounce = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _animationTimer?.cancel();
    _animationTimer = null;
  }

  Future<void> _startLiveLocationUpdates() async {
    if (_isStartingLiveLocationUpdates) return;
    _isStartingLiveLocationUpdates = true;
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint('Live buses map location unavailable: permission denied');
        return;
      }

      const settings = LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      );
      await _positionStream?.cancel();
      _positionStream = Geolocator.getPositionStream(locationSettings: settings)
          .listen((position) {
        if (!mounted) return;
        setState(() => _liveCurrentPosition = position);
        if (_isCompassMode && _isMapReady) {
          _mapController.move(
            LatLng(position.latitude, position.longitude),
            _mapController.camera.zoom,
          );
        }
      });
    } catch (error, stackTrace) {
      AppError.log(
        error,
        stackTrace: stackTrace,
        source: 'live buses map location',
      );
    } finally {
      _isStartingLiveLocationUpdates = false;
    }
  }

  void _toggleCompassMode() {
    if (_isCompassMode) {
      _disableCompassMode();
    } else {
      _enableCompassMode();
    }
  }

  Future<void> _enableCompassMode() async {
    setState(() => _isCompassMode = true);

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      try {
        permission = await Geolocator.requestPermission();
      } catch (error, stackTrace) {
        AppError.log(
          error,
          stackTrace: stackTrace,
          source: 'live buses map location permission',
        );
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _isCompassMode = false);
        return;
      }
    }

    if (_positionStream == null) {
      await _startLiveLocationUpdates();
    }

    _compassStream?.cancel();
    try {
      _compassStream = FlutterCompass.events?.listen((event) {
        if (!_isCompassMode || !_isMapReady) return;
        final heading = event.heading;
        if (heading != null) {
          _mapController.rotate(-heading);
        }
      });
    } catch (error, stackTrace) {
      AppError.log(
        error,
        stackTrace: stackTrace,
        source: 'live buses map compass',
      );
    }

    final position = _liveCurrentPosition;
    if (position != null && _isMapReady) {
      _mapController.move(LatLng(position.latitude, position.longitude), 16);
    }
  }

  void _disableCompassMode() {
    if (mounted) {
      setState(() => _isCompassMode = false);
    } else {
      _isCompassMode = false;
    }
    _compassStream?.cancel();
    _compassStream = null;
  }

  Future<void> _loadFavoriteMarkers() async {
    final favorites = await FavoritesManager.getFavorites();
    final friends = await SupabaseService.getFriends();
    if (!mounted) return;
    setState(() {
      _favoriteMarkers = buildFavoriteMapMarkers(
        favorites.where((favorite) => favorite.type == 'station').toList(),
      );
      _friendMarkers = buildFriendMapMarkers(friends);
    });
  }

  Future<void> _bootstrap() async {
    if (widget.currentPosition != null) {
      _initialCenter = LatLng(
        widget.currentPosition!.latitude,
        widget.currentPosition!.longitude,
      );
      _initialZoom = 13.5;
      if (mounted) {
        setState(() => _isLoadingInitialView = false);
      }
      return;
    }

    try {
      final initial = await TransportApi.fetchMapInitial();
      final lat = (initial?['lat'] as num?)?.toDouble();
      final lon = (initial?['lon'] as num?)?.toDouble();
      final zoom = (initial?['zoom'] as num?)?.toDouble();
      if (lat != null && lon != null) {
        _initialCenter = LatLng(lat, lon);
      }
      if (zoom != null) {
        _initialZoom = zoom.clamp(10, 15);
      }
    } catch (_) {
      // Fall back to Berlin if Transitous initial map config is unavailable.
    } finally {
      if (mounted) {
        setState(() => _isLoadingInitialView = false);
      }
    }
  }

  void _scheduleFetch({bool force = false}) {
    if (!_appIsActive) return;
    if (force) {
      _forceNextFetch = true;
    }
    _fetchDebounce?.cancel();
    _fetchDebounce = Timer(_fetchDebounceDuration, _fetchTripsForViewport);
  }

  String _coordString(LatLng point) => '${point.latitude},${point.longitude}';

  int _zoomBucketFor(double zoom) {
    if (zoom < 10) return 10;
    if (zoom < 11) return 10;
    if (zoom < 12) return 11;
    if (zoom < 13) return 12;
    if (zoom < 14) return 13;
    if (zoom < 15) return 14;
    return 15;
  }

  double _requestZoom(double zoom) => _zoomBucketFor(zoom).toDouble();

  double _fetchPaddingFactorForZoom(double zoom) {
    if (zoom < 10) return 0.10;
    if (zoom < 11) return 0.12;
    if (zoom < 12) return 0.05;
    if (zoom < 13) return 0.12;
    if (zoom < 14) return 0.20;
    return 0.30;
  }

  double _maxRequestHeightKmForZoom(int zoomBucket) {
    switch (zoomBucket) {
      case 10:
        return 64;
      case 11:
        return 36;
      case 12:
        return 24;
      case 13:
        return 16;
      case 14:
        return 10;
      default:
        return 7;
    }
  }

  double _maxRequestWidthKmForZoom(int zoomBucket) {
    switch (zoomBucket) {
      case 10:
        return 92;
      case 11:
        return 54;
      case 12:
        return 34;
      case 13:
        return 22;
      case 14:
        return 14;
      default:
        return 10;
    }
  }

  double _markerRotationRadians(double heading) =>
      (heading - 90) * math.pi / 180;

  Future<void> _fetchTripsForViewport() async {
    final camera = _latestCamera;
    final force = _forceNextFetch;
    _forceNextFetch = false;

    if (_isFetchPipelineActive) {
      _hasPendingViewportFetch = true;
      _pendingForceFetch = _pendingForceFetch || force;
      return;
    }

    if (!mounted || !_isMapReady || camera == null) {
      return;
    }

    if (camera.zoom < _minLiveZoom) {
      if (_trips.isNotEmpty || _errorMessage != null) {
        _selectedTripRouteRequestToken++;
        setState(() {
          _trips = const [];
          _selectedBus = null;
          _errorMessage = null;
        });
      }
      _lastFetchedViewport = null;
      return;
    }

    final visibleBounds = _safeVisibleBounds(camera);
    if (visibleBounds == null) {
      debugPrint('Live map: skipping fetch because visible bounds are invalid');
      return;
    }
    final zoomBucket = _zoomBucketFor(camera.zoom);
    final requestZoom = _requestZoom(camera.zoom);
    if (!force &&
        _lastFetchedViewport?.covers(
              visibleBounds: visibleBounds,
              requestZoom: requestZoom,
              center: camera.center,
            ) ==
            true) {
      return;
    }

    final resolvedRequest = _resolveRequestViewport(
      visibleBounds: visibleBounds,
      center: camera.center,
      zoomBucket: zoomBucket,
    );
    final bounds = resolvedRequest.bounds;
    final now = DateTime.now();
    final fetchStartedAt = Stopwatch()..start();
    _isFetchPipelineActive = true;

    setState(() {
      _isFetchingTrips = true;
      _errorMessage = null;
    });

    try {
      final rawBody = await TransportApi.fetchLiveMapTrips(
        min: _coordString(_southWest(bounds)),
        max: _coordString(_northEast(bounds)),
        startTime: now.subtract(_lookBehind),
        endTime: now.add(_lookAhead),
        zoom: requestZoom,
      );
      final networkMs = fetchStartedAt.elapsedMilliseconds;
      if (!mounted) return;

      final retentionBounds = _expandBounds(
        visibleBounds,
        _retentionPaddingFactor,
      );
      final parseStartedAt = Stopwatch()..start();
      final parseResult = await compute(
        _parseLiveMapTripsIsolate,
        LiveMapParseRequest(
          body: rawBody,
          fetchedAtMs: now.toUtc().millisecondsSinceEpoch,
          nowMs: now.toUtc().millisecondsSinceEpoch,
          visibleBounds: LiveMapBoundsData.fromLatLngBounds(visibleBounds),
          retentionBounds: LiveMapBoundsData.fromLatLngBounds(retentionBounds),
        ),
      );
      final parseMs = parseStartedAt.elapsedMilliseconds;
      if (!mounted) return;

      final incomingTrips = parseResult.trips
          .map(_LiveBusTrip.fromParsed)
          .toList(growable: false);

      final mergeStartedAt = Stopwatch()..start();
      final trips = _mergeTrips(
        existing: _trips,
        incoming: incomingTrips,
        now: now,
        visibleBounds: visibleBounds,
      );
      final mergeMs = mergeStartedAt.elapsedMilliseconds;
      debugPrint(
        'Live map fetch summary: '
        'zoomBucket=$zoomBucket, '
        'clamped=${resolvedRequest.clamped}, '
        'raw=${parseResult.rawSegments}, '
        'rawBusSegments=${parseResult.rawBusSegments}, '
        'built=${parseResult.builtTrips}, '
        'visible=${parseResult.visibleTrips}, '
        'onscreen=${parseResult.onScreenTrips}, '
        'nearby=${parseResult.nearbyTrips}, '
        'merged=${trips.length}, '
        'networkMs=$networkMs, '
        'parseMs=$parseMs, '
        'mergeMs=$mergeMs, '
        'firstVisibleMs=${trips.isEmpty ? -1 : fetchStartedAt.elapsedMilliseconds}',
      );
      final selectedTrip = _selectedBus == null
          ? null
          : trips.cast<_LiveBusTrip?>().firstWhere(
                (trip) => trip?.id == _selectedBus!.tripId,
                orElse: () => null,
              );

      setState(() {
        _trips = trips;
        _invalidateDisplayedTripsCache();
        final existingSelection = _selectedBus;
        _selectedBus = selectedTrip == null
            ? null
            : existingSelection?.tripId == selectedTrip.id
                ? existingSelection
                : _SelectedBus(tripId: selectedTrip.id);
      });
      _lastFetchedViewport = _FetchedViewport(
        bounds: bounds,
        requestZoom: requestZoom,
        clamped: resolvedRequest.clamped,
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      AppError.log(
        error,
        stackTrace: stackTrace,
        source: 'live map trips',
      );
      setState(() {
        _errorMessage = AppError.userMessage(
          context,
          error,
          fallback: 'Could not load live buses.',
        );
      });
    } finally {
      _isFetchPipelineActive = false;
      if (mounted) {
        setState(() => _isFetchingTrips = false);
      }
      if (_hasPendingViewportFetch) {
        final pendingForce = _pendingForceFetch;
        _hasPendingViewportFetch = false;
        _pendingForceFetch = false;
        _scheduleFetch(force: pendingForce);
      }
    }
  }

  List<_LiveBusTrip> _mergeTrips({
    required List<_LiveBusTrip> existing,
    required List<_LiveBusTrip> incoming,
    required DateTime now,
    required LatLngBounds visibleBounds,
  }) {
    final selectedTripId = _selectedBus?.tripId;
    final merged = <String, _LiveBusTrip>{
      for (final trip in incoming) trip.id: trip,
    };
    final retentionBounds = _expandBounds(
      visibleBounds,
      _retentionPaddingFactor,
    );

    for (final trip in existing) {
      if (merged.containsKey(trip.id)) {
        // Prevent older in-flight requests from overwriting newer local data
        if (trip.fetchedAtMs > merged[trip.id]!.fetchedAtMs) {
          merged[trip.id] = trip;
        }
        continue;
      }
      final age = now.toUtc().millisecondsSinceEpoch - trip.fetchedAtMs;
      if (trip.id == selectedTripId ||
          (age <= _tripRetentionDuration.inMilliseconds &&
              _containsPoint(retentionBounds, trip.sample(now).position))) {
        merged[trip.id] = trip;
      }
    }

    final combined = merged.values.toList();
    combined.sort((a, b) {
      final byName = a.displayName.compareTo(b.displayName);
      if (byName != 0) return byName;
      return a.id.compareTo(b.id);
    });
    return combined;
  }

  void _invalidateDisplayedTripsCache() {
    _displayedTripsCacheKey = null;
    _displayedTripsCache = const [];
  }

  List<_LiveBusTrip> _displayedTripsFor({
    required LatLng center,
    required double zoom,
  }) {
    final cacheKey = [
      identityHashCode(_trips),
      _selectedBus?.tripId ?? '',
      zoom.toStringAsFixed(2),
      center.latitude.toStringAsFixed(4),
      center.longitude.toStringAsFixed(4),
    ].join('|');

    if (_displayedTripsCacheKey == cacheKey) {
      return _displayedTripsCache;
    }

    final displayed = _prioritizeTripsForDisplay(
      _trips,
      center: center,
      zoom: zoom,
    );
    _displayedTripsCacheKey = cacheKey;
    _displayedTripsCache = displayed;
    return displayed;
  }

  _ResolvedRequestViewport _resolveRequestViewport({
    required LatLngBounds visibleBounds,
    required LatLng center,
    required int zoomBucket,
  }) {
    final padded = _expandBounds(
      visibleBounds,
      _fetchPaddingFactorForZoom(zoomBucket.toDouble()),
    );
    final maxHeightKm = _maxRequestHeightKmForZoom(zoomBucket);
    final maxWidthKm = _maxRequestWidthKmForZoom(zoomBucket);
    final heightKm = _axisDistanceKm(
      LatLng(padded.south, center.longitude),
      LatLng(padded.north, center.longitude),
    );
    final widthKm = _axisDistanceKm(
      LatLng(center.latitude, padded.west),
      LatLng(center.latitude, padded.east),
    );

    if (heightKm <= maxHeightKm && widthKm <= maxWidthKm) {
      return _ResolvedRequestViewport(bounds: padded, clamped: false);
    }

    return _ResolvedRequestViewport(
      bounds: _boundsAroundCenter(
        center,
        widthKm: maxWidthKm,
        heightKm: maxHeightKm,
      ),
      clamped: true,
    );
  }

  double _interpolateZoomValue(
    double zoom,
    List<(double zoom, double value)> stops,
  ) {
    if (stops.isEmpty) return 0;
    if (zoom <= stops.first.$1) return stops.first.$2;

    for (var index = 1; index < stops.length; index++) {
      final previous = stops[index - 1];
      final current = stops[index];
      if (zoom <= current.$1) {
        final t =
            ((zoom - previous.$1) / (current.$1 - previous.$1)).clamp(0.0, 1.0);
        return _lerp(previous.$2, current.$2, t);
      }
    }

    return stops.last.$2;
  }

  int _maxVisibleTripsForZoom(double zoom) {
    final interpolated = _interpolateZoomValue(zoom, const [
      (9.5, 220.0),
      (10.0, 320.0),
      (11.0, 420.0),
      (12.0, 520.0),
      (13.5, 620.0),
      (15.0, 720.0),
    ]);
    return interpolated.round();
  }

  List<_LiveBusTrip> _prioritizeTripsForDisplay(List<_LiveBusTrip> trips,
      {required LatLng center, required double zoom}) {
    final selectedTripId = _selectedBus?.tripId;
    final maxVisible = _maxVisibleTripsForZoom(zoom);
    if (trips.length <= maxVisible) return trips;

    final scored = trips.toList()
      ..sort((a, b) {
        final aScore = _displayPriorityScore(
          a,
          selectedTripId: selectedTripId,
          center: center,
        );
        final bScore = _displayPriorityScore(
          b,
          selectedTripId: selectedTripId,
          center: center,
        );
        final byScore = bScore.compareTo(aScore);
        if (byScore != 0) return byScore;
        return a.id.compareTo(b.id);
      });

    return scored.take(maxVisible).toList();
  }

  double _displayPriorityScore(
    _LiveBusTrip trip, {
    required String? selectedTripId,
    required LatLng center,
  }) {
    final sample = trip.sample(_clock.value);
    final distanceFromCenterKm = _safeDistanceAs(
      center,
      sample.position,
      fallback: double.infinity,
    );

    var score = 0.0;
    if (trip.id == selectedTripId) score += 10000;
    if (trip.realTime) score += 600;
    score += _lateTripPriorityBoost(trip);
    score += math.max(0, 300 - distanceFromCenterKm * 35);

    final line = trip.displayName.trim().toUpperCase();
    if (line.startsWith('N')) score -= 120;

    return score;
  }

  double _lateTripPriorityBoost(_LiveBusTrip trip) {
    if (!trip.realTime) return 0;

    final lateMinutes = math.max(0, trip.arrivalDelaySeconds) / 60;
    if (lateMinutes <= 0) return 0;
    return math.min(900, 120 + lateMinutes * 85);
  }

  Size _baseMarkerSizeForZoom(double zoom) {
    final normalizedZoom =
        ((zoom - _minLiveZoom) / (15 - _minLiveZoom)).clamp(0.0, 1.0);
    return Size(
      _lerp(80, 112, normalizedZoom),
      _lerp(40, 58, normalizedZoom),
    );
  }

  double _globalMarkerScaleFor(double zoom, int visibleCount) {
    final maxVisible = _maxVisibleTripsForZoom(zoom).toDouble();
    final crowdingRatio =
        maxVisible == 0 ? 0.0 : (visibleCount / maxVisible).clamp(0.0, 1.0);
    final normalizedZoom =
        ((zoom - _minLiveZoom) / (15 - _minLiveZoom)).clamp(0.0, 1.0);
    final shrinkAmount = _lerp(0.18, 0.08, normalizedZoom) * crowdingRatio;
    return (1 - shrinkAmount).clamp(0.82, 1.0);
  }

  double _markerPaintPriority(_LiveBusTrip trip) {
    var score = 0.0;

    if (_selectedBus?.tripId == trip.id) score += 10000;
    if (trip.realTime) score += 150;
    score += _lateTripPriorityBoost(trip);

    return score;
  }

  LatLng? get _userPositionLatLng {
    final position = _liveCurrentPosition;
    if (position == null) return null;
    return LatLng(position.latitude, position.longitude);
  }

  Size _markerSizeForScale(Size baseSize, double scale) {
    final width = (baseSize.width * scale).clamp(64.0, 114.0);
    final height = (baseSize.height * scale).clamp(34.0, 58.0);
    return Size(width, height);
  }

  List<_MarkerVisual> _markerVisualsFor({
    required List<_LiveBusTrip> trips,
    required DateTime now,
    required double zoom,
  }) {
    final baseSize = _baseMarkerSizeForZoom(zoom);
    final scale = _globalMarkerScaleFor(zoom, trips.length).clamp(0.78, 1.0);
    final size = _markerSizeForScale(baseSize, scale);

    final visuals = <_MarkerVisual>[
      for (final trip in trips)
        _MarkerVisual(
          trip: trip,
          sample: trip.sample(now),
          size: size,
          scale: scale,
          paintPriority: _markerPaintPriority(trip),
        ),
    ]..sort((a, b) {
        final byPriority = a.paintPriority.compareTo(b.paintPriority);
        if (byPriority != 0) return byPriority;
        return a.trip.id.compareTo(b.trip.id);
      });

    return visuals;
  }

  void _selectTrip(_LiveBusTrip trip) {
    final existingSelection = _selectedBus;
    final isSameTrip = existingSelection?.tripId == trip.id;
    final hasFullRoute =
        (existingSelection?.fullRoutePoints?.length ?? 0) >= 2 && isSameTrip;
    final isAlreadyLoading = existingSelection?.isLoadingFullRoute == true;
    final shouldFetchFullRoute = !hasFullRoute && !isAlreadyLoading;

    setState(() {
      _invalidateDisplayedTripsCache();
      _selectedBus = isSameTrip
          ? existingSelection!.copyWith(
              isLoadingFullRoute: shouldFetchFullRoute || isAlreadyLoading,
            )
          : _SelectedBus(
              tripId: trip.id,
              isLoadingFullRoute: true,
            );
    });

    if (shouldFetchFullRoute || !isSameTrip) {
      unawaited(_loadFullTripRouteForSelection(trip.id));
    }
  }

  void _clearSelection() {
    if (_selectedBus == null) return;
    _selectedTripRouteRequestToken++;
    setState(() {
      _selectedBus = null;
      _invalidateDisplayedTripsCache();
    });
  }

  List<LatLng> _selectedRoutePointsFor(_LiveBusTrip trip) {
    final fullRoutePoints =
        _selectedBus?.tripId == trip.id ? _selectedBus?.fullRoutePoints : null;
    if (fullRoutePoints == null || fullRoutePoints.length < 2) {
      return trip.points;
    }
    return fullRoutePoints;
  }

  List<LatLng> _selectedStopPointsFor(_LiveBusTrip trip) {
    final fullStopPoints =
        _selectedBus?.tripId == trip.id ? _selectedBus?.fullStopPoints : null;
    if (fullStopPoints != null && fullStopPoints.isNotEmpty) {
      return fullStopPoints;
    }

    if (trip.points.length < 2) return trip.points;
    return _dedupeSequentialPoints([trip.points.first, trip.points.last]);
  }

  String _selectedFromNameFor(_LiveBusTrip trip) {
    final selectedName =
        _selectedBus?.tripId == trip.id ? _selectedBus?.fullFromName : null;
    return (selectedName == null || selectedName.isEmpty)
        ? trip.fromName
        : selectedName;
  }

  String _selectedToNameFor(_LiveBusTrip trip) {
    final selectedName =
        _selectedBus?.tripId == trip.id ? _selectedBus?.fullToName : null;
    return (selectedName == null || selectedName.isEmpty)
        ? trip.toName
        : selectedName;
  }

  List<LatLng> _selectedRemainingPathFor(_LiveBusTrip trip, DateTime now) {
    final fullRoutePoints =
        _selectedBus?.tripId == trip.id ? _selectedBus?.fullRoutePoints : null;
    if (fullRoutePoints == null || fullRoutePoints.length < 2) {
      return trip.remainingPath(now);
    }

    final sample = trip.sample(now);
    return _remainingPathFromPosition(
      fullRoutePoints,
      sample.position,
    );
  }

  Future<void> _loadFullTripRouteForSelection(String tripId) async {
    final requestToken = ++_selectedTripRouteRequestToken;

    try {
      final itinerary = await TransportApi.fetchTripItinerary(
        tripId,
        withScheduledSkippedStops: true,
        joinInterlinedLegs: true,
      );
      final fullRoute =
          itinerary == null ? null : _extractFullTripRoute(itinerary);

      if (!mounted ||
          _selectedBus?.tripId != tripId ||
          requestToken != _selectedTripRouteRequestToken) {
        return;
      }

      setState(() {
        _selectedBus = _selectedBus?.copyWith(
          isLoadingFullRoute: false,
          fullRoutePoints: fullRoute?.points,
          fullStopPoints: fullRoute?.stopPoints,
          fullFromName: fullRoute?.fromName,
          fullToName: fullRoute?.toName,
        );
      });
    } catch (error, stackTrace) {
      AppError.log(
        error,
        stackTrace: stackTrace,
        source: 'live map trip itinerary',
      );

      if (!mounted ||
          _selectedBus?.tripId != tripId ||
          requestToken != _selectedTripRouteRequestToken) {
        return;
      }

      setState(() {
        _selectedBus = _selectedBus?.copyWith(isLoadingFullRoute: false);
      });
    }
  }

  _FullTripRouteData? _extractFullTripRoute(Map<String, dynamic> itinerary) {
    final legs = itinerary['legs'] as List?;
    if (legs == null || legs.isEmpty) return null;

    final routePoints = <LatLng>[];
    final stopPoints = <LatLng>[];
    String? fromName;
    String? toName;

    for (final rawLeg in legs) {
      if (rawLeg is! Map) continue;
      final leg = Map<String, dynamic>.from(rawLeg);
      final legPoints = <LatLng>[];

      fromName ??= (leg['from'] as Map<String, dynamic>?)?['name']?.toString();
      toName =
          (leg['to'] as Map<String, dynamic>?)?['name']?.toString() ?? toName;

      _appendUniqueRoutePoints(
        stopPoints,
        _fallbackPointsFromLegStops(leg),
      );

      final legGeometry = leg['legGeometry'] as Map?;
      final encodedPoints = legGeometry?['points']?.toString();
      if (encodedPoints != null && encodedPoints.isNotEmpty) {
        final precision = (legGeometry?['precision'] as num?)?.toInt() ?? 6;
        final decoded = _decodePolyline(
          encodedPoints,
          precision: precision,
        );
        for (var index = 0; index < decoded.latitudes.length; index++) {
          legPoints.add(
            LatLng(decoded.latitudes[index], decoded.longitudes[index]),
          );
        }
      }

      if (legPoints.isEmpty) {
        _appendUniqueRoutePoints(
          legPoints,
          _fallbackPointsFromLegStops(leg),
        );
      }

      _appendUniqueRoutePoints(routePoints, legPoints);
    }

    final dedupedRoutePoints = _dedupeSequentialPoints(routePoints);
    if (dedupedRoutePoints.length < 2) return null;

    return _FullTripRouteData(
      points: dedupedRoutePoints,
      stopPoints: _dedupeSequentialPoints(stopPoints),
      fromName: fromName ?? 'Unknown stop',
      toName: toName ?? 'Unknown stop',
    );
  }

  List<LatLng> _fallbackPointsFromLegStops(Map<String, dynamic> leg) {
    final points = <LatLng>[];

    void addPlace(dynamic place) {
      final point = _latLngFromMotisPlace(place);
      if (point == null) return;
      if (points.isEmpty || !_samePoint(points.last, point)) {
        points.add(point);
      }
    }

    addPlace(leg['from']);

    final intermediateStops = leg['intermediateStops'] as List?;
    if (intermediateStops != null) {
      for (final stop in intermediateStops) {
        addPlace(stop);
      }
    }

    addPlace(leg['to']);
    return points;
  }

  LatLng? _latLngFromMotisPlace(dynamic place) {
    if (place is! Map) return null;
    final latitude = (place['lat'] as num?)?.toDouble() ??
        (place['latitude'] as num?)?.toDouble();
    final longitude = (place['lon'] as num?)?.toDouble() ??
        (place['longitude'] as num?)?.toDouble();
    if (latitude == null || longitude == null) return null;
    return LatLng(latitude, longitude);
  }

  void _appendUniqueRoutePoints(List<LatLng> target, Iterable<LatLng> points) {
    for (final point in points) {
      if (target.isEmpty || !_samePoint(target.last, point)) {
        target.add(point);
      }
    }
  }

  List<LatLng> _remainingPathFromPosition(
    List<LatLng> routePoints,
    LatLng position,
  ) {
    if (routePoints.isEmpty) return const [];
    if (routePoints.length == 1) return routePoints;

    var bestSegmentIndex = 0;
    var bestProjectedPoint = routePoints.first;
    var bestDistanceSquared = double.infinity;

    for (var index = 0; index < routePoints.length - 1; index++) {
      final projectedPoint = _projectPointOnSegment(
        position,
        routePoints[index],
        routePoints[index + 1],
      );
      final distanceSquared = _distanceSquaredBetween(position, projectedPoint);
      if (distanceSquared < bestDistanceSquared) {
        bestDistanceSquared = distanceSquared;
        bestSegmentIndex = index;
        bestProjectedPoint = projectedPoint;
      }
    }

    final remaining = <LatLng>[bestProjectedPoint];
    remaining.addAll(routePoints.skip(bestSegmentIndex + 1));
    return _dedupeSequentialPoints(remaining);
  }

  LatLng _projectPointOnSegment(LatLng point, LatLng start, LatLng end) {
    final deltaLatitude = end.latitude - start.latitude;
    final deltaLongitude = end.longitude - start.longitude;
    final segmentLengthSquared =
        deltaLatitude * deltaLatitude + deltaLongitude * deltaLongitude;
    if (segmentLengthSquared <= 0) {
      return start;
    }

    final projection = ((point.latitude - start.latitude) * deltaLatitude +
            (point.longitude - start.longitude) * deltaLongitude) /
        segmentLengthSquared;
    final clampedProjection = projection.clamp(0.0, 1.0);

    return LatLng(
      start.latitude + deltaLatitude * clampedProjection,
      start.longitude + deltaLongitude * clampedProjection,
    );
  }

  double _distanceSquaredBetween(LatLng a, LatLng b) {
    final deltaLatitude = a.latitude - b.latitude;
    final deltaLongitude = a.longitude - b.longitude;
    return deltaLatitude * deltaLatitude + deltaLongitude * deltaLongitude;
  }

  _LiveBusTrip? _currentSelectedTrip() {
    final selectedTripId = _selectedBus?.tripId;
    if (selectedTripId == null) return null;

    return _trips.cast<_LiveBusTrip?>().firstWhere(
          (trip) => trip?.id == selectedTripId,
          orElse: () => null,
        );
  }

  String _delayLabel(_LiveBusTrip trip) {
    if (!trip.realTime) return 'No realtime';

    final delayMinutes = (trip.arrivalDelaySeconds / 60).round();
    if (delayMinutes <= 0) return 'On time';
    return '+$delayMinutes min';
  }

  String _nextStopArrivalLabel(BuildContext context, _LiveBusTrip trip) {
    if (trip.timestampsMs.isEmpty) return 'Arrival time unavailable';

    final arrival = DateTime.fromMillisecondsSinceEpoch(
      trip.timestampsMs.last,
      isUtc: true,
    ).toLocal();
    final arrivalTime = TimeOfDay.fromDateTime(arrival).format(context);
    return 'Arrives at $arrivalTime';
  }

  Widget _buildBusMarker(
      BuildContext context, _LiveBusTrip trip, _TripSample sample,
      {required double scale}) {
    final colors = TransColors.of(context);
    final isSelected = _selectedBus?.tripId == trip.id;
    final markerAngle = _markerRotationRadians(sample.heading);
    final markerTextColor = trip.vehicleTextColor;
    final normalizedScale = ((scale - 0.78) / 0.22).clamp(0.0, 1.0);
    final horizontalPadding = _lerp(7, 10, normalizedScale);
    final verticalPadding = _lerp(5, 8, normalizedScale);
    final borderRadius = _lerp(12, 16, normalizedScale);
    final delayMinutes = math.max(0, trip.arrivalDelaySeconds) / 60;
    final shadowStrength = isSelected
        ? 1.0
        : delayMinutes >= 5
            ? 0.9
            : delayMinutes > 0
                ? 0.7
                : 0.5;

    return GestureDetector(
      onTap: () => _selectTrip(trip),
      child: Transform.rotate(
        angle: markerAngle,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          decoration: BoxDecoration(
            color: trip.vehicleColor,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: isSelected ? colors.textPrimary : Colors.white,
              width: isSelected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: 0.12 + shadowStrength * 0.12,
                ),
                blurRadius: _lerp(8, 18, shadowStrength),
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: _ExpandedBusMarkerLabel(
                label: trip.displayName,
                textColor: markerTextColor,
                iconLeads: math.cos(markerAngle) >= 0,
                scale: scale,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserLocationMarker(BuildContext context) {
    final colors = TransColors.of(context);
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.navBarSelected.withValues(alpha: 0.18),
      ),
      padding: const EdgeInsets.all(7),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.navBarSelected,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.24),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStopDot(Color borderColor) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBanner(
    BuildContext context, {
    required int busesVisible,
    required int totalLoaded,
    required double zoom,
  }) {
    final colors = TransColors.of(context);

    String text;
    if (!_isMapReady) {
      text = 'Preparing live map...';
    } else if (zoom < _minLiveZoom) {
      text =
          'Zoom in to ${_minLiveZoom.toStringAsFixed(1)}+ to reveal live buses.';
    } else if (_isFetchingTrips && busesVisible == 0) {
      text = 'Loading live buses...';
    } else if (_errorMessage != null) {
      text = _errorMessage!;
    } else if (totalLoaded > busesVisible) {
      text = 'Showing $busesVisible of $totalLoaded live buses';
    } else {
      text = '$busesVisible live buses in this area';
    }

    return Positioned(
      top: 12,
      left: 12,
      right: 12,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: colors.cardBg.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: colors.navBarSelected.withValues(alpha: 0.18),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionSheet(BuildContext context) {
    final selected = _currentSelectedTrip();
    if (selected == null) return const SizedBox.shrink();

    final colors = TransColors.of(context);
    final realtimeLabel = selected.realTime ? 'Realtime' : 'Scheduled';
    final isLoadingFullRoute = _selectedBus?.tripId == selected.id &&
        _selectedBus?.isLoadingFullRoute == true;
    final fromName = _selectedFromNameFor(selected);
    final toName = _selectedToNameFor(selected);

    return Positioned(
      left: 12,
      right: 12,
      bottom: 12,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.cardBg.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: selected.routeColor.withValues(alpha: 0.35),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 20,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: selected.routeColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      selected.displayName,
                      style: TextStyle(
                        color: selected.routeTextColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    realtimeLabel,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: selected.vehicleColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _delayLabel(selected),
                      style: TextStyle(
                        color: selected.vehicleTextColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _clearSelection,
                    icon: const Icon(Icons.close),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '$fromName -> $toName',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isLoadingFullRoute
                    ? 'Loading the full route...'
                    : 'Tap another bus to switch the highlighted route.',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Next stop: ${selected.toName}',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _nextStopArrivalLabel(context, selected),
                style: TextStyle(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    final center = _latestCamera?.center ?? _initialCenter;
    final zoom = _latestCamera?.zoom ?? _initialZoom;
    final selectedTrip = _currentSelectedTrip();
    final displayedTrips = _displayedTripsFor(center: center, zoom: zoom);
    final userPosition = _userPositionLatLng;

    if (_isLoadingInitialView) {
      return Scaffold(
        backgroundColor: colors.scaffoldBg,
        appBar: AppBar(title: Text(AppLocalizations.of(context)!.liveBuses)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: colors.scaffoldBg,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.liveBuses),
        actions: [
          IconButton(
            tooltip: AppLocalizations.of(context)!.refresh,
            onPressed: () => _scheduleFetch(force: true),
            icon: _isFetchingTrips
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (userPosition != null)
            FloatingActionButton(
              heroTag: 'live-map-compass',
              mini: true,
              tooltip: AppLocalizations.of(context)!.compass,
              backgroundColor:
                  _isCompassMode ? colors.navBarSelected : Colors.white,
              foregroundColor: _isCompassMode ? Colors.white : Colors.black,
              onPressed: _toggleCompassMode,
              child: CustomPaint(
                size: const Size(24, 24),
                painter: CompassIconPainter(
                  color: _isCompassMode ? Colors.white : Colors.black,
                ),
              ),
            ),
          if (userPosition != null) const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'live-map-center',
            tooltip: AppLocalizations.of(context)!.recenter,
            onPressed: () {
              _clearSelection();
              if (!_isMapReady) return;
              if (_isCompassMode) _disableCompassMode();
              final target = _userPositionLatLng ?? _initialCenter;
              final targetZoom = _userPositionLatLng == null
                  ? _initialZoom
                  : math.max(_mapController.camera.zoom, 15.0);
              _mapController.move(target, targetZoom);
              _mapController.rotate(0);
              _scheduleFetch(force: true);
            },
            child: const Icon(Icons.center_focus_strong),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _initialCenter,
              initialZoom: _initialZoom,
              onMapReady: () {
                if (!mounted) return;
                setState(() {
                  _isMapReady = true;
                  _latestCamera = _mapController.camera;
                });
                _scheduleFetch(force: true);
              },
              onTap: (_, __) => _clearSelection(),
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture && _isCompassMode) {
                  _disableCompassMode();
                }
                setState(() {
                  _latestCamera = camera;
                  _invalidateDisplayedTripsCache();
                });
                _scheduleFetch();
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.trans',
              ),
              if (_favoriteMarkers.isNotEmpty)
                MarkerLayer(markers: _favoriteMarkers),
              if (_friendMarkers.isNotEmpty)
                MarkerLayer(markers: _friendMarkers),
              if (selectedTrip != null)
                ValueListenableBuilder<DateTime>(
                  valueListenable: _clock,
                  builder: (context, now, _) {
                    final routePoints = _selectedRoutePointsFor(selectedTrip);
                    final remainingPath =
                        _selectedRemainingPathFor(selectedTrip, now);
                    return PolylineLayer(
                      polylines: [
                        if (routePoints.length >= 2)
                          Polyline(
                            points: routePoints,
                            strokeWidth: 12,
                            color: Colors.black.withValues(alpha: 0.10),
                          ),
                        if (routePoints.length >= 2)
                          Polyline(
                            points: routePoints,
                            strokeWidth: 6,
                            color: selectedTrip.routeColor,
                          ),
                        if (remainingPath.length >= 2)
                          Polyline(
                            points: remainingPath,
                            strokeWidth: 12,
                            color: Colors.white.withValues(alpha: 0.92),
                          ),
                        if (remainingPath.length >= 2)
                          Polyline(
                            points: remainingPath,
                            strokeWidth: 7,
                            color: selectedTrip.vehicleColor,
                          ),
                        if (remainingPath.length >= 2)
                          Polyline(
                            points: remainingPath.take(2).toList(),
                            strokeWidth: 9,
                            color: selectedTrip.routeColor,
                          ),
                      ],
                    );
                  },
                ),
              if (selectedTrip != null)
                MarkerLayer(
                  markers: [
                    for (final point in _selectedStopPointsFor(selectedTrip))
                      Marker(
                        point: point,
                        width: 10,
                        height: 10,
                        child: _buildStopDot(selectedTrip.routeColor),
                      ),
                  ],
                ),
              ValueListenableBuilder<DateTime>(
                valueListenable: _clock,
                builder: (context, now, _) {
                  final markerVisuals = _markerVisualsFor(
                    trips: displayedTrips,
                    now: now,
                    zoom: zoom,
                  );
                  final markers = <Marker>[
                    for (final visual in markerVisuals)
                      (() {
                        return Marker(
                          point: visual.sample.position,
                          width: visual.size.width,
                          height: visual.size.height,
                          child: KeyedSubtree(
                            key: ValueKey('live-bus-${visual.trip.id}'),
                            child: _buildBusMarker(
                              context,
                              visual.trip,
                              visual.sample,
                              scale: visual.scale,
                            ),
                          ),
                        );
                      })(),
                  ];
                  return MarkerLayer(markers: markers);
                },
              ),
              if (userPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: userPosition,
                      width: 34,
                      height: 34,
                      child: _buildUserLocationMarker(context),
                    ),
                  ],
                ),
            ],
          ),
          _buildTopBanner(
            context,
            busesVisible: displayedTrips.length,
            totalLoaded: _trips.length,
            zoom: zoom,
          ),
          _buildSelectionSheet(context),
        ],
      ),
    );
  }
}

class _SelectedBus {
  final String tripId;
  final List<LatLng>? fullRoutePoints;
  final List<LatLng>? fullStopPoints;
  final String? fullFromName;
  final String? fullToName;
  final bool isLoadingFullRoute;

  const _SelectedBus({
    required this.tripId,
    this.fullRoutePoints,
    this.fullStopPoints,
    this.fullFromName,
    this.fullToName,
    this.isLoadingFullRoute = false,
  });

  _SelectedBus copyWith({
    String? tripId,
    List<LatLng>? fullRoutePoints,
    bool clearFullRoutePoints = false,
    List<LatLng>? fullStopPoints,
    bool clearFullStopPoints = false,
    String? fullFromName,
    bool clearFullFromName = false,
    String? fullToName,
    bool clearFullToName = false,
    bool? isLoadingFullRoute,
  }) {
    return _SelectedBus(
      tripId: tripId ?? this.tripId,
      fullRoutePoints: clearFullRoutePoints
          ? null
          : (fullRoutePoints ?? this.fullRoutePoints),
      fullStopPoints:
          clearFullStopPoints ? null : (fullStopPoints ?? this.fullStopPoints),
      fullFromName:
          clearFullFromName ? null : (fullFromName ?? this.fullFromName),
      fullToName: clearFullToName ? null : (fullToName ?? this.fullToName),
      isLoadingFullRoute: isLoadingFullRoute ?? this.isLoadingFullRoute,
    );
  }
}

class _FullTripRouteData {
  final List<LatLng> points;
  final List<LatLng> stopPoints;
  final String fromName;
  final String toName;

  const _FullTripRouteData({
    required this.points,
    required this.stopPoints,
    required this.fromName,
    required this.toName,
  });
}

class _FetchedViewport {
  final LatLngBounds bounds;
  final double requestZoom;
  final bool clamped;

  const _FetchedViewport({
    required this.bounds,
    required this.requestZoom,
    required this.clamped,
  });

  bool covers({
    required LatLngBounds visibleBounds,
    required double requestZoom,
    required LatLng center,
  }) {
    if (this.requestZoom != requestZoom) return false;
    if (clamped) return _containsPoint(bounds, center);

    return _containsPoint(bounds, _northWest(visibleBounds)) &&
        _containsPoint(bounds, _southEast(visibleBounds));
  }
}

class _TripSample {
  final LatLng position;
  final double heading;
  final int nextIndex;

  const _TripSample({
    required this.position,
    required this.heading,
    required this.nextIndex,
  });
}

class _LiveBusTrip {
  final String id;
  final String displayName;
  final String fromName;
  final String toName;
  final bool realTime;
  final int arrivalDelaySeconds;
  final int fetchedAtMs;
  final Color routeColor;
  final Color routeTextColor;
  final Color vehicleColor;
  final Color vehicleTextColor;
  final List<LatLng> points;
  final List<int> timestampsMs;
  final List<double> headings;

  const _LiveBusTrip({
    required this.id,
    required this.displayName,
    required this.fromName,
    required this.toName,
    required this.realTime,
    required this.arrivalDelaySeconds,
    required this.fetchedAtMs,
    required this.routeColor,
    required this.routeTextColor,
    required this.vehicleColor,
    required this.vehicleTextColor,
    required this.points,
    required this.timestampsMs,
    required this.headings,
  });

  factory _LiveBusTrip.fromParsed(LiveMapTripData data) {
    final points = <LatLng>[
      for (var index = 0; index < data.latitudes.length; index++)
        LatLng(data.latitudes[index], data.longitudes[index]),
    ];

    return _LiveBusTrip(
      id: data.id,
      displayName: data.displayName,
      fromName: data.fromName,
      toName: data.toName,
      realTime: data.realTime,
      arrivalDelaySeconds: data.arrivalDelaySeconds,
      fetchedAtMs: data.fetchedAtMs,
      routeColor: Color(data.routeColorValue),
      routeTextColor: Color(data.routeTextColorValue),
      vehicleColor: Color(data.vehicleColorValue),
      vehicleTextColor: Color(data.vehicleTextColorValue),
      points: points,
      timestampsMs: data.timestampsMs,
      headings: data.headings,
    );
  }

  _TripSample sample(DateTime now) {
    if (points.length == 1 || timestampsMs.length == 1) {
      return _TripSample(
        position: points.first,
        heading: headings.firstOrZero,
        nextIndex: 0,
      );
    }

    final nowMs = now.toUtc().millisecondsSinceEpoch;
    if (nowMs <= timestampsMs.first) {
      return _TripSample(
        position: points.first,
        heading: headings.firstOrZero,
        nextIndex: 0,
      );
    }
    if (nowMs >= timestampsMs.last) {
      final lastIndex = points.length - 1;
      return _TripSample(
        position: points.last,
        heading: headings.lastOrZero,
        nextIndex: lastIndex,
      );
    }

    final index = _lowerBound(timestampsMs, nowMs);
    final previousIndex = math.max(index - 1, 0);
    final nextIndex = math.min(index, points.length - 1);
    final previousTime = timestampsMs[previousIndex];
    final nextTime = timestampsMs[nextIndex];
    final progress = nextTime == previousTime
        ? 0.0
        : (nowMs - previousTime) / (nextTime - previousTime);
    final clampedProgress = progress.clamp(0.0, 1.0);

    final previousPoint = points[previousIndex];
    final nextPoint = points[nextIndex];

    return _TripSample(
      position: LatLng(
        _lerp(previousPoint.latitude, nextPoint.latitude, clampedProgress),
        _lerp(previousPoint.longitude, nextPoint.longitude, clampedProgress),
      ),
      heading: _lerpAngle(
        headings[previousIndex],
        headings[nextIndex],
        clampedProgress,
      ),
      nextIndex: nextIndex,
    );
  }

  List<LatLng> remainingPath(DateTime now) {
    final sampleNow = sample(now);
    final startIndex = sampleNow.nextIndex.clamp(0, points.length - 1);
    final remaining = <LatLng>[sampleNow.position];
    remaining.addAll(points.skip(startIndex));
    return _dedupeSequentialPoints(remaining);
  }
}

class _SampledSegment {
  final List<double> latitudes;
  final List<double> longitudes;
  final List<int> timestampsMs;
  final List<double> headings;

  const _SampledSegment({
    required this.latitudes,
    required this.longitudes,
    required this.timestampsMs,
    required this.headings,
  });
}

class _ResolvedRequestViewport {
  final LatLngBounds bounds;
  final bool clamped;

  const _ResolvedRequestViewport({
    required this.bounds,
    required this.clamped,
  });
}

class _DecodedPolyline {
  final List<double> latitudes;
  final List<double> longitudes;

  const _DecodedPolyline({
    required this.latitudes,
    required this.longitudes,
  });
}

class _ExpandedBusMarkerLabel extends StatelessWidget {
  final String label;
  final Color textColor;
  final bool iconLeads;
  final double scale;

  const _ExpandedBusMarkerLabel({
    required this.label,
    required this.textColor,
    required this.iconLeads,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedScale = ((scale - 0.78) / 0.22).clamp(0.0, 1.0);
    final iconSize = _lerp(12, 16, normalizedScale);
    final spacing = _lerp(3, 6, normalizedScale);
    final fontSize = _lerp(9, 12, normalizedScale);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!iconLeads)
          Icon(
            Icons.directions_bus_filled_rounded,
            size: iconSize,
            color: textColor,
          ),
        if (!iconLeads) SizedBox(width: spacing),
        Text(
          label,
          maxLines: 1,
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w800,
            fontSize: fontSize,
          ),
        ),
        if (iconLeads) SizedBox(width: spacing),
        if (iconLeads)
          Icon(
            Icons.directions_bus_filled_rounded,
            size: iconSize,
            color: textColor,
          ),
      ],
    );
  }
}

class _MarkerVisual {
  final _LiveBusTrip trip;
  final _TripSample sample;
  final Size size;
  final double scale;
  final double paintPriority;

  const _MarkerVisual({
    required this.trip,
    required this.sample,
    required this.size,
    required this.scale,
    required this.paintPriority,
  });
}

@immutable
class LiveMapBoundsData {
  final double north;
  final double south;
  final double east;
  final double west;

  const LiveMapBoundsData({
    required this.north,
    required this.south,
    required this.east,
    required this.west,
  });

  factory LiveMapBoundsData.fromLatLngBounds(LatLngBounds bounds) {
    return LiveMapBoundsData(
      north: bounds.north,
      south: bounds.south,
      east: bounds.east,
      west: bounds.west,
    );
  }

  bool contains(double latitude, double longitude) {
    return latitude >= south &&
        latitude <= north &&
        longitude >= west &&
        longitude <= east;
  }
}

@immutable
class LiveMapParseRequest {
  final String body;
  final int fetchedAtMs;
  final int nowMs;
  final LiveMapBoundsData visibleBounds;
  final LiveMapBoundsData retentionBounds;

  const LiveMapParseRequest({
    required this.body,
    required this.fetchedAtMs,
    required this.nowMs,
    required this.visibleBounds,
    required this.retentionBounds,
  });
}

@immutable
class LiveMapTripData {
  final String id;
  final String displayName;
  final String fromName;
  final String toName;
  final bool realTime;
  final int arrivalDelaySeconds;
  final int fetchedAtMs;
  final int routeColorValue;
  final int routeTextColorValue;
  final int vehicleColorValue;
  final int vehicleTextColorValue;
  final List<double> latitudes;
  final List<double> longitudes;
  final List<int> timestampsMs;
  final List<double> headings;

  const LiveMapTripData({
    required this.id,
    required this.displayName,
    required this.fromName,
    required this.toName,
    required this.realTime,
    required this.arrivalDelaySeconds,
    required this.fetchedAtMs,
    required this.routeColorValue,
    required this.routeTextColorValue,
    required this.vehicleColorValue,
    required this.vehicleTextColorValue,
    required this.latitudes,
    required this.longitudes,
    required this.timestampsMs,
    required this.headings,
  });
}

@immutable
class LiveMapParseResult {
  final List<LiveMapTripData> trips;
  final int rawSegments;
  final int rawBusSegments;
  final int builtTrips;
  final int visibleTrips;
  final int onScreenTrips;
  final int nearbyTrips;

  const LiveMapParseResult({
    required this.trips,
    required this.rawSegments,
    required this.rawBusSegments,
    required this.builtTrips,
    required this.visibleTrips,
    required this.onScreenTrips,
    required this.nearbyTrips,
  });
}

_SampledSegment _sampleSegment(
  List<double> latitudes,
  List<double> longitudes,
  int startMs,
  int endMs,
) {
  if (latitudes.isEmpty || longitudes.isEmpty) {
    return const _SampledSegment(
      latitudes: [],
      longitudes: [],
      timestampsMs: [],
      headings: [],
    );
  }

  if (latitudes.length == 1) {
    return _SampledSegment(
      latitudes: latitudes,
      longitudes: longitudes,
      timestampsMs: [startMs],
      headings: const [0],
    );
  }

  final cumulativeDistances = List<double>.filled(latitudes.length, 0);
  final headings = List<double>.filled(latitudes.length, 0);

  var totalDistance = 0.0;
  for (var i = 1; i < latitudes.length; i++) {
    totalDistance += _distanceMeters(
      latitudes[i - 1],
      longitudes[i - 1],
      latitudes[i],
      longitudes[i],
    );
    cumulativeDistances[i] = totalDistance;
    headings[i - 1] = _bearingFromCoords(
      latitudes[i - 1],
      longitudes[i - 1],
      latitudes[i],
      longitudes[i],
    );
  }
  headings[latitudes.length - 1] = headings[latitudes.length - 2];

  final duration = endMs - startMs;
  final timestamps = List<int>.generate(latitudes.length, (index) {
    if (totalDistance == 0 || duration <= 0) return startMs;
    final progress = cumulativeDistances[index] / totalDistance;
    return startMs + (duration * progress).round();
  });

  return _SampledSegment(
    latitudes: latitudes,
    longitudes: longitudes,
    timestampsMs: timestamps,
    headings: headings,
  );
}

LatLngBounds _expandBounds(LatLngBounds bounds, double factor) {
  final north = math.max(bounds.north, bounds.south);
  final south = math.min(bounds.north, bounds.south);
  final east = math.max(bounds.east, bounds.west);
  final west = math.min(bounds.east, bounds.west);
  final latPadding = (north - south).abs() * factor;
  final lonPadding = (east - west).abs() * factor;
  final expandedNorth = _clampLatitude(north + latPadding);
  final expandedSouth = _clampLatitude(south - latPadding);
  final expandedEast = _clampLongitude(east + lonPadding);
  final expandedWest = _clampLongitude(west - lonPadding);

  return LatLngBounds.unsafe(
    north: math.max(expandedNorth, expandedSouth),
    south: math.min(expandedNorth, expandedSouth),
    east: math.max(expandedEast, expandedWest),
    west: math.min(expandedEast, expandedWest),
  );
}

LatLngBounds? _safeVisibleBounds(MapCamera camera) {
  try {
    // In flutter_map v8, pixelBounds natively represents the exact bounding box
    // of the view (including rotation scaling) in world pixels.
    final Rect pw = camera.pixelBounds;

    // Unprojecting these exact pixel bounds provides the perfect geographic rectangle
    // without the math over-approximation that made the API bounds too large.
    final LatLng bottomLeft = camera.unprojectAtZoom(pw.bottomLeft);
    final LatLng topRight = camera.unprojectAtZoom(pw.topRight);

    final north =
        _clampLatitude(math.max(bottomLeft.latitude, topRight.latitude));
    final south =
        _clampLatitude(math.min(bottomLeft.latitude, topRight.latitude));
    final east =
        _clampLongitude(math.max(bottomLeft.longitude, topRight.longitude));
    final west =
        _clampLongitude(math.min(bottomLeft.longitude, topRight.longitude));

    final bounds = LatLngBounds.unsafe(
      north: north,
      south: south,
      east: east,
      west: west,
    );

    if (!_isValidBounds(bounds)) {
      return null;
    }
    return bounds;
  } catch (error) {
    debugPrint('Live map: failed to compute safe bounds: $error');
    return null;
  }
}

bool _isValidBounds(LatLngBounds bounds) {
  final north = bounds.north;
  final south = bounds.south;
  final east = bounds.east;
  final west = bounds.west;

  return north.isFinite &&
      south.isFinite &&
      east.isFinite &&
      west.isFinite &&
      north <= 90 &&
      north >= -90 &&
      south <= 90 &&
      south >= -90 &&
      east <= 180 &&
      east >= -180 &&
      west <= 180 &&
      west >= -180 &&
      north >= south &&
      east >= west;
}

double _clampLatitude(double value) {
  if (!value.isFinite) return 0;
  if (value > 90) return 90;
  if (value < -90) return -90;
  return value;
}

double _clampLongitude(double value) {
  if (!value.isFinite) return 0;
  if (value > 180) return 180;
  if (value < -180) return -180;
  return value;
}

LatLngBounds _boundsAroundCenter(
  LatLng center, {
  required double widthKm,
  required double heightKm,
}) {
  final latHalfSpan = heightKm / 2 / 111.32;
  final lonDivisor =
      111.32 * math.max(0.2, math.cos(center.latitude * math.pi / 180).abs());
  final lonHalfSpan = widthKm / 2 / lonDivisor;

  return LatLngBounds.unsafe(
    north: _clampLatitude(center.latitude + latHalfSpan),
    south: _clampLatitude(center.latitude - latHalfSpan),
    east: _clampLongitude(center.longitude + lonHalfSpan),
    west: _clampLongitude(center.longitude - lonHalfSpan),
  );
}

LatLng _northWest(LatLngBounds bounds) =>
    LatLng(_clampLatitude(bounds.north), _clampLongitude(bounds.west));

LatLng _southEast(LatLngBounds bounds) =>
    LatLng(_clampLatitude(bounds.south), _clampLongitude(bounds.east));

LatLng _southWest(LatLngBounds bounds) =>
    LatLng(_clampLatitude(bounds.south), _clampLongitude(bounds.west));

LatLng _northEast(LatLngBounds bounds) =>
    LatLng(_clampLatitude(bounds.north), _clampLongitude(bounds.east));

bool _containsPoint(LatLngBounds bounds, LatLng point) {
  final southWest = _southWest(bounds);
  final northEast = _northEast(bounds);

  return point.latitude >= southWest.latitude &&
      point.latitude <= northEast.latitude &&
      point.longitude >= southWest.longitude &&
      point.longitude <= northEast.longitude;
}

double _safeDistanceAs(
  LatLng from,
  LatLng to, {
  double fallback = 0,
}) {
  if (!_isValidPoint(from) || !_isValidPoint(to)) {
    return fallback;
  }

  try {
    final result = _distanceMeters(
          from.latitude,
          from.longitude,
          to.latitude,
          to.longitude,
        ) /
        1000;
    if (!result.isFinite) return fallback;
    return result;
  } catch (error) {
    debugPrint('Live map: distance calculation failed: $error');
    return fallback;
  }
}

bool _isValidPoint(LatLng point) =>
    point.latitude.isFinite &&
    point.longitude.isFinite &&
    point.latitude >= -90 &&
    point.latitude <= 90 &&
    point.longitude >= -180 &&
    point.longitude <= 180;

double _axisDistanceKm(LatLng from, LatLng to) =>
    _safeDistanceAs(from, to, fallback: double.infinity);

List<LatLng> _dedupeSequentialPoints(List<LatLng> points) {
  if (points.length < 2) return points;

  final deduped = <LatLng>[points.first];
  for (final point in points.skip(1)) {
    if (!_samePoint(deduped.last, point)) {
      deduped.add(point);
    }
  }
  return deduped;
}

_DecodedPolyline _decodePolyline(String encoded, {int precision = 5}) {
  final latitudes = <double>[];
  final longitudes = <double>[];
  var index = 0;
  var lat = 0;
  var lng = 0;
  final factor = math.pow(10, precision).toDouble();

  while (index < encoded.length) {
    var shift = 0;
    var result = 0;
    int byte;

    do {
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);

    final latChange = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    lat += latChange;

    shift = 0;
    result = 0;
    do {
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);

    final lngChange = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    lng += lngChange;

    latitudes.add(lat / factor);
    longitudes.add(lng / factor);
  }

  return _DecodedPolyline(latitudes: latitudes, longitudes: longitudes);
}

double _bearingFromCoords(
  double fromLatitude,
  double fromLongitude,
  double toLatitude,
  double toLongitude,
) {
  final fromLat = fromLatitude * math.pi / 180;
  final toLat = toLatitude * math.pi / 180;
  final deltaLng = (toLongitude - fromLongitude) * math.pi / 180;

  final y = math.sin(deltaLng) * math.cos(toLat);
  final x = math.cos(fromLat) * math.sin(toLat) -
      math.sin(fromLat) * math.cos(toLat) * math.cos(deltaLng);

  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

double _lerp(double a, double b, double t) => a + (b - a) * t.clamp(0, 1);

double _lerpAngle(double a, double b, double t) {
  final delta = ((b - a + 540) % 360) - 180;
  return (a + delta * t.clamp(0, 1) + 360) % 360;
}

bool _samePoint(LatLng a, LatLng b) =>
    (a.latitude - b.latitude).abs() < 0.000001 &&
    (a.longitude - b.longitude).abs() < 0.000001;

bool _sameCoordinate(
  double aLat,
  double aLon,
  double bLat,
  double bLon,
) =>
    (aLat - bLat).abs() < 0.000001 && (aLon - bLon).abs() < 0.000001;

int _delaySeconds(String? scheduled, String? actual) {
  if (scheduled == null || actual == null) return 0;
  final scheduledTime = DateTime.tryParse(scheduled);
  final actualTime = DateTime.tryParse(actual);
  if (scheduledTime == null || actualTime == null) return 0;
  return actualTime.difference(scheduledTime).inSeconds;
}

int? _parseHexColorValue(String? value) {
  if (value == null || value.isEmpty) return null;
  final sanitized = value.replaceFirst('#', '');
  if (sanitized.length != 6) return null;
  final parsed = int.tryParse('FF$sanitized', radix: 16);
  return parsed;
}

final int _defaultRouteColorValue = const Color(0xFF1E88E5).toARGB32();
final int _defaultVehicleMutedColorValue =
    const Color(0xFF7A8697).withValues(alpha: 0.85).toARGB32();

int _foregroundColorValue(int backgroundValue) =>
    Color(backgroundValue).computeLuminance() > 0.45
        ? Colors.black.toARGB32()
        : Colors.white.toARGB32();

int _vehicleStatusColorValue(bool realTime, int arrivalDelaySeconds) {
  if (!realTime) {
    return _defaultVehicleMutedColorValue;
  }

  final delayMinutes = arrivalDelaySeconds / 60;
  if (delayMinutes <= 0) return const Color(0xFF2E9B57).toARGB32();
  if (delayMinutes <= 2) {
    return (Color.lerp(
              const Color(0xFF2E9B57),
              const Color(0xFFF2C94C),
              delayMinutes / 2,
            ) ??
            const Color(0xFFF2C94C))
        .toARGB32();
  }
  if (delayMinutes <= 5) {
    return (Color.lerp(
              const Color(0xFFF2C94C),
              const Color(0xFFF2994A),
              (delayMinutes - 2) / 3,
            ) ??
            const Color(0xFFF2994A))
        .toARGB32();
  }
  if (delayMinutes <= 10) {
    return (Color.lerp(
              const Color(0xFFF2994A),
              const Color(0xFFEB5757),
              (delayMinutes - 5) / 5,
            ) ??
            const Color(0xFFEB5757))
        .toARGB32();
  }
  return const Color(0xFFC0392B).toARGB32();
}

double _distanceMeters(
  double fromLatitude,
  double fromLongitude,
  double toLatitude,
  double toLongitude,
) {
  final dLat = (toLatitude - fromLatitude) * math.pi / 180;
  final dLon = (toLongitude - fromLongitude) * math.pi / 180;
  final startLat = fromLatitude * math.pi / 180;
  final endLat = toLatitude * math.pi / 180;

  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(startLat) * math.cos(endLat) * math.pow(math.sin(dLon / 2), 2);
  final normalized = a.toDouble().clamp(0.0, 1.0);
  final c = 2 * math.atan2(math.sqrt(normalized), math.sqrt(1 - normalized));
  return 6371000 * c;
}

int _lowerBound(List<int> values, int target) {
  var low = 0;
  var high = values.length;
  while (low < high) {
    final mid = low + ((high - low) >> 1);
    if (values[mid] < target) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low;
}

LiveMapParseResult _parseLiveMapTripsIsolate(LiveMapParseRequest request) {
  final decoded = jsonDecode(request.body);
  if (decoded is! List) {
    throw FormatException(
      'Unsupported live map trips response: ${decoded.runtimeType}',
    );
  }

  final grouped = <String, List<Map<String, dynamic>>>{};
  var rawBusSegments = 0;

  for (final entry in decoded) {
    if (entry is! Map) continue;
    final trip = Map<String, dynamic>.from(entry);
    final mode = (trip['mode'] as String?)?.toUpperCase();
    if (mode != 'BUS') continue;
    rawBusSegments++;

    final trips = trip['trips'] as List?;
    final firstTrip = trips?.isNotEmpty == true ? trips!.first : null;
    final tripId = (firstTrip as Map<String, dynamic>?)?['tripId']?.toString();
    if (tripId == null || tripId.isEmpty) continue;

    grouped.putIfAbsent(tripId, () => <Map<String, dynamic>>[]).add(trip);
  }

  final builtTrips = <LiveMapTripData>[];
  final visibleTrips = <LiveMapTripData>[];
  final onScreenTrips = <LiveMapTripData>[];
  final nearbyTrips = <LiveMapTripData>[];

  for (final entry in grouped.entries) {
    final trip = _buildParsedTrip(
      entry.key,
      entry.value,
      fetchedAtMs: request.fetchedAtMs,
      nowMs: request.nowMs,
    );
    if (trip == null) continue;
    builtTrips.add(trip);

    if (_tripDataVisibleAt(trip, request.nowMs)) {
      visibleTrips.add(trip);
    }

    if (_tripDataIntersectsBounds(trip, request.visibleBounds)) {
      onScreenTrips.add(trip);
    }

    if (_tripDataIntersectsBounds(trip, request.retentionBounds)) {
      nearbyTrips.add(trip);
    }
  }

  final activeNearbyTrips = nearbyTrips
      .where((trip) => _tripDataVisibleAt(trip, request.nowMs))
      .toList(growable: false);
  final activeOnScreenTrips = onScreenTrips
      .where((trip) => _tripDataVisibleAt(trip, request.nowMs))
      .toList(growable: false);
  final activeBuiltTrips = builtTrips
      .where((trip) => _tripDataVisibleAt(trip, request.nowMs))
      .toList(growable: false);

  final preferredTrips = (activeNearbyTrips.isNotEmpty
      ? activeNearbyTrips
      : activeOnScreenTrips.isNotEmpty
          ? activeOnScreenTrips
          : activeBuiltTrips)
    ..sort((a, b) {
      final byName = a.displayName.compareTo(b.displayName);
      if (byName != 0) return byName;
      return a.id.compareTo(b.id);
    });

  return LiveMapParseResult(
    trips: preferredTrips,
    rawSegments: decoded.length,
    rawBusSegments: rawBusSegments,
    builtTrips: builtTrips.length,
    visibleTrips: visibleTrips.length,
    onScreenTrips: onScreenTrips.length,
    nearbyTrips: nearbyTrips.length,
  );
}

Map<String, dynamic>? _currentSegmentForTrip(
  List<Map<String, dynamic>> segments,
  int nowMs,
) {
  Map<String, dynamic>? bestSegment;
  var bestScore = 1 << 62;

  for (final segment in segments) {
    final score = _segmentActiveScore(segment, nowMs);
    if (score == null || score >= bestScore) continue;
    bestScore = score;
    bestSegment = segment;
  }

  return bestSegment;
}

int? _segmentActiveScore(
  Map<String, dynamic> segment,
  int nowMs, {
  int preStartGraceMs = 2 * 60 * 1000,
  int postEndGraceMs = 60 * 1000,
}) {
  final start = DateTime.tryParse(segment['departure']?.toString() ?? '');
  final end = DateTime.tryParse(segment['arrival']?.toString() ?? '');
  if (start == null || end == null) return null;

  final startMs = start.toUtc().millisecondsSinceEpoch;
  final endMs = end.toUtc().millisecondsSinceEpoch;
  if (endMs < startMs) return null;

  if (nowMs >= startMs && nowMs <= endMs) return 0;
  if (nowMs >= startMs - preStartGraceMs && nowMs < startMs) {
    return startMs - nowMs;
  }
  if (nowMs > endMs && nowMs <= endMs + postEndGraceMs) {
    return nowMs - endMs;
  }

  return null;
}

LiveMapTripData? _buildParsedTrip(
  String tripId,
  List<Map<String, dynamic>> segments, {
  required int fetchedAtMs,
  required int nowMs,
}) {
  if (segments.isEmpty) return null;

  segments.sort((a, b) {
    final aTime = DateTime.tryParse(a['departure']?.toString() ?? '');
    final bTime = DateTime.tryParse(b['departure']?.toString() ?? '');
    return (aTime ?? DateTime.fromMillisecondsSinceEpoch(0))
        .compareTo(bTime ?? DateTime.fromMillisecondsSinceEpoch(0));
  });

  final currentSegment = _currentSegmentForTrip(segments, nowMs);
  if (currentSegment == null) return null;

  final firstSegment = currentSegment;
  final lastSegment = currentSegment;
  final latitudes = <double>[];
  final longitudes = <double>[];
  final timestamps = <int>[];
  final headings = <double>[];

  for (final segment in [currentSegment]) {
    final polyline = segment['polyline']?.toString();
    if (polyline == null || polyline.isEmpty) continue;

    final decoded = _decodePolyline(polyline);
    if (decoded.latitudes.isEmpty || decoded.longitudes.isEmpty) continue;

    final start = DateTime.tryParse(segment['departure']?.toString() ?? '');
    final end = DateTime.tryParse(segment['arrival']?.toString() ?? '');
    if (start == null || end == null) continue;

    final sampled = _sampleSegment(
      decoded.latitudes,
      decoded.longitudes,
      start.toUtc().millisecondsSinceEpoch,
      end.toUtc().millisecondsSinceEpoch,
    );
    if (sampled.latitudes.isEmpty || sampled.longitudes.isEmpty) continue;

    final overlaps = latitudes.isNotEmpty &&
        sampled.latitudes.isNotEmpty &&
        _sameCoordinate(
          latitudes.last,
          longitudes.last,
          sampled.latitudes.first,
          sampled.longitudes.first,
        );
    final sameTimestamp = overlaps &&
        timestamps.isNotEmpty &&
        sampled.timestampsMs.isNotEmpty &&
        timestamps.last == sampled.timestampsMs.first;
    final startIndex = overlaps && sameTimestamp ? 1 : 0;

    latitudes.addAll(sampled.latitudes.skip(startIndex));
    longitudes.addAll(sampled.longitudes.skip(startIndex));
    timestamps.addAll(sampled.timestampsMs.skip(startIndex));
    headings.addAll(sampled.headings.skip(startIndex));
  }

  if (latitudes.isEmpty || timestamps.isEmpty || headings.isEmpty) return null;

  final trips = lastSegment['trips'] as List?;
  final firstTrip = trips?.isNotEmpty == true ? trips!.first : null;
  final displayName =
      (firstTrip as Map<String, dynamic>?)?['displayName']?.toString() ??
          tripId;
  final realTime = lastSegment['realTime'] == true;
  final arrivalDelaySeconds = _delaySeconds(
    lastSegment['scheduledArrival']?.toString(),
    lastSegment['arrival']?.toString(),
  );
  final routeColorValue =
      _parseHexColorValue(lastSegment['routeColor']?.toString()) ??
          _defaultRouteColorValue;
  final routeTextColorValue =
      _parseHexColorValue(lastSegment['routeTextColor']?.toString()) ??
          _foregroundColorValue(routeColorValue);
  final vehicleColorValue =
      _vehicleStatusColorValue(realTime, arrivalDelaySeconds);

  return LiveMapTripData(
    id: tripId,
    displayName: displayName,
    fromName:
        (firstSegment['from'] as Map<String, dynamic>?)?['name']?.toString() ??
            'Unknown stop',
    toName: (lastSegment['to'] as Map<String, dynamic>?)?['name']?.toString() ??
        'Unknown stop',
    realTime: realTime,
    arrivalDelaySeconds: arrivalDelaySeconds,
    fetchedAtMs: fetchedAtMs,
    routeColorValue: routeColorValue,
    routeTextColorValue: routeTextColorValue,
    vehicleColorValue: vehicleColorValue,
    vehicleTextColorValue: _foregroundColorValue(vehicleColorValue),
    latitudes: latitudes,
    longitudes: longitudes,
    timestampsMs: timestamps,
    headings: headings,
  );
}

bool _tripDataVisibleAt(
  LiveMapTripData trip,
  int nowMs, {
  int preStartGraceMs = 2 * 60 * 1000,
  int postEndGraceMs = 60 * 1000,
}) {
  if (trip.timestampsMs.isEmpty) return false;
  return nowMs >= trip.timestampsMs.first - preStartGraceMs &&
      nowMs <= trip.timestampsMs.last + postEndGraceMs;
}

bool _tripDataIntersectsBounds(
  LiveMapTripData trip,
  LiveMapBoundsData bounds,
) {
  if (trip.latitudes.isEmpty || trip.longitudes.isEmpty) return false;

  var minLatitude = double.infinity;
  var maxLatitude = double.negativeInfinity;
  var minLongitude = double.infinity;
  var maxLongitude = double.negativeInfinity;

  for (var index = 0; index < trip.latitudes.length; index++) {
    final latitude = trip.latitudes[index];
    final longitude = trip.longitudes[index];
    minLatitude = math.min(minLatitude, latitude);
    maxLatitude = math.max(maxLatitude, latitude);
    minLongitude = math.min(minLongitude, longitude);
    maxLongitude = math.max(maxLongitude, longitude);
    if (bounds.contains(latitude, longitude)) {
      return true;
    }
  }

  return maxLatitude >= bounds.south &&
      minLatitude <= bounds.north &&
      maxLongitude >= bounds.west &&
      minLongitude <= bounds.east;
}

extension on List<double> {
  double get firstOrZero => isEmpty ? 0 : first;
  double get lastOrZero => isEmpty ? 0 : last;
}
