import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_theme.dart';
import '../services/transport_api.dart';
import '../utils/app_error.dart';

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

class _TransitousLiveMapScreenState extends State<TransitousLiveMapScreen> {
  static const double _minLiveZoom = 11;
  static const Duration _lookBehind = Duration(minutes: 1);
  static const Duration _lookAhead = Duration(minutes: 3);
  static const Duration _fetchDebounceDuration = Duration(milliseconds: 350);
  static const Duration _refreshInterval = Duration(seconds: 5);
  static const Duration _animationInterval = Duration(milliseconds: 120);
  static const Duration _tripRetentionDuration = Duration(minutes: 2);
  static const double _fetchPaddingFactor = 0.9;
  static const double _retentionPaddingFactor = 1.5;
  static const double _zoomRequestStep = 0.5;

  final MapController _mapController = MapController();
  final Distance _distance = const Distance();

  LatLng _initialCenter = const LatLng(52.52, 13.405);
  double _initialZoom = 13;
  bool _isLoadingInitialView = true;
  bool _isFetchingTrips = false;
  bool _isMapReady = false;
  String? _errorMessage;
  MapCamera? _latestCamera;
  _FetchedViewport? _lastFetchedViewport;
  DateTime _now = DateTime.now();
  List<_LiveBusTrip> _trips = const [];
  _SelectedBus? _selectedBus;

