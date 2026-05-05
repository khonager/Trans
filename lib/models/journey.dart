import 'package:trans/models/station.dart';

class JourneyStep {
  final String type; // 'ride', 'wait', 'transfer', 'walk', 'bike'
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
  final String? arrivalPlatform;
  final List<dynamic>? stopovers;
  final int? chatCount;

  // NEW: Store exact time for alternatives search
  final DateTime? dateTime;

  // NEW: UI refinements
  final String? startStationName;
  final String? destinationName;
  final String? headsign;
  final String? tripId; // NEW

  // Real-time data
  final int? departureDelay; // minutes
  final int? arrivalDelay; // minutes
  final bool isCancelled;
  final DateTime? plannedDeparture;
  final DateTime? plannedArrival;

  // New: Alarm state
  final bool isWakeAlarmOn;
  final double? alarmTargetLat;
  final double? alarmTargetLng;
  final double? alarmTargetOriginLat;
  final double? alarmTargetOriginLng;
  final String? alarmTargetName;

  // New: Display breakdown
  final Duration? walkDuration;
  final Duration? bikeDuration;
  final Duration? waitDuration;

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
    this.arrivalPlatform,
    this.stopovers,
    this.chatCount,
    this.dateTime,
    this.departureDelay,
    this.arrivalDelay,
    this.isCancelled = false,
    this.plannedDeparture,
    this.plannedArrival,
    this.startStationName,
    this.destinationName,
    this.headsign,
    this.tripId,
    this.isWakeAlarmOn = false,
    this.alarmTargetLat,
    this.alarmTargetLng,
    this.alarmTargetOriginLat,
    this.alarmTargetOriginLng,
    this.alarmTargetName,
    this.walkDuration,
    this.bikeDuration,
    this.waitDuration,
  });

  JourneyStep copyWith({
    String? type,
    String? line,
    String? instruction,
    String? duration,
    String? departureTime,
    String? arrivalTime,
    bool? isWalking,
    double? startLat,
    double? startLng,
    double? endLat,
    double? endLng,
    List<dynamic>? path,
    String? startStationId,
    String? platform,
    String? arrivalPlatform,
    List<dynamic>? stopovers,
    int? chatCount,
    DateTime? dateTime,
    int? departureDelay,
    int? arrivalDelay,
    bool? isCancelled,
    DateTime? plannedDeparture,
    DateTime? plannedArrival,
    String? startStationName,
    String? destinationName,
    String? headsign,
    String? tripId,
    bool? isWakeAlarmOn,
    double? alarmTargetLat,
    double? alarmTargetLng,
    double? alarmTargetOriginLat,
    double? alarmTargetOriginLng,
    String? alarmTargetName,
    bool clearAlarmTarget = false,
    Duration? walkDuration,
    Duration? bikeDuration,
    Duration? waitDuration,
  }) {
    return JourneyStep(
      type: type ?? this.type,
      line: line ?? this.line,
      instruction: instruction ?? this.instruction,
      duration: duration ?? this.duration,
      departureTime: departureTime ?? this.departureTime,
      arrivalTime: arrivalTime ?? this.arrivalTime,
      isWalking: isWalking ?? this.isWalking,
      startLat: startLat ?? this.startLat,
      startLng: startLng ?? this.startLng,
      endLat: endLat ?? this.endLat,
      endLng: endLng ?? this.endLng,
      path: path ?? this.path,
      startStationId: startStationId ?? this.startStationId,
      platform: platform ?? this.platform,
      arrivalPlatform: arrivalPlatform ?? this.arrivalPlatform,
      stopovers: stopovers ?? this.stopovers,
      chatCount: chatCount ?? this.chatCount,
      dateTime: dateTime ?? this.dateTime,
      departureDelay: departureDelay ?? this.departureDelay,
      arrivalDelay: arrivalDelay ?? this.arrivalDelay,
      isCancelled: isCancelled ?? this.isCancelled,
      plannedDeparture: plannedDeparture ?? this.plannedDeparture,
      plannedArrival: plannedArrival ?? this.plannedArrival,
      startStationName: startStationName ?? this.startStationName,
      destinationName: destinationName ?? this.destinationName,
      headsign: headsign ?? this.headsign,
      tripId: tripId ?? this.tripId,
      isWakeAlarmOn: isWakeAlarmOn ?? this.isWakeAlarmOn,
      alarmTargetLat:
          clearAlarmTarget ? null : (alarmTargetLat ?? this.alarmTargetLat),
      alarmTargetLng:
          clearAlarmTarget ? null : (alarmTargetLng ?? this.alarmTargetLng),
      alarmTargetOriginLat: clearAlarmTarget
          ? null
          : (alarmTargetOriginLat ?? this.alarmTargetOriginLat),
      alarmTargetOriginLng: clearAlarmTarget
          ? null
          : (alarmTargetOriginLng ?? this.alarmTargetOriginLng),
      alarmTargetName:
          clearAlarmTarget ? null : (alarmTargetName ?? this.alarmTargetName),
      walkDuration: walkDuration ?? this.walkDuration,
      bikeDuration: bikeDuration ?? this.bikeDuration,
      waitDuration: waitDuration ?? this.waitDuration,
    );
  }
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
  final Duration totalWalkingDuration;
  final Duration totalBikingDuration;
  final DateTime? plannedDeparture; // NEW
  final DateTime? plannedArrival; // NEW

  Journey({
    required this.steps,
    required this.departure,
    required this.arrival,
    required this.duration,
    required this.transferCount,
    required this.totalWaitTime,
    required this.rawSource,
    required this.source,
    this.totalWalkingDuration = Duration.zero,
    this.totalBikingDuration = Duration.zero,
    this.plannedDeparture,
    this.plannedArrival,
  });

  Journey copyWith({
    List<JourneyStep>? steps,
    DateTime? departure,
    DateTime? arrival,
    Duration? duration,
    int? transferCount,
    Duration? totalWaitTime,
    Map<String, dynamic>? rawSource,
    String? source,
    Duration? totalWalkingDuration,
    Duration? totalBikingDuration,
    DateTime? plannedDeparture,
    DateTime? plannedArrival,
  }) {
    return Journey(
      steps: steps ?? this.steps,
      departure: departure ?? this.departure,
      arrival: arrival ?? this.arrival,
      duration: duration ?? this.duration,
      transferCount: transferCount ?? this.transferCount,
      totalWaitTime: totalWaitTime ?? this.totalWaitTime,
      rawSource: rawSource ?? this.rawSource,
      source: source ?? this.source,
      totalWalkingDuration: totalWalkingDuration ?? this.totalWalkingDuration,
      totalBikingDuration: totalBikingDuration ?? this.totalBikingDuration,
      plannedDeparture: plannedDeparture ?? this.plannedDeparture,
      plannedArrival: plannedArrival ?? this.plannedArrival,
    );
  }

  bool get isCancelled => steps.any((s) => s.isCancelled);

  int get departureDelay =>
      steps
          .firstWhere((s) => s.type == 'ride', orElse: () => steps.first)
          .departureDelay ??
      0;

  int get arrivalDelay =>
      steps
          .lastWhere((s) => s.type == 'ride', orElse: () => steps.last)
          .arrivalDelay ??
      0;
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
      activeJourney:
          clearActiveJourney ? null : (activeJourney ?? this.activeJourney),
      isStackExpanded: isStackExpanded ?? this.isStackExpanded,
    );
  }
}
