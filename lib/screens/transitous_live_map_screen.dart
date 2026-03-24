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
  static const double _minLiveZoom = 12;
  static const Duration _lookAhead = Duration(minutes: 3);
  static const Duration _fetchDebounceDuration = Duration(milliseconds: 350);
  static const Duration _refreshInterval = Duration(minutes: 1);
  static const Duration _animationInterval = Duration(milliseconds: 250);

  final MapController _mapController = MapController();
  final Distance _distance = const Distance();

  LatLng _initialCenter = const LatLng(52.52, 13.405);
  double _initialZoom = 13;
  bool _isLoadingInitialView = true;
  bool _isFetchingTrips = false;
  String? _errorMessage;
  MapCamera? _latestCamera;
  DateTime _now = DateTime.now();
  List<_LiveBusTrip> _trips = const [];
  _SelectedBus? _selectedBus;

  Timer? _fetchDebounce;
  Timer? _refreshTimer;
  Timer? _animationTimer;
  int _requestToken = 0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _animationTimer = Timer.periodic(_animationInterval, (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
    _refreshTimer = Timer.periodic(_refreshInterval, (_) => _scheduleFetch());
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

  void _scheduleFetch() {
    _fetchDebounce?.cancel();
    _fetchDebounce = Timer(_fetchDebounceDuration, _fetchTripsForViewport);
  }

  String _coordString(LatLng point) => '${point.latitude},${point.longitude}';

  Future<void> _fetchTripsForViewport() async {
    final camera = _latestCamera ?? _mapController.camera;
    if (!mounted || camera.zoom < _minLiveZoom) {
      if (_trips.isNotEmpty || _errorMessage != null) {
        setState(() {
          _trips = const [];
          _selectedBus = null;
          _errorMessage = null;
        });
      }
      return;
    }

    final bounds = camera.visibleBounds;
    final now = DateTime.now();
    final token = ++_requestToken;

    setState(() {
      _isFetchingTrips = true;
      _errorMessage = null;
    });

    try {
      final rawTrips = await TransportApi.fetchLiveMapTrips(
        min: _coordString(bounds.southEast),
        max: _coordString(bounds.northWest),
        startTime: now,
        endTime: now.add(_lookAhead),
        zoom: camera.zoom,
      );
      if (!mounted || token != _requestToken) return;

      final trips = _buildTrips(rawTrips);
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
    } catch (error, stackTrace) {
      if (!mounted || token != _requestToken) return;
      AppError.log(
        error,
        stackTrace: stackTrace,
        source: 'live map trips',
      );
      setState(() {
        _trips = const [];
        _selectedBus = null;
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

  List<_LiveBusTrip> _buildTrips(List<Map<String, dynamic>> rawTrips) {
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
      );
      if (trip != null) {
        combined.add(trip);
      }
    }

    combined.sort((a, b) => a.displayName.compareTo(b.displayName));
    return combined;
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

  Widget _buildBusMarker(
    BuildContext context,
    _LiveBusTrip trip,
    _TripSample sample,
  ) {
    final colors = TransColors.of(context);
    final isSelected = _selectedBus?.tripId == trip.id;
    final routeColor = _routeColor(trip, context);
    final routeTextColor = _routeTextColor(trip, context);

    return GestureDetector(
      onTap: () => _selectTrip(trip),
      child: Transform.rotate(
        angle: sample.heading * math.pi / 180,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: routeColor,
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
            children: [
              Icon(
                Icons.directions_bus_filled_rounded,
                size: 16,
                color: routeTextColor,
              ),
              const SizedBox(width: 6),
              Text(
                trip.displayName,
                style: TextStyle(
                  color: routeTextColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBanner(BuildContext context) {
    final colors = TransColors.of(context);
    final zoom = _latestCamera?.zoom ?? _initialZoom;
    final busesVisible = _trips.length;

    String text;
    if (zoom < _minLiveZoom) {
      text = 'Zoom in to ${_minLiveZoom.toInt()}+ to reveal live buses.';
    } else if (_isFetchingTrips && busesVisible == 0) {
      text = 'Loading live buses...';
    } else if (_errorMessage != null) {
      text = _errorMessage!;
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
    final selected = _selectedBus == null
        ? null
        : _trips.cast<_LiveBusTrip?>().firstWhere(
              (trip) => trip?.id == _selectedBus!.tripId,
              orElse: () => null,
            );
    if (selected == null) return const SizedBox.shrink();

    final colors = TransColors.of(context);
    final sample = selected.sample(_now);
    final delayMinutes = (selected.arrivalDelaySeconds / 60).round();
    final realtimeLabel = selected.realTime ? 'Realtime' : 'Scheduled';

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
                delayMinutes == 0
                    ? 'On time'
                    : '${delayMinutes > 0 ? '+' : ''}$delayMinutes min',
                style: TextStyle(
                  color: delayMinutes == 0 ? Colors.green : Colors.orange,
                  fontWeight: FontWeight.w700,
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

    if (_isLoadingInitialView) {
      return Scaffold(
        backgroundColor: colors.scaffoldBg,
        appBar: AppBar(title: const Text('Live Buses')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final markers = <Marker>[
      for (final trip in _trips)
        Marker(
          point: trip.sample(_now).position,
          width: 96,
          height: 44,
          child: _buildBusMarker(context, trip, trip.sample(_now)),
        ),
    ];

    return Scaffold(
      backgroundColor: colors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Live Buses'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _fetchTripsForViewport,
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
          _mapController.move(_initialCenter, _initialZoom);
          _scheduleFetch();
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
              onMapReady: _scheduleFetch,
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

class _TripSample {
  final LatLng position;
  final double heading;

  const _TripSample({
    required this.position,
    required this.heading,
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
    required this.points,
    required this.timestampsMs,
    required this.headings,
  });

  static _LiveBusTrip? fromSegments(
    String tripId,
    List<Map<String, dynamic>> segments, {
    required Distance distance,
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
      final startIndex = overlaps ? 1 : 0;

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
      points: points,
      timestampsMs: timestamps,
      headings: headings,
    );
  }

  _TripSample sample(DateTime now) {
    if (points.length == 1 || timestampsMs.length == 1) {
      return _TripSample(position: points.first, heading: headings.firstOrZero);
    }

    final nowMs = now.toUtc().millisecondsSinceEpoch;
    if (nowMs <= timestampsMs.first) {
      return _TripSample(position: points.first, heading: headings.firstOrZero);
    }
    if (nowMs >= timestampsMs.last) {
      return _TripSample(position: points.last, heading: headings.lastOrZero);
    }

    var index = 1;
    while (index < timestampsMs.length && timestampsMs[index] < nowMs) {
      index++;
    }

    final previousIndex = math.max(index - 1, 0);
    final nextIndex = math.min(index, points.length - 1);
    final previousTime = timestampsMs[previousIndex];
    final nextTime = timestampsMs[nextIndex];
    final progress = nextTime == previousTime
        ? 0.0
        : (nowMs - previousTime) / (nextTime - previousTime);

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
    );
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
