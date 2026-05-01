import 'package:flutter/material.dart';

import '../models/favorite.dart';

const List<IconData> kAvailableFavoriteIcons = [
  Icons.star,
  Icons.home,
  Icons.work,
  Icons.favorite,
  Icons.train,
  Icons.directions_bus,
  Icons.school,
  Icons.person,
  Icons.location_on,
  Icons.shopping_cart,
  Icons.fitness_center,
  Icons.local_cafe,
  Icons.local_airport,
];

IconData resolveFavoriteIcon(Favorite favorite) {
  if (favorite.iconCode != null) {
    return kAvailableFavoriteIcons.firstWhere(
      (icon) => icon.codePoint == favorite.iconCode,
      orElse: () => _fallbackFavoriteIcon(favorite),
    );
  }

  return _fallbackFavoriteIcon(favorite);
}

IconData _fallbackFavoriteIcon(Favorite favorite) {
  final label = favorite.label.trim().toLowerCase();
  if (label == 'home') return Icons.home;
  if (label == 'work') return Icons.work;

  final stationType = favorite.station?.type.trim().toLowerCase();
  if (stationType == 'address' || stationType == 'location') {
    return Icons.place_rounded;
  }

  return Icons.star_rounded;
}
