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
      if (widget.focusStep != null && 
          widget.focusStep!.startLat != null && 
          widget.focusStep!.endLat != null) {
        
        final centerLat = (widget.focusStep!.startLat! + widget.focusStep!.endLat!) / 2;
        final centerLng = (widget.focusStep!.startLng! + widget.focusStep!.endLng!) / 2;
        _mapController.move(LatLng(centerLat, centerLng), 15);
      } else if (widget.steps.isNotEmpty) {
        double sumLat = 0;
        double sumLng = 0;
        int count = 0;
        for(var s in widget.steps) {
          if(s.startLat != null) { sumLat += s.startLat!; sumLng += s.startLng!; count++; }
          if(s.endLat != null) { sumLat += s.endLat!; sumLng += s.endLng!; count++; }
        }
        if(count > 0) {
          _mapController.move(LatLng(sumLat/count, sumLng/count), 12);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    
    // 1. Build Markers
    List<Marker> markers = [];
    
    if (widget.currentPosition != null) {
      markers.add(
        Marker(
          point: LatLng(widget.currentPosition!.latitude, widget.currentPosition!.longitude),
          width: 40,
          height: 40,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.3),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Center(
              child: Icon(Icons.my_location, color: Colors.blue, size: 20),
            ),
          ),
        ),
      );
    }

    for (var step in widget.steps) {
      if (step.startLat != null && step.startLng != null) {
        markers.add(Marker(
          point: LatLng(step.startLat!, step.startLng!),
          width: 30,
          height: 30,
          child: Icon(
            step.type == 'walk' ? Icons.directions_walk : Icons.circle, 
            color: step.type == 'walk' ? Colors.orange : Colors.indigo,
            size: step.type == 'walk' ? 20 : 12,
          ),
        ));
      }
    }

    // 2. Build Polylines
    List<Polyline> polylines = [];
    
    for (var step in widget.steps) {
      if (step.startLat != null && step.startLng != null && step.endLat != null && step.endLng != null) {
        final isFocus = widget.focusStep == step;
        
        polylines.add(Polyline(
          points: [
            LatLng(step.startLat!, step.startLng!),
            LatLng(step.endLat!, step.endLng!),
          ],
          strokeWidth: isFocus ? 6.0 : 4.0,
          // Walking = Orange, Ride = Indigo
          color: step.type == 'walk' 
              ? (isFocus ? Colors.orange : Colors.orange.withValues(alpha: 0.7))
              : (isFocus ? Colors.indigo : Colors.indigo.withValues(alpha: 0.7)),
        ));
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.focusStep != null ? "Walking Directions" : "Route Overview"),
        backgroundColor: colors.appBarBg,
        foregroundColor: colors.textPrimary,
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: const MapOptions(
          initialCenter: LatLng(51.1657, 10.4515), 
          initialZoom: 6.0,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.trans',
          ),
          PolylineLayer(polylines: polylines),
          MarkerLayer(markers: markers),
          
          if (widget.focusStep != null && widget.focusStep!.isWalking)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.all(20),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.cardBg.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(blurRadius: 10, color: Colors.black.withValues(alpha: 0.1))]
                ),
                child: Text(
                  "Displaying straight line direction.\nFollow local street signs.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
              ),
            )
        ],
      ),
    );
  }
}