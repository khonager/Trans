class Station {
  final String id;
  final String name;
  final String type; // 'station', 'stop', 'address', 'location'
  final double? distance;
  final double? latitude;
  final double? longitude;
  final String? city;
  final String? region;
  final String? country;
  final String? postalCode;
  final String? category;
  final double? searchScore;
  final double? searchImportance;

  Station({
    required this.id,
    required this.name,
    this.type = 'station',
    this.distance,
    this.latitude,
    this.longitude,
    this.city,
    this.region,
    this.country,
    this.postalCode,
    this.category,
    this.searchScore,
    this.searchImportance,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'distance': distance,
        'latitude': latitude,
        'longitude': longitude,
        'city': city,
        'region': region,
        'country': country,
        'postalCode': postalCode,
        'category': category,
        'score': searchScore,
        'importance': searchImportance,
      };

  factory Station.fromJson(Map<String, dynamic> json) {
    String name = json['name'] ?? 'Unknown';
    String id = json['id']?.toString() ?? '';
    String type = json['type'] ?? 'station';
    String? city = _stringOrNull(json['city']);
    String? region =
        _stringOrNull(json['region']) ?? _stringOrNull(json['state']);
    String? country = _stringOrNull(json['country']);
    String? postalCode =
        _stringOrNull(json['postalCode']) ?? _stringOrNull(json['zip']);
    String? category = _stringOrNull(json['category']);
    final searchScore = (json['score'] as num?)?.toDouble();
    final searchImportance = (json['importance'] as num?)?.toDouble();

    // Address handling
    if (json['address'] != null) {
      final address = json['address'];
      if (address is String) {
        name = address;
        type = 'address';
      } else if (address is Map<String, dynamic>) {
        name = _firstNonEmptyString([
              address['name'],
              address['street'],
              address['label'],
              name,
            ]) ??
            name;
        type = 'address';
        city ??= _firstNonEmptyString([
          address['city'],
          address['town'],
          address['village'],
          address['municipality'],
          address['county'],
        ]);
        region ??= _firstNonEmptyString([address['state'], address['region']]);
        country ??=
            _firstNonEmptyString([address['countryCode'], address['country']]);
        postalCode ??=
            _firstNonEmptyString([address['postcode'], address['zip']]);
      }
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

    city ??= _cityFromName(name);

    return Station(
      id: id,
      name: name,
      type: type,
      distance: json['distance'] != null
          ? (json['distance'] as num).toDouble()
          : null,
      latitude: lat,
      longitude: lng,
      city: city,
      region: region,
      country: country,
      postalCode: postalCode,
      category: category,
      searchScore: searchScore,
      searchImportance: searchImportance,
    );
  }

  /// Parse from MOTIS geocode response format
  /// MOTIS uses: { type: "STOP"|"ADDRESS"|"PLACE", name, id, lat, lon }
  factory Station.fromMotis(Map<String, dynamic> json) {
    String type = 'station';
    final motisType = json['type'] as String?;
    if (motisType == 'ADDRESS') type = 'address';
    if (motisType == 'PLACE') type = 'location';
    if (motisType == 'STOP') type = 'stop';

    String id = json['id']?.toString() ?? '';
    final lat = (json['lat'] as num?)?.toDouble();
    final lon = (json['lon'] as num?)?.toDouble();
    final searchScore = (json['score'] as num?)?.toDouble();
    final searchImportance = (json['importance'] as num?)?.toDouble();

    // Fallback ID from coordinates
    if (id.isEmpty && lat != null && lon != null) {
      id = '$lat,$lon';
    }

    final areas =
        (json['areas'] as List?)?.whereType<Map<String, dynamic>>().toList() ??
            const <Map<String, dynamic>>[];
    final defaultArea = areas.cast<Map<String, dynamic>?>().firstWhere(
          (area) => area?['default'] == true,
          orElse: () => null,
        );
    final cityArea = areas.cast<Map<String, dynamic>?>().firstWhere(
          (area) =>
              area != null &&
              area['name'] != null &&
              ((area['adminLevel'] as num?)?.toInt() ?? 0) >= 8,
          orElse: () => null,
        );
    final regionArea = areas.cast<Map<String, dynamic>?>().firstWhere(
      (area) {
        final level = (area?['adminLevel'] as num?)?.toInt() ?? 0;
        return area != null && area['name'] != null && level >= 4 && level <= 6;
      },
      orElse: () => null,
    );

    final city = _firstNonEmptyString([
      defaultArea?['name'],
      cityArea?['name'],
      _cityFromName(json['name']),
    ]);

    return Station(
      id: id,
      name: json['name'] ?? 'Unknown',
      type: type,
      latitude: lat,
      longitude: lon,
      city: city,
      region: _firstNonEmptyString([regionArea?['name']]),
      country: _stringOrNull(json['country']),
      postalCode: _stringOrNull(json['zip']),
      category: _stringOrNull(json['category']),
      searchScore: searchScore,
      searchImportance: searchImportance,
    );
  }

  String get cityGroupLabel =>
      _firstNonEmptyString([city, _cityFromName(name), country, 'Other'])!;

  String? get locationSummary {
    final parts = <String>[];
    if (city != null && city!.trim().isNotEmpty) parts.add(city!.trim());
    if (region != null &&
        region!.trim().isNotEmpty &&
        !parts.contains(region!.trim())) {
      parts.add(region!.trim());
    }
    if (country != null &&
        country!.trim().isNotEmpty &&
        !parts.contains(country!.trim())) {
      parts.add(country!.trim());
    }
    if (postalCode != null &&
        postalCode!.trim().isNotEmpty &&
        !parts.contains(postalCode!.trim())) {
      parts.add(postalCode!.trim());
    }
    if (parts.isEmpty) return null;
    return parts.join(' • ');
  }
}

String? _stringOrNull(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

String? _firstNonEmptyString(List<dynamic> values) {
  for (final value in values) {
    final text = _stringOrNull(value);
    if (text != null) return text;
  }
  return null;
}

String? _cityFromName(String? name) {
  final text = _stringOrNull(name);
  if (text == null || !text.contains(',')) return null;
  final parts = text
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.length < 2) return null;
  return parts.last;
}
