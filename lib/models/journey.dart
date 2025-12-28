class JourneyStep {
  final String type; // 'ride', 'wait', 'transfer', 'walk'
  final String line;
  final String instruction;
  final String duration;
  final String departureTime;
  final String arrivalTime;
  final bool isWalking;
  final double? startLat;
  final double? startLng;
  final double? endLat;
  final double? endLng;
  final List<dynamic>? path; // [[lat, lng], ...]
  final String? startStationId;
  final String? platform;
  final List<dynamic>? stopovers;
  final int? chatCount;
  
  // NEW: Store exact time for alternatives search
  final DateTime? dateTime;

  JourneyStep({
    required this.type,
    required this.line,
    required this.instruction,
    required this.duration,
    required this.departureTime,
    required this.arrivalTime,
    this.isWalking = false,
    this.startLat,
    this.startLng,
    this.endLat,
    this.endLng,
    this.path,
    this.startStationId,
    this.platform,
    this.stopovers,
    this.chatCount,
    this.dateTime,
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