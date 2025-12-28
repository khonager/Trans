import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:trans/models/journey.dart';
import 'package:geolocator/geolocator.dart';

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
  Widget build(BuildContext context) {
    final points = <LatLng>[];
    final markers = <Marker>[];
    
    // 1. Determine Scope
    final stepsToShow = widget.focusStep != null ? [widget.focusStep!] : widget.steps;

    for (var step in stepsToShow) {
      // --- A. Build the Line (Polyline) ---
      if (step.path != null && step.path!.isNotEmpty) {
        points.addAll(step.path!.map((p) => LatLng(p[0], p[1])));
      } 
      else if (step.stopovers != null && step.stopovers!.isNotEmpty) {
        if (step.startLat != null && step.startLng != null) {
          points.add(LatLng(step.startLat!, step.startLng!));
        }
        for (var stop in step.stopovers!) {
          if (stop['stop'] != null && stop['stop']['location'] != null) {
            points.add(LatLng(
              stop['stop']['location']['latitude'], 
              stop['stop']['location']['longitude']
            ));
          }
        }
        if (step.endLat != null && step.endLng != null) {
          points.add(LatLng(step.endLat!, step.endLng!));
        }
      } 
      else if (step.startLat != null && step.startLng != null && step.endLat != null && step.endLng != null) {
        points.add(LatLng(step.startLat!, step.startLng!));
        points.add(LatLng(step.endLat!, step.endLng!));
      }
    }

    // --- B. Build Markers ---
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

    if (widget.currentPosition != null) {
      markers.add(Marker(
        point: LatLng(widget.currentPosition!.latitude, widget.currentPosition!.longitude),
        width: 40, height: 40,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.3),
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
    } else if (widget.currentPosition != null) {
      bounds = LatLngBounds(
        LatLng(widget.currentPosition!.latitude - 0.01, widget.currentPosition!.longitude - 0.01),
        LatLng(widget.currentPosition!.latitude + 0.01, widget.currentPosition!.longitude + 0.01)
      );
    }

    final initialCenter = bounds?.center ?? const LatLng(51.1657, 10.4515);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.focusStep?.instruction ?? "Route Map"),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      // NEW: Recenter Button
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (bounds != null) {
            _mapController.fitCamera(CameraFit.bounds(bounds: bounds!, padding: const EdgeInsets.all(50)));
          } else {
            _mapController.move(initialCenter, 13);
          }
        },
        child: const Icon(Icons.center_focus_strong),
      ),
      body: FlutterMap(
        mapController: _mapController, // Linked Controller
        options: MapOptions(
          initialCenter: initialCenter,
          initialZoom: 13,
          initialCameraFit: bounds != null 
            ? CameraFit.bounds(bounds: bounds!, padding: const EdgeInsets.all(50)) 
            : null,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.trans',
          ),
          if (points.isNotEmpty)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: points,
                  strokeWidth: 5.0,
                  color: Colors.blueAccent,
                  // Removed isDotted: false to fix error
                ),
              ],
            ),
          MarkerLayer(markers: markers),
        ],
      ),
    );
  }
}