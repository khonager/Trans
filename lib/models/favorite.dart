import 'station.dart';

class Favorite {
  final String id;
  final String label;
  final String type; // 'station' or 'friend'
  final Station? station; // If type is station
  final String? friendId; // If type is friend
  final int? iconCode; // NEW: Stores the IconData.codePoint

  Favorite({
    required this.id,
    required this.label,
    required this.type,
    this.station,
    this.friendId,
    this.iconCode,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'type': type,
        'station': station?.toJson(),
        'friendId': friendId,
        'iconCode': iconCode,
      };

  factory Favorite.fromJson(Map<String, dynamic> json) {
    final rawIconCode = json['iconCode'];
    return Favorite(
      id: json['id'].toString(),
      label: json['label']?.toString() ?? '',
      type: json['type']?.toString() ?? 'station',
      station:
          json['station'] != null ? Station.fromJson(json['station']) : null,
      friendId: json['friendId']?.toString(),
      iconCode: rawIconCode is num
          ? rawIconCode.toInt()
          : int.tryParse(rawIconCode?.toString() ?? ''),
    );
  }
}
