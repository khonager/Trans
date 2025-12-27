import 'package:flutter/material.dart';
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
    return Favorite(
      id: json['id'],
      label: json['label'],
      type: json['type'],
      station: json['station'] != null ? Station.fromJson(json['station']) : null,
      friendId: json['friendId'],
      iconCode: json['iconCode'],
    );
  }
}