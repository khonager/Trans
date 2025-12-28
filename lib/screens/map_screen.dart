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
    // Delay slightly to ensure map is ready
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _fitBounds();
    });
  }

  void _fitBounds() {
    List<LatLng> points = [];
    
    // Logic: Gather all points we want to see
    if (widget.focusStep != null) {
      // 1. Focus Mode: Only show this specific leg
      if (widget.focusStep!.startLat != null) points.add(LatLng(widget.focusStep!.startLat!, widget.focusStep!.startLng!));
      if (widget.focusStep!.endLat != null) points.add(LatLng(widget.focusStep!.endLat!, widget.focusStep!.endLng!));
      
      if (widget.focusStep!.path != null) {
        for (var p in widget.focusStep!.path!) {
          points.add(LatLng(p[0], p[1]));
        }
      }
    } else {
      // 2. Overview Mode: Show everything
      for (var s in widget.steps) {
        if (s.startLat != null) points.add(LatLng(s.startLat!, s.startLng!));
        if (s.endLat != null) points.add(LatLng(s.endLat!, s.endLng!));
        if (s.path != null) {
          for (var p in s.path!) points.add(LatLng(p[0], p[1]));
        }
      }
    }

    if (points.isEmpty) return;

    // FIX: Robust Bounds Calculation
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

    // FIX: Check if bounds are too small (single point)
    double latDiff = (maxLat - minLat).abs();
    double lngDiff = (maxLng - minLng).abs();

    if (latDiff < 0.001 && lngDiff < 0.001) {
      // Points are virtually the same place -> Just center on them
      _mapController.move(LatLng(minLat, minLng), 16.0);
    } else {
      // Valid bounds -> Fit camera
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng)),
          padding: const EdgeInsets.all(50),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    
    List<Marker> markers = [];
    List<Polyline> polylines = [];
    
    // User Location Marker
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

    for (var step in widget.steps) {
      // If we are focusing on one step, skip the others
      if (widget.focusStep != null && widget.focusStep != step) continue;

      List<LatLng> linePoints = [];

      // 1. Try Actual Geometry (Path)
      if (step.path != null && step.path!.isNotEmpty) {
        linePoints = step.path!.map((p) => LatLng(p[0], p[1])).toList();
      } 
      // 2. Fallback: Connect the dots (Start -> Stopover 1 -> Stopover 2 -> End)
      else if (step.startLat != null && step.startLng != null && step.endLat != null) {
        linePoints.add(LatLng(step.startLat!, step.startLng!));
        
        if (step.stopovers != null) {
          for (var stop in step.stopovers!) {
            var loc = stop['stop'] != null ? stop['stop']['location'] : null;
            if (loc != null) {
              linePoints.add(LatLng(loc['latitude'], loc['longitude']));
            }
          }
        }
        
        linePoints.add(LatLng(step.endLat!, step.endLng!));
      }

      if (linePoints.isNotEmpty) {
        polylines.add(Polyline(
          points: linePoints,
          strokeWidth: 5.0,
          color: step.type == 'walk' ? Colors.orange : Colors.indigo,
        ));
      }

      // Draw Intermediate Stops (Small gray dots)
      if (step.stopovers != null) {
        for (var stop in step.stopovers!) {
          var loc = stop['stop'] != null ? stop['stop']['location'] : null;
          if (loc != null) {
            markers.add(Marker(
              point: LatLng(loc['latitude'], loc['longitude']),
              width: 8, height: 8,
              child: Container(decoration: const BoxDecoration(color: Colors.grey, shape: BoxShape.circle)),
            ));
          }
        }
      }

      // Draw Main Station Markers (Big circles)
      if (step.startLat != null) {
        markers.add(Marker(
          point: LatLng(step.startLat!, step.startLng!),
          width: 30, height: 30,
          child: Icon(
            step.type == 'walk' ? Icons.directions_walk : Icons.circle, 
            color: step.type == 'walk' ? Colors.orange : Colors.indigo, 
            size: 18
          ),
        ));
      }
      
      // Draw Destination Marker (if this is the last step or focused)
      if (step.endLat != null && (widget.focusStep == step || widget.steps.last == step)) {
         markers.add(Marker(
          point: LatLng(step.endLat!, step.endLng!),
          width: 30, height: 30,
          child: const Icon(Icons.location_on, color: Colors.red, size: 24),
        ));
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.focusStep != null ? "Step Details" : "Route Map"),
        backgroundColor: colors.appBarBg,
        foregroundColor: colors.textPrimary,
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: const MapOptions(initialCenter: LatLng(51.16, 10.45), initialZoom: 6.0),
        children: [
          TileLayer(
            // Use a standard OSM tile server
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.trans',
          ),
          PolylineLayer(polylines: polylines),
          MarkerLayer(markers: markers),
          
          // Disclaimer
          Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.all(4.0),
              child: Text("© OpenStreetMap contributors", style: TextStyle(fontSize: 10, color: Colors.black.withValues(alpha: 0.5))),
            ),
          ),
        ],
      ),
    );
  }
}