import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../models/journey.dart';
import '../config/app_theme.dart';

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

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _fitBounds();
    });
  }

  void _fitBounds() {
    List<LatLng> points = [];
    
    // Logic: If focusing on a step, we calculate bounds for that step ONLY
    // so we zoom in tight. But we will DRAW everything.
    if (widget.focusStep != null) {
      if (widget.focusStep!.startLat != null) points.add(LatLng(widget.focusStep!.startLat!, widget.focusStep!.startLng!));
      if (widget.focusStep!.endLat != null) points.add(LatLng(widget.focusStep!.endLat!, widget.focusStep!.endLng!));
      
      // Add detailed path points if available (e.g. for walk geometry)
      if (widget.focusStep!.path != null) {
        for (var p in widget.focusStep!.path!) {
          points.add(LatLng(p[0], p[1]));
        }
      }
    } else {
      // General view: include everything
      for (var s in widget.steps) {
        if (s.startLat != null) points.add(LatLng(s.startLat!, s.startLng!));
        if (s.endLat != null) points.add(LatLng(s.endLat!, s.endLng!));
        if (s.path != null) {
          for (var p in s.path!) points.add(LatLng(p[0], p[1]));
        }
      }
    }

    if (points.isEmpty) return;

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (var p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    // FIX: If points are too close (e.g. just start/end of a short walk), 
    // bounds calculation fails or looks weird. Force a minimum box.
    double latDiff = (maxLat - minLat).abs();
    double lngDiff = (maxLng - minLng).abs();

    if (latDiff < 0.002 && lngDiff < 0.002) {
      // Zoom in to the center point
      _mapController.move(LatLng(minLat, minLng), 16.0);
    } else {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng)),
          padding: const EdgeInsets.all(60), // Generous padding so line isn't at edge
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    
    List<Marker> markers = [];
    List<Polyline> polylines = [];
    
    if (widget.currentPosition != null) {
      markers.add(Marker(
        point: LatLng(widget.currentPosition!.latitude, widget.currentPosition!.longitude),
        width: 40, height: 40,
        child: Container(
          decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.3), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
          child: const Center(child: Icon(Icons.my_location, color: Colors.blue, size: 20)),
        ),
      ));
    }

    // Draw ALL steps (never hide anything)
    for (var step in widget.steps) {
      bool isWalk = step.type == 'walk';
      Color color = isWalk ? Colors.orange : Colors.indigo;
      double width = 5.0;

      // Highlight focused step visually (make it thicker/bolder), don't hide others
      if (widget.focusStep != null) {
        if (widget.focusStep != step) {
          color = color.withValues(alpha: 0.3); // Dim others
          width = 3.0;
        } else {
          width = 6.0; // Highlight focused
        }
      }

      // 1. Draw Polyline
      if (step.path != null && step.path!.isNotEmpty) {
        // Detailed geometry
        polylines.add(Polyline(
          points: step.path!.map((p) => LatLng(p[0], p[1])).toList(),
          strokeWidth: width,
          color: color,
        ));
      } else if (step.startLat != null && step.startLng != null && step.endLat != null) {
        // Fallback: Connect the dots (Start -> Stops -> End)
        List<LatLng> points = [LatLng(step.startLat!, step.startLng!)];
        
        if (step.stopovers != null) {
          for (var stop in step.stopovers!) {
            var loc = stop['stop'] != null ? stop['stop']['location'] : null;
            if (loc != null) {
              points.add(LatLng(loc['latitude'], loc['longitude']));
            }
          }
        }
        
        points.add(LatLng(step.endLat!, step.endLng!));
        
        polylines.add(Polyline(
          points: points,
          strokeWidth: width,
          color: color,
        ));
      }

      // 2. Draw Markers (Only for main points to avoid clutter)
      if (step.startLat != null) {
        markers.add(Marker(
          point: LatLng(step.startLat!, step.startLng!),
          width: 24, height: 24,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2)
            ),
            child: Icon(isWalk ? Icons.directions_walk : Icons.circle, size: 14, color: color),
          ),
        ));
      }
    }
    
    // Add final destination marker
    if (widget.steps.isNotEmpty && widget.steps.last.endLat != null) {
       markers.add(Marker(
          point: LatLng(widget.steps.last.endLat!, widget.steps.last.endLng!),
          width: 30, height: 30,
          child: const Icon(Icons.location_on, color: Colors.red, size: 30),
        ));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.focusStep != null ? "Walking Segment" : "Full Route"),
        backgroundColor: colors.appBarBg,
        foregroundColor: colors.textPrimary,
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: const MapOptions(initialCenter: LatLng(51.16, 10.45), initialZoom: 6.0),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.trans',
          ),
          PolylineLayer(polylines: polylines),
          MarkerLayer(markers: markers),
        ],
      ),
    );
  }
}