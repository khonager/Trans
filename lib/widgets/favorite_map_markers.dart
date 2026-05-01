import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/favorite.dart';

List<Marker> buildFavoriteMapMarkers(List<Favorite> favorites) {
  final markers = <Marker>[];

  for (final favorite in favorites) {
    final station = favorite.station;
    final latitude = station?.latitude;
    final longitude = station?.longitude;
    if (latitude == null || longitude == null) continue;

    markers.add(
      Marker(
        point: LatLng(latitude, longitude),
        width: 38,
        height: 38,
        child: Tooltip(
          message: favorite.label,
          child: _FavoriteMapMarker(favorite: favorite),
        ),
      ),
    );
  }

  return markers;
}

class _FavoriteMapMarker extends StatelessWidget {
  final Favorite favorite;

  const _FavoriteMapMarker({required this.favorite});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = _favoriteIcon(favorite);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primary,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(
        icon,
        size: 19,
        color: colorScheme.onPrimary,
      ),
    );
  }
}

IconData _favoriteIcon(Favorite favorite) {
  if (favorite.iconCode != null) {
    return IconData(favorite.iconCode!, fontFamily: 'MaterialIcons');
  }

  final label = favorite.label.trim().toLowerCase();
  if (label == 'home') return Icons.home;
  if (label == 'work') return Icons.work;

  final stationType = favorite.station?.type.trim().toLowerCase();
  if (stationType == 'address' || stationType == 'location') {
    return Icons.place_rounded;
  }

  return Icons.star_rounded;
}
