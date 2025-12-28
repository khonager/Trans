import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:trans/models/journey.dart';
import 'package:geolocator/geolocator.dart';

class MapScreen extends StatelessWidget {
  final List<JourneyStep> steps;
  final JourneyStep? focusStep; // NEW: Only show this part if provided
  final Position? currentPosition;

  const MapScreen({
    super.key,
    required this.steps,
    this.focusStep,
    this.currentPosition,
  });

  @override
  Widget build(BuildContext context) {
    final points = <LatLng>[];
    final markers = <Marker>[];
    
    // Determine which steps to show
    final stepsToShow = focusStep != null ? [focusStep!] : steps;

    for (var step in stepsToShow) {
      if (step.path != null && step.path!.isNotEmpty) {
        // Use high-res path if available
        points.addAll(step.path!.map((p) => LatLng(p[0], p[1])));
      } else if (step.startLat != null && step.startLng != null && step.endLat != null && step.endLng != null) {
        // Fallback to straight line
        points.add(LatLng(step.startLat!, step.startLng!));
        points.add(LatLng(step.endLat!, step.endLng!));
      }

      // Add Markers
      if (step.startLat != null && step.startLng != null) {
        markers.add(Marker(
          point: LatLng(step.startLat!, step.startLng!),
          width: 40, height: 40,
          child: const Icon(Icons.circle, size: 12, color: Colors.blue),
        ));
      }
    }

    // Add current user position
    if (currentPosition != null) {
      markers.add(Marker(
        point: LatLng(currentPosition!.latitude, currentPosition!.longitude),
        width: 40, height: 40,
        child: const Icon(Icons.my_location, color: Colors.blue, size: 24),
      ));
    }

    // Calculate Bounds
    LatLngBounds? bounds;
    if (points.isNotEmpty) {
      bounds = LatLngBounds.fromPoints(points);
    } else if (currentPosition != null) {
      bounds = LatLngBounds(
        LatLng(currentPosition!.latitude - 0.01, currentPosition!.longitude - 0.01),
        LatLng(currentPosition!.latitude + 0.01, currentPosition!.longitude + 0.01)
      );
    }

    // Default center if nothing else
    final initialCenter = bounds?.center ?? const LatLng(51.1657, 10.4515); // Germany center

    return Scaffold(
      appBar: AppBar(title: Text(focusStep?.instruction ?? "Route Map")),
      body: FlutterMap(
        options: MapOptions(
          initialCenter: initialCenter,
          initialZoom: 13,
          initialCameraFit: bounds != null 
            ? CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)) 
            : null,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.trans',
          ),
          PolylineLayer(
            polylines: [
              Polyline(
                points: points,
                strokeWidth: 4.0,
                color: Colors.blue,
              ),
            ],
          ),
          MarkerLayer(markers: markers),
        ],
      ),
    );
  }
}