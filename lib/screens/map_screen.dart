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
    
    // If focused, only look at that step's geometry
    if (widget.focusStep != null) {
      // Add start/end
      if (widget.focusStep!.startLat != null) points.add(LatLng(widget.focusStep!.startLat!, widget.focusStep!.startLng!));
      if (widget.focusStep!.endLat != null) points.add(LatLng(widget.focusStep!.endLat!, widget.focusStep!.endLng!));
      
      // Add detailed path points if available
      if (widget.focusStep!.path != null) {
        for (var p in widget.focusStep!.path!) {
          points.add(LatLng(p[0], p[1]));
        }
      }
    } else {
      // Add all points from all steps
      for (var s in widget.steps) {
        if (s.startLat != null) points.add(LatLng(s.startLat!, s.startLng!));
        if (s.endLat != null) points.add(LatLng(s.endLat!, s.endLng!));
        if (s.path != null) {
          for (var p in s.path!) {
            points.add(LatLng(p[0], p[1]));
          }
        }
      }
    }

    if (points.isNotEmpty) {
      // Calculate bounds manually to ensure LatLngBounds works with any version
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
    
    // 1. Build Markers & Polylines
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

    for (var step in widget.steps) {
      // Only draw if we are showing all, or this is the focused step
      if (widget.focusStep != null && widget.focusStep != step) continue;

      // Draw Path
      if (step.path != null && step.path!.isNotEmpty) {
        List<LatLng> linePoints = step.path!.map((p) => LatLng(p[0], p[1])).toList();
        polylines.add(Polyline(
          points: linePoints,
          strokeWidth: 5.0,
          color: step.type == 'walk' ? Colors.orange : Colors.indigo,
        ));
      } else if (step.startLat != null && step.startLng != null && step.endLat != null) {
        // Fallback to straight line
        polylines.add(Polyline(
          points: [LatLng(step.startLat!, step.startLng!), LatLng(step.endLat!, step.endLng!)],
          strokeWidth: 4.0,
          color: step.type == 'walk' ? Colors.orange.withValues(alpha: 0.5) : Colors.indigo.withValues(alpha: 0.5),
        ));
      }

      // Draw Stop Markers (Small dots for intermediate stops)
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

      // Draw Main Station Markers
      if (step.startLat != null) {
        markers.add(Marker(
          point: LatLng(step.startLat!, step.startLng!),
          width: 30, height: 30,
          child: Icon(step.type == 'walk' ? Icons.directions_walk : Icons.circle, color: step.type == 'walk' ? Colors.orange : Colors.indigo, size: 18),
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
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.trans'),
          PolylineLayer(polylines: polylines),
          MarkerLayer(markers: markers),
        ],
      ),
    );
  }
}