import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:trans/models/joint_journey.dart';
import 'package:trans/models/journey.dart';

class JointJourneyPlanner {
  static List<JointJourneyOption> rank({
    required List<Journey> myJourneys,
    required List<Journey> friendJourneys,
    JointJourneyPreferences preferences =
        const JointJourneyPreferences.balanced(),
    bool isArrival = false,
    int limit = 12,
  }) {
    if (myJourneys.isEmpty || friendJourneys.isEmpty) return const [];

    final myBaseline = _soloBaseline(myJourneys, isArrival: isArrival);
    final friendBaseline = _soloBaseline(friendJourneys, isArrival: isArrival);
    // Time both would already spend together by simply taking their own best
    // route. Only what an option adds on top of that is worth a detour, which
    // is what keeps the ranking meaningful for short and long journeys alike.
    final baselineShared = _unionDuration(
      _sharedSegments(myBaseline, friendBaseline),
    );
    final baselineSharedMinutes = baselineShared.inSeconds / 60;
    final budget = math.max(0.05, preferences.detourMinutesPerSharedMinute);
    final options = <JointJourneyOption>[];

    for (final mine in myJourneys) {
      final myExtra = _extraMinutes(
        mine,
        myBaseline,
        isArrival: isArrival,
      );
      final myTransfers = math.max(
        0,
        mine.transferCount - myBaseline.transferCount,
      );
      if (myExtra > preferences.maxExtraTravelMinutes ||
          myTransfers > preferences.maxExtraTransfers) {
        continue;
      }

      for (final friend in friendJourneys) {
        final friendExtra = _extraMinutes(
          friend,
          friendBaseline,
          isArrival: isArrival,
        );
        final friendTransfers = math.max(
          0,
          friend.transferCount - friendBaseline.transferCount,
        );
        if (friendExtra > preferences.maxExtraTravelMinutes ||
            friendTransfers > preferences.maxExtraTransfers) {
          continue;
        }

        final shared = _sharedSegments(mine, friend);
        if (shared.isEmpty) continue;
        final sharedDuration = _unionDuration(shared);
        final sharedMinutes = sharedDuration.inSeconds / 60;
        if (sharedMinutes < 1) continue;

        final ride = _unionDuration(
          shared.where((segment) => segment.mode == SharedJourneyMode.ride),
        );
        final walk = _unionDuration(
          shared.where((segment) => segment.mode == SharedJourneyMode.walk),
        );
        final wait = _unionDuration(
          shared.where((segment) => segment.mode == SharedJourneyMode.wait),
        );

        // Everything both people give up, expressed in travel minutes.
        final detourMinutes = myExtra +
            friendExtra +
            (myTransfers + friendTransfers) *
                preferences.transferPenaltyMinutes;
        // A plan where one person carries the whole detour is worth less than
        // the same total split evenly.
        final unfairness =
            (myExtra - friendExtra).abs() * preferences.unfairnessPenaltyWeight;
        final gain = sharedMinutes - baselineSharedMinutes;
        final net = gain - (detourMinutes + unfairness) / budget;

        // Options that cost nothing stay in the list even when they only match
        // the baseline: they are what the pair gets for free.
        if (detourMinutes > 0 && net <= 0) continue;

        options.add(JointJourneyOption(
          myJourney: mine,
          friendJourney: friend,
          sharedSegments: shared,
          sharedDuration: sharedDuration,
          sharedRideDuration: ride,
          sharedWalkDuration: walk,
          sharedWaitDuration: wait,
          baselineSharedDuration: baselineShared,
          myExtraMinutes: myExtra,
          friendExtraMinutes: friendExtra,
          myExtraTransfers: myTransfers,
          friendExtraTransfers: friendTransfers,
          detourMinutes: detourMinutes,
          sharedGainMinutes: gain,
          netTogetherMinutes: net,
        ));
      }
    }

    options.sort((a, b) {
      final byNet = b.netTogetherMinutes.compareTo(a.netTogetherMinutes);
      if (byNet != 0) return byNet;
      final byShared = b.sharedDuration.compareTo(a.sharedDuration);
      if (byShared != 0) return byShared;
      return a.detourMinutes.compareTo(b.detourMinutes);
    });

    final deduped = <JointJourneyOption>[];
    final seen = <String>{};
    for (final option in options) {
      final key = '${_journeyKey(option.myJourney)}|'
          '${_journeyKey(option.friendJourney)}';
      if (!seen.add(key)) continue;
      deduped.add(option);
      if (deduped.length >= limit) break;
    }
    return deduped;
  }

