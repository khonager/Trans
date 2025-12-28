class JourneyStep {
  final String type; // 'ride', 'walk', 'wait', 'transfer'
  final String line;
  final String instruction;
  final String duration;
  final String departureTime;
  final String arrivalTime;
  final bool isWalking;
  final String? platform;
  final String? startStationId;
  final List<dynamic>? stopovers;
  final int? chatCount;

  // New fields for Map
  final double? startLat;
  final double? startLng;
  final double? endLat;
  final double? endLng;

  JourneyStep({
    required this.type,
    required this.line,
    required this.instruction,
    required this.duration,
    required this.departureTime,
    required this.arrivalTime,
    this.isWalking = false,
    this.platform,
    this.startStationId,
    this.stopovers,
    this.chatCount,
    this.startLat,
    this.startLng,
    this.endLat,
    this.endLng,
  });
}

class RouteTab {
  final String id;
  final String title;
  final String subtitle;
  final String eta;
  final String totalDuration;
  final String destinationId;
  final List<JourneyStep> steps;

  RouteTab({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.eta,
    required this.totalDuration,
    required this.destinationId,
    required this.steps,
  });
}