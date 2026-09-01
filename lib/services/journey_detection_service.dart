import 'dart:math' as math;

import '../models/journey.dart';

/// Where a candidate journey came from.
///
/// This is what the app knows about the user's intent before any GPS is
/// involved: a journey they opened is a far better guess than one of twenty
/// search results that happens to pass the same street.
enum JourneyDetectionSource {
  /// The journey the user opened and is looking at.
  selected,

  /// Opened earlier and kept as an alternative in a tab.
  opened,

  /// A saved connection, whether or not a tab is open for it.
  saved,

  /// One of many results of a search that is still on screen.
  searchResult,
}

extension JourneyDetectionSourceWeight on JourneyDetectionSource {
  /// Scales the evidence a candidate collects. A search result needs stronger
  /// proof to win, because the user never said they meant to take it.
  double get confidenceWeight => switch (this) {
        JourneyDetectionSource.selected => 1,
        JourneyDetectionSource.opened => 0.92,
        JourneyDetectionSource.saved => 0.9,
        JourneyDetectionSource.searchResult => 0.8,
      };
}

/// A journey the user could plausibly be travelling on.
///
/// Journeys that belong to somebody else — a companion's half of a joint plan,
/// a route a friend sent — are never turned into candidates, so they can never
/// be detected or published as the user's own presence.
class JourneyDetectionCandidate {
  final String key;
  final Journey journey;
  final JourneyDetectionSource source;

  /// Where the journey ends, for the presence payload. Kept on the candidate
  /// so detection does not depend on a tab still being open.
  final String destinationName;

  /// The tab this came from, when it came from one.
  final String? tabId;

  const JourneyDetectionCandidate({
    required this.key,
    required this.journey,
    required this.source,
    required this.destinationName,
    this.tabId,
  });
}

class JourneyDetectionMatch {
  final JourneyDetectionCandidate candidate;

  /// How well position and time fit, before the source is taken into account.
  final double evidence;

  final double score;
  final double progress;
  final JourneyStep? currentRide;

  const JourneyDetectionMatch({
    required this.candidate,
    required this.evidence,
    required this.score,
    required this.progress,
    required this.currentRide,
  });

  Journey get journey => candidate.journey;
  String get key => candidate.key;
  JourneyDetectionSource get source => candidate.source;
  String get destinationName => candidate.destinationName;
  String? get tabId => candidate.tabId;
}

class JourneyDetectionService {
  static const Duration monitoringWindow = Duration(minutes: 7);
  static const Duration arrivalGrace = Duration(minutes: 12);
  static const double activationScore = 0.62;
  static const double requiredScoreMargin = 0.08;

  static bool isInMonitoringWindow(Journey journey, DateTime now) {
    return now.isAfter(journey.departure.subtract(monitoringWindow)) &&
        now.isBefore(journey.arrival.add(arrivalGrace));
  }

  static List<JourneyDetectionMatch> rankCandidates({
    required Iterable<JourneyDetectionCandidate> candidates,
    required DateTime now,
    required double latitude,
    required double longitude,
  }) {
    final matches = <JourneyDetectionMatch>[];
    for (final candidate in candidates) {
      final journey = candidate.journey;
      if (!isInMonitoringWindow(journey, now) || journey.isCancelled) continue;

      final points = _journeyPoints(journey);
      if (points.isEmpty) continue;
      var nearestMeters = double.infinity;
      var nearestIndex = 0;
      for (var i = 0; i < points.length; i++) {
        final distance = _distanceMeters(
          latitude,
          longitude,
          points[i].$1,
          points[i].$2,
        );
        if (distance < nearestMeters) {
          nearestMeters = distance;
          nearestIndex = i;
        }
      }

      final spatialScore = (1 - nearestMeters / 900).clamp(0.0, 1.0);
      final departureDistance =
          now.difference(journey.departure).inSeconds.abs() / 60.0;
      final temporalScore = (1 - departureDistance / 30).clamp(0.0, 1.0);
      final inJourneyTime = now.isAfter(journey.departure) &&
          now.isBefore(journey.arrival.add(const Duration(minutes: 3)));
      final timeProgress = _timeProgress(journey, now);
      final spatialProgress = points.length <= 1
          ? timeProgress
          : nearestIndex / (points.length - 1);
      final progress =
          (spatialProgress * 0.65 + timeProgress * 0.35).clamp(0.0, 1.0);
      final evidence = (spatialScore * 0.68 +
              temporalScore * 0.22 +
              (inJourneyTime ? 0.10 : 0.0))
          .clamp(0.0, 1.0);

      matches.add(JourneyDetectionMatch(
        candidate: candidate,
        evidence: evidence,
        score: evidence * candidate.source.confidenceWeight,
        progress: progress,
        currentRide: currentRideFor(journey, now),
      ));
    }
    matches.sort((a, b) => b.score.compareTo(a.score));
    return matches;
  }

  static bool isConfident(List<JourneyDetectionMatch> ranked) {
    if (ranked.isEmpty || ranked.first.score < activationScore) return false;
    if (ranked.length == 1) return true;
    return ranked.first.score - ranked[1].score >= requiredScoreMargin;
  }

  static JourneyStep? currentRideFor(Journey journey, DateTime now) {
    final rides = journey.steps.where((step) => step.type == 'ride').toList();
    for (final step in rides) {
      final departure = step.dateTime ?? step.plannedDeparture;
      final arrival = step.plannedArrival;
      if (departure != null &&
          arrival != null &&
          !now.isBefore(departure) &&
          !now.isAfter(arrival)) {
        return step;
      }
    }
    if (rides.isEmpty) return null;
    return rides.reduce((best, step) {
      final bestTime = best.dateTime ?? best.plannedDeparture;
      final stepTime = step.dateTime ?? step.plannedDeparture;
      if (bestTime == null) return step;
      if (stepTime == null) return best;
      return (now.difference(stepTime).inSeconds.abs() <
              now.difference(bestTime).inSeconds.abs())
          ? step
          : best;
    });
  }

  static List<Map<String, dynamic>> sanitizedItinerary(Journey journey) {
    return journey.steps
        .where((step) => step.type != 'walk' && step.type != 'bike')
        .map((step) => <String, dynamic>{
              'type': step.type,
              'line': step.line,
              'from': step.startStationName ?? step.departureStopLabel,
              'to': step.destinationName ?? step.arrivalStopLabel,
              'departure': step.departureTime,
              'arrival': step.arrivalTime,
              if (step.platform != null) 'platform': step.platform,
            })
        .toList();
  }

  static String progressLabel(JourneyDetectionMatch match) {
    final ride = match.currentRide;
    if (ride == null) return '${(match.progress * 100).round()}%';
    final from = ride.startStationName ?? ride.departureStopLabel;
    final to = ride.destinationName ?? ride.arrivalStopLabel;
    if (from != null && to != null) return '$from → $to';
    return ride.line.isEmpty ? '${(match.progress * 100).round()}%' : ride.line;
  }

  static double _timeProgress(Journey journey, DateTime now) {
    final total = journey.arrival.difference(journey.departure).inSeconds;
    if (total <= 0) return 0;
    return (now.difference(journey.departure).inSeconds / total)
        .clamp(0.0, 1.0);
  }

  static List<(double, double)> _journeyPoints(Journey journey) {
    final points = <(double, double)>[];
    for (final step in journey.steps) {
      if (step.startLat != null && step.startLng != null) {
        points.add((step.startLat!, step.startLng!));
      }
      if (step.path != null) {
        for (final raw in step.path!) {
          if (raw is List &&
              raw.length >= 2 &&
              raw[0] is num &&
              raw[1] is num) {
            points
                .add(((raw[0] as num).toDouble(), (raw[1] as num).toDouble()));
          }
        }
      }
      for (final stopover in step.stopovers ?? const <dynamic>[]) {
        if (stopover is! Map) continue;
        final stop = stopover['stop'];
        final location = stop is Map ? stop['location'] : null;
        final latitude = location is Map ? location['latitude'] : null;
        final longitude = location is Map ? location['longitude'] : null;
        if (latitude is num && longitude is num) {
          points.add((latitude.toDouble(), longitude.toDouble()));
        }
      }
      if (step.endLat != null && step.endLng != null) {
        points.add((step.endLat!, step.endLng!));
      }
    }
    return points;
  }

  static double _distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0;
    final p1 = lat1 * math.pi / 180;
    final p2 = lat2 * math.pi / 180;
    final dp = (lat2 - lat1) * math.pi / 180;
    final dl = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dp / 2) * math.sin(dp / 2) +
        math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}
