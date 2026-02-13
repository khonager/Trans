import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:trans/models/journey.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:trans/services/transport_api.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MapScreen extends StatefulWidget {
  final List<JourneyStep> steps;
  final JourneyStep? focusStep;
  final Position? currentPosition;

  const MapScreen({
    super.key,
    required this.steps,
    this.focusStep,
    this.currentPosition,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class CompassIconPainter extends CustomPainter {
  final Color color;
  CompassIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..strokeWidth = 2; // For the dot if drawn as circle

    final center = Offset(size.width / 2, size.height / 2);
    final w = size.width;
    final h = size.height;

    // Draw Dot
    canvas.drawCircle(center, 2.5, paint);

    // Arrow 1: Bottom Left to Center
    // Tip at center - offset slightly to not cover dot? Or touch dot.
    // Let's make arrows "point to" the dot.
    // Start: Bottom Left (0, h) -> End: Center (w/2, h/2)
    // Actually user said: "one arrow from the bottom left to the middle... and another arrow from the other side, the top right to the middle"
    
    final p1 = Path();
    // Arrow head at center-ish
    // Let's draw a simple stylized arrow
    // Bottom Left Arrow
    p1.moveTo(2, h - 2); // Start bottom left
    p1.lineTo(w / 2 - 4, h / 2 + 4); // To near center
    // Make it an arrow? Or just a line? "two arrows pointing to a dot"
    // Let's add arrow heads.
    // This is small (icon size). Simple chevron or triangle might be best.
    
    // Draw Arrow 1 (Bottom Left -> Center)
    _drawArrow(canvas, paint, Offset(2, h-2), Offset(w/2 - 3, h/2 + 3));

    // Draw Arrow 2 (Top Right -> Center)
    _drawArrow(canvas, paint, Offset(w-2, 2), Offset(w/2 + 3, h/2 - 3));
  }
  
  void _drawArrow(Canvas canvas, Paint paint, Offset start, Offset end) {
      // Draw line
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 2.5;
      canvas.drawLine(start, end, paint);
      
      // Draw head
      // Vector
      final dx = end.dx - start.dx;
      final dy = end.dy - start.dy;
      final angle = atan2(dy, dx);
      
      final arrowSize = 6.0;
      final p = Path();
      p.moveTo(end.dx - arrowSize * cos(angle - pi / 6), end.dy - arrowSize * sin(angle - pi / 6));
      p.lineTo(end.dx, end.dy);
      p.lineTo(end.dx - arrowSize * cos(angle + pi / 6), end.dy - arrowSize * sin(angle + pi / 6));
      
      paint.style = PaintingStyle.stroke;
      canvas.drawPath(p, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  List<LatLng> _routePoints = [];
  List<Marker> _markers = [];
  LatLngBounds? _bounds;
  bool _isLoadingPath = true;
  
  // Compass Mode State
  bool _isCompassMode = false;
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<CompassEvent>? _compassStream;
  double? _currentHeading;

  @override
  void initState() {
    super.initState();
    _loadRoute();
  }
  
  @override
  void dispose() {
    _positionStream?.cancel();
    _compassStream?.cancel();
    super.dispose();
  }
  
  void _toggleCompassMode() {
    if (_isCompassMode) {
      _disableCompassMode();
    } else {
      _enableCompassMode();
    }
  }
  
  void _enableCompassMode() async {
    setState(() => _isCompassMode = true);
    
    // Check permissions just in case (though RoutesTab usually handles it)
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
       // Try request?
       try { permission = await Geolocator.requestPermission(); } catch(_) {}
       if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          setState(() => _isCompassMode = false);
          return;
       }
    }
    
    // Start listening to Position (for centering)
    final settings = const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0); 
    _positionStream?.cancel();
    _positionStream = Geolocator.getPositionStream(locationSettings: settings).listen((pos) {
       if (_isCompassMode) { 
         // Only Move Center here.
         _mapController.move(LatLng(pos.latitude, pos.longitude), _mapController.camera.zoom);
       }
    });

    // Start listening to Compass (for rotation)
    _compassStream?.cancel();
    try {
      _compassStream = FlutterCompass.events?.listen((event) {
         if (!_isCompassMode) return;
         final heading = event.heading;
         if (heading != null) {
            _currentHeading = heading;
            // Rotate map
            _mapController.rotate(-heading);
         }
      });
    } catch (e) {
      debugPrint("Compass error: $e");
    }
    
    // Initial Move if we have current position
    if (widget.currentPosition != null) {
       _mapController.move(LatLng(widget.currentPosition!.latitude, widget.currentPosition!.longitude), 16); // Zoom in for navigation
    }
  }
  
  void _disableCompassMode() {
    setState(() => _isCompassMode = false);
    _positionStream?.cancel();
    _positionStream = null;
    _compassStream?.cancel();
    _compassStream = null;
  }

  LatLng? _getTriggerPoint(List<LatLng> points, LatLng target, double triggerDist) {
    if (points.isEmpty) return null;
    
    // 1. Find the point in the path closest to the target stop
    int targetIdx = -1;
    double minTargetDist = double.infinity;
    for (int i = 0; i < points.length; i++) {
        double d = Geolocator.distanceBetween(points[i].latitude, points[i].longitude, target.latitude, target.longitude);
        if (d < minTargetDist) {
            minTargetDist = d;
            targetIdx = i;
        }
    }
    
    // If target stop not found or it's the very first point, return it
    if (targetIdx <= 0) return points[0];

    // 2. Search backwards from target stop to find where we enter the trigger zone
    for (int i = targetIdx - 1; i >= 0; i--) {
        double d = Geolocator.distanceBetween(points[i].latitude, points[i].longitude, target.latitude, target.longitude);
        if (d > triggerDist) {
            // Segment (points[i] -> points[i+1]) crosses the trigger boundary
            double dNext = Geolocator.distanceBetween(points[i+1].latitude, points[i+1].longitude, target.latitude, target.longitude);
            double totalD = d - dNext;
            if (totalD <= 0) return points[i+1];
            
            double ratio = (d - triggerDist) / totalD;
            // Clamp ratio
            ratio = ratio.clamp(0.0, 1.0);
            
            return LatLng(
                points[i].latitude + (points[i+1].latitude - points[i].latitude) * ratio,
                points[i].longitude + (points[i+1].longitude - points[i].longitude) * ratio
            );
        }
    }
    
    // 3. Fallback: if all points are inside the zone, return the start
    return points[0];
  }

  Future<void> _loadRoute() async {
    try {
      final stepsToShow = widget.focusStep != null ? [widget.focusStep!] : widget.steps;
      List<LatLng> allPoints = [];
      List<Marker> markers = [];

      final prefs = await SharedPreferences.getInstance();
      final int stopsBefore = prefs.getInt('alarm_stops_before') ?? 1;
      final String thresholdSetting = prefs.getString('alarm_trigger_threshold') ?? '5%';

      for (var step in stepsToShow) {
        List<LatLng> stepPoints = [];
        // 1. Walking Path - Prefer Motis path if available
        if (widget.focusStep != null && (step.type == 'walk' || step.isWalking) && step.startLat != null && step.endLat != null) {
           if (step.path != null && step.path!.isNotEmpty) {
             try {
               stepPoints.addAll(step.path!.map((p) => LatLng(p[0], p[1])));
             } catch(e) { debugPrint("Path mapping error: $e"); }
           } else {
             try {
               // Fallback to OSRM only if no path from Motis
               final path = await TransportApi.getWalkingRoute(step.startLat!, step.startLng!, step.endLat!, step.endLng!);
               stepPoints.addAll(path.map((p) => LatLng(p[0], p[1])));
             } catch (_) {
               stepPoints.add(LatLng(step.startLat!, step.startLng!));
               stepPoints.add(LatLng(step.endLat!, step.endLng!));
             }
           }
        } 
        // 2. Existing path (bus/train)
        else if (step.path != null && step.path!.isNotEmpty) {
          try {
             stepPoints.addAll(step.path!.map((p) => LatLng(p[0], p[1])));
          } catch(e) { debugPrint("Step path error: $e"); }
        } 
        // 3. Fallback for stopovers
        else if (step.stopovers != null && step.stopovers!.isNotEmpty) {
          if (step.startLat != null) stepPoints.add(LatLng(step.startLat!, step.startLng!));
          for (var stop in step.stopovers!) {
            if (stop['stop'] != null && stop['stop']['location'] != null) {
              stepPoints.add(LatLng(stop['stop']['location']['latitude'], stop['stop']['location']['longitude']));
            }
          }
          if (step.endLat != null) stepPoints.add(LatLng(step.endLat!, step.endLng!));
        } 
        // 4. Simple straight line fallback
        else if (step.startLat != null && step.endLat != null) {
          stepPoints.add(LatLng(step.startLat!, step.startLng!));
          stepPoints.add(LatLng(step.endLat!, step.endLng!));
        }

        allPoints.addAll(stepPoints);

        // Add Markers
        // Start Marker
        if (step.startLat != null) {
          markers.add(Marker(
              point: LatLng(step.startLat!, step.startLng!),
              width: 16, height: 16,
              child: Container(decoration: BoxDecoration(color: step.type == 'walk' ? Colors.orange : Colors.blue, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)))
          ));
        }
        // Stopover markers
        if (step.stopovers != null) {
          for (var stop in step.stopovers!) {
            if (stop['stop'] != null && stop['stop']['location'] != null) {
              markers.add(Marker(
                point: LatLng(stop['stop']['location']['latitude'], stop['stop']['location']['longitude']),
                width: 10, height: 10,
                child: Container(decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: Colors.blue, width: 2))),
              ));
            }
          }
        }

        // Trigger Marker logic
        if (step.isWakeAlarmOn) {
          double? targetLat = step.endLat;
          double? targetLng = step.endLng;
          double? originLat = step.startLat;
          double? originLng = step.startLng;

          if (step.stopovers != null && step.stopovers!.isNotEmpty) {
            final stops = step.stopovers!;
            if (stopsBefore > 0) {
              int targetIndex = stops.length - stopsBefore;
              if (targetIndex >= 0) {
                final stopData = stops[targetIndex];
                if (stopData['stop'] != null && stopData['stop']['location'] != null) {
                   targetLat = stopData['stop']['location']['latitude'];
                   targetLng = stopData['stop']['location']['longitude'];
                   if (targetIndex > 0) {
                      final originData = stops[targetIndex - 1];
                      originLat = originData['stop']?['location']?['latitude'];
                      originLng = originData['stop']?['location']?['longitude'];
                   }
                }
              }
            } else {
              // Trigger at destination, origin is the last stopover
              final originData = stops.last;
              originLat = originData['stop']?['location']?['latitude'];
              originLng = originData['stop']?['location']?['longitude'];
            }
          }

          if (targetLat != null && targetLng != null) {
            double triggerDist = 500;
            if (thresholdSetting.endsWith('m')) {
               try { triggerDist = double.parse(thresholdSetting.replaceAll('m', '')); } catch (_) {}
            } else if (originLat != null && originLng != null) {
               // Base calculations on the segment immediately preceding the target
               double segmentDist = Geolocator.distanceBetween(originLat, originLng, targetLat, targetLng);
               
               // Robust percentage parsing
               double percentValue = 5;
               try {
                 percentValue = double.parse(thresholdSetting.replaceAll('%', ''));
               } catch (_) {}
               triggerDist = segmentDist * (percentValue / 100.0);
            }

            final triggerPoint = _getTriggerPoint(stepPoints, LatLng(targetLat, targetLng), triggerDist);
            if (triggerPoint != null) {
              markers.add(Marker(
                point: triggerPoint,
                width: 32, height: 32,
                child: Container(
                  decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.8), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                  child: const Icon(Icons.notifications_active, color: Colors.white, size: 18),
                ),
              ));
            }
          }
        }
      }

      // Final Destination Marker
      if (allPoints.isNotEmpty) {
         markers.add(Marker(
           point: allPoints.last,
           width: 32, height: 32,
           alignment: Alignment.topCenter,
           child: const Icon(Icons.location_on, color: Colors.red, size: 32),
         ));
      }
      
      // User Position
      if (widget.currentPosition != null) {
        markers.add(Marker(
          point: LatLng(widget.currentPosition!.latitude, widget.currentPosition!.longitude),
          width: 32, height: 32,
          child: Container(decoration: BoxDecoration(color: Colors.blue.withOpacity(0.3), shape: BoxShape.circle), child: const Icon(Icons.my_location, color: Colors.blue, size: 16)),
        ));
      }

      // Calculate Bounds
      LatLngBounds? bounds;
      try {
        if (allPoints.isNotEmpty) {
          bounds = LatLngBounds.fromPoints(allPoints);
          // Fix: If bounds are a single point (zero area), expand them to avoid "Camera zoom must be finite" crash
          if (bounds.south == bounds.north && bounds.west == bounds.east) {
            final center = bounds.center;
            bounds = LatLngBounds(
              LatLng(center.latitude - 0.002, center.longitude - 0.002),
              LatLng(center.latitude + 0.002, center.longitude + 0.002),
            );
          }
        } else if (widget.currentPosition != null) {
           final p = LatLng(widget.currentPosition!.latitude, widget.currentPosition!.longitude);
           bounds = LatLngBounds(LatLng(p.latitude-0.01, p.longitude-0.01), LatLng(p.latitude+0.01, p.longitude+0.01));
        }
      } catch (e) {
        debugPrint("Bounds calc error: $e");
      }

      if (mounted) {
        setState(() {
          _routePoints = allPoints;
          _markers = markers;
          _bounds = bounds;
        });
      }
    } catch (e) {
      debugPrint("Error loading route: $e");
    } finally {
      if (mounted) setState(() => _isLoadingPath = false);
    }
  }

  void _openGoogleMaps() async {
    if (_routePoints.isEmpty) return;
    final start = _routePoints.first;
    final end = _routePoints.last;
    final url = Uri.parse("https://www.google.com/maps/dir/?api=1&origin=${start.latitude},${start.longitude}&destination=${end.latitude},${end.longitude}&travelmode=walking");
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingPath) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final initialCenter = _bounds?.center ?? const LatLng(51.1657, 10.4515);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.focusStep?.instruction ?? "Route Map"),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Google Maps Button (Left)
            FloatingActionButton(
              heroTag: "gmaps",
              backgroundColor: Colors.white,
              onPressed: _openGoogleMaps,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Image.asset(
                  'assets/google_maps_icon.png',
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.map, color: Colors.blue),
                ),
              ),
            ),
            
            // Right Side Buttons (Compass + Recenter)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                 // Compass Button
                 if (widget.currentPosition != null) 
                   FloatingActionButton(
                     heroTag: "compass",
                     mini: true,
                     backgroundColor: _isCompassMode ? Theme.of(context).primaryColor : Colors.white,
                     foregroundColor: _isCompassMode ? Colors.white : Colors.black,
                     onPressed: _toggleCompassMode,
                     child: CustomPaint(
                       size: const Size(24, 24),
                       painter: CompassIconPainter(color: _isCompassMode ? Colors.white : Colors.black),
                     ),
                   ),
                 if (widget.currentPosition != null) const SizedBox(height: 12),
                 const SizedBox(height: 12),
                 
                 // Recenter Button
                 FloatingActionButton(
                  heroTag: "center",
                  onPressed: () {
                    if (_isCompassMode) _disableCompassMode();
                    if (_bounds != null) {
                      _mapController.fitCamera(CameraFit.bounds(bounds: _bounds!, padding: const EdgeInsets.all(50)));
                      // Reset rotation?
                      _mapController.rotate(0);
                    }
                  },
                  child: const Icon(Icons.center_focus_strong),
                ),
              ],
            ),
          ],
        ),
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: initialCenter,
          initialZoom: 13,
          initialCameraFit: _bounds != null ? CameraFit.bounds(bounds: _bounds!, padding: const EdgeInsets.all(50)) : null,
          onPositionChanged: (pos, hasGesture) {
             if (hasGesture && _isCompassMode) {
                // User manually moved/zoomed the map, disable Compass Mode
                _disableCompassMode();
             }
          },
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.trans',
          ),
          if (_routePoints.isNotEmpty)
            PolylineLayer<Object>(
              polylines: [
                Polyline(
                  points: _routePoints,
                  strokeWidth: 5.0,
                  color: (widget.focusStep?.type == 'walk' || (widget.focusStep?.isWalking ?? false)) 
                      ? Theme.of(context).colorScheme.primary 
                      : Colors.blueAccent,
                ),
              ],
            ),
          MarkerLayer(markers: _markers),
        ],
      ),
    );
  }
}