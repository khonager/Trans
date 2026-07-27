import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/favorite.dart';
import '../widgets/favorite_map_markers.dart';
import '../widgets/friend_map_markers.dart';

class FriendLocationScreen extends StatelessWidget {
  final String username;
  final String? avatarEmoji;
  final dynamic themeColor;
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final DateTime? updatedAt;
  final List<dynamic> sharedFavorites;

  const FriendLocationScreen({
    super.key,
    required this.username,
    this.avatarEmoji,
    this.themeColor,
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    this.updatedAt,
    this.sharedFavorites = const [],
  });

  @override
  Widget build(BuildContext context) {
    final point = LatLng(latitude, longitude);
    final favorites = sharedFavorites
        .map((raw) {
          if (raw is! Map) return null;
          try {
            return Favorite.fromJson(Map<String, dynamic>.from(raw));
          } catch (_) {
            return null;
          }
        })
        .whereType<Favorite>()
        .toList(growable: false);
    final favoriteMarkers = buildFavoriteMapMarkers(favorites);
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
              if (favoriteMarkers.isNotEmpty)
                MarkerLayer(markers: favoriteMarkers),
              MarkerLayer(markers: [
                Marker(
                  point: point,
                  width: 50,
                  height: 50,
                  child: FriendProfileMarker(
                    username: username,
                    emoji: avatarEmoji,
                    themeColor: themeColor,
                  ),
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
