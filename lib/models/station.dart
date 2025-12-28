class Station {
  final String id;
  final String name;
  final String type; // 'station', 'stop', 'address', 'location'
  final double? distance;
  final double? latitude;
  final double? longitude;

  Station({
    required this.id,
    required this.name,
    this.type = 'station',
    this.distance,
    this.latitude,
    this.longitude,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'distance': distance,
    'latitude': latitude,
    'longitude': longitude,
  };

  factory Station.fromJson(Map<String, dynamic> json) {
    String name = json['name'] ?? 'Unknown';
    String id = json['id']?.toString() ?? '';
    String type = json['type'] ?? 'station';
    
    // Address handling
    if (json['address'] != null) {
      name = json['address'];
      type = 'address';
    }

    double? lat;
    double? lng;

    if (json['location'] != null) {
      final loc = json['location'];
      lat = loc['latitude'];
      lng = loc['longitude'];
      // Prefer ID from location if available
      if (loc['id'] != null) id = loc['id'].toString();
    } else {
      lat = json['latitude'];
      lng = json['longitude'];
    }

    // Fallback for addresses without IDs: Use coordinates as ID
    if (id.isEmpty && lat != null && lng != null) {
      id = "$lat,$lng";
    }

    return Station(
      id: id,
      name: name,
      type: type,
      distance: json['distance'] != null ? (json['distance'] as num).toDouble() : null,
      latitude: lat,
      longitude: lng,
    );
  }
}