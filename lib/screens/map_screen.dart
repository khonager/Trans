import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:trans/models/journey.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

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

  void _openGoogleMaps(double startLat, double startLng, double destLat, double destLng) async {
    // Google Maps URL with origin and destination
    final webUrl = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&origin=$startLat,$startLng'
      '&destination=$destLat,$destLng'
      '&travelmode=walking'
    );
    
    try {
      await launchUrl(webUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      // Fallback: open in browser
      await launchUrl(webUrl, mode: LaunchMode.inAppBrowserView);
    }
  }

  // Cached Google Maps icon loaded from the internet
  static final Widget _googleMapsIcon = ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: Image.network(
      'https://www.gstatic.com/images/branding/product/1x/maps_48dp.png',
      width: 28,
      height: 28,
      cacheWidth: 56, // Cache at 2x for crisp display
      cacheHeight: 56,
      errorBuilder: (context, error, stackTrace) => const Icon(Icons.map, color: Colors.green),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final points = <LatLng>[];
    final markers = <Marker>[];
    
    final stepsToShow = widget.focusStep != null ? [widget.focusStep!] : widget.steps;

    for (var step in stepsToShow) {
      // 1. PATH LINE
      if (step.path != null && step.path!.isNotEmpty) {
        points.addAll(step.path!.map((p) => LatLng(p[0], p[1])));
      } else if (step.stopovers != null && step.stopovers!.isNotEmpty) {
        if (step.startLat != null && step.startLng != null) points.add(LatLng(step.startLat!, step.startLng!));
        for (var stop in step.stopovers!) {
          if (stop['stop'] != null && stop['stop']['location'] != null) {
            points.add(LatLng(stop['stop']['location']['latitude'], stop['stop']['location']['longitude']));
          }
        }
        if (step.endLat != null && step.endLng != null) points.add(LatLng(step.endLat!, step.endLng!));
      } else if (step.startLat != null && step.startLng != null && step.endLat != null && step.endLng != null) {
        points.add(LatLng(step.startLat!, step.startLng!));
        points.add(LatLng(step.endLat!, step.endLng!));
      }

      // 2. STOP MARKERS (Small Dots for every intermediate stop)
      if (step.stopovers != null) {
        for (var stop in step.stopovers!) {
          if (stop['stop'] != null && stop['stop']['location'] != null) {
            markers.add(Marker(
              point: LatLng(stop['stop']['location']['latitude'], stop['stop']['location']['longitude']),
              width: 10, height: 10,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.8),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5)
                ),
              ),
            ));
          }
        }
      }

      // 3. TRANSFER POINTS (Larger Orange Dots)
      // We check if this step is a transfer or walk, AND we are viewing the full route
      if (widget.focusStep == null && (step.type == 'transfer' || step.type == 'walk')) {
         if (step.startLat != null && step.startLng != null) {
            markers.add(Marker(
              point: LatLng(step.startLat!, step.startLng!),
              width: 16, height: 16,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.orange,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2)
                ),
              ),
            ));
         }
      }
    }

    // 4. DESTINATION PIN (Only one at the very end)
    if (points.isNotEmpty) {
      final lastPoint = points.last;
      markers.add(Marker(
        point: lastPoint,
        width: 40, height: 40,
        child: const Icon(Icons.location_on, color: Colors.red, size: 40),
        alignment: Alignment.topCenter,
      ));
    }

    // 5. USER POSITION
    if (widget.currentPosition != null) {
      markers.add(Marker(
        point: LatLng(widget.currentPosition!.latitude, widget.currentPosition!.longitude),
        width: 40, height: 40,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.3),
            shape: BoxShape.circle
          ),
          child: const Center(child: Icon(Icons.my_location, color: Colors.blue, size: 20)),
        ),
      ));
    }

    // Bounds Calculation
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

    // Determine if this is a walking route
    final isWalkingRoute = widget.focusStep != null && 
        (widget.focusStep!.type == 'walk' || widget.focusStep!.isWalking);
    final startLat = points.isNotEmpty ? points.first.latitude : null;
    final startLng = points.isNotEmpty ? points.first.longitude : null;
    final destinationLat = points.isNotEmpty ? points.last.latitude : null;
    final destinationLng = points.isNotEmpty ? points.last.longitude : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.focusStep?.instruction ?? "Route Map"),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (isWalkingRoute && startLat != null && startLng != null && destinationLat != null && destinationLng != null)
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: FloatingActionButton(
                heroTag: 'google_maps',
                backgroundColor: Colors.white,
                onPressed: () => _openGoogleMaps(startLat, startLng, destinationLat, destinationLng),
                child: _googleMapsIcon,
              ),
            ),
          if (!isWalkingRoute || startLat == null || destinationLat == null)
            const SizedBox(), // Spacer when no left button
          FloatingActionButton(
            heroTag: 'recenter',
            onPressed: () {
              if (bounds != null) {
                _mapController.fitCamera(CameraFit.bounds(bounds: bounds!, padding: const EdgeInsets.all(50)));
              } else {
                _mapController.move(initialCenter, 13);
              }
            },
            child: const Icon(Icons.center_focus_strong),
          ),
        ],
      ),
      body: FlutterMap(
        mapController: _mapController,
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
                ),
              ],
            ),
          MarkerLayer(markers: markers),
        ],
      ),
    );
  }
}