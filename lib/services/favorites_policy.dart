import '../models/favorite.dart';

const String kSupportedFavoriteType = 'station';

bool isSupportedFavorite(Favorite favorite) {
  return favorite.type == kSupportedFavoriteType;
}

List<Favorite> sanitizeFavorites(Iterable<Favorite> favorites) {
  return favorites.where(isSupportedFavorite).toList(growable: false);
}

List<Map<String, dynamic>> sanitizeFavoritePayloads(
  Iterable<dynamic> favorites,
) {
  final sanitized = <Map<String, dynamic>>[];

  for (final favorite in favorites) {
    if (favorite is! Map) continue;

    final normalized = Map<String, dynamic>.from(favorite);
    if (normalized['type'] != kSupportedFavoriteType) continue;

    normalized.remove('friendId');
    sanitized.add(normalized);
  }

  return sanitized;
}
