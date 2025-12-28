import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:trans/models/journey.dart';
import 'package:geolocator/geolocator.dart';

class MapScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final points = <LatLng>[];
    final markers = <Marker>[];
    
    // 1. Determine Scope
    // If focusStep is provided, we only look at that single step.
    // Otherwise, we show the whole route.
    final stepsToShow = focusStep != null ? [focusStep!] : steps;

    for (var step in stepsToShow) {
      // --- A. Build the Line (Polyline) ---
      
      // Option 1: High-res decoded path from API (Best)
      if (step.path != null && step.path!.isNotEmpty) {
        points.addAll(step.path!.map((p) => LatLng(p[0], p[1])));
      } 
      // Option 2: Connect the dots between stopovers (Better than straight line)
      else if (step.stopovers != null && step.stopovers!.isNotEmpty) {
        // Add start point
        if (step.startLat != null && step.startLng != null) {
          points.add(LatLng(step.startLat!, step.startLng!));
        }
        
        // Add all intermediate stops
        for (var stop in step.stopovers!) {
          if (stop['stop'] != null && stop['stop']['location'] != null) {
            points.add(LatLng(
              stop['stop']['location']['latitude'], 
              stop['stop']['location']['longitude']
            ));
          }
        }
        
        // Add end point
        if (step.endLat != null && step.endLng != null) {
          points.add(LatLng(step.endLat!, step.endLng!));
        }
      } 
      // Option 3: Straight line start to end (Fallback)
      else if (step.startLat != null && step.startLng != null && step.endLat != null && step.endLng != null) {
        points.add(LatLng(step.startLat!, step.startLng!));
        points.add(LatLng(step.endLat!, step.endLng!));
      }
    }

    // --- B. Build Markers ---

    // 1. Start Marker (Green Flag) - Location of first step
    if (stepsToShow.isNotEmpty) {
      final first = stepsToShow.first;
      if (first.startLat != null && first.startLng != null) {
        markers.add(Marker(
          point: LatLng(first.startLat!, first.startLng!),
          width: 40, height: 40,
          child: const Icon(Icons.flag, color: Colors.green, size: 32),
          alignment: Alignment.topCenter,
        ));
      }
    }

    // 2. Destination Marker (Red Pin) - Location of last step
    if (stepsToShow.isNotEmpty) {
      final last = stepsToShow.last;
      if (last.endLat != null && last.endLng != null) {
        markers.add(Marker(
          point: LatLng(last.endLat!, last.endLng!),
          width: 40, height: 40,
          child: const Icon(Icons.location_on, color: Colors.red, size: 36),
          alignment: Alignment.topCenter,
        ));
      }
    }

    // 3. User Position (Blue Dot)
    if (currentPosition != null) {
      markers.add(Marker(
        point: LatLng(currentPosition!.latitude, currentPosition!.longitude),
        width: 40, height: 40,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.3),
            shape: BoxShape.circle
          ),
          child: const Center(
            child: Icon(Icons.my_location, color: Colors.blue, size: 20),
          ),
        ),
      ));
    }

    // --- C. Camera Bounds ---
    LatLngBounds? bounds;
    if (points.isNotEmpty) {
      bounds = LatLngBounds.fromPoints(points);
    } else if (currentPosition != null) {
      // Fallback bounds around user if no route points
      bounds = LatLngBounds(
        LatLng(currentPosition!.latitude - 0.01, currentPosition!.longitude - 0.01),
        LatLng(currentPosition!.latitude + 0.01, currentPosition!.longitude + 0.01)
      );
    }

    // Default center (Germany)
    final initialCenter = bounds?.center ?? const LatLng(51.1657, 10.4515);

    return Scaffold(
      appBar: AppBar(
        title: Text(focusStep?.instruction ?? "Route Map"),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
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
          // Draw the path
          if (points.isNotEmpty)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: points,
                  strokeWidth: 5.0,
                  color: Colors.blueAccent,
                  isDotted: false,
                ),
              ],
            ),
          // Draw markers on top
          MarkerLayer(markers: markers),
        ],
      ),
    );
  }
}