  /// Ranks at the given window and, when that shows nothing new, keeps
  /// stretching the budget over the same journeys until it does.
  ///
  /// Nothing here touches the network: it only re-scores journeys that were
  /// already fetched. When even the widest budget cannot improve on
  /// [previousOptions], the outcome says more departures are needed.
  static JointSearchOutcome rankProgressively({
    required List<Journey> myJourneys,
    required List<Journey> friendJourneys,
    required JointSearchWindow window,
    List<JointJourneyOption> previousOptions = const [],
    bool isArrival = false,
    int limit = 12,
  }) {
    var current = window;
    var options = rank(
      myJourneys: myJourneys,
      friendJourneys: friendJourneys,
      preferences: current.preferences,
      isArrival: isArrival,
      limit: limit,
    );
    if (_improvesOn(options, previousOptions)) {
      return JointSearchOutcome(
        options: options,
        window: current,
        needsMoreDepartures: false,
      );
    }

    while (current.canWidenBudget) {
      current = current.widened();
      final widened = rank(
        myJourneys: myJourneys,
        friendJourneys: friendJourneys,
        preferences: current.preferences,
        isArrival: isArrival,
        limit: limit,
      );
      if (widened.length >= options.length) options = widened;
      if (_improvesOn(widened, previousOptions)) {
        return JointSearchOutcome(
          options: widened,
          window: current,
          needsMoreDepartures: false,
        );
      }
    }

    return JointSearchOutcome(
      options: options,
      window: current,
      needsMoreDepartures: true,
    );
  }

  /// More options, or more time together than before, counts as progress.
  static bool _improvesOn(
    List<JointJourneyOption> candidates,
    List<JointJourneyOption> previous,
  ) {
    if (candidates.isEmpty) return false;
    if (previous.isEmpty) return true;
    if (candidates.length > previous.length) return true;
    return _bestSharedSeconds(candidates) > _bestSharedSeconds(previous);
  }

  static int _bestSharedSeconds(List<JointJourneyOption> options) =>
      options.fold<int>(
        0,
        (best, option) => math.max(best, option.sharedDuration.inSeconds),
      );

  static Journey _soloBaseline(
    List<Journey> journeys, {
    required bool isArrival,
  }) {
    return journeys.reduce((best, candidate) {
      final timeComparison = isArrival
          ? best.departure.compareTo(candidate.departure)
          : candidate.arrival.compareTo(best.arrival);
      if (timeComparison < 0) return candidate;
      if (timeComparison == 0 && candidate.transferCount < best.transferCount) {
        return candidate;
      }
      if (timeComparison == 0 &&
          candidate.transferCount == best.transferCount &&
          candidate.duration < best.duration) {
        return candidate;
      }
      return best;
    });
  }

  static int _extraMinutes(
    Journey candidate,
    Journey baseline, {
    required bool isArrival,
  }) {
    final difference = isArrival
        ? baseline.departure.difference(candidate.departure)
        : candidate.arrival.difference(baseline.arrival);
    return math.max(0, difference.inMinutes);
  }

  static List<SharedJourneySegment> _sharedSegments(
    Journey mine,
    Journey friend,
  ) {
    final mySegments = _segments(mine);
    final friendSegments = _segments(friend);
    final matches = <SharedJourneySegment>[];
    for (final a in mySegments) {
      for (final b in friendSegments) {
        if (!_sameActivity(a, b)) continue;
        final start = a.start.isAfter(b.start) ? a.start : b.start;
        final end = a.end.isBefore(b.end) ? a.end : b.end;
        if (!end.isAfter(start)) continue;
        matches.add(SharedJourneySegment(
          mode: a.mode,
          start: start,
          end: end,
          label: a.label.isNotEmpty ? a.label : b.label,
        ));
      }
    }
    matches.sort((a, b) => a.start.compareTo(b.start));
    return _merge(matches);
  }

