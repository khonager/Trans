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
    // Default to the root ID, but check if it's usable
    String id = json['id']?.toString() ?? '';
    double? lat;
    double? lng;

    if (json['location'] != null) {
      final loc = json['location'];
      name = loc['name'] ?? name;
      lat = loc['latitude'];
      lng = loc['longitude'];
      
      // FIX: Always prefer the ID inside 'location' if available, 
      // as the root ID can sometimes be an internal artifact (e.g. "0000008")
      if (loc['id'] != null) {
        id = loc['id'].toString();
      }
    } else {
      lat = json['latitude'];
      lng = json['longitude'];
    }

    return Station(
      id: id,
      name: name,
      distance: json['distance'] != null ? (json['distance'] as num).toDouble() : null,
      latitude: lat,
      longitude: lng,
    );
  }
}