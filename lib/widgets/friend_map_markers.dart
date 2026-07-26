import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

Color friendThemeColor(dynamic value) {
  if (value is int) return Color(value);
  if (value is num) return Color(value.toInt());

  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return Colors.indigo;
  final normalized = raw
      .replaceFirst('#', '')
      .replaceFirst(RegExp(r'^0x', caseSensitive: false), '');
  final parsed = int.tryParse(normalized, radix: 16);
  if (parsed == null) return Colors.indigo;
  return Color(normalized.length <= 6 ? 0xFF000000 | parsed : parsed);
}

List<Marker> buildFriendMapMarkers(
  Iterable<Map<String, dynamic>> friends,
) {
  return friends
      .map((friend) {
        final latitude = friend['latitude'];
        final longitude = friend['longitude'];
        if (latitude is! num || longitude is! num) return null;

        final username = friend['username']?.toString() ?? 'Friend';
        return Marker(
          point: LatLng(latitude.toDouble(), longitude.toDouble()),
          width: 46,
          height: 46,
          child: Tooltip(
            message: username,
            child: FriendProfileMarker(
              username: username,
              emoji: friend['avatar_emoji']?.toString(),
              themeColor: friend['theme_color'],
            ),
          ),
        );
      })
      .whereType<Marker>()
      .toList(growable: false);
}

class FriendProfileMarker extends StatelessWidget {
  final String username;
  final String? emoji;
  final dynamic themeColor;
  final double diameter;

  const FriendProfileMarker({
    super.key,
    required this.username,
    this.emoji,
    this.themeColor,
    this.diameter = 42,
  });

  @override
  Widget build(BuildContext context) {
    final trimmedEmoji = emoji?.trim() ?? '';
    final initial =
        username.trim().isEmpty ? '?' : username.trim()[0].toUpperCase();
    final color = friendThemeColor(themeColor);
    final foreground =
        color.computeLuminance() > 0.55 ? Colors.black : Colors.white;

    return Container(
      width: diameter,
      height: diameter,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        trimmedEmoji.isNotEmpty ? trimmedEmoji : initial,
        style: TextStyle(
          color: foreground,
          fontSize: trimmedEmoji.isNotEmpty ? diameter * 0.5 : diameter * 0.42,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}