  Timer? _fetchDebounce;
  Timer? _refreshTimer;
  Timer? _animationTimer;
  int _requestToken = 0;
  bool _forceNextFetch = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _animationTimer = Timer.periodic(_animationInterval, (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
    _refreshTimer = Timer.periodic(
      _refreshInterval,
      (_) => _scheduleFetch(force: true),
    );
  }

  @override
  void dispose() {
    _fetchDebounce?.cancel();
    _refreshTimer?.cancel();
    _animationTimer?.cancel();
    super.dispose();
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
    if (force) {
      _forceNextFetch = true;
    }
    _fetchDebounce?.cancel();
    _fetchDebounce = Timer(_fetchDebounceDuration, _fetchTripsForViewport);
  }

  String _coordString(LatLng point) => '${point.latitude},${point.longitude}';

  double _requestZoom(double zoom) =>
      (zoom / _zoomRequestStep).round() * _zoomRequestStep;

  double _markerRotationRadians(double heading) =>
      (heading - 90) * math.pi / 180;

  Future<void> _fetchTripsForViewport() async {
    final camera = _latestCamera;
    final force = _forceNextFetch;
    _forceNextFetch = false;

    if (!mounted || !_isMapReady || camera == null) {
      return;
    }

    if (camera.zoom < _minLiveZoom) {
      if (_trips.isNotEmpty || _errorMessage != null) {
        setState(() {
          _trips = const [];
          _selectedBus = null;
          _errorMessage = null;
        });
      }
      _lastFetchedViewport = null;
      return;
    }

    final visibleBounds = camera.visibleBounds;
    final requestZoom = _requestZoom(camera.zoom);
    if (!force &&
        _lastFetchedViewport?.covers(
              visibleBounds: visibleBounds,
              requestZoom: requestZoom,
            ) ==
            true) {
      return;
    }

    final bounds = _expandBounds(visibleBounds, _fetchPaddingFactor);
    final now = DateTime.now();
    final token = ++_requestToken;

    setState(() {
      _isFetchingTrips = true;
      _errorMessage = null;
    });

    try {
      final rawTrips = await TransportApi.fetchLiveMapTrips(
        min: _coordString(_southWest(bounds)),
        max: _coordString(_northEast(bounds)),
        startTime: now.subtract(_lookBehind),
        endTime: now.add(_lookAhead),
        zoom: requestZoom,
      );
      if (!mounted || token != _requestToken) return;

      final incomingTrips = _buildTrips(
        rawTrips,
        fetchedAtMs: now.toUtc().millisecondsSinceEpoch,
      );
      final retentionBounds = _expandBounds(
        visibleBounds,
        _retentionPaddingFactor,
      );
      final visibleIncomingTrips = incomingTrips
          .where(
            (trip) => trip.isVisibleAt(now),
          )
          .toList();
      final nearbyIncomingTrips = visibleIncomingTrips
          .where((trip) => trip.intersectsBounds(retentionBounds))
          .toList();
      final preferredIncomingTrips = nearbyIncomingTrips.isNotEmpty
          ? nearbyIncomingTrips
          : visibleIncomingTrips;

      final trips = _mergeTrips(
        existing: _trips,
        incoming: preferredIncomingTrips,
        now: now,
        visibleBounds: visibleBounds,
      );
      final selectedTrip = _selectedBus == null
          ? null
          : trips.cast<_LiveBusTrip?>().firstWhere(
                (trip) => trip?.id == _selectedBus!.tripId,
                orElse: () => null,
              );

      setState(() {
        _now = now;
        _trips = trips;
        _selectedBus = selectedTrip == null
            ? null
            : _SelectedBus(
                tripId: selectedTrip.id,
                position: selectedTrip.sample(now).position,
              );
      });
      _lastFetchedViewport = _FetchedViewport(
        bounds: bounds,
        requestZoom: requestZoom,
      );
    } catch (error, stackTrace) {
      if (!mounted || token != _requestToken) return;
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
      if (mounted && token == _requestToken) {
        setState(() => _isFetchingTrips = false);
      }
    }
  }

  List<_LiveBusTrip> _buildTrips(
    List<Map<String, dynamic>> rawTrips, {
    required int fetchedAtMs,
  }) {
    final grouped = <String, List<Map<String, dynamic>>>{};

    for (final trip in rawTrips) {
      final mode = (trip['mode'] as String?)?.toUpperCase();
      if (mode != 'BUS') continue;

      final trips = trip['trips'] as List?;
      final firstTrip = trips?.isNotEmpty == true ? trips!.first : null;
      final tripId =
          (firstTrip as Map<String, dynamic>?)?['tripId']?.toString();
      if (tripId == null || tripId.isEmpty) continue;

      grouped.putIfAbsent(tripId, () => []).add(trip);
    }

    final combined = <_LiveBusTrip>[];
    for (final entry in grouped.entries) {
      final trip = _LiveBusTrip.fromSegments(
        entry.key,
        entry.value,
        distance: _distance,
        fetchedAtMs: fetchedAtMs,
      );
      if (trip != null) {
        combined.add(trip);
      }
    }

    combined.sort((a, b) {
      final byName = a.displayName.compareTo(b.displayName);
      if (byName != 0) return byName;
      return a.id.compareTo(b.id);
    });
    return combined;
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
      if (merged.containsKey(trip.id)) continue;
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

  int _maxVisibleTripsForZoom(double zoom) {
    if (zoom >= 14.5) return 220;
    if (zoom >= 13.5) return 140;
    if (zoom >= 12.5) return 90;
    if (zoom >= 11.5) return 50;
    return 24;
  }

  List<_LiveBusTrip> _prioritizeTripsForDisplay(
    List<_LiveBusTrip> trips,
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
    final sample = trip.sample(_now);
    final distanceFromCenterKm =
        _distance.as(LengthUnit.Kilometer, center, sample.position);

    var score = 0.0;
    if (trip.id == selectedTripId) score += 10000;
    if (trip.realTime) score += 600;
    score += trip.arrivalDelaySeconds.abs() / 6;
    score += math.max(0, 300 - distanceFromCenterKm * 35);

    final line = trip.displayName.trim().toUpperCase();
    if (line.startsWith('N')) score -= 120;

    return score;
  }

  Size _markerSizeForZoom(double zoom) {
    if (zoom >= 14.5) return const Size(112, 58);
    if (zoom >= 13.5) return const Size(98, 52);
    if (zoom >= 12.5) return const Size(90, 48);
    return const Size(78, 42);
  }

  void _selectTrip(_LiveBusTrip trip) {
    setState(() {
      _selectedBus = _SelectedBus(
        tripId: trip.id,
        position: trip.sample(_now).position,
      );
    });
  }

  void _clearSelection() {
    if (_selectedBus == null) return;
    setState(() => _selectedBus = null);
  }

  _LiveBusTrip? _currentSelectedTrip() {
    final selectedTripId = _selectedBus?.tripId;
    if (selectedTripId == null) return null;

    return _trips.cast<_LiveBusTrip?>().firstWhere(
          (trip) => trip?.id == selectedTripId,
          orElse: () => null,
        );
  }

  Color _routeColor(_LiveBusTrip trip, BuildContext context) {
    final routeColor = _parseHexColor(trip.routeColorHex);
    if (routeColor != null) return routeColor;
    return TransColors.of(context).navBarSelected;
  }

  Color _routeTextColor(_LiveBusTrip trip, BuildContext context) {
    final textColor = _parseHexColor(trip.routeTextColorHex);
    if (textColor != null) return textColor;
    return _routeColor(trip, context).computeLuminance() > 0.5
        ? Colors.black
        : Colors.white;
  }

  Color _vehicleStatusColor(_LiveBusTrip trip, BuildContext context) {
    final colors = TransColors.of(context);
    if (!trip.realTime) {
      return colors.textSecondary.withValues(alpha: 0.75);
    }

    final delayMinutes = trip.arrivalDelaySeconds / 60;
    if (delayMinutes <= 0) return const Color(0xFF2E9B57);
    if (delayMinutes <= 2) {
      return Color.lerp(
            const Color(0xFF2E9B57),
            const Color(0xFFF2C94C),
            delayMinutes / 2,
          ) ??
          const Color(0xFFF2C94C);
    }
    if (delayMinutes <= 5) {
      return Color.lerp(
            const Color(0xFFF2C94C),
            const Color(0xFFF2994A),
            (delayMinutes - 2) / 3,
          ) ??
          const Color(0xFFF2994A);
    }
    if (delayMinutes <= 10) {
      return Color.lerp(
            const Color(0xFFF2994A),
            const Color(0xFFEB5757),
            (delayMinutes - 5) / 5,
          ) ??
          const Color(0xFFEB5757);
    }
    return const Color(0xFFC0392B);
  }

  Color _foregroundFor(Color background) =>
      background.computeLuminance() > 0.45 ? Colors.black : Colors.white;

  String _delayLabel(_LiveBusTrip trip) {
    if (!trip.realTime) return 'No realtime';

    final delayMinutes = (trip.arrivalDelaySeconds / 60).round();
    if (delayMinutes <= 0) return 'On time';
    return '+$delayMinutes min';
  }

  Widget _buildBusMarker(
    BuildContext context,
    _LiveBusTrip trip,
    _TripSample sample,
  ) {
    final colors = TransColors.of(context);
    final isSelected = _selectedBus?.tripId == trip.id;
    final vehicleColor = _vehicleStatusColor(trip, context);
    final markerTextColor = _foregroundFor(vehicleColor);
    final markerAngle = _markerRotationRadians(sample.heading);
    final iconLeads = math.cos(markerAngle) >= 0;
    final content = <Widget>[
      if (!iconLeads)
        Icon(
          Icons.directions_bus_filled_rounded,
          size: 16,
          color: markerTextColor,
        ),
      if (!iconLeads) const SizedBox(width: 6),
      Text(
        trip.displayName,
        style: TextStyle(
          color: markerTextColor,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
      if (iconLeads) const SizedBox(width: 6),
      if (iconLeads)
        Icon(
          Icons.directions_bus_filled_rounded,
          size: 16,
          color: markerTextColor,
        ),
    ];

    return GestureDetector(
      onTap: () => _selectTrip(trip),
      child: Transform.rotate(
        angle: markerAngle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: vehicleColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? colors.textPrimary : Colors.white,
              width: isSelected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: isSelected ? 18 : 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: content,
          ),
        ),
      ),
    );
  }

  Widget _buildTopBanner(BuildContext context) {
    final colors = TransColors.of(context);
    final center = _latestCamera?.center ?? _initialCenter;
    final zoom = _latestCamera?.zoom ?? _initialZoom;
    final prioritizedTrips = _prioritizeTripsForDisplay(
      _trips,
      center: center,
      zoom: zoom,
    );
    final busesVisible = prioritizedTrips.length;
    final totalLoaded = _trips.length;

    String text;
    if (!_isMapReady) {
      text = 'Preparing live map...';
    } else if (zoom < _minLiveZoom) {
      text = 'Zoom in to ${_minLiveZoom.toInt()}+ to reveal live buses.';
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
    final sample = selected.sample(_now);
    final realtimeLabel = selected.realTime ? 'Realtime' : 'Scheduled';
    final delayColor = _vehicleStatusColor(selected, context);
    final delayTextColor = _foregroundFor(delayColor);

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
              color: _routeColor(selected, context).withValues(alpha: 0.35),
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
                      color: _routeColor(selected, context),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      selected.displayName,
                      style: TextStyle(
                        color: _routeTextColor(selected, context),
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
                      color: delayColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _delayLabel(selected),
                      style: TextStyle(
                        color: delayTextColor,
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
                '${selected.fromName} -> ${selected.toName}',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Tap another bus to switch the highlighted route.',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Lat ${sample.position.latitude.toStringAsFixed(5)}, '
                'Lng ${sample.position.longitude.toStringAsFixed(5)}',
                style: TextStyle(color: colors.textSecondary),
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
    final remainingPath = selectedTrip?.remainingPath(_now) ?? const <LatLng>[];
    final displayedTrips = _prioritizeTripsForDisplay(
      _trips,
      center: center,
      zoom: zoom,
    );
    final markerSize = _markerSizeForZoom(zoom);

    if (_isLoadingInitialView) {
      return Scaffold(
        backgroundColor: colors.scaffoldBg,
        appBar: AppBar(title: const Text('Live Buses')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final markers = <Marker>[
      for (final trip in displayedTrips)
        (() {
          final sample = trip.sample(_now);
          return Marker(
            point: sample.position,
            width: markerSize.width,
            height: markerSize.height,
            child: KeyedSubtree(
              key: ValueKey('live-bus-${trip.id}'),
              child: _buildBusMarker(context, trip, sample),
            ),
          );
        })(),
    ];

    return Scaffold(
      backgroundColor: colors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Live Buses'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
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
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _clearSelection();
          if (!_isMapReady) return;
          _mapController.move(_initialCenter, _initialZoom);
          _scheduleFetch(force: true);
        },
        child: const Icon(Icons.center_focus_strong),
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
                _latestCamera = camera;
                if (hasGesture) {
                  _clearSelection();
                }
                _scheduleFetch();
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.trans',
              ),
              if (selectedTrip != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: selectedTrip.points,
                      strokeWidth: 12,
                      color: Colors.black.withValues(alpha: 0.10),
                    ),
                    Polyline(
                      points: selectedTrip.points,
                      strokeWidth: 6,
                      color: _routeColor(selectedTrip, context),
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
                        color: _vehicleStatusColor(selectedTrip, context),
                      ),
                    if (remainingPath.length >= 2)
                      Polyline(
                        points: remainingPath.take(2).toList(),
                        strokeWidth: 9,
                        color: _routeColor(selectedTrip, context),
                      ),
                  ],
                ),
              MarkerLayer(markers: markers),
            ],
          ),
          _buildTopBanner(context),
          _buildSelectionSheet(context),
        ],
      ),
    );
  }
}

