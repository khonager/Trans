import 'package:trans/models/station.dart';

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
  
  // NEW: UI refinements
  final String? destinationName;
  final String? headsign;
  final String? tripId; // NEW

  // Real-time data
  final int? departureDelay; // minutes
  final int? arrivalDelay;   // minutes
  final bool isCancelled;
  final DateTime? plannedDeparture;
  final DateTime? plannedArrival;

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
    this.departureDelay,
    this.arrivalDelay,
    this.isCancelled = false,
    this.plannedDeparture,
    this.plannedArrival,
    this.destinationName,
    this.headsign,
    this.tripId,
  });
}


class Journey {
  final List<JourneyStep> steps;
  final DateTime departure;
  final DateTime arrival;
  final Duration duration;
  final int transferCount;
  final Duration totalWaitTime;
  final Map<String, dynamic> rawSource;
  final String source; // 'motis', 'v6'

  Journey({
    required this.steps,
    required this.departure,
    required this.arrival,
    required this.duration,
    required this.transferCount,
    required this.totalWaitTime,
    required this.rawSource,
    required this.source,
  });

  bool get isCancelled => steps.any((s) => s.isCancelled);
  
  int get departureDelay => steps
      .firstWhere((s) => s.type == 'ride', orElse: () => steps.first)
      .departureDelay ?? 0;
      
  int get arrivalDelay => steps
      .lastWhere((s) => s.type == 'ride', orElse: () => steps.last)
      .arrivalDelay ?? 0;
}

class RouteTab {
  final String id;
  final String title;
  final String subtitle;
  final String eta;
  final String totalDuration;
  final Station destination;
  final Station? origin; // NEW: Store origin station for pagination context
  final List<JourneyStep> steps; // Kept for legacy/active view
  final String? source;
  
  // NEW: Multiple candidates (Search Results)
  final List<Journey>? candidates;
  // NEW: Manually opened journeys (The Stack)
  final List<Journey> stack; 
  // NEW: Currently selected journey (if any)
  final Journey? activeJourney;
  // NEW: State for expanding/collapsing the secondary row
  final bool isStackExpanded;

  RouteTab({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.eta,
    required this.totalDuration,
    required this.destination,
    this.origin,
    required this.steps,
    this.source,
    this.candidates,
    this.stack = const [], 
    this.activeJourney,
    this.isStackExpanded = true, // Default open
  });
  
  RouteTab copyWith({
    String? id,
    String? title,
    String? subtitle,
    String? eta,
    String? totalDuration,
    Station? destination,
    Station? origin,
    List<JourneyStep>? steps,
    String? source,
    List<Journey>? candidates,
    List<Journey>? stack,
    Journey? activeJourney,
    bool clearActiveJourney = false,
    bool? isStackExpanded,
  }) {
    return RouteTab(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      eta: eta ?? this.eta,
      totalDuration: totalDuration ?? this.totalDuration,
      destination: destination ?? this.destination,
      origin: origin ?? this.origin,
      steps: steps ?? this.steps,
      source: source ?? this.source,
      candidates: candidates ?? this.candidates,
      stack: stack ?? this.stack,
      activeJourney: clearActiveJourney ? null : (activeJourney ?? this.activeJourney),
      isStackExpanded: isStackExpanded ?? this.isStackExpanded,
    );
  }
}