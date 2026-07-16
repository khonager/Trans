import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class FriendLocationScreen extends StatelessWidget {
  final String username;
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final DateTime? updatedAt;

  const FriendLocationScreen({
    super.key,
    required this.username,
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    this.updatedAt,
  });

  @override
  Widget build(BuildContext context) {
    final point = LatLng(latitude, longitude);
    final age = updatedAt == null
        ? null
        : DateTime.now().toUtc().difference(updatedAt!.toUtc());
    final isGerman = Localizations.localeOf(context).languageCode == 'de';
    final freshness = age == null
        ? (isGerman
            ? 'Aktualisierungszeit unbekannt'
            : 'Update time unavailable')
        : age.inMinutes < 1
            ? (isGerman ? 'Gerade aktualisiert' : 'Updated just now')
            : isGerman
                ? 'Vor ${age.inMinutes} Min. aktualisiert'
                : 'Updated ${age.inMinutes} min ago';
    return Scaffold(
      appBar: AppBar(title: Text(username)),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(initialCenter: point, initialZoom: 15),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'io.github.khonager.trans',
              ),
              if (accuracyMeters != null && accuracyMeters! > 0)
                CircleLayer(circles: [
                  CircleMarker(
                    point: point,
                    radius: accuracyMeters!,
                    useRadiusInMeter: true,
                    color: Colors.blue.withValues(alpha: 0.12),
                    borderColor: Colors.blue.withValues(alpha: 0.45),
                    borderStrokeWidth: 1,
                  ),
                ]),
              MarkerLayer(markers: [
                Marker(
                  point: point,
                  width: 64,
                  height: 64,
                  child: const Icon(Icons.location_pin,
                      size: 52, color: Colors.red),
                ),
              ]),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  '$freshness${accuracyMeters == null ? '' : ' · ±${accuracyMeters!.round()} m'}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