class _SelectedBus {
  final String tripId;
  final LatLng position;

  const _SelectedBus({
    required this.tripId,
    required this.position,
  });
}

class _FetchedViewport {
  final LatLngBounds bounds;
  final double requestZoom;

  const _FetchedViewport({
    required this.bounds,
    required this.requestZoom,
  });

  bool covers({
    required LatLngBounds visibleBounds,
    required double requestZoom,
  }) {
    if (this.requestZoom != requestZoom) return false;

    return _containsPoint(bounds, _northWest(visibleBounds)) &&
        _containsPoint(bounds, _southEast(visibleBounds));
  }
}

class _TripSample {
  final LatLng position;
  final double heading;
  final int previousIndex;
  final int nextIndex;
  final double progress;

  const _TripSample({
    required this.position,
    required this.heading,
    required this.previousIndex,
    required this.nextIndex,
    required this.progress,
  });
}

class _LiveBusTrip {
  final String id;
  final String displayName;
  final String fromName;
  final String toName;
  final bool realTime;
  final String? routeColorHex;
  final String? routeTextColorHex;
  final int arrivalDelaySeconds;
  final int fetchedAtMs;
  final List<LatLng> points;
  final List<int> timestampsMs;
  final List<double> headings;

  const _LiveBusTrip({
    required this.id,
    required this.displayName,
    required this.fromName,
    required this.toName,
    required this.realTime,
    required this.routeColorHex,
    required this.routeTextColorHex,
    required this.arrivalDelaySeconds,
    required this.fetchedAtMs,
    required this.points,
    required this.timestampsMs,
    required this.headings,
  });

