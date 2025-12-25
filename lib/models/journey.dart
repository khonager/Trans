class JourneyStep {
  final String type; // 'walk', 'ride', 'wait'
  final String line;
  final String instruction;
  final String duration;
  final String departureTime;
  final String arrivalTime; 
  final String? alert;
  final String? seating;
  final int? chatCount;
  final String? startStationId;
  final String? platform;

  JourneyStep({
    required this.type,
    required this.line,
    required this.instruction,
    required this.duration,
    required this.departureTime,
    required this.arrivalTime,
    this.alert,
    this.seating,
    this.chatCount,
    this.startStationId,
    this.platform,
  });
}

class RouteTab {
  final String id;
  final String title;
  final String subtitle;
  final String eta;
  final String totalDuration; // NEW: Total time
  final List<JourneyStep> steps;

  RouteTab({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.eta,
    required this.totalDuration,
    required this.steps,
  });
}