  static List<_TravelSegment> _segments(Journey journey) {
    final result = <_TravelSegment>[];
    for (var index = 0; index < journey.steps.length; index++) {
      final step = journey.steps[index];
      final start = _stepStart(step, journey, index);
      final end = _stepEnd(step, journey, index, start);
      if (start == null || end == null || !end.isAfter(start)) continue;

      if (step.type == 'ride') {
        result.add(_TravelSegment.fromStep(
          SharedJourneyMode.ride,
          start,
          end,
          step,
          identity: (step.tripId ?? '').trim(),
          label: step.line,
        ));
        continue;
      }

      final walk = step.walkDuration ??
          (step.type == 'walk' ? end.difference(start) : Duration.zero);
      final wait = step.waitDuration ??
          (step.type == 'wait' ? end.difference(start) : Duration.zero);
      var cursor = start;
      if (walk > Duration.zero) {
        final walkEnd = _minDate(end, cursor.add(walk));
        result.add(_TravelSegment.fromStep(
          SharedJourneyMode.walk,
          cursor,
          walkEnd,
          step,
          label: step.instruction,
        ));
        cursor = walkEnd;
      }
      if (wait > Duration.zero && end.isAfter(cursor)) {
        result.add(_TravelSegment.fromStep(
          SharedJourneyMode.wait,
          cursor,
          end,
          step,
          useEndLocation: true,
          label: step.destinationName ?? step.startStationName ?? '',
        ));
      }
    }
    return result;
  }

  static DateTime? _stepStart(JourneyStep step, Journey journey, int index) {
    return step.plannedDeparture ??
        step.dateTime ??
        _timeOnJourneyDate(step.departureTime, journey.departure);
  }

  static DateTime? _stepEnd(
    JourneyStep step,
    Journey journey,
    int index,
    DateTime? start,
  ) {
    if (step.plannedArrival != null) return step.plannedArrival;
    if (index + 1 < journey.steps.length) {
      final next = journey.steps[index + 1];
      final nextStart = next.plannedDeparture ?? next.dateTime;
      if (nextStart != null && (start == null || nextStart.isAfter(start))) {
        return nextStart;
      }
    }
    final parsed = _timeOnJourneyDate(step.arrivalTime, journey.departure);
    if (parsed != null && start != null && parsed.isBefore(start)) {
      return parsed.add(const Duration(days: 1));
    }
    return parsed;
  }

  static DateTime? _timeOnJourneyDate(String value, DateTime anchor) {
    final parts = value.trim().split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return DateTime(anchor.year, anchor.month, anchor.day, hour, minute);
  }

  static bool _sameActivity(_TravelSegment a, _TravelSegment b) {
    if (a.mode != b.mode) return false;
    switch (a.mode) {
      case SharedJourneyMode.ride:
        if (a.identity.isNotEmpty && b.identity.isNotEmpty) {
          return a.identity == b.identity;
        }
        return a.label.trim().toLowerCase() == b.label.trim().toLowerCase() &&
            a.label.trim().isNotEmpty &&
            _sameDirection(a, b) &&
            a.start.difference(b.start).abs() <= const Duration(minutes: 3);
      case SharedJourneyMode.walk:
        final leftPath = _coordinates(a.path);
        final rightPath = _coordinates(b.path);
        if (leftPath.length >= 2 && rightPath.length >= 2) {
          return _coordinatePathsOverlap(leftPath, rightPath);
        }
        return _sameDirection(a, b);
      case SharedJourneyMode.wait:
        return _samePlace(
          a.startId,
          a.startName,
          a.startLat,
          a.startLng,
          b.startId,
          b.startName,
          b.startLat,
          b.startLng,
        );
    }
  }

  static bool _sameDirection(_TravelSegment a, _TravelSegment b) {
    return _samePlace(
          a.startId,
          a.startName,
          a.startLat,
          a.startLng,
          b.startId,
          b.startName,
          b.startLat,
          b.startLng,
        ) &&
        _samePlace(
          a.endId,
          a.endName,
          a.endLat,
          a.endLng,
          b.endId,
          b.endName,
          b.endLat,
          b.endLng,
        );
  }

  static bool _samePlace(
    String? aId,
    String? aName,
    double? aLat,
    double? aLng,
    String? bId,
    String? bName,
    double? bLat,
    double? bLng,
  ) {
    final leftId = (aId ?? '').trim();
    final rightId = (bId ?? '').trim();
    if (leftId.isNotEmpty && rightId.isNotEmpty && leftId == rightId) {
      return true;
    }
    final leftName = (aName ?? '').trim().toLowerCase();
    final rightName = (bName ?? '').trim().toLowerCase();
    if (leftName.isNotEmpty && leftName == rightName) return true;
    if (aLat == null || aLng == null || bLat == null || bLng == null) {
      return false;
    }
    return Geolocator.distanceBetween(aLat, aLng, bLat, bLng) <= 100;
  }

  static bool _coordinatePathsOverlap(
    List<(double, double)> left,
    List<(double, double)> right,
  ) {
    var close = 0;
    for (final point in left) {
      if (right.any((other) =>
          Geolocator.distanceBetween(point.$1, point.$2, other.$1, other.$2) <=
          60)) {
        close++;
      }
    }
    return close >= 2 && close / left.length >= 0.35;
  }

  static List<(double, double)> _coordinates(List<dynamic>? path) {
    if (path == null) return const [];
    final result = <(double, double)>[];
    for (final point in path) {
      if (point is List &&
          point.length >= 2 &&
          point[0] is num &&
          point[1] is num) {
        result
            .add(((point[0] as num).toDouble(), (point[1] as num).toDouble()));
      } else if (point is Map) {
        final lat = point['latitude'] ?? point['lat'];
        final lng = point['longitude'] ?? point['lng'] ?? point['lon'];
        if (lat is num && lng is num) {
          result.add((lat.toDouble(), lng.toDouble()));
        }
      }
    }
    return result;
  }

  static List<SharedJourneySegment> _merge(
    List<SharedJourneySegment> segments,
  ) {
    if (segments.isEmpty) return const [];
    final merged = <SharedJourneySegment>[];
    for (final segment in segments) {
      if (merged.isEmpty) {
        merged.add(segment);
        continue;
      }
      final previous = merged.last;
      if (previous.mode == segment.mode &&
          !segment.start.isAfter(previous.end)) {
        merged[merged.length - 1] = SharedJourneySegment(
          mode: previous.mode,
          start: previous.start,
          end: segment.end.isAfter(previous.end) ? segment.end : previous.end,
          label: previous.label.isNotEmpty ? previous.label : segment.label,
        );
      } else {
        merged.add(segment);
      }
    }
    return merged;
  }

  static Duration _unionDuration(Iterable<SharedJourneySegment> segments) {
    final sorted = segments.toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    if (sorted.isEmpty) return Duration.zero;
    var total = Duration.zero;
    var start = sorted.first.start;
    var end = sorted.first.end;
    for (final segment in sorted.skip(1)) {
      if (!segment.start.isAfter(end)) {
        if (segment.end.isAfter(end)) end = segment.end;
      } else {
        total += end.difference(start);
        start = segment.start;
        end = segment.end;
      }
    }
    return total + end.difference(start);
  }

  static DateTime _minDate(DateTime a, DateTime b) => a.isBefore(b) ? a : b;

  static String _journeyKey(Journey journey) =>
      '${journey.departure.millisecondsSinceEpoch}-'
      '${journey.arrival.millisecondsSinceEpoch}-'
      '${journey.steps.where((step) => step.type == 'ride').map((step) => step.tripId ?? step.line).join(',')}';
}

class _TravelSegment {
  final SharedJourneyMode mode;
  final DateTime start;
  final DateTime end;
  final String identity;
  final String label;
  final String? startId;
  final String? startName;
  final double? startLat;
  final double? startLng;
  final String? endId;
  final String? endName;
  final double? endLat;
  final double? endLng;
  final List<dynamic>? path;

  const _TravelSegment({
    required this.mode,
    required this.start,
    required this.end,
    required this.identity,
    required this.label,
    this.startId,
    this.startName,
    this.startLat,
    this.startLng,
    this.endId,
    this.endName,
    this.endLat,
    this.endLng,
    this.path,
  });

  factory _TravelSegment.fromStep(
    SharedJourneyMode mode,
    DateTime start,
    DateTime end,
    JourneyStep step, {
    String identity = '',
    String label = '',
    bool useEndLocation = false,
  }) {
    return _TravelSegment(
      mode: mode,
      start: start,
      end: end,
      identity: identity,
      label: label,
      startId: useEndLocation ? step.destinationStationId : step.startStationId,
      startName: useEndLocation ? step.destinationName : step.startStationName,
      startLat: useEndLocation ? step.endLat : step.startLat,
      startLng: useEndLocation ? step.endLng : step.startLng,
      endId: step.destinationStationId,
      endName: step.destinationName,
      endLat: step.endLat,
      endLng: step.endLng,
      path: step.path,
    );
  }
}