  static _LiveBusTrip? fromSegments(
    String tripId,
    List<Map<String, dynamic>> segments, {
    required Distance distance,
    required int fetchedAtMs,
  }) {
    if (segments.isEmpty) return null;

    segments.sort((a, b) {
      final aTime = DateTime.tryParse(a['departure']?.toString() ?? '');
      final bTime = DateTime.tryParse(b['departure']?.toString() ?? '');
      return (aTime ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(bTime ?? DateTime.fromMillisecondsSinceEpoch(0));
    });

    final firstSegment = segments.first;
    final lastSegment = segments.last;
    final points = <LatLng>[];
    final timestamps = <int>[];
    final headings = <double>[];

    for (final segment in segments) {
      final polyline = segment['polyline']?.toString();
      if (polyline == null || polyline.isEmpty) continue;

      final decoded = _decodePolyline(polyline);
      if (decoded.isEmpty) continue;

      final start = DateTime.tryParse(segment['departure']?.toString() ?? '');
      final end = DateTime.tryParse(segment['arrival']?.toString() ?? '');
      if (start == null || end == null) continue;

      final sampled = _sampleSegment(
        decoded,
        start.toUtc().millisecondsSinceEpoch,
        end.toUtc().millisecondsSinceEpoch,
        distance,
      );
      if (sampled.points.isEmpty) continue;

      final overlaps = points.isNotEmpty &&
          sampled.points.isNotEmpty &&
          _samePoint(points.last, sampled.points.first);
      final sameTimestamp = overlaps &&
          timestamps.isNotEmpty &&
          sampled.timestampsMs.isNotEmpty &&
          timestamps.last == sampled.timestampsMs.first;
      final startIndex = overlaps && sameTimestamp ? 1 : 0;

      points.addAll(sampled.points.skip(startIndex));
      timestamps.addAll(sampled.timestampsMs.skip(startIndex));
      headings.addAll(sampled.headings.skip(startIndex));
    }

    if (points.isEmpty || timestamps.isEmpty || headings.isEmpty) return null;

    final trips = lastSegment['trips'] as List?;
    final firstTrip = trips?.isNotEmpty == true ? trips!.first : null;

    return _LiveBusTrip(
      id: tripId,
      displayName:
          (firstTrip as Map<String, dynamic>?)?['displayName']?.toString() ??
              tripId,
      fromName: (firstSegment['from'] as Map<String, dynamic>?)?['name']
              ?.toString() ??
          'Unknown stop',
      toName:
          (lastSegment['to'] as Map<String, dynamic>?)?['name']?.toString() ??
              'Unknown stop',
      realTime: lastSegment['realTime'] == true,
      routeColorHex: lastSegment['routeColor']?.toString(),
      routeTextColorHex: lastSegment['routeTextColor']?.toString(),
      arrivalDelaySeconds: _delaySeconds(
        lastSegment['scheduledArrival']?.toString(),
        lastSegment['arrival']?.toString(),
      ),
      fetchedAtMs: fetchedAtMs,
      points: points,
      timestampsMs: timestamps,
      headings: headings,
    );
  }

  _TripSample sample(DateTime now) {
    if (points.length == 1 || timestampsMs.length == 1) {
      return _TripSample(
        position: points.first,
        heading: headings.firstOrZero,
        previousIndex: 0,
        nextIndex: 0,
        progress: 0,
      );
    }

    final nowMs = now.toUtc().millisecondsSinceEpoch;
    if (nowMs <= timestampsMs.first) {
      return _TripSample(
        position: points.first,
        heading: headings.firstOrZero,
        previousIndex: 0,
        nextIndex: 0,
        progress: 0,
      );
    }
    if (nowMs >= timestampsMs.last) {
      final lastIndex = points.length - 1;
      return _TripSample(
        position: points.last,
        heading: headings.lastOrZero,
        previousIndex: lastIndex,
        nextIndex: lastIndex,
        progress: 1,
      );
    }

    var index = 1;
    while (index < timestampsMs.length && timestampsMs[index] < nowMs) {
      index++;
    }

    final previousIndex = math.max(index - 1, 0);
    final nextIndex = math.min(index, points.length - 1);
    final previousTime = timestampsMs[previousIndex];
    final nextTime = timestampsMs[nextIndex];
    final rawProgress = nextTime == previousTime
        ? 0.0
        : (nowMs - previousTime) / (nextTime - previousTime);
    final progress =
        Curves.easeInOutSine.transform(rawProgress.clamp(0.0, 1.0));

    final previousPoint = points[previousIndex];
    final nextPoint = points[nextIndex];

    return _TripSample(
      position: LatLng(
        _lerp(previousPoint.latitude, nextPoint.latitude, progress),
        _lerp(previousPoint.longitude, nextPoint.longitude, progress),
      ),
      heading: _lerpAngle(
        headings[previousIndex],
        headings[nextIndex],
        progress,
      ),
      previousIndex: previousIndex,
      nextIndex: nextIndex,
      progress: progress,
    );
  }

  List<LatLng> remainingPath(DateTime now) {
    final sampleNow = sample(now);
    final startIndex = sampleNow.nextIndex.clamp(0, points.length - 1);
    final remaining = <LatLng>[sampleNow.position];
    remaining.addAll(points.skip(startIndex));
    return _dedupeSequentialPoints(remaining);
  }

  bool isVisibleAt(
    DateTime now, {
    Duration preStartGrace = const Duration(minutes: 2),
    Duration postEndGrace = const Duration(minutes: 1),
  }) {
    if (timestampsMs.isEmpty) return false;

    final nowMs = now.toUtc().millisecondsSinceEpoch;
    return nowMs >= timestampsMs.first - preStartGrace.inMilliseconds &&
        nowMs <= timestampsMs.last + postEndGrace.inMilliseconds;
  }

  bool intersectsBounds(LatLngBounds bounds) {
    if (points.isEmpty) return false;

    for (var index = 0; index < points.length; index += 6) {
      if (_containsPoint(bounds, points[index])) {
        return true;
      }
    }

    return _containsPoint(bounds, points.last);
  }
}

class _SampledSegment {
  final List<LatLng> points;
  final List<int> timestampsMs;
  final List<double> headings;

  const _SampledSegment({
    required this.points,
    required this.timestampsMs,
    required this.headings,
  });
}

_SampledSegment _sampleSegment(
  List<LatLng> decoded,
  int startMs,
  int endMs,
  Distance distance,
) {
  if (decoded.isEmpty) {
    return const _SampledSegment(points: [], timestampsMs: [], headings: []);
  }

  if (decoded.length == 1) {
    return _SampledSegment(
      points: decoded,
      timestampsMs: [startMs],
      headings: const [0],
    );
  }

  final cumulativeDistances = List<double>.filled(decoded.length, 0);
  final headings = List<double>.filled(decoded.length, 0);

  var totalDistance = 0.0;
  for (var i = 1; i < decoded.length; i++) {
    totalDistance += distance.as(LengthUnit.Meter, decoded[i - 1], decoded[i]);
    cumulativeDistances[i] = totalDistance;
    headings[i - 1] = _bearing(decoded[i - 1], decoded[i]);
  }
  headings[decoded.length - 1] = headings[decoded.length - 2];

  final duration = endMs - startMs;
  final timestamps = List<int>.generate(decoded.length, (index) {
    if (totalDistance == 0 || duration <= 0) return startMs;
    final progress = cumulativeDistances[index] / totalDistance;
    return startMs + (duration * progress).round();
  });

  return _SampledSegment(
    points: decoded,
    timestampsMs: timestamps,
    headings: headings,
  );
}

LatLngBounds _expandBounds(LatLngBounds bounds, double factor) {
  final northWest = _northWest(bounds);
  final southEast = _southEast(bounds);
  final latPadding = (northWest.latitude - southEast.latitude).abs() * factor;
  final lonPadding = (southEast.longitude - northWest.longitude).abs() * factor;

  return LatLngBounds(
    LatLng(
      southEast.latitude - latPadding,
      northWest.longitude - lonPadding,
    ),
    LatLng(
      northWest.latitude + latPadding,
      southEast.longitude + lonPadding,
    ),
  );
}

LatLng _northWest(LatLngBounds bounds) =>
    LatLng(bounds.northWest.latitude, bounds.northWest.longitude);

LatLng _southEast(LatLngBounds bounds) =>
    LatLng(bounds.southEast.latitude, bounds.southEast.longitude);

LatLng _southWest(LatLngBounds bounds) =>
    LatLng(bounds.southEast.latitude, bounds.northWest.longitude);

LatLng _northEast(LatLngBounds bounds) =>
    LatLng(bounds.northWest.latitude, bounds.southEast.longitude);

bool _containsPoint(LatLngBounds bounds, LatLng point) {
  final southWest = _southWest(bounds);
  final northEast = _northEast(bounds);

  return point.latitude >= southWest.latitude &&
      point.latitude <= northEast.latitude &&
      point.longitude >= southWest.longitude &&
      point.longitude <= northEast.longitude;
}

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

List<LatLng> _decodePolyline(String encoded, {int precision = 5}) {
  final points = <LatLng>[];
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

    points.add(LatLng(lat / factor, lng / factor));
  }

  return points;
}

double _bearing(LatLng from, LatLng to) {
  final fromLat = from.latitude * math.pi / 180;
  final toLat = to.latitude * math.pi / 180;
  final deltaLng = (to.longitude - from.longitude) * math.pi / 180;

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

int _delaySeconds(String? scheduled, String? actual) {
  if (scheduled == null || actual == null) return 0;
  final scheduledTime = DateTime.tryParse(scheduled);
  final actualTime = DateTime.tryParse(actual);
  if (scheduledTime == null || actualTime == null) return 0;
  return actualTime.difference(scheduledTime).inSeconds;
}

Color? _parseHexColor(String? value) {
  if (value == null || value.isEmpty) return null;
  final sanitized = value.replaceFirst('#', '');
  if (sanitized.length != 6) return null;
  final parsed = int.tryParse('FF$sanitized', radix: 16);
  return parsed == null ? null : Color(parsed);
}

extension on List<double> {
  double get firstOrZero => isEmpty ? 0 : first;
  double get lastOrZero => isEmpty ? 0 : last;
}
