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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fitBounds();
    });
  }

  void _fitBounds() {
    List<LatLng> points = [];

    // Add current position
    if (widget.currentPosition != null) {
      points.add(LatLng(widget.currentPosition!.latitude, widget.currentPosition!.longitude));
    }

    if (widget.focusStep != null) {
      // Focus only on the specific step
      final s = widget.focusStep!;
      if (s.startLat != null && s.startLng != null) points.add(LatLng(s.startLat!, s.startLng!));
      if (s.endLat != null && s.endLng != null) points.add(LatLng(s.endLat!, s.endLng!));
      if (s.path != null) {
        points.addAll(s.path!.map((p) => LatLng(p[0], p[1])));
      }
    } else {
      // Show full route
      for (var s in widget.steps) {
        if (s.startLat != null && s.startLng != null) points.add(LatLng(s.startLat!, s.startLng!));
        if (s.endLat != null && s.endLng != null) points.add(LatLng(s.endLat!, s.endLng!));
        if (s.path != null) {
          points.addAll(s.path!.map((p) => LatLng(p[0], p[1])));
        }
      }
    }

    if (points.isEmpty) return;
    
    // Add some padding by creating a bounds object
    if (points.length == 1) {
       _mapController.move(points.first, 15);
    } else {
       final bounds = LatLngBounds.fromPoints(points);
       _mapController.fitCamera(
         CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50))
       );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);

    // Build polylines
    List<Polyline> polylines = [];
    
    // If focusing on a single step, dim the others
    for (var s in widget.steps) {
      if (s.path == null || s.path!.isEmpty) continue;
      
      final points = s.path!.map((p) => LatLng(p[0], p[1])).toList();
      final isFocused = widget.focusStep == null || widget.focusStep == s;
      
      Color color;
      double strokeWidth = 4.0;

      if (s.type == 'walk' || s.type == 'transfer') {
        // Walking: Grey or Lighter color
        color = isFocused ? Colors.grey : Colors.grey.withValues(alpha: 0.3);
        if (!isFocused) color = Colors.grey.withValues(alpha: 0.1); 
        strokeWidth = 3.0; // Slightly thinner for walking
      } else {
        // Ride: Blue or Primary color
        color = isFocused ? Colors.blue : Colors.blue.withValues(alpha: 0.3);
      }
      
      polylines.add(Polyline(
        points: points,
        strokeWidth: strokeWidth,
        color: color,
        // isDotted removed as it is no longer supported in v6+
      ));
    }

    // Build markers
    List<Marker> markers = [];
    
    // Current Location Marker
    if (widget.currentPosition != null) {
      markers.add(Marker(
        point: LatLng(widget.currentPosition!.latitude, widget.currentPosition!.longitude),
        width: 40,
        height: 40,
        child: const Icon(Icons.my_location, color: Colors.blue, size: 24),
      ));
    }

    // Start/End Markers for steps
    for (var s in widget.steps) {
       final isFocused = widget.focusStep == null || widget.focusStep == s;
       if (!isFocused) continue;

       if (s.startLat != null && s.startLng != null) {
         markers.add(Marker(
           point: LatLng(s.startLat!, s.startLng!),
           width: 30,
           height: 30,
           child: Container(
             decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(blurRadius: 2, color: Colors.black26)]),
             child: const Icon(Icons.circle, color: Colors.black, size: 14),
           ),
         ));
       }
       // Only add end marker if it's the very last step or the focused step
       if (s == widget.steps.last || isFocused) {
         if (s.endLat != null && s.endLng != null) {
           markers.add(Marker(
             point: LatLng(s.endLat!, s.endLng!),
             width: 30,
             height: 30,
             child: const Icon(Icons.location_on, color: Colors.red, size: 30),
           ));
         }
       }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.focusStep?.instruction ?? "Route Map"),
        backgroundColor: colors.cardBg,
        foregroundColor: colors.textPrimary,
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: const MapOptions(
          initialCenter: LatLng(51.1657, 10.4515), // Center of Germany default
          initialZoom: 6.0,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.trans',
          ),
          PolylineLayer(polylines: polylines),
          MarkerLayer(markers: markers),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _fitBounds,
        child: const Icon(Icons.center_focus_strong),
      ),
    );
  }
}