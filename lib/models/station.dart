class Station {
  final String id;
  final String name;
  final double? distance;
  final double? latitude;
  final double? longitude;

  Station({
    required this.id,
    required this.name,
    this.distance,
    this.latitude,
    this.longitude,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'distance': distance,
    'latitude': latitude,
    'longitude': longitude,
  };

  factory Station.fromJson(Map<String, dynamic> json) {
    String name = json['name'] ?? 'Unknown Station';
    double? lat;
    double? lng;

    if (json['location'] != null) {
      name = json['location']['name'] ?? name;
      lat = json['location']['latitude'];
      lng = json['location']['longitude'];
    } else {
      lat = json['latitude'];
      lng = json['longitude'];
    }

    return Station(
      id: json['id']?.toString() ?? '',
      name: name,
      distance: json['distance'] != null ? (json['distance'] as num).toDouble() : null,
      latitude: lat,
      longitude: lng,
    );
  }
}