import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:trans/models/station.dart';
import 'package:trans/models/journey.dart';
import 'package:trans/models/joint_journey.dart';
import 'package:trans/models/joint_plan_friend.dart';
import 'package:trans/models/favorite.dart';
import 'package:trans/services/joint_journey_planner.dart';
import 'package:trans/services/transport_api.dart';
import 'package:trans/services/community_safety_service.dart';
import 'package:trans/services/supabase_service.dart';
import 'package:trans/services/history_manager.dart';
import 'package:trans/services/favorites_manager.dart';
import 'package:trans/services/favorites_policy.dart';
import 'package:trans/services/journey_detection_service.dart';
import 'package:trans/services/notification_manager.dart';
import 'package:trans/services/foreground_haptics.dart';
import 'package:trans/services/wake_alarm_preview_player.dart';
import 'package:trans/services/wake_alarm_settings.dart';
import 'package:trans/utils/favorite_icons.dart';
import 'package:trans/widgets/chat_sheet.dart';
import 'package:trans/widgets/joint_friend_chips.dart';
import 'package:trans/widgets/stop_departures_sheet.dart';
import 'package:trans/widgets/running_border.dart';
import 'package:trans/config/app_theme.dart';
import 'package:trans/utils/app_error.dart';
import 'package:trans/utils/format_utils.dart';
import '../../l10n/app_localizations.dart';
import '../map_screen.dart';
import '../joint_route_results_screen.dart';
import 'route_results_view.dart';

// A route detail refresh needs enough of a window to find the selected
// service again, including when the provider returns nearby alternatives
// first. This is only used for explicit/visible detail refreshes.
const int _activeJourneyRefreshWindowSize = 20;
const int _routeLoadMoreResultCount = 30;
const int _routeLoadEarlierResultCount = 16;

/// Departures fetched per person for one "look further" step. Deliberately
/// small: two people means two requests per press.
const int _jointExpansionResultCount = 12;
const String _routeSortOrderPreferenceKey = 'route_results_sort_order';

/// Returns the stable saved identity when a journey originated from storage.
/// Provider payloads and realtime times are only used for journeys which have
/// not yet been associated with a persisted saved entry.
@visibleForTesting
String savedJourneyConnectionKeyFor({
  required Journey journey,
  required Station from,
  required Station to,
}) {
  return journey.savedConnectionKey ??
      SearchHistoryManager.buildSavedJourneyConnectionKey(
        from: from,
        to: to,
        departure: journey.plannedDeparture ?? journey.departure,
        arrival: journey.plannedArrival ?? journey.arrival,
        journeyData: journey.rawSource,
      );
}

enum RouteHistoryView { frequent, recent }

class _RouteSearchDefaults {
  final int minTransferTimeMinutes;
  final int additionalTransferTimeMinutes;
  final double transferTimeFactor;
  final double pedestrianSpeedKmh;
  final int maxWalkingTimeMinutes;

  const _RouteSearchDefaults({
    required this.minTransferTimeMinutes,
    required this.additionalTransferTimeMinutes,
    required this.transferTimeFactor,
    required this.pedestrianSpeedKmh,
    required this.maxWalkingTimeMinutes,
  });
}

class _JointRouteContext {
  final List<JointJourneyOption> options;

  /// Null when the companion's start was typed in rather than picked from a
  /// friend who shares a location, which is the only case that can be shared
  /// back into a chat.
  final String? friendId;
  final String friendName;
  final String destinationName;
  final JointSearchWindow window;

  // Everything needed to look further without asking the user again.
  final Station myOrigin;
  final Station friendOrigin;
  final Station destination;
  final RouteSearchSettings searchSettings;
  final List<Journey> myJourneys;
  final List<Journey> friendJourneys;
  final bool isExpanding;

  /// True once neither a wider budget nor more departures can add anything.
  final bool exhausted;

  const _JointRouteContext({
    required this.options,
    required this.friendId,
    required this.friendName,
    required this.destinationName,
    required this.window,
    required this.myOrigin,
    required this.friendOrigin,
    required this.destination,
    required this.searchSettings,
    required this.myJourneys,
    required this.friendJourneys,
    this.isExpanding = false,
    this.exhausted = false,
  });

  bool get canExpand => !exhausted && window.canExpand;

  _JointRouteContext copyWith({
    List<JointJourneyOption>? options,
    JointSearchWindow? window,
    List<Journey>? myJourneys,
    List<Journey>? friendJourneys,
    bool? isExpanding,
    bool? exhausted,
  }) {
    return _JointRouteContext(
      options: options ?? this.options,
      friendId: friendId,
      friendName: friendName,
      destinationName: destinationName,
      window: window ?? this.window,
      myOrigin: myOrigin,
      friendOrigin: friendOrigin,
      destination: destination,
      searchSettings: searchSettings,
      myJourneys: myJourneys ?? this.myJourneys,
      friendJourneys: friendJourneys ?? this.friendJourneys,
      isExpanding: isExpanding ?? this.isExpanding,
      exhausted: exhausted ?? this.exhausted,
    );
  }
}

/// Identity of a journey inside a candidate key, exposed for tests that build
/// the same keys the detection suppression list uses.
@visibleForTesting
String journeyListKeyForTesting(Journey journey) => _journeyListKey(journey);

/// The journeys the app may consider the user to be travelling on.
///
/// Tabs holding somebody else's route — a companion's half of a joint plan, a
/// route a friend sent — are skipped outright, so a foreign journey can never
/// be detected or published as the user's own presence. What is left is sorted
/// by how much it says about intent: the journey the user opened beats one they
/// merely have in a result list.
///
/// The same journey can sit in several places; it is kept once, under its
/// strongest source, so duplicates cannot split the confidence between them.
@visibleForTesting
List<JourneyDetectionCandidate> journeyDetectionCandidates({
  required Iterable<RouteTab> tabs,
  Iterable<JourneyDetectionCandidate> savedCandidates = const [],
  Set<String> suppressedKeys = const <String>{},
}) {
  final byJourney = <String, JourneyDetectionCandidate>{};

  void offer(JourneyDetectionCandidate candidate) {
    if (suppressedKeys.contains(candidate.key)) return;
    final journeyKey = _journeyListKey(candidate.journey);
    final existing = byJourney[journeyKey];
    if (existing != null &&
        existing.source.confidenceWeight >= candidate.source.confidenceWeight) {
      return;
    }
    byJourney[journeyKey] = candidate;
  }

  for (final tab in tabs) {
    if (tab.isCompanionRoute) continue;
    final destinationName = tab.destination.name;

    JourneyDetectionCandidate build(
      Journey journey,
      JourneyDetectionSource source,
    ) =>
        JourneyDetectionCandidate(
          key: '${tab.id}:${_journeyListKey(journey)}',
          journey: journey,
          source: source,
          destinationName: destinationName,
          tabId: tab.id,
        );

    final active = tab.activeJourney;
    if (active != null) {
      offer(build(active, JourneyDetectionSource.selected));
    }
    for (final journey in tab.stack) {
      offer(build(journey, JourneyDetectionSource.opened));
    }
    for (final journey in tab.candidates ?? const <Journey>[]) {
      offer(build(journey, JourneyDetectionSource.searchResult));
    }
  }

  for (final candidate in savedCandidates) {
    offer(candidate);
  }

  return byJourney.values.toList();
}

/// Saved connections as detection candidates, so a journey the user saved is
/// recognised even when no tab is open for it.
@visibleForTesting
List<JourneyDetectionCandidate> savedJourneyDetectionCandidates(
  List<Map<String, dynamic>> savedJourneys,
  Journey? Function(Map<String, dynamic> rawJourney, String destinationName)
      rehydrate,
) {
  final candidates = <JourneyDetectionCandidate>[];
  for (final entry in savedJourneys) {
    final rawJourney = entry['journey'];
    final destination = entry['to'];
    if (rawJourney is! Map || destination is! Map) continue;
    final destinationName = destination['name']?.toString();
    if (destinationName == null || destinationName.isEmpty) continue;

    final journey = rehydrate(
      Map<String, dynamic>.from(rawJourney),
      destinationName,
    );
    if (journey == null) continue;

    final connectionKey = entry['connectionKey']?.toString();
    candidates.add(JourneyDetectionCandidate(
      key: 'saved:${connectionKey ?? _journeyListKey(journey)}',
      journey: journey,
      source: JourneyDetectionSource.saved,
      destinationName: destinationName,
    ));
  }
  return candidates;
}

/// Whether the search button can start a search with the inputs at hand.
///
/// Planning together needs one extra piece of information — where the
/// companion starts — and that is the only thing joint mode adds to the
/// regular requirements.
@visibleForTesting
bool canStartRouteSearch({
  required bool hasOrigin,
  required bool hasDestination,
  required bool jointPlanningEnabled,
  required bool hasCompanionOrigin,
}) {
  if (!hasOrigin || !hasDestination) return false;
  return !jointPlanningEnabled || hasCompanionOrigin;
}

@visibleForTesting
({int leadMinutes, int waitMinutes}) savedJourneyReminderOptionFromWait(
  int reminderMinutes,
) {
  return (leadMinutes: reminderMinutes, waitMinutes: reminderMinutes);
}

@visibleForTesting
String formatRideLineWithPlatform(String line, String? platform) {
  final normalizedLine = _stripInlineRidePlatformText(line.trim());
  final normalizedPlatform = platform?.trim();
  if (normalizedLine.isEmpty ||
      normalizedPlatform == null ||
      normalizedPlatform.isEmpty) {
    return normalizedLine;
  }

  if (normalizedLine.contains('(Pl.') || normalizedLine.contains('(Gl.')) {
    return normalizedLine;
  }

  final isNumericPlatform = int.tryParse(normalizedPlatform) != null;
  final formattedPlatform = isNumericPlatform
      ? '${_lineLooksRailForPlatformLabel(normalizedLine) ? 'Gl.' : 'Pl.'} $normalizedPlatform'
      : normalizedPlatform;
  return '$normalizedLine ($formattedPlatform)';
}

@visibleForTesting
String formatRealtimeDelay(int minutes) {
  final sign = minutes > 0 ? '+' : (minutes < 0 ? '-' : '');
  final absoluteMinutes = minutes.abs();
  if (absoluteMinutes < 60) return '$sign$absoluteMinutes min';

  final hours = absoluteMinutes ~/ 60;
  final remainingMinutes = absoluteMinutes % 60;
  return remainingMinutes == 0
      ? '$sign${hours}h'
      : '$sign${hours}h ${remainingMinutes}min';
}

@visibleForTesting
int realtimeChangedSuffixStart(String plannedTime, String actualTime) {
  final limit = min(plannedTime.length, actualTime.length);
  var index = 0;
  while (index < limit && plannedTime[index] == actualTime[index]) {
    index++;
  }
  return index;
}

bool _lineLooksRailForPlatformLabel(String line) {
  final normalized = line.trim().toUpperCase();
  if (normalized.isEmpty) return false;
  const railPrefixes = ['ICE', 'ECE', 'IC', 'EC', 'RE', 'RB', 'IR'];
  for (final prefix in railPrefixes) {
    if (!normalized.startsWith(prefix)) continue;
    if (normalized.length == prefix.length) return true;
    final next = normalized[prefix.length];
    return next == ' ' || int.tryParse(next) != null;
  }
  if (!normalized.startsWith('S')) return false;
  if (normalized.length == 1) return true;
  final next = normalized[1];
  return next == ' ' || int.tryParse(next) != null;
}

final RegExp _embeddedNumericParenthesesPattern = RegExp(r'\s*\(\d+\)');
final RegExp _embeddedPlatformParenthesesPattern = RegExp(
  r'\s*\((?:pl\.|gl\.|gleis|gleise|steig|bahnsteig|bussteig|bussteige|bstg\.?|platz)\s+[^)]+\)',
  caseSensitive: false,
);

String _stripInlineRidePlatformText(String value) {
  return value
      .replaceAll(_embeddedPlatformParenthesesPattern, '')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();
}

IconData _rideModeIconForLine(String line) {
  return _lineLooksRailForPlatformLabel(line)
      ? Icons.train_outlined
      : Icons.directions_bus_filled_rounded;
}

bool _shouldDisplayTripId(String? tripId) {
  final normalizedTripId = tripId?.trim();
  if (normalizedTripId == null || normalizedTripId.isEmpty) return false;
  if (normalizedTripId.length > 10) return false;
  if (normalizedTripId.contains('_') ||
      normalizedTripId.contains(':') ||
      normalizedTripId.contains(' ') ||
      normalizedTripId.toLowerCase().contains('de-delfi')) {
    return false;
  }
  if (!RegExp(r'^[A-Za-z0-9-]+$').hasMatch(normalizedTripId)) {
    return false;
  }
  return RegExp(r'\d').hasMatch(normalizedTripId);
}

@visibleForTesting
String formatRideDisplayLine({
  required String line,
  String? platform,
  String? arrivalPlatform,
  String? tripId,
  required bool showTrainNumbers,
}) {
  String baseLine = _stripInlineRidePlatformText(line.trim());
  final normalizedTripId = tripId?.trim();
  final displayableTripId =
      _shouldDisplayTripId(normalizedTripId) ? normalizedTripId : null;
  if (!showTrainNumbers) {
    baseLine =
        baseLine.replaceAll(_embeddedNumericParenthesesPattern, '').trim();

    if (normalizedTripId != null && normalizedTripId.isNotEmpty) {
      final escapedTripId = RegExp.escape(normalizedTripId);
      baseLine = baseLine
          .replaceAll(RegExp(r'\s*\(\s*' + escapedTripId + r'\s*\)'), '')
          .replaceAll(RegExp(r'\b' + escapedTripId + r'\b'), '')
          .replaceAll(RegExp(r'\s{2,}'), ' ')
          .trim();
    }
  }

  baseLine = _stripInlineRidePlatformText(baseLine);
  final effectivePlatform = platform?.trim();
  final displayLine = formatRideLineWithPlatform(baseLine, effectivePlatform);

  if (showTrainNumbers &&
      displayableTripId != null &&
      !displayLine.contains(displayableTripId)) {
    return '$displayLine ($displayableTripId)';
  }

  return displayLine;
}

String? _normalizeStopDetailLabel(String? label, {String? stationName}) {
  final normalized = label?.trim();
  if (normalized == null || normalized.isEmpty) return null;
  final station = stationName?.trim();
  if (station != null &&
      station.isNotEmpty &&
      normalized.toLowerCase() == station.toLowerCase()) {
    return null;
  }
  if (_looksLikeOpaqueStopCode(normalized)) {
    return null;
  }
  return normalized;
}

String _normalizeStationIdentityName(String name) {
  return name
      .trim()
      .toLowerCase()
      // Transit feeds commonly use these two forms interchangeably, including
      // between a ride's destination and the following ride's origin.
      .replaceAll('hauptbahnhof', 'hbf')
      .replaceAll(RegExp(r'[^a-z0-9äöüß]+'), '');
}

bool _sameTransitStation(
  String? leftId,
  String? leftName,
  String? rightId,
  String? rightName,
) {
  final aId = leftId?.trim();
  final bId = rightId?.trim();
  if (aId != null && aId.isNotEmpty && bId != null && bId.isNotEmpty) {
    if (aId == bId) return true;
  }

  final aName = leftName?.trim();
  final bName = rightName?.trim();
  if (aName == null || aName.isEmpty || bName == null || bName.isEmpty) {
    return false;
  }
  return _normalizeStationIdentityName(aName) ==
      _normalizeStationIdentityName(bName);
}

@visibleForTesting
bool sameTransitStationForTesting(
  String? leftId,
  String? leftName,
  String? rightId,
  String? rightName,
) =>
    _sameTransitStation(leftId, leftName, rightId, rightName);

bool _looksLikeOpaqueStopCode(String label) {
  final lower = label.toLowerCase();
  const userFacingKeywords = <String>[
    'gleis',
    'bahnsteig',
    'bussteig',
    'bussteige',
    'tramsteig',
    'haltestelle',
    'steig',
    'bstg',
    'pos.',
    'position',
    'platform',
    'stop',
  ];
  if (userFacingKeywords.any(lower.contains)) return false;

  final compact = label.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  if (compact.isEmpty) return true;

  final hasDigit = RegExp(r'\d').hasMatch(compact);
  final hasLower = RegExp(r'[a-z]').hasMatch(compact);
  final hasUpper = RegExp(r'[A-Z]').hasMatch(compact);

  if (!hasDigit &&
      compact.length <= 16 &&
      (RegExp(r'^[NSEWV][A-Z][A-Za-z]+$').hasMatch(compact) ||
          RegExp(r'^[A-Z]{2,}[A-Za-z]{0,8}$').hasMatch(compact) ||
          (hasUpper && !hasLower))) {
    return true;
  }

  return false;
}

String _cleanStopDetailLabel(String label) {
  final trimmed = label.trim();
  final match = RegExp(
    r'^(.*?\b(?:platz|steig|bussteig|bussteige|bahnsteig|haltestelle|bstg\.?)\s+[A-Za-z0-9]+)(?:\s+[A-Z]{2,}.*)$',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (match != null) {
    return match.group(1)!.trim();
  }
  return trimmed;
}

bool _matchesSimpleStopLabel(
  String lowerStopLabel,
  String lowerPlatform,
  List<String> prefixes,
) {
  for (final prefix in prefixes) {
    if (lowerStopLabel == '$prefix $lowerPlatform') return true;
  }
  return false;
}

/// Matches a label that names several tracks at once ("Gleis1/11", "Gleis 24-25").
final RegExp _multiTrackLabelPattern = RegExp(r'\d+\s*[/&+-]\s*\d+');

/// True when the only platform we have is a whole platform area: the label
/// names several tracks and the feed pinned the trip to one of them, so the
/// number is not trustworthy.
bool platformLooksLikeTrackArea(String? platform, String? stopLabel) {
  final normalizedPlatform = platform?.trim();
  if (normalizedPlatform == null || normalizedPlatform.isEmpty) return false;
  final label = stopLabel?.trim();
  if (label == null || !_multiTrackLabelPattern.hasMatch(label)) return false;
  return RegExp(r'[A-Za-z0-9]+')
      .allMatches(label)
      .map((match) => match.group(0)!.toLowerCase())
      .contains(normalizedPlatform.toLowerCase());
}

String? _extractStopDetailCode(String label, {required bool isRail}) {
  final normalized = label.trim();
  if (normalized.isEmpty) return null;

  final typeKeywords = isRail
      ? '(?:gleis|schiene|platform|track)'
      : '(?:bussteig|bussteige|steig|platz|haltestelle|bstg\\.?)';

  // Keep every track of a combined platform area instead of silently picking
  // the first one, which would name a track the trip does not use.
  final multiTrack = RegExp(
    '\\b$typeKeywords\\s*([A-Za-z0-9]+(?:\\s*[/&+-]\\s*[A-Za-z0-9]+)+)',
    caseSensitive: false,
  ).firstMatch(normalized);
  if (multiTrack != null) {
    return multiTrack
        .group(1)!
        .replaceAllMapped(RegExp(r'\s*([/&+-])\s*'), (m) => m.group(1)!);
  }

  final afterType = RegExp(
    '\\b$typeKeywords\\s*([A-Za-z0-9]+)\\b',
    caseSensitive: false,
  ).firstMatch(normalized);
  if (afterType != null) return afterType.group(1);

  final beforeType = RegExp(
    '\\b([A-Za-z0-9]+)\\s*[•/-]?\\s*$typeKeywords\\b',
    caseSensitive: false,
  ).firstMatch(normalized);
  if (beforeType != null) return beforeType.group(1);

  return null;
}

@visibleForTesting
String? combinePlatformAndStopLabel(
  String? platform,
  String? stopLabel, {
  String? stationName,
  required bool isRail,
}) {
  final normalizedPlatform = platform?.trim();
  final normalizedStopLabel = _normalizeStopDetailLabel(
    stopLabel,
    stationName: stationName,
  );
  final prefix = isRail ? 'Gl.' : 'Steig';

  String? formatWithPrefix(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    return '$prefix $normalized';
  }

  final extractedCode = normalizedStopLabel == null
      ? null
      : _extractStopDetailCode(normalizedStopLabel, isRail: isRail);
  // The structured track wins over anything parsed out of the free-text label:
  // the label can describe the whole platform area ("Gleis1/11") and would
  // otherwise announce a different track than the rest of the journey shows.
  final hasPlatform =
      normalizedPlatform != null && normalizedPlatform.isNotEmpty;
  if (extractedCode != null &&
      (!hasPlatform ||
          extractedCode.toLowerCase() == normalizedPlatform.toLowerCase())) {
    return formatWithPrefix(extractedCode);
  }

  if (normalizedPlatform == null || normalizedPlatform.isEmpty) {
    return normalizedStopLabel == null
        ? null
        : formatWithPrefix(normalizedStopLabel);
  }
  if (normalizedStopLabel == null || normalizedStopLabel.isEmpty) {
    return formatWithPrefix(normalizedPlatform);
  }

  final cleanedStopLabel = _cleanStopDetailLabel(normalizedStopLabel);

  final lowerPlatform = normalizedPlatform.toLowerCase();
  final lowerStopLabel = cleanedStopLabel.toLowerCase();

  if (lowerStopLabel == lowerPlatform) {
    return formatWithPrefix(normalizedPlatform);
  }

  if (_matchesSimpleStopLabel(lowerStopLabel, lowerPlatform, const [
    'gleis',
    'bahnsteig gleis',
    's-bahnsteig gleis',
    'u-bahnsteig gleis',
  ])) {
    return formatWithPrefix(normalizedPlatform);
  }

  if (_matchesSimpleStopLabel(lowerStopLabel, lowerPlatform, const [
    'bussteig',
    'bussteige',
    'steig',
    'platz',
    'bstg.',
    'bstg',
    'haltestelle',
  ])) {
    return formatWithPrefix(normalizedPlatform);
  }

  return formatWithPrefix(normalizedPlatform);
}

String _formatBoardingText(
  AppLocalizations l10n, {
  required String stationName,
  String? platform,
  String? stopLabel,
}) {
  return l10n.boardAt(stationName);
}

String _formatAlightingText(
  AppLocalizations l10n, {
  required String stationName,
  String? platform,
  String? stopLabel,
}) {
  return l10n.getOffAt(stationName);
}

String _formatIntermediateStopTitle(
  String name, {
  String? platform,
  String? stopLabel,
}) {
  return name;
}

@visibleForTesting
bool savedJourneyLongPressShowsDelete({
  required bool isCompleted,
  required bool isLegacy,
  required bool hasStarted,
}) {
  return isCompleted || isLegacy || hasStarted;
}

String _ellipsize(String value, int maxLength) {
  final normalized = value.trim();
  if (normalized.length <= maxLength) return normalized;
  if (maxLength <= 1) return '…';
  return '${normalized.substring(0, maxLength - 1)}…';
}

@visibleForTesting
String compactSavedRouteLabel(String fromName, String toName) {
  final from = fromName.trim();
  final to = toName.trim();
  if (to.isEmpty) return '';
  if (from.isEmpty) return _ellipsize(to, 34);
  return '${_ellipsize(from, 16)} → ${_ellipsize(to, 16)}';
}

const int _savedRouteStatusNotificationIdSalt = 0x5a5a5a5a;
const int _savedRouteStatusDetailMaxLength = 38;

@visibleForTesting
int savedRouteStatusNotificationIdForKey(String routeKey) {
  // Salt separates saved-route IDs from other notification families.
  return ((routeKey.hashCode * 31) ^ _savedRouteStatusNotificationIdSalt) &
      0x7fffffff;
}

@visibleForTesting
DateTime? alternativeJourneyDisplayDepartureLocal(
    Map<String, dynamic> journey) {
  try {
    final legs = (journey['legs'] as List?)?.cast<Map<String, dynamic>>();
    if (legs == null || legs.isEmpty) return null;

    final firstLeg = legs.first;
    final firstRide = legs.firstWhere(
      (leg) => leg['line'] != null,
      orElse: () => firstLeg,
    );
    final rawTime = firstLeg['plannedDeparture'] ??
        firstLeg['departure'] ??
        firstRide['plannedDeparture'] ??
        firstRide['departure'];
    if (rawTime == null) return null;
    return DateTime.parse(rawTime.toString()).toLocal();
  } catch (_) {
    return null;
  }
}

/// Ride steps that should be checked for an earlier departure right now.
///
/// Opening a route checks the first two upcoming rides; as rides depart the
/// window slides forward, so the ride after them gets its turn one at a time.
@visibleForTesting
List<int> earlierAlternativeScanTargets(
  List<JourneyStep> steps,
  DateTime now, {
  int lookahead = 2,
}) {
  final targets = <int>[];
  for (var i = 0; i < steps.length && targets.length < lookahead; i++) {
    final step = steps[i];
    if (step.type != 'ride') continue;
    final departure = step.plannedDeparture ?? step.dateTime;
    if (departure == null || !departure.isAfter(now)) continue;
    targets.add(i);
  }
  return targets;
}

/// Whether an alternative departure is worth pointing at: meaningfully
/// earlier, still catchable, and not arriving later than the current plan.
@visibleForTesting
bool earlierAlternativeQualifies({
  required DateTime plannedDeparture,
  required DateTime alternativeDeparture,
  required DateTime alternativeArrival,
  required DateTime earliestCatchable,
  required DateTime latestArrival,
  Duration minGain = const Duration(minutes: 3),
}) {
  if (alternativeDeparture.isAfter(plannedDeparture.subtract(minGain))) {
    return false;
  }
  if (alternativeDeparture.isBefore(earliestCatchable)) return false;
  if (alternativeArrival.isAfter(latestArrival)) return false;
  return true;
}

/// First transit leg of a raw journey map, if it has one.
Map<String, dynamic>? _firstRideLegOf(Map<String, dynamic> journey) {
  final legs = (journey['legs'] as List?)?.cast<Map<String, dynamic>>();
  if (legs == null || legs.isEmpty) return null;
  for (final leg in legs) {
    if (leg['line'] != null) return leg;
  }
  return null;
}

/// When the traveller actually boards: a leading walk leg makes the journey
/// start earlier than the ride, which is what the route view shows.
@visibleForTesting
DateTime? alternativeJourneyBoardingLocal(Map<String, dynamic> journey) {
  final ride = _firstRideLegOf(journey);
  final rawTime = ride?['plannedDeparture'] ?? ride?['departure'];
  if (rawTime == null) return alternativeJourneyDisplayDepartureLocal(journey);
  try {
    return DateTime.parse(rawTime.toString()).toLocal();
  } catch (_) {
    return alternativeJourneyDisplayDepartureLocal(journey);
  }
}

@visibleForTesting
String? alternativeJourneyTripId(Map<String, dynamic> journey) {
  final ride = _firstRideLegOf(journey);
  final tripId = (ride?['line'] as Map?)?['tripId'] ?? ride?['tripId'];
  final normalized = tripId?.toString().trim();
  if (normalized == null || normalized.isEmpty) return null;
  return normalized;
}

/// Line label without the train number, for comparing two rides.
@visibleForTesting
String normalizeRideLineKey(String line) {
  return line
      .toUpperCase()
      .replaceAll(RegExp(r'\s*\(\d+\)'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// True when a listed journey starts with the very ride the traveller is
/// already on - the same trip is not an alternative to itself.
@visibleForTesting
bool alternativeIsSameRide(
  Map<String, dynamic> journey, {
  String? tripId,
  String? line,
  DateTime? departure,
}) {
  final journeyTripId = alternativeJourneyTripId(journey);
  if (tripId != null && tripId.isNotEmpty && journeyTripId == tripId) {
    return true;
  }

  // Trip ids that differ prove nothing: MOTIS hands out opaque tokens that can
  // come back different for the same trip in another response. So fall through
  // instead of trusting the mismatch - the same line leaving at the same minute
  // is the same ride. Compare boarding times, since a leading walk shifts the
  // start of the journey.
  if (departure == null) return false;
  final boarding = alternativeJourneyBoardingLocal(journey);
  if (boarding == null) return false;
  if (boarding.difference(departure).abs() > const Duration(minutes: 1)) {
    return false;
  }
  if (line == null || line.isEmpty) return true;
  final ride = _firstRideLegOf(journey);
  final journeyLine = (ride?['line'] as Map?)?['name']?.toString();
  if (journeyLine == null) return true;
  return normalizeRideLineKey(journeyLine) == normalizeRideLineKey(line);
}

/// Keeps the earlier departures short: at most [maxEarlier] of the ones
/// closest to [reference], everything from [reference] on stays untouched.
@visibleForTesting
List<Map<String, dynamic>> limitEarlierAlternatives(
  List<Map<String, dynamic>> journeys, {
  required DateTime reference,
  int maxEarlier = 3,
}) {
  bool isEarlier(Map<String, dynamic> journey) {
    final boarding = alternativeJourneyBoardingLocal(journey);
    return boarding != null && boarding.isBefore(reference);
  }

  final earlierCount = journeys.where(isEarlier).length;
  if (earlierCount <= maxEarlier) return journeys;

  // The list runs from early to late, so dropping from the front keeps the
  // departures closest to the planned one.
  var skip = earlierCount - maxEarlier;
  final kept = <Map<String, dynamic>>[];
  for (final journey in journeys) {
    if (skip > 0 && isEarlier(journey)) {
      skip--;
      continue;
    }
    kept.add(journey);
  }
  return kept;
}

/// Number of legs of [original] that still belong to the trip when the ride at
/// [rideLegIndex] is swapped for an alternative: everything before it, minus
/// the walking legs that lead up to it - the alternative brings its own.
@visibleForTesting
int journeyPrefixLegCount(List<dynamic> original, int rideLegIndex) {
  var prefix = rideLegIndex.clamp(0, original.length);
  while (prefix > 0) {
    final leg = original[prefix - 1];
    final isRide = leg is Map && leg['line'] != null;
    if (isRide) break;
    prefix--;
  }
  return prefix;
}

/// Builds the full trip out of the part already travelled and the alternative
/// picked for the rest, so a chosen alternative does not start mid-route.
@visibleForTesting
Map<String, dynamic> spliceAlternativeIntoJourney({
  required Map<String, dynamic> original,
  required Map<String, dynamic> alternative,
  required int rideLegIndex,
}) {
  final originalLegs = (original['legs'] as List?) ?? const [];
  final alternativeLegs = (alternative['legs'] as List?) ?? const [];
  final prefix = journeyPrefixLegCount(originalLegs, rideLegIndex);
  if (prefix <= 0 || alternativeLegs.isEmpty) return alternative;

  final legs = [...originalLegs.take(prefix), ...alternativeLegs];
  final spliced = Map<String, dynamic>.from(alternative)..['legs'] = legs;

  final firstLeg = legs.first;
  final lastLeg = legs.last;
  if (firstLeg is Map) {
    final departure = firstLeg['departure'] ?? firstLeg['plannedDeparture'];
    if (departure != null) spliced['departure'] = departure;
  }
  if (lastLeg is Map) {
    final arrival = lastLeg['arrival'] ?? lastLeg['plannedArrival'];
    if (arrival != null) spliced['arrival'] = arrival;
  }
  // Recomputed from the legs; a stale value would describe the alternative
  // alone, not the spliced trip.
  spliced.remove('duration');
  spliced.remove('transfers');
  return spliced;
}

bool _isBeforeFirstJourneyStep(int builtStepCount) => builtStepCount == 0;

@visibleForTesting
bool isBeforeFirstJourneyStepForTesting(int builtStepCount) =>
    _isBeforeFirstJourneyStep(builtStepCount);

/// Identity of the ride a journey starts with. Two results that begin with the
/// same ride are one choice for the traveller, however they continue.
@visibleForTesting
String? alternativeRideKey(Map<String, dynamic> journey) {
  final tripId = alternativeJourneyTripId(journey);
  if (tripId != null) return 'trip:$tripId';

  final boarding = alternativeJourneyBoardingLocal(journey);
  if (boarding == null) return null;
  final ride = _firstRideLegOf(journey);
  final line = (ride?['line'] as Map?)?['name']?.toString() ?? '';
  return '${normalizeRideLineKey(line)}@${boarding.millisecondsSinceEpoch}';
}

/// Keeps one entry per ride, the one that reaches the destination first, in
/// the order the rides depart.
@visibleForTesting
List<Map<String, dynamic>> collapseAlternativesByRide(
  Iterable<Map<String, dynamic>> journeys,
) {
  final collapsed = <Map<String, dynamic>>[];
  final indexByRide = <String, int>{};

  for (final journey in journeys) {
    final key = alternativeRideKey(journey);
    if (key == null) {
      collapsed.add(journey);
      continue;
    }
    final index = indexByRide[key];
    if (index == null) {
      indexByRide[key] = collapsed.length;
      collapsed.add(journey);
      continue;
    }

    final keptArrival = alternativeJourneyArrivalLocal(collapsed[index]);
    final arrival = alternativeJourneyArrivalLocal(journey);
    if (keptArrival == null ||
        (arrival != null && arrival.isBefore(keptArrival))) {
      collapsed[index] = journey;
    }
  }

  return collapsed;
}

/// Identity of a raw journey map: departure and arrival pin one connection.
@visibleForTesting
String? alternativeJourneyKey(Map<String, dynamic> journey) {
  final departure = alternativeJourneyDisplayDepartureLocal(journey);
  final arrival = alternativeJourneyArrivalLocal(journey);
  if (departure == null || arrival == null) return null;
  return '${departure.millisecondsSinceEpoch}_'
      '${arrival.millisecondsSinceEpoch}';
}

/// Arrival of a raw journey map at its final stop.
@visibleForTesting
DateTime? alternativeJourneyArrivalLocal(Map<String, dynamic> journey) {
  try {
    final legs = (journey['legs'] as List?)?.cast<Map<String, dynamic>>();
    if (legs == null || legs.isEmpty) return null;
    final lastLeg = legs.last;
    final rawTime = lastLeg['plannedArrival'] ?? lastLeg['arrival'];
    if (rawTime == null) return null;
    return DateTime.parse(rawTime.toString()).toLocal();
  } catch (_) {
    return null;
  }
}

@visibleForTesting
List<Map<String, dynamic>> mergeAlternativeJourneys(
  Iterable<Map<String, dynamic>> existing,
  Iterable<Map<String, dynamic>> incoming,
) {
  final merged = <Map<String, dynamic>>[];
  final seenIds = <String>{};

  void addJourney(Map<String, dynamic> journey) {
    final id = alternativeJourneyKey(journey);
    if (id == null) return;
    if (!seenIds.add(id)) return;
    merged.add(journey);
  }

  for (final journey in existing) {
    addJourney(journey);
  }
  for (final journey in incoming) {
    addJourney(journey);
  }

  merged.sort((a, b) {
    final depA = alternativeJourneyDisplayDepartureLocal(a);
    final depB = alternativeJourneyDisplayDepartureLocal(b);
    if (depA == null && depB == null) return 0;
    if (depA == null) return 1;
    if (depB == null) return -1;
    return depA.compareTo(depB);
  });
  return merged;
}

String _journeyRefreshSignature(Iterable<Journey> journeys) {
  return journeys.map((journey) {
    final realtime = journey.steps
        .where((step) => step.type == 'ride')
        .map((step) => [
              step.tripId?.trim() ?? '',
              step.departureTime,
              step.arrivalTime,
              step.departureDelay?.toString() ?? '',
              step.arrivalDelay?.toString() ?? '',
              step.isCancelled ? '1' : '0',
            ].join('|'))
        .join('||');
    return '${journey.plannedDeparture ?? journey.departure}_'
        '${journey.plannedArrival ?? journey.arrival}_$realtime';
  }).join("||");
}

String _journeyListKey(Journey journey) {
  final departure = journey.plannedDeparture?.millisecondsSinceEpoch ??
      journey.departure.millisecondsSinceEpoch;
  final arrival = journey.plannedArrival?.millisecondsSinceEpoch ??
      journey.arrival.millisecondsSinceEpoch;
  String firstLine = '';
  String firstTripId = '';
  for (final step in journey.steps) {
    if (step.type != 'ride') continue;
    firstLine = step.line;
    firstTripId = step.tripId ?? '';
    break;
  }
  return '$departure|$arrival|$firstLine|$firstTripId';
}

int _journeyPlatformSignal(Journey journey) {
  var score = 0;
  for (final step in journey.steps.where((step) => step.type == 'ride')) {
    if ((step.platform ?? '').trim().isNotEmpty) {
      score += 2;
      // A track resolved to a single platform beats one that is still just the
      // combined area from the feed, so a corrected track counts as progress.
      if (!platformLooksLikeTrackArea(step.platform, step.departureStopLabel)) {
        score += 1;
      }
    }
    if ((step.arrivalPlatform ?? '').trim().isNotEmpty) {
      score += 1;
      if (!platformLooksLikeTrackArea(
        step.arrivalPlatform,
        step.arrivalStopLabel,
      )) {
        score += 1;
      }
    }
    if ((step.departureStopLabel ?? '').trim().isNotEmpty) score += 1;
    if ((step.arrivalStopLabel ?? '').trim().isNotEmpty) score += 1;
  }
  return score;
}

String _firstRideLineKey(Journey journey) {
  for (final step in journey.steps) {
    if (step.type != 'ride') continue;
    return normalizeRideLineKey(step.line);
  }
  return '';
}

String _firstRideTripId(Journey journey) {
  for (final step in journey.steps) {
    if (step.type != 'ride') continue;
    return step.tripId?.trim() ?? '';
  }
  return '';
}

int _journeyLineDetailSignal(Journey journey) {
  var score = 0;
  for (final step in journey.steps.where((step) => step.type == 'ride')) {
    score += step.line.split('/').length;
  }
  return score;
}

/// Whether two journey objects stand for the same entry in a tab's stack.
///
/// Object identity alone is not enough: a realtime refresh replaces the active
/// journey with a fresh instance, and the tab strip would then highlight
/// nothing at all.
bool _isSameJourneyEntry(Journey a, Journey b) {
  if (identical(a, b)) return true;
  // A branch shares its start - and often its arrival - with the journey it
  // came from, so the two must not collapse into one entry.
  if (a.branchStepIndex != b.branchStepIndex) return false;
  return _journeyListKey(a) == _journeyListKey(b);
}

@visibleForTesting
bool isSameJourneyEntryForTesting(Journey a, Journey b) =>
    _isSameJourneyEntry(a, b);

bool _journeysLikelySameRoute(Journey a, Journey b) {
  final depA = a.plannedDeparture ?? a.departure;
  final depB = b.plannedDeparture ?? b.departure;
  final arrA = a.plannedArrival ?? a.arrival;
  final arrB = b.plannedArrival ?? b.arrival;
  if (depA.difference(depB).abs() > const Duration(minutes: 2)) {
    return false;
  }
  if (arrA.difference(arrB).abs() > const Duration(minutes: 2)) {
    return false;
  }
  final tripA = _firstRideTripId(a);
  final tripB = _firstRideTripId(b);
  if (tripA.isNotEmpty && tripB.isNotEmpty && tripA == tripB) return true;
  final lineA = _firstRideLineKey(a);
  final lineB = _firstRideLineKey(b);
  return lineA.isEmpty || lineB.isEmpty || lineA == lineB;
}

Journey _preferJourneyWithMorePlatformDetail(
  Journey existing,
  Journey incoming,
) {
  final incomingScore = _journeyPlatformSignal(incoming);
  final existingScore = _journeyPlatformSignal(existing);
  if (incomingScore > existingScore) {
    return incoming.copyWith(
      parentJourney: existing.parentJourney,
      branchStepIndex: existing.branchStepIndex,
      savedConnectionKey: existing.savedConnectionKey,
    );
  }
  if (incomingScore == existingScore &&
      _journeyLineDetailSignal(incoming) > _journeyLineDetailSignal(existing)) {
    return incoming.copyWith(
      parentJourney: existing.parentJourney,
      branchStepIndex: existing.branchStepIndex,
      savedConnectionKey: existing.savedConnectionKey,
    );
  }
  return existing;
}

@visibleForTesting
Journey preferJourneyWithMorePlatformDetailForTesting(
  Journey existing,
  Journey incoming,
) =>
    _preferJourneyWithMorePlatformDetail(existing, incoming);

bool _sameRideForRealtimeRefresh(JourneyStep current, JourneyStep fresh) {
  final currentTripId = current.tripId?.trim();
  final freshTripId = fresh.tripId?.trim();
  if ((currentTripId?.isNotEmpty ?? false) &&
      (freshTripId?.isNotEmpty ?? false)) {
    return currentTripId == freshTripId;
  }

  if (current.plannedDeparture != null &&
      fresh.plannedDeparture != null &&
      current.plannedArrival != null &&
      fresh.plannedArrival != null) {
    return current.plannedDeparture == fresh.plannedDeparture &&
        current.plannedArrival == fresh.plannedArrival &&
        current.startStationName == fresh.startStationName &&
        current.destinationName == fresh.destinationName;
  }

  return current.line.trim().toLowerCase() == fresh.line.trim().toLowerCase() &&
      current.startStationName == fresh.startStationName &&
      current.destinationName == fresh.destinationName;
}

/// Retains local route-only state (walk legs, alarms and richer platform
/// labels) while treating the incoming provider result as the newest source
/// for every matched vehicle's live fields.
Journey _mergeJourneyWithFreshRealtime(
  Journey existing,
  Journey incoming, {
  bool updateJourneyBounds = true,
  bool replaceRawSource = true,
}) {
  final freshRideSteps =
      incoming.steps.where((step) => step.type == 'ride').toList();
  var matchedRide = false;

  final mergedSteps = existing.steps.map((step) {
    if (step.type != 'ride') return step;

    JourneyStep? fresh;
    for (final candidate in freshRideSteps) {
      if (_sameRideForRealtimeRefresh(step, candidate)) {
        fresh = candidate;
        break;
      }
    }
    if (fresh == null) return step;
    matchedRide = true;

    return step.copyWith(
      departureTime: fresh.departureTime,
      arrivalTime: fresh.arrivalTime,
      dateTime: fresh.dateTime,
      startStationId: fresh.startStationId ?? step.startStationId,
      destinationStationId:
          fresh.destinationStationId ?? step.destinationStationId,
      platform: fresh.platform ?? step.platform,
      arrivalPlatform: fresh.arrivalPlatform ?? step.arrivalPlatform,
      departureStopLabel: fresh.departureStopLabel ?? step.departureStopLabel,
      arrivalStopLabel: fresh.arrivalStopLabel ?? step.arrivalStopLabel,
      stopovers: fresh.stopovers ?? step.stopovers,
      departureDelay: fresh.departureDelay,
      arrivalDelay: fresh.arrivalDelay,
      clearDepartureDelay: fresh.departureDelay == null,
      clearArrivalDelay: fresh.arrivalDelay == null,
      isCancelled: fresh.isCancelled,
      plannedDeparture: fresh.plannedDeparture ?? step.plannedDeparture,
      plannedArrival: fresh.plannedArrival ?? step.plannedArrival,
      headsign: fresh.headsign ?? step.headsign,
      tripId: fresh.tripId ?? step.tripId,
    );
  }).toList();

  // Do not replace an itinerary merely because a same-key provider result has
  // an unexpected shape. This can happen when a transfer is no longer offered.
  if (!matchedRide && existing.steps.any((step) => step.type == 'ride')) {
    return _preferJourneyWithMorePlatformDetail(existing, incoming);
  }

  return existing.copyWith(
    steps: mergedSteps,
    departure: updateJourneyBounds ? incoming.departure : existing.departure,
    arrival: updateJourneyBounds ? incoming.arrival : existing.arrival,
    duration: updateJourneyBounds ? incoming.duration : existing.duration,
    rawSource: replaceRawSource ? incoming.rawSource : existing.rawSource,
    source: replaceRawSource ? incoming.source : existing.source,
    plannedDeparture: incoming.plannedDeparture ?? existing.plannedDeparture,
    plannedArrival: incoming.plannedArrival ?? existing.plannedArrival,
  );
}

@visibleForTesting
List<Journey> mergeRefreshedJourneyCandidates(
  Iterable<Journey> existing,
  Iterable<Journey> incoming,
) {
  final byKey = <String, Journey>{};
  for (final journey in existing) {
    byKey[_journeyListKey(journey)] = journey;
  }
  for (final journey in incoming) {
    final key = _journeyListKey(journey);
    final previous = byKey[key];
    byKey[key] = previous == null
        ? journey
        : _mergeJourneyWithFreshRealtime(previous, journey);
  }

  return byKey.values.toList()
    ..sort((a, b) => a.departure.compareTo(b.departure));
}

List<Journey> _mergeJourneyCandidates(
  Iterable<Journey> existing,
  Iterable<Journey> incoming,
) =>
    mergeRefreshedJourneyCandidates(existing, incoming);

Journey _bestCurrentJourneyVersion(
  Journey target,
  Iterable<Journey> candidates,
) {
  var best = target;
  for (final candidate in candidates) {
    if (_journeyListKey(candidate) != _journeyListKey(target) &&
        !_journeysLikelySameRoute(candidate, target)) {
      continue;
    }
    best = _mergeJourneyWithFreshRealtime(best, candidate);
  }
  return best;
}

class _SuggestionSection {
  final String? title;
  final List<dynamic> items;

  const _SuggestionSection({this.title, required this.items});
}

class RoutesTab extends StatefulWidget {
  final Position? currentPosition;
  final bool onlyNahverkehr;
  final bool showTrainNumbers;
  final bool alwaysWakeMe;
  final int signalLevel;
  final void Function(bool active) onHighAccuracyTrackingChanged;

  const RoutesTab({
    super.key,
    required this.currentPosition,
    required this.onlyNahverkehr,
    this.showTrainNumbers = false,
    required this.alwaysWakeMe,
    required this.signalLevel,
    required this.onHighAccuracyTrackingChanged,
  });

  @override
  State<RoutesTab> createState() => RoutesTabState();
}

class RoutesTabState extends State<RoutesTab>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final List<RouteTab> _tabs = [];
  String? _activeTabId;

  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _toController = TextEditingController();
  final TextEditingController _friendOriginController = TextEditingController();

  final FocusNode _fromFocusNode = FocusNode();
  final FocusNode _toFocusNode = FocusNode();
  final FocusNode _friendOriginFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _suggestionsScrollController = ScrollController();
  final GlobalKey _fromFieldKey = GlobalKey();
  final GlobalKey _toFieldKey = GlobalKey();
  final GlobalKey _friendFieldKey = GlobalKey();

  Station? _fromStation;
  Station? _toStation;
  bool _toIsCapturedCurrentLocation = false;

  List<dynamic> _suggestions = [];
  String _activeSearchField = '';
  Timer? _debounce;
  int _suggestionRequestToken = 0;
  Timer? _focusDebounce; // Delayed focus handling for Web clicks
  bool _isLoadingRoute = false;
  int _nextRouteSearchToken = 0;
  int? _activeRouteSearchToken;
  final Set<int> _cancelledRouteSearchTokens = <int>{};
  final Set<String> _activePlatformEnrichmentKeys = <String>{};
  final Set<String> _completedActivePlatformEnrichmentKeys = <String>{};

  /// Per tab: step index of a ride that can be swapped for an earlier
  /// departure, pointing at the ride key of that suggestion. Keyed by ride and
  /// not by connection, because the sheet may keep a different continuation of
  /// the same ride than the check happened to see.
  final Map<String, Map<int, String>> _earlierAlternativeSteps =
      <String, Map<int, String>>{};

  /// Rides already looked up, so each one costs at most one search.
  final Set<String> _earlierAlternativeScanKeys = <String>{};

  /// Rides whose alternatives the traveller has opened; the border stops
  /// circling for those.
  final Set<String> _seenAlternativeHints = <String>{};

  /// Results the background check already fetched, so the sheet has something
  /// to show the moment it opens.
  final Map<String, List<Map<String, dynamic>>> _preloadedAlternatives =
      <String, List<Map<String, dynamic>>>{};
  Set<String> _activeRouteLoadPhases = <String>{};
  bool _isSuggestionsLoading = false;

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  bool _isArrival = false;
  bool _bikeSearchToggleEnabledForDevice = false;
  bool _hasBikeModesConfiguredForDevice = false;

  bool _isWakeAlarmSet = false;
  int _alarmStopsBefore = 1;
  StreamSubscription<Position>? _gpsStream;
  StreamSubscription<Position>? _sharingGpsStream;
  Timer? _journeyDetectionTimer;
  Timer? _activeJourneyRefreshTimer;
  DateTime? _lastActiveJourneyRefresh;
  JourneyDetectionMatch? _detectedJourney;
  String? _detectedDestinationName;
  String? _pendingDetectionKey;
  int _pendingDetectionSamples = 0;
  int _detectedMismatchSamples = 0;
  final Set<String> _suppressedDetectionKeys = <String>{};
  List<JourneyDetectionCandidate> _savedDetectionCandidates =
      const <JourneyDetectionCandidate>[];
  int _maximumEffectiveSignalLevel = 0;
  double? _gpsAccuracy;
  List<Favorite> _favorites = [];
  List<Station> _sharedFriendPlaces = [];
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  bool _wasKeyboardVisible = false;
  String? _currentAddress; // Store the reverse-geocoded address
  bool _fromUsesCurrentLocation = true;
  bool _isRefreshingLocation = false;
  Position? _manualCurrentPosition;
  List<Map<String, dynamic>> _frequentJourneys = [];
  List<Map<String, dynamic>> _recentJourneys = [];
  List<Map<String, dynamic>> _savedJourneys = [];
  final Set<String> _savedReminderPickerVisibleFor = <String>{};
  final Set<String> _savedCompletedDeleteVisibleFor = <String>{};
  final Map<String, Timer> _savedJourneyReminderTimers = <String, Timer>{};
  Timer? _savedJourneyLiveCountdownTicker;
  final Map<String, String> _savedJourneyLiveCountdownTexts =
      <String, String>{};
  final Set<String> _savedJourneyTriggeredReminderKeys = <String>{};
  Timer? _savedJourneyStatusPollTimer;
  final Map<String, String> _savedJourneyLastStatusSignatures =
      <String, String>{};
  final Set<String> _savingRouteIds = <String>{};
  final Map<String, ScrollController> _routeResultsScrollControllers =
      <String, ScrollController>{};
  final Map<String, ScrollController> _activeJourneyScrollControllers =
      <String, ScrollController>{};
  final Map<String, double> _routeResultsScrollOffsets = <String, double>{};

  /// Scroll position the fixed tab strip is currently pulling on, or null when
  /// no header pull is in flight.
  ScrollPosition? _tabBarPullPosition;
  final Map<String, RouteSortOption> _routeResultsSortSelections =
      <String, RouteSortOption>{};
  final Map<String, _JointRouteContext> _jointRouteContexts =
      <String, _JointRouteContext>{};
  List<RouteSortOption> _routeResultsSortOrder =
      List<RouteSortOption>.from(defaultRouteSortOrder);
  bool _isCheckingSavedJourneyStatuses = false;
  DateTime? _lastSavedJourneyStatusCheck;
  RouteHistoryView _historyView = RouteHistoryView.frequent;
  bool _jointPlanningEnabled = false;
  late final AnimationController _jointHeaderController;
  double _jointHeaderDragStartGlobalX = 0;
  double _jointHeaderDragStartProgress = 0;

  /// Friends who currently share a location and can be picked in one tap.
  List<JointPlanFriend> _jointPlanningFriends = [];

  /// Set when the companion's start came from a friend rather than free text.
  JointPlanFriend? _selectedJointFriend;
  Station? _friendOriginStation;
  double _jointTogetherness =
      JointJourneyPreferences.togethernessFor(JointJourneyIntent.balanced);

  Position? get _effectiveCurrentPosition =>
      _manualCurrentPosition ?? widget.currentPosition;

  void routeToSharedPlace(Station station) {
    setState(() {
      _activeTabId = null;
      _toStation = station;
      _toIsCapturedCurrentLocation = false;
      _toController.text = station.name;
      _activeSearchField = '';
      _suggestions = [];
    });
    FocusScope.of(context).unfocus();
  }

  AppLocalizations? _reminderL10n;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reminder notifications are built after awaits, where `context` may already
    // be defunct, so keep a live copy of the current localizations here.
    _reminderL10n = AppLocalizations.of(context);
  }

  @override
  void initState() {
    super.initState();
    _jointHeaderController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _fetchSuggestions(forceHistory: true);
    _loadFavorites();
    _loadDeviceRoutePreferences();
    SupabaseService.settingsRefreshNotifier
        .addListener(_handleDeviceRouteSettingsRefresh);
    _initNotifications();
    WidgetsBinding.instance.addObserver(this);
    _fromFocusNode.addListener(_onFocusChange);
    _toFocusNode.addListener(_onFocusChange);
    _friendOriginFocusNode.addListener(_onFocusChange);
    _resolveCurrentAddress();
    _loadHistoryData();
    _loadJointPlanningFriends();
    _refreshJourneySharingConfiguration();
    _journeyDetectionTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _updateJourneyDetectionMonitoring(),
    );
    _activeJourneyRefreshTimer = Timer.periodic(
      const Duration(minutes: 3),
      (_) => _refreshVisibleActiveJourneyIfDue(),
    );
  }

  Future<void> _loadJointPlanningFriends() async {
    try {
      final friends = await SupabaseService.getFriends();
      final selectable = JointPlanFriend.selectableFrom(friends);
      if (!mounted) return;
      setState(() {
        _jointPlanningFriends = selectable;
        final selected = _selectedJointFriend;
        if (selected == null) return;
        JointPlanFriend? refreshed;
        for (final friend in selectable) {
          if (friend.id == selected.id) {
            refreshed = friend;
            break;
          }
        }
        if (refreshed == null) {
          // They stopped sharing; the start they contributed stays usable, but
          // it can no longer be refreshed.
          _selectedJointFriend = null;
          return;
        }
        _selectedJointFriend = refreshed;
        // A friend on the move should not be planned from a position we
        // already know is outdated.
        if (_friendOriginStation?.id == refreshed.toOriginStation()?.id) {
          _friendOriginStation = refreshed.toOriginStation();
        }
      });
    } catch (error, stackTrace) {
      AppError.log(
        error,
        stackTrace: stackTrace,
        source: 'RoutesTab._loadJointPlanningFriends',
      );
    }
  }

  JointJourneyPreferences get _jointJourneyPreferences =>
      JointJourneyPreferences.fromTogetherness(_jointTogetherness);

  List<JointPlanFriend> _matchingJointFriends(String query) =>
      _jointPlanningFriends.where((friend) => friend.matches(query)).toList();

  /// How old a friend's shared position is, in a full sentence. A position
  /// without a timestamp says so instead of pretending to know.
  String _friendLocationAgeNote(
    JointPlanFriend friend, {
    required bool german,
  }) {
    if (friend.locationAge() == null) {
      return german
          ? 'Für diesen Standort gibt es keine Zeitangabe.'
          : 'There is no timestamp for this location.';
    }
    final label = JointFriendChips.freshnessLabel(friend, german: german);
    return german
        ? 'Dieser Standort wurde $label aktualisiert.'
        : 'This location was last updated $label.';
  }

  /// Switches between the normal planner and the two-origin planner.
  void _setJointPlanningEnabled(bool enabled) {
    setState(() {
      _jointPlanningEnabled = enabled;
      if (!enabled && _activeSearchField == 'friend') {
        _activeSearchField = '';
        _suggestions = [];
        _isSuggestionsLoading = false;
      }
    });
    unawaited(_jointHeaderController.animateTo(
      enabled ? 1 : 0,
      curve: Curves.easeOutCubic,
    ));
    if (enabled) unawaited(_loadJointPlanningFriends());
  }

  Widget _buildPlanModeHeader(TransColors colors, {required bool isGerman}) {
    final planStyle = TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.bold,
      color: colors.textPrimary,
    );
    final togetherStyle = TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.bold,
      color: colors.effectiveSeed,
    );
    final planText = AppLocalizations.of(context)!.planJourney;
    final togetherText = isGerman ? ' zusammen' : ' Together';

    Widget glass({required bool moving, double progress = 0}) {
      Widget glyph = Icon(Icons.search, color: colors.searchHeaderIcon);
      // Only the glyph turns. Flipping the tinted square along with it made
      // its edges read as a bright sliver that kept the untransformed width.
      if (moving) {
        glyph = Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(pi * progress),
          child: glyph,
        );
      }
      return Container(
        width: 40,
        height: 40,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: colors.searchHeaderIconBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: glyph,
      );
    }

    return SizedBox(
      key: const ValueKey('joint-plan-swipe-header'),
      height: 42,
      child: LayoutBuilder(builder: (context, constraints) {
        final travel = max(1.0, constraints.maxWidth - 40);
        final textDirection = Directionality.of(context);
        final textScaler = MediaQuery.textScalerOf(context);
        // Text.rich paints its spans on top of the ambient default style, so
        // the measurement has to start from that same style. Leaving it out
        // dropped the theme's letter spacing and left the reveal a glyph short
        // of the real end of Together.
        final titleSpan = TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(text: planText, style: planStyle),
            TextSpan(text: togetherText, style: togetherStyle),
          ],
        );
        // Measure the two runs as the single line they are painted as.
        final titlePainter = TextPainter(
          text: titleSpan,
          textDirection: textDirection,
          textScaler: textScaler,
          maxLines: 1,
        )..layout();
        // A little slack for glyphs that paint past their advance width.
        final intrinsicTitleWidth = titlePainter.width + 2;
        // At the completed position the moving icon is the reveal boundary.
        // Scale long/localized titles just enough to leave a small gap before
        // that boundary rather than letting the text and handle drift apart.
        final availableTitleWidth = max(1.0, travel - 56);
        final titleScale = intrinsicTitleWidth <= availableTitleWidth
            ? 1.0
            : availableTitleWidth / intrinsicTitleWidth;
        Widget buildHeader(double progress) {
          final iconLeft = travel * progress;
          final renderedTitleWidth = intrinsicTitleWidth * titleScale;
          final revealedTitleWidth =
              (iconLeft - 52).clamp(0.0, renderedTitleWidth).toDouble();
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(left: 0, top: 1, child: glass(moving: false)),
              Positioned(
                left: 52,
                top: 0,
                bottom: 0,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Transform.scale(
                    scale: titleScale,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      planText,
                      key: const ValueKey('joint-plan-title-base'),
                      style: planStyle,
                    ),
                  ),
                ),
              ),
              // Draw the complete title as one line and reveal it up to the
              // moving icon. The always-visible Plan Journey layer beneath
              // is identical, while Together now shares its exact baseline.
              if (revealedTitleWidth > 0)
                Positioned(
                  left: 52,
                  top: 0,
                  bottom: 0,
                  width: revealedTitleWidth,
                  child: ClipRect(
                    key: const ValueKey('joint-together-reveal'),
                    child: OverflowBox(
                      alignment: Alignment.centerLeft,
                      minWidth: intrinsicTitleWidth,
                      maxWidth: intrinsicTitleWidth,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Transform.scale(
                          scale: titleScale,
                          alignment: Alignment.centerLeft,
                          child: Text.rich(
                            key: const ValueKey('joint-plan-title-reveal'),
                            titleSpan,
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                key: const ValueKey('joint-plan-handle-position'),
                left: iconLeft,
                top: 1,
                child: Semantics(
                  button: true,
                  label: _jointPlanningEnabled
                      ? (isGerman
                          ? 'Zur normalen Reiseplanung wechseln'
                          : 'Switch to normal journey planning')
                      : (isGerman
                          ? 'Zur gemeinsamen Reiseplanung wischen'
                          : 'Swipe to plan a journey together'),
                  child: GestureDetector(
                    key: const ValueKey('joint-plan-swipe-handle'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        _setJointPlanningEnabled(!_jointPlanningEnabled),
                    onHorizontalDragStart: (details) {
                      _jointHeaderController.stop();
                      _jointHeaderDragStartGlobalX = details.globalPosition.dx;
                      _jointHeaderDragStartProgress =
                          _jointHeaderController.value;
                    },
                    onHorizontalDragUpdate: (details) {
                      _jointHeaderController.value =
                          (_jointHeaderDragStartProgress +
                                  (details.globalPosition.dx -
                                          _jointHeaderDragStartGlobalX) /
                                      travel)
                              .clamp(0.0, 1.0);
                    },
                    onHorizontalDragEnd: (_) => _setJointPlanningEnabled(
                      _jointHeaderController.value >= 0.45,
                    ),
                    onHorizontalDragCancel: () =>
                        _setJointPlanningEnabled(_jointPlanningEnabled),
                    child: glass(moving: true, progress: progress),
                  ),
                ),
              ),
            ],
          );
        }

        return AnimatedBuilder(
          animation: _jointHeaderController,
          builder: (context, _) => buildHeader(_jointHeaderController.value),
        );
      }),
    );
  }

  Future<void> _loadDeviceRoutePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final savedSortOrder =
        prefs.getStringList(_routeSortOrderPreferenceKey)?.map((name) {
      for (final option in RouteSortOption.values) {
        if (option.name == name) return option;
      }
      return null;
    }).whereType<RouteSortOption>();
    final alarmStopsBefore = prefs.getInt('alarm_stops_before') ?? 1;
    final advancedEnabled = prefs.getBool(
          TransportApi.advancedSettingsEnabledPreferenceKey,
        ) ??
        false;
    final preBikeEnabled = prefs.getBool(
          TransportApi.advancedPreTransitBikeEnabledPreferenceKey,
        ) ??
        false;
    final postBikeEnabled = prefs.getBool(
          TransportApi.advancedPostTransitBikeEnabledPreferenceKey,
        ) ??
        false;
    final hasBikeModesConfigured =
        advancedEnabled && (preBikeEnabled || postBikeEnabled);
    final bikeToggleEnabled = prefs.getBool(
          TransportApi.advancedBikeTogglePreferenceKey,
        ) ??
        false;
    final jointTogetherness = (prefs.getDouble(
              jointTogethernessPreferenceKey,
            ) ??
            JointJourneyPreferences.togethernessFor(
              JointJourneyIntent.balanced,
            ))
        .clamp(0.0, 1.0)
        .toDouble();
    final effectiveToggleEnabled = hasBikeModesConfigured && bikeToggleEnabled;
    if (!hasBikeModesConfigured && bikeToggleEnabled) {
      await prefs.setBool(TransportApi.advancedBikeTogglePreferenceKey, false);
    }

    TransportApi.setBikeToggleEnabledForDevice(effectiveToggleEnabled);
    if (!mounted) return;
    setState(() {
      _alarmStopsBefore = alarmStopsBefore;
      _hasBikeModesConfiguredForDevice = hasBikeModesConfigured;
      _bikeSearchToggleEnabledForDevice = effectiveToggleEnabled;
      _jointTogetherness = jointTogetherness;
      _routeResultsSortOrder = normalizedRouteSortOrder(
        savedSortOrder ?? defaultRouteSortOrder,
      );
    });
  }

  Future<void> _saveRouteResultsSortOrder(
    List<RouteSortOption> order,
  ) async {
    final normalized = normalizedRouteSortOrder(order);
    setState(() => _routeResultsSortOrder = normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _routeSortOrderPreferenceKey,
      normalized.map((option) => option.name).toList(),
    );
    await SupabaseService.updateRouteResultsSortOrder(
      normalized.map((option) => option.name).toList(),
    );
  }

  RouteSearchSettings _routeSearchSettingsForRequest(
    DateTime when, {
    required bool isArrival,
  }) {
    return RouteSearchSettings(
      when: when,
      isArrival: isArrival,
    );
  }

  RouteSearchSettings _fallbackRouteSearchSettingsForSavedJourney(
    Map<String, dynamic> journey,
  ) {
    DateTime when = DateTime.now();
    bool isArrival = false;
    final rawDeparture = journey['departure'] ?? journey['plannedDeparture'];
    final parsedDeparture = rawDeparture is String
        ? DateTime.tryParse(rawDeparture)?.toLocal()
        : null;
    if (parsedDeparture != null) {
      when = parsedDeparture;
    } else {
      final rawArrival = journey['arrival'] ?? journey['plannedArrival'];
      final parsedArrival = rawArrival is String
          ? DateTime.tryParse(rawArrival)?.toLocal()
          : null;
      if (parsedArrival != null) {
        when = parsedArrival;
        isArrival = true;
      }
    }
    return _routeSearchSettingsForRequest(when, isArrival: isArrival);
  }

  Future<_RouteSearchDefaults> _loadRouteSearchDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    return _RouteSearchDefaults(
      minTransferTimeMinutes: prefs.getInt(
            TransportApi.advancedMinTransferTimeMinutesPreferenceKey,
          ) ??
          TransportApi.defaultAdvancedMinTransferTimeMinutes,
      additionalTransferTimeMinutes: prefs.getInt(
            TransportApi.advancedAdditionalTransferTimeMinutesPreferenceKey,
          ) ??
          TransportApi.defaultAdvancedAdditionalTransferTimeMinutes,
      transferTimeFactor: ((prefs.getDouble(
                        TransportApi.advancedTransferTimeFactorPreferenceKey,
                      ) ??
                      TransportApi.defaultAdvancedTransferTimeFactor) *
                  10)
              .round() /
          10,
      pedestrianSpeedKmh: (prefs.getDouble(
                TransportApi.advancedPedestrianSpeedKmhPreferenceKey,
              ) ??
              TransportApi.defaultAdvancedPedestrianSpeedKmh)
          .clamp(2.0, 10.0),
      maxWalkingTimeMinutes: prefs.getInt(
            TransportApi.advancedMaxWalkingTimeMinutesPreferenceKey,
          ) ??
          TransportApi.defaultAdvancedMaxWalkingTimeMinutes,
    );
  }

  Future<List<Map<String, dynamic>>> _searchJourneysForSettings(
    Station from,
    Station to, {
    required RouteSearchSettings settings,
    int results = 7,
    Function(List<Map<String, dynamic>>)? onPartialResults,
    void Function(Set<String> activePhases)? onLoadStateChanged,
    bool Function()? shouldContinue,
  }) {
    return TransportApi.searchJourneys(
      from,
      to,
      nahverkehrOnly: widget.onlyNahverkehr,
      when: settings.when,
      isArrival: settings.isArrival,
      results: results,
      minTransferTimeMinutesOverride: settings.minTransferTimeMinutes,
      additionalTransferTimeMinutesOverride:
          settings.additionalTransferTimeMinutes,
      transferTimeFactorOverride: settings.transferTimeFactor,
      pedestrianSpeedKmhOverride: settings.pedestrianSpeedKmh,
      maxWalkingTimeMinutesOverride: settings.maxWalkingTimeMinutes,
      onPartialResults: onPartialResults,
      onLoadStateChanged: onLoadStateChanged,
      shouldContinue: shouldContinue,
      // Result cards do not show platforms. The selected journey is enriched
      // lazily, so doing this for every candidate only delays search completion.
      enrichPlatforms: false,
    );
  }

  void _handleDeviceRouteSettingsRefresh() {
    unawaited(_loadDeviceRoutePreferences());
    unawaited(_refreshJourneySharingConfiguration());
  }

  Future<void> _refreshJourneySharingConfiguration() async {
    final settings = await SupabaseService.getJourneySharingSettings();
    final overrideMaximum = settings.friendOverrides.values.fold<int>(
      0,
      (maximum, level) => level > maximum ? level : maximum,
    );
    _maximumEffectiveSignalLevel = settings.hasFriends
        ? (settings.globalLevel > overrideMaximum
            ? settings.globalLevel
            : overrideMaximum)
        : 0;
    if (_maximumEffectiveSignalLevel == 0) {
      await _sharingGpsStream?.cancel();
      _sharingGpsStream = null;
      _detectedJourney = null;
      _detectedDestinationName = null;
      await SupabaseService.clearPublishedJourney(keepLastLine: false);
      return;
    }
    await _updateJourneyDetectionMonitoring();
  }

  Future<void> _setBikeSearchToggleEnabledForDevice(bool enabled) async {
    if (!_hasBikeModesConfiguredForDevice) return;
    setState(() => _bikeSearchToggleEnabledForDevice = enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(TransportApi.advancedBikeTogglePreferenceKey, enabled);
    TransportApi.setBikeToggleEnabledForDevice(enabled);
  }

  bool get _showBikeSearchToggle => _hasBikeModesConfiguredForDevice;

  Future<void> _loadHistoryData() async {
    final history = await SearchHistoryManager.getHistory();
    final frequent = await SearchHistoryManager.getFrequentJourneys();
    final recent = await SearchHistoryManager.getRecentJourneys();
    final saved = await SearchHistoryManager.getSavedJourneys();
    debugPrint(
        "Loaded history: ${history.length} items, frequent: ${frequent.length} items, recent: ${recent.length} items, saved: ${saved.length} items");
    if (mounted) {
      setState(() {
        _frequentJourneys = frequent;
        _recentJourneys = recent;
        _savedJourneys = saved;
      });
      _rebuildSavedDetectionCandidates();
      unawaited(_updateJourneyDetectionMonitoring());
    }
    _syncSavedJourneyReminderTimers(saved);
    _syncSavedJourneyStatusMonitoring(saved);
  }

  @override
  void didUpdateWidget(RoutesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentPosition != oldWidget.currentPosition) {
      _manualCurrentPosition = null;
      if (_fromStation == null &&
          _isCurrentLocationText(_fromController.text)) {
        _fromUsesCurrentLocation = true;
      }
      _resolveCurrentAddress();
      final position = widget.currentPosition;
      if (position != null) {
        unawaited(_handleJourneyDetectionPosition(position));
      }
    }
    if (widget.signalLevel != oldWidget.signalLevel) {
      unawaited(_refreshJourneySharingConfiguration());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_loadDeviceRoutePreferences());
      _refreshVisibleActiveJourneyIfDue();
    }
  }

  void _refreshVisibleActiveJourneyIfDue() {
    if (!mounted || _isLoadingRoute || _activeTabId == null) return;

    final route = _tabs.cast<RouteTab?>().firstWhere(
          (tab) => tab?.id == _activeTabId,
          orElse: () => null,
        );
    final journey = route?.activeJourney;
    if (route == null || journey == null) return;

    // Rides that have meanwhile departed free up the lookahead window, so the
    // ride after them gets checked for an earlier departure.
    _scheduleEarlierAlternativeScans(route, journey);

    final now = DateTime.now();
    final departure = journey.plannedDeparture ?? journey.departure;
    // Poll only a journey that is about to start or has just started. A
    // single visible tab is refreshed at most once every three minutes.
    if (departure.isBefore(now.subtract(const Duration(minutes: 15))) ||
        departure.isAfter(now.add(const Duration(hours: 2))) ||
        (_lastActiveJourneyRefresh != null &&
            now.difference(_lastActiveJourneyRefresh!) <
                const Duration(minutes: 3))) {
      return;
    }

    _lastActiveJourneyRefresh = now;
    unawaited(_refreshActiveJourney(route, showCompletionFeedback: false));
  }

  bool _isCurrentLocationText(String text, {String? addressOverride}) {
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    final localizedCurrentLocation =
        AppLocalizations.of(context)?.currentLocation.toLowerCase();
    if (normalized == 'current location' ||
        (localizedCurrentLocation != null &&
            normalized == localizedCurrentLocation)) {
      return true;
    }
    final address = (addressOverride ?? _currentAddress)?.trim().toLowerCase();
    return address != null && address.isNotEmpty && normalized == address;
  }

  Future<void> _resolveCurrentAddress() async {
    final position = _effectiveCurrentPosition;
    if (position == null) return;
    try {
      // Use getNearbyStops to find the nearest stop or address
      // Prioritize "address" or "station" type from results
      final stops = await TransportApi.getNearbyStops(
          position.latitude, position.longitude);
      if (stops.isNotEmpty) {
        final previousAddress = _currentAddress;
        final nextAddress = stops.first.name;
        if (mounted) {
          setState(() {
            _currentAddress = nextAddress;
            if (_fromStation == null &&
                _fromUsesCurrentLocation &&
                _isCurrentLocationText(_fromController.text,
                    addressOverride: previousAddress)) {
              _fromController.text = nextAddress;
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Error resolving address: $e");
    }
  }

  Future<String> _currentLocationName(Position position) async {
    try {
      final stops = await TransportApi.getNearbyStops(
        position.latitude,
        position.longitude,
      );
      final name = stops.isNotEmpty ? stops.first.name.trim() : '';
      if (name.isNotEmpty) {
        if (mounted) {
          setState(() => _currentAddress = name);
        }
        return name;
      }
    } catch (e) {
      debugPrint('Error resolving current location name: $e');
    }

    final knownAddress = _currentAddress?.trim();
    if (knownAddress != null && knownAddress.isNotEmpty) {
      return knownAddress;
    }
    // A coordinate is still an actual, stable location and avoids persisting
    // the UI-only "Current Location" placeholder in route history.
    return '${position.latitude.toStringAsFixed(5)}, '
        '${position.longitude.toStringAsFixed(5)}';
  }

  Future<void> _refreshCurrentLocationManually() async {
    if (_isRefreshingLocation) return;
    setState(() => _isRefreshingLocation = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:
                  Text(AppLocalizations.of(context)!.locationNotAvailable)));
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  AppLocalizations.of(context)!.locationPermissionDenied)));
        }
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(AppLocalizations.of(context)!
                  .locationPermissionPermanentlyDenied)));
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
              locationSettings:
                  const LocationSettings(accuracy: LocationAccuracy.high))
          .timeout(const Duration(seconds: 8));
      final stops =
          await TransportApi.getNearbyStops(pos.latitude, pos.longitude);
      final nextAddress = stops.isNotEmpty ? stops.first.name : null;

      if (!mounted) return;
      setState(() {
        _manualCurrentPosition = pos;
        _fromStation = null;
        _fromUsesCurrentLocation = true;
        _currentAddress = nextAddress;
        _fromController.text =
            nextAddress ?? AppLocalizations.of(context)!.currentLocation;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)!.locationNotAvailable)));
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshingLocation = false);
      }
    }
  }

  void _onFocusChange() {
    if (_fromFocusNode.hasFocus) {
      _focusDebounce?.cancel();
      if (_activeSearchField != 'from') {
        setState(() {
          _activeSearchField = 'from';
          _fetchSuggestions(forceHistory: _fromController.text.isEmpty);
        });
        _scrollFocusedFieldIntoViewIfNeeded();
      }
    } else if (_toFocusNode.hasFocus) {
      _focusDebounce?.cancel();
      if (_activeSearchField != 'to') {
        setState(() {
          _activeSearchField = 'to';
          _fetchSuggestions(forceHistory: _toController.text.isEmpty);
        });
        _scrollFocusedFieldIntoViewIfNeeded();
      }
    } else if (_friendOriginFocusNode.hasFocus) {
      _focusDebounce?.cancel();
      if (_activeSearchField != 'friend') {
        setState(() {
          _activeSearchField = 'friend';
          _fetchSuggestions(forceHistory: _friendOriginController.text.isEmpty);
        });
        _scrollFocusedFieldIntoViewIfNeeded();
      }
    } else {
      // We no longer clear suggestions on focus loss so users can interact with them after dismissing the keyboard.
      _focusDebounce?.cancel();
    }
  }

  void _initNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const linux = LinuxInitializationSettings(defaultActionName: 'Open');
    const initSettings =
        InitializationSettings(android: android, iOS: ios, linux: linux);
    try {
      await _notificationsPlugin.initialize(settings: initSettings);
    } catch (e, st) {
      if (e.runtimeType.toString() == 'LateError') {
        debugPrint('Notifications unavailable in this runtime: $e');
      } else {
        AppError.log(e, stackTrace: st, source: 'RoutesTab._initNotifications');
      }
    }
  }

  @override
  void dispose() {
    _jointHeaderController.dispose();
    _fromController.dispose();
    _toController.dispose();
    _friendOriginController.dispose();
    _fromFocusNode.dispose();
    _toFocusNode.dispose();
    _friendOriginFocusNode.dispose();
    _scrollController.dispose();
    _suggestionsScrollController.dispose();
    for (final controller in _routeResultsScrollControllers.values) {
      controller.dispose();
    }
    for (final controller in _activeJourneyScrollControllers.values) {
      controller.dispose();
    }
    _debounce?.cancel();
    _focusDebounce?.cancel();
    _gpsStream?.cancel();
    _sharingGpsStream?.cancel();
    _journeyDetectionTimer?.cancel();
    _activeJourneyRefreshTimer?.cancel();
    for (final timer in _savedJourneyReminderTimers.values) {
      timer.cancel();
    }
    _savedJourneyReminderTimers.clear();
    _savedJourneyLiveCountdownTicker?.cancel();
    _savedJourneyLiveCountdownTicker = null;
    _savedJourneyStatusPollTimer?.cancel();
    _savedJourneyStatusPollTimer = null;
    SupabaseService.settingsRefreshNotifier
        .removeListener(_handleDeviceRouteSettingsRefresh);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  List<JourneyDetectionCandidate> _journeyDetectionCandidates() {
    return journeyDetectionCandidates(
      tabs: _tabs,
      savedCandidates: _savedDetectionCandidates,
      suppressedKeys: _suppressedDetectionKeys,
    );
  }

  /// Saved journeys cost a full parse each, so they are rebuilt when the saved
  /// list changes rather than on every position update.
  void _rebuildSavedDetectionCandidates() {
    _savedDetectionCandidates = savedJourneyDetectionCandidates(
      _savedJourneys,
      (rawJourney, destinationName) {
        try {
          return _createJourney(
            rawJourney,
            destinationNameOverride: destinationName,
          );
        } catch (_) {
          // A saved entry from an older format is simply not a candidate.
          return null;
        }
      },
    );
  }

  Future<void> _updateJourneyDetectionMonitoring() async {
    if (!mounted || _maximumEffectiveSignalLevel <= 0) return;
    final now = DateTime.now();
    final detected = _detectedJourney;
    if (detected != null &&
        now.isAfter(detected.journey.arrival
            .add(JourneyDetectionService.arrivalGrace))) {
      _detectedJourney = null;
      _detectedDestinationName = null;
      await SupabaseService.clearPublishedJourney();
    }

    final shouldMonitor = _detectedJourney != null ||
        _journeyDetectionCandidates().any(
          (candidate) => JourneyDetectionService.isInMonitoringWindow(
            candidate.journey,
            now,
          ),
        );
    if (!shouldMonitor) {
      await _sharingGpsStream?.cancel();
      _sharingGpsStream = null;
      return;
    }
    if (_gpsStream != null) return;
    // Level 7/8 already has the low-power app-wide location stream. Its
    // positions arrive through didUpdateWidget, so starting another stream
    // here would only waste battery.
    if (_maximumEffectiveSignalLevel >= 7) return;
    if (_sharingGpsStream != null) return;
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    LocationSettings settings = const LocationSettings(
      accuracy: LocationAccuracy.medium,
      distanceFilter: 120,
    );
    if (defaultTargetPlatform == TargetPlatform.android) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 120,
        intervalDuration: const Duration(seconds: 45),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Privacy Level',
          notificationText: 'Checking for your current journey',
          notificationIcon: AndroidResource(name: 'ic_launcher'),
          enableWakeLock: false,
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.medium,
        activityType: ActivityType.otherNavigation,
        distanceFilter: 120,
        pauseLocationUpdatesAutomatically: true,
        showBackgroundLocationIndicator: _maximumEffectiveSignalLevel >= 6,
      );
    }
    _sharingGpsStream =
        Geolocator.getPositionStream(locationSettings: settings).listen(
      (position) => unawaited(_handleJourneyDetectionPosition(position)),
      onError: (Object error, StackTrace stackTrace) {
        AppError.log(error,
            stackTrace: stackTrace, source: 'Privacy Level GPS');
        _sharingGpsStream?.cancel();
        _sharingGpsStream = null;
      },
    );
  }

  Future<void> _handleJourneyDetectionPosition(Position position) async {
    if (!mounted || _maximumEffectiveSignalLevel <= 0) return;
    final now = DateTime.now();
    var match = _detectedJourney;
    if (match == null) {
      final ranked = JourneyDetectionService.rankCandidates(
        candidates: _journeyDetectionCandidates(),
        now: now,
        latitude: position.latitude,
        longitude: position.longitude,
      );
      if (!JourneyDetectionService.isConfident(ranked)) {
        _pendingDetectionKey = null;
        _pendingDetectionSamples = 0;
        return;
      }
      final best = ranked.first;
      if (_pendingDetectionKey == best.key) {
        _pendingDetectionSamples++;
      } else {
        _pendingDetectionKey = best.key;
        _pendingDetectionSamples = 1;
      }
      if (_pendingDetectionSamples < 2) return;
      match = best;
      _detectedJourney = best;
      _detectedDestinationName = best.destinationName;
      _pendingDetectionKey = null;
      _pendingDetectionSamples = 0;
      _detectedMismatchSamples = 0;
    } else {
      final reranked = JourneyDetectionService.rankCandidates(
        candidates: [match.candidate],
        now: now,
        latitude: position.latitude,
        longitude: position.longitude,
      );
      if (reranked.isNotEmpty) {
        if (reranked.first.score < 0.25) {
          _detectedMismatchSamples++;
        } else {
          _detectedMismatchSamples = 0;
          match = reranked.first;
          _detectedJourney = match;
        }
      } else {
        _detectedMismatchSamples++;
      }
      if (_detectedMismatchSamples >= 3) {
        _suppressedDetectionKeys.add(match.key);
        _detectedJourney = null;
        _detectedDestinationName = null;
        _detectedMismatchSamples = 0;
        await SupabaseService.clearPublishedJourney();
        await _updateJourneyDetectionMonitoring();
        return;
      }
    }

    // The candidate carries its own destination, so a detected journey keeps
    // publishing even after its tab is closed.
    _detectedDestinationName = match.destinationName;
    final destinationName = _detectedDestinationName;
    if (destinationName == null || destinationName.isEmpty) return;
    final currentLine = match.currentRide?.line;
    await SupabaseService.publishJourneyPresence({
      'journey_id': match.key,
      'is_active': true,
      if (currentLine != null && currentLine.trim().isNotEmpty)
        'current_line': currentLine,
      'departure_at': match.journey.departure.toUtc().toIso8601String(),
      'arrival_at': match.journey.arrival.toUtc().toIso8601String(),
      'destination_name': destinationName,
      'itinerary': JourneyDetectionService.sanitizedItinerary(match.journey),
      'progress': match.progress,
      'progress_label': JourneyDetectionService.progressLabel(match),
      'line_expires_at':
          now.toUtc().add(const Duration(minutes: 30)).toIso8601String(),
      'journey_expires_at': match.journey.arrival
          .toUtc()
          .add(JourneyDetectionService.arrivalGrace)
          .toIso8601String(),
      if (_maximumEffectiveSignalLevel >= 6) 'latitude': position.latitude,
      if (_maximumEffectiveSignalLevel >= 6) 'longitude': position.longitude,
      if (_maximumEffectiveSignalLevel >= 6) 'accuracy_m': position.accuracy,
      if (_maximumEffectiveSignalLevel >= 6) 'location_is_journey': true,
    });
  }

  /// Handles the back button press.
  /// Returns true if the back navigation was handled internally (e.g., closing a route tab),
  /// and false otherwise (which should presumably trigger the app exit dialog).
  bool handleBack() {
    if (_activeTabId != null) {
      final idx = _tabs.indexWhere((t) => t.id == _activeTabId);
      if (idx != -1) {
        final currentTab = _tabs[idx];
        // If we are looking at a specific journey (details view), go back to list
        if (currentTab.activeJourney != null) {
          setState(() {
            _tabs[idx] = currentTab.copyWith(clearActiveJourney: true);
          });
          return true;
        }
      }

      // If we are at the list view (or no active journey), close the tab
      _closeTab(_activeTabId!);
      return true;
    }
    // Check if search suggestions are open, maybe close them?
    // For now, let's say if suggestions are open, we just close them.
    if (_activeSearchField.isNotEmpty || _suggestions.isNotEmpty) {
      _collapseSearchSuggestions();
      return true;
    }

    return false;
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final bottomInset = View.of(context).viewInsets.bottom;
    final isVisible = bottomInset > 0;
    if (!_wasKeyboardVisible &&
        isVisible &&
        _activeTabId == null &&
        _activeSearchField.isNotEmpty) {
      _scrollFocusedFieldIntoViewIfNeeded();
    }
    if (_wasKeyboardVisible && !isVisible) {
      // Keyboard JUST closed
      if (_fromFocusNode.hasFocus ||
          _toFocusNode.hasFocus ||
          _friendOriginFocusNode.hasFocus) {
        FocusScope.of(context).unfocus();
      }
    }
    _wasKeyboardVisible = isVisible;
  }

  void _scrollToTop() {
    if (_fromFocusNode.hasFocus ||
        _toFocusNode.hasFocus ||
        _friendOriginFocusNode.hasFocus) {
      _scrollFocusedFieldIntoViewIfNeeded();
      return;
    }
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(0.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut);
      }
    });
  }

  /// Gives the focused field room for its suggestion list on compact screens.
  /// Large viewports already have that room, so their scroll position is left
  /// untouched.
  void _scrollFocusedFieldIntoViewIfNeeded() {
    final fieldKey = _fromFocusNode.hasFocus
        ? _fromFieldKey
        : _friendOriginFocusNode.hasFocus
            ? _friendFieldKey
            : _toFieldKey;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (!_fromFocusNode.hasFocus &&
          !_toFocusNode.hasFocus &&
          !_friendOriginFocusNode.hasFocus) {
        return;
      }

      final fieldContext = fieldKey.currentContext;
      final viewportContext = _scrollController.position.context.storageContext;
      if (fieldContext == null) return;

      final fieldBox = fieldContext.findRenderObject() as RenderBox?;
      final viewportBox = viewportContext.findRenderObject() as RenderBox?;
      if (fieldBox == null || viewportBox == null) return;

      final fieldBottom = fieldBox
          .localToGlobal(
            Offset(0, fieldBox.size.height),
          )
          .dy;
      final viewportBottom = viewportBox
          .localToGlobal(
            Offset(0, viewportBox.size.height),
          )
          .dy;

      // Suggestions are capped at 250 px; reserve that space below the
      // field so the user can type and choose a result without extra scrolls.
      const suggestionRoom = 250.0;
      if (viewportBottom - fieldBottom >= suggestionRoom) return;

      Scrollable.ensureVisible(
        fieldContext,
        alignment: 0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _collapseSearchSuggestions() {
    _suggestionRequestToken++;
    _debounce?.cancel();
    setState(() {
      _activeSearchField = '';
      _suggestions = [];
      _isSuggestionsLoading = false;
    });
    FocusScope.of(context).unfocus();
  }

  void _scrollSuggestionsToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_suggestionsScrollController.hasClients) {
        _suggestionsScrollController.jumpTo(0.0);
      }
    });
  }

  IconData _favoriteIcon(Favorite favorite) {
    return resolveFavoriteIcon(favorite);
  }

  Future<void> _loadFavorites() async {
    final favs = await FavoritesManager.getFavorites();
    final sharedPlaces = <Station>[];
    if (SupabaseService.currentUser != null) {
      final friends = await SupabaseService.getFriends();
      for (final friend in friends) {
        final username = friend['username']?.toString() ?? 'Friend';
        final latitude = friend['latitude'];
        final longitude = friend['longitude'];
        if (latitude is num && longitude is num) {
          sharedPlaces.add(Station(
            id: 'friend:${friend['id']}',
            name: username,
            type: 'location',
            latitude: latitude.toDouble(),
            longitude: longitude.toDouble(),
          ));
        }
        final favorites = friend['shared_favorites'];
        if (favorites is! List) continue;
        for (final raw in favorites) {
          if (raw is! Map || raw['station'] is! Map) continue;
          try {
            final station = Station.fromJson(
              Map<String, dynamic>.from(raw['station'] as Map),
            );
            sharedPlaces.add(Station(
              id: 'friend-favorite:${friend['id']}:${raw['id']}',
              name: '$username · ${raw['label'] ?? station.name}',
              type: station.type,
              latitude: station.latitude,
              longitude: station.longitude,
            ));
          } catch (_) {}
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _favorites = favs;
      _sharedFriendPlaces = sharedPlaces;
    });
  }

  bool _isRouteSearchCancelled(int token) =>
      _cancelledRouteSearchTokens.contains(token);

  void _releaseBlockingRouteLoad(int token) {
    if (!mounted || _activeRouteSearchToken != token || !_isLoadingRoute) {
      return;
    }
    setState(() {
      _isLoadingRoute = false;
    });
  }

  void _cancelActiveBackgroundRouteSearch() {
    final token = _activeRouteSearchToken;
    if (token == null || _isLoadingRoute) return;
    _cancelledRouteSearchTokens.add(token);
    if (!mounted) return;
    setState(() {
      _activeRouteSearchToken = null;
      _activeRouteLoadPhases = <String>{};
    });
  }

  void _setRouteLoadPhasesForToken(int token, Set<String> phases) {
    if (!mounted ||
        _activeRouteSearchToken != token ||
        _isRouteSearchCancelled(token)) {
      return;
    }
    setState(() => _activeRouteLoadPhases = phases);
  }

  Color _routeLoadingColor(TransColors colors) {
    if (_activeRouteLoadPhases.contains(TransportApi.loadPhaseSynthetic)) {
      return Colors.green;
    }
    if (_activeRouteLoadPhases.contains(TransportApi.loadPhaseMotis)) {
      return Colors.blue;
    }
    if (_activeRouteLoadPhases.contains(TransportApi.loadPhaseV6)) {
      return Colors.red;
    }
    return colors.searchBtnText;
  }

  void _disposeRouteSearch(int token) {
    _cancelledRouteSearchTokens.remove(token);
    if (!mounted || _activeRouteSearchToken != token) return;
    setState(() {
      _activeRouteSearchToken = null;
      _isLoadingRoute = false;
      _activeRouteLoadPhases = <String>{};
    });
  }

  Future<void> _copySyntheticDebugLogs() async {
    final logText = TransportApi.syntheticDebugLogText();
    await Clipboard.setData(ClipboardData(text: logText));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Synthetic debug logs copied'),
      duration: Duration(seconds: 2),
    ));
  }

  Future<void> _showPlatformLookupDialog() async {
    final stationController = TextEditingController(
      text: _fromStation?.name ?? _fromController.text.trim(),
    );
    final lineController = TextEditingController();
    var expectedTime = _selectedDate != null
        ? DateTime(
            _selectedDate!.year,
            _selectedDate!.month,
            _selectedDate!.day,
            _selectedTime?.hour ?? TimeOfDay.now().hour,
            _selectedTime?.minute ?? TimeOfDay.now().minute,
          )
        : DateTime.now();
    var arrivals = false;
    var isLoading = false;
    String? resultText;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> runLookup() async {
              final station = stationController.text.trim();
              final line = lineController.text.trim();
              if (station.isEmpty || line.isEmpty) {
                setDialogState(() {
                  resultText = 'Enter both station and train/line.';
                });
                return;
              }
              setDialogState(() {
                isLoading = true;
                resultText = null;
              });
              try {
                final result = await TransportApi.debugLookupBahnPlatform(
                  stationName: station,
                  lineName: line,
                  expectedTime: expectedTime,
                  arrivals: arrivals,
                );
                const encoder = JsonEncoder.withIndent('  ');
                setDialogState(() {
                  resultText = encoder.convert(result);
                });
              } catch (error) {
                setDialogState(() {
                  resultText = 'Lookup failed: $error';
                });
              } finally {
                setDialogState(() => isLoading = false);
              }
            }

            return AlertDialog(
              title: const Text('Platform Check'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: stationController,
                        decoration: const InputDecoration(
                          labelText: 'Station',
                          hintText: 'Erfurt Hbf',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: lineController,
                        decoration: const InputDecoration(
                          labelText: 'Train / line',
                          hintText: 'ICE 697 or RE3 (3916)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              DateFormat('yyyy-MM-dd HH:mm')
                                  .format(expectedTime),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              final pickedDate = await showDatePicker(
                                context: context,
                                initialDate: expectedTime,
                                firstDate: DateTime.now()
                                    .subtract(const Duration(days: 30)),
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 90)),
                              );
                              if (pickedDate == null || !context.mounted) {
                                return;
                              }
                              final pickedTime = await showTimePicker(
                                context: context,
                                initialTime:
                                    TimeOfDay.fromDateTime(expectedTime),
                              );
                              if (pickedTime == null) return;
                              setDialogState(() {
                                expectedTime = DateTime(
                                  pickedDate.year,
                                  pickedDate.month,
                                  pickedDate.day,
                                  pickedTime.hour,
                                  pickedTime.minute,
                                );
                              });
                            },
                            icon: const Icon(Icons.schedule, size: 18),
                            label: const Text('Time'),
                          ),
                        ],
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                            arrivals ? 'Arrival board' : 'Departure board'),
                        value: arrivals,
                        onChanged: (value) =>
                            setDialogState(() => arrivals = value),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: isLoading ? null : runLookup,
                        icon: isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.search),
                        label: Text(isLoading ? 'Checking...' : 'Check'),
                      ),
                      if (resultText != null) ...[
                        const SizedBox(height: 12),
                        SelectableText(
                          resultText!,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _cancelRouteSearch() {
    final token = _activeRouteSearchToken;
    if (token == null) return;
    _cancelledRouteSearchTokens.add(token);
    if (!mounted) return;
    setState(() {
      _activeRouteSearchToken = null;
      _isLoadingRoute = false;
      _activeRouteLoadPhases = <String>{};
    });
  }

  void _showRouteRefreshToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showStopDeparturesForStop({
    required String stopId,
    required String stopName,
    required DateTime date,
    String? preferredPlatform,
  }) async {
    _cancelRouteSearch();
    await StopDeparturesSheet.show(
      context,
      stopId: stopId,
      stopName: stopName,
      date: date,
      preferredPlatform: preferredPlatform,
    );
  }

  // --- WAKE ALARM LOGIC ---
  void _toggleStepAlarm(RouteTab route, JourneyStep step) {
    if (route.activeJourney == null) return;

    final updatedSteps = route.activeJourney!.steps.map((s) {
      if (s == step) {
        return s.copyWith(
          isWakeAlarmOn: !s.isWakeAlarmOn,
          clearAlarmTarget: true,
        );
      }
      return s;
    }).toList();

    final updatedJourney = route.activeJourney!.copyWith(steps: updatedSteps);

    setState(() {
      final idx = _tabs.indexWhere((t) => t.id == route.id);
      if (idx != -1) {
        _tabs[idx] =
            route.copyWith(activeJourney: updatedJourney, steps: updatedSteps);
      }
    });

    // Check if we need to start/stop the global alarm tracking
    bool anyAlarmOn = updatedSteps.any((s) => s.isWakeAlarmOn);
    if (anyAlarmOn && !_isWakeAlarmSet) {
      _startWakeAlarm(route);
    } else if (!anyAlarmOn && _isWakeAlarmSet) {
      _stopWakeAlarm();
    }
  }

  bool _coordsMatch(double? firstLat, double? firstLng, double? secondLat,
      double? secondLng) {
    if (firstLat == null ||
        firstLng == null ||
        secondLat == null ||
        secondLng == null) {
      return false;
    }
    const epsilon = 0.00001;
    return (firstLat - secondLat).abs() < epsilon &&
        (firstLng - secondLng).abs() < epsilon;
  }

  bool _isIntermediateAlarmSelectedForStep(
    JourneyStep step, {
    required int stopIndex,
    required String stopName,
    required double? targetLat,
    required double? targetLng,
  }) {
    if (!step.isWakeAlarmOn) return false;

    if (step.alarmTargetName != null) {
      if (_coordsMatch(
        step.alarmTargetLat,
        step.alarmTargetLng,
        targetLat,
        targetLng,
      )) {
        return true;
      }
      return step.alarmTargetName == stopName;
    }

    if (_alarmStopsBefore <= 0) return false;
    final stopovers = step.stopovers;
    if (stopovers == null || stopovers.isEmpty) return false;
    final targetIndex = stopovers.length - _alarmStopsBefore;
    return stopIndex == targetIndex;
  }

  void _toggleIntermediateStopAlarm(
    RouteTab route,
    JourneyStep step, {
    required int stopIndex,
    required String stopName,
    required double? targetLat,
    required double? targetLng,
    required double? originLat,
    required double? originLng,
  }) {
    final isSelected = _isIntermediateAlarmSelectedForStep(
      step,
      stopIndex: stopIndex,
      stopName: stopName,
      targetLat: targetLat,
      targetLng: targetLng,
    );

    if (isSelected) {
      _toggleStepAlarm(route, step);
      return;
    }

    _setIntermediateStopAlarm(
      route,
      step,
      stopName: stopName,
      targetLat: targetLat,
      targetLng: targetLng,
      originLat: originLat,
      originLng: originLng,
    );
  }

  void _setIntermediateStopAlarm(
    RouteTab route,
    JourneyStep step, {
    required String stopName,
    required double? targetLat,
    required double? targetLng,
    required double? originLat,
    required double? originLng,
  }) {
    if (route.activeJourney == null) return;
    final l10n = AppLocalizations.of(context)!;

    if (targetLat == null || targetLng == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.missingDestCoords)));
      return;
    }

    final updatedSteps = route.activeJourney!.steps.map((s) {
      if (s == step) {
        return s.copyWith(
          isWakeAlarmOn: true,
          alarmTargetName: stopName,
          alarmTargetLat: targetLat,
          alarmTargetLng: targetLng,
          alarmTargetOriginLat: originLat,
          alarmTargetOriginLng: originLng,
        );
      }
      return s;
    }).toList();

    final updatedJourney = route.activeJourney!.copyWith(steps: updatedSteps);

    setState(() {
      final idx = _tabs.indexWhere((t) => t.id == route.id);
      if (idx != -1) {
        _tabs[idx] =
            route.copyWith(activeJourney: updatedJourney, steps: updatedSteps);
      }
    });

    if (!_isWakeAlarmSet) {
      _startWakeAlarm(route);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text(AppLocalizations.of(context)!.wakeAlertSetFor(stopName))),
    );
  }

  void _stopWakeAlarm() {
    _gpsStream?.cancel();
    _gpsStream = null;
    widget.onHighAccuracyTrackingChanged(false);
    SupabaseService.clearJourneyStatus();
    unawaited(_updateJourneyDetectionMonitoring());
    if (mounted) setState(() => _isWakeAlarmSet = false);
  }

  Future<void> _startWakeAlarm(RouteTab route) async {
    if (route.steps.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;

    // 1. Request Permissions
    await NotificationManager.requestPermissions();
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.locationPermissionDenied)));
        }
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.locationPermissionPermanentlyDenied)));
      }
      return;
    }

    final firstRide = route.steps
        .firstWhere((s) => s.type == 'ride', orElse: () => route.steps.first);

    double? targetLat = firstRide.endLat;
    double? targetLng = firstRide.endLng;

    if (targetLat == null || targetLng == null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.missingDestCoords)));
      }
      return;
    }

    if (mounted) {
      setState(() => _isWakeAlarmSet = true);
    }
    widget.onHighAccuracyTrackingChanged(true);
    await _sharingGpsStream?.cancel();
    _sharingGpsStream = null;

    // 2a. Recreate the wake alarm notification channel with the user's
    //     custom vibration pattern. On Android 8.0+ the vibration pattern
    //     must be registered on the channel; per-notification overrides are
    //     ignored. Deleting and recreating the channel is the only reliable
    //     way to apply the user's choice so background notifications vibrate
    //     correctly even when the screen is off.
    {
      final prefs = await SharedPreferences.getInstance();
      final patternName = prefs.getString('vibration_pattern') ?? 'standard';
      final soundId = prefs.getString(WakeAlarmSettings.soundPreferenceKey) ??
          WakeAlarmSettings.defaultSoundId;
      final wakeSoundEnabled =
          prefs.getBool(WakeAlarmSettings.wakeSoundEnabledPreferenceKey) ??
              true;
      final wakeVibrationEnabled =
          prefs.getBool(WakeAlarmSettings.wakeVibrationEnabledPreferenceKey) ??
              true;
      await NotificationManager.updateWakeAlarmChannel(
        WakeAlarmSettings.vibrationPatternForId(patternName),
        soundId: soundId,
        soundEnabled: wakeSoundEnabled,
        vibrationEnabled: wakeVibrationEnabled,
      );
    }

    // 3. Configure Background Location (Foreground Service)
    AndroidSettings androidSettings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 50,
      forceLocationManager: true,
      intervalDuration: const Duration(seconds: 10),
      // Foreground Notification to keep service alive
      foregroundNotificationConfig: ForegroundNotificationConfig(
        notificationTitle: l10n.wakeAlarmTitle,
        notificationText: l10n.wakeAlarmTracking,
        notificationIcon: AndroidResource(name: 'ic_launcher'),
        enableWakeLock: true,
      ),
    );

    AppleSettings appleSettings = AppleSettings(
      accuracy: LocationAccuracy.high,
      activityType: ActivityType.fitness,
      distanceFilter: 50,
      pauseLocationUpdatesAutomatically: false,
      showBackgroundLocationIndicator: true,
    );

    const LocationSettings settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 50,
    );

    LocationSettings activeSettings = settings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      activeSettings = androidSettings;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      activeSettings = appleSettings;
    }

    if (_effectiveCurrentPosition != null) {
      // We don't have a single "currentLine" anymore since multiple legs might be active
      SupabaseService.updateLocation(_effectiveCurrentPosition!);
    }

    _gpsStream = Geolocator.getPositionStream(locationSettings: activeSettings)
        .listen((Position pos) async {
      if (mounted) setState(() => _gpsAccuracy = pos.accuracy);
      SupabaseService.updateLocation(pos);
      unawaited(_handleJourneyDetectionPosition(pos));

      // Get the currently active route and its enabled alarm steps
      final idx = _tabs.indexWhere((t) => t.id == route.id);
      if (idx == -1) {
        _stopWakeAlarm();
        return;
      }
      final currentTab = _tabs[idx];
      if (currentTab.activeJourney == null) {
        _stopWakeAlarm();
        return;
      }

      final alarmSteps = currentTab.activeJourney!.steps
          .where((s) => s.isWakeAlarmOn)
          .toList();
      if (alarmSteps.isEmpty) {
        _stopWakeAlarm();
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final int stopsBefore = prefs.getInt('alarm_stops_before') ?? 1;

      final String thresholdSetting =
          prefs.getString('alarm_trigger_threshold') ?? '5%';

      bool triggered = false;
      List<JourneyStep> remainingSteps =
          List.from(currentTab.activeJourney!.steps);

      for (var step in alarmSteps) {
        double? targetLat = step.endLat;
        double? targetLng = step.endLng;
        double? originLat = step.startLat;
        double? originLng = step.startLng;

        if (step.alarmTargetLat != null && step.alarmTargetLng != null) {
          targetLat = step.alarmTargetLat;
          targetLng = step.alarmTargetLng;
          originLat = step.alarmTargetOriginLat ?? originLat;
          originLng = step.alarmTargetOriginLng ?? originLng;
        } else if (step.stopovers != null && step.stopovers!.isNotEmpty) {
          final stops = step.stopovers!;
          if (stopsBefore > 0) {
            int targetIndex = stops.length - stopsBefore;
            if (targetIndex >= 0) {
              final stopData = stops[targetIndex];
              if (stopData['stop'] != null &&
                  stopData['stop']['location'] != null) {
                targetLat = stopData['stop']['location']['latitude'];
                targetLng = stopData['stop']['location']['longitude'];

                // Origin of this segment
                if (targetIndex > 0) {
                  final originData = stops[targetIndex - 1];
                  originLat = originData['stop']?['location']?['latitude'];
                  originLng = originData['stop']?['location']?['longitude'];
                }
              }
            }
          } else {
            // stopsBefore == 0, target is destination, origin is the last stopover
            final originData = stops.last;
            originLat = originData['stop']?['location']?['latitude'];
            originLng = originData['stop']?['location']?['longitude'];
          }
        }

        if (targetLat == null || targetLng == null) continue;

        double dist = Geolocator.distanceBetween(
            pos.latitude, pos.longitude, targetLat, targetLng);

        // Calculate trigger distance logic
        double triggerDist = 500; // Default fallback
        if (thresholdSetting.endsWith('m')) {
          // Fixed distance mode (e.g. "500m")
          try {
            triggerDist = double.parse(thresholdSetting.replaceAll('m', ''));
          } catch (e) {
            triggerDist = 500; // Fallback if parse fails
          }
        } else {
          // Percentage mode
          if (originLat != null && originLng != null) {
            double segmentDist = Geolocator.distanceBetween(
                originLat, originLng, targetLat, targetLng);
            double percentValue = 5;
            try {
              percentValue = double.parse(thresholdSetting.replaceAll('%', ''));
            } catch (e) {/* ignore */}
            triggerDist = segmentDist * (percentValue / 100.0);
          }
        }

        if (dist <= triggerDist) {
          _triggerVibration();
          _showNotification();
          triggered = true;
          final triggerStopName =
              step.alarmTargetName ?? step.destinationName ?? 'your stop';

          // Turn off alarm for THIS step
          int stepIdx = remainingSteps.indexOf(step);
          if (stepIdx != -1) {
            remainingSteps[stepIdx] = step.copyWith(
              isWakeAlarmOn: false,
              clearAlarmTarget: true,
            );
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(AppLocalizations.of(context)!
                    .wakeUpApproaching(triggerStopName)),
                backgroundColor: Colors.red));
          }
        }
      }

      if (triggered) {
        setState(() {
          final newJourney =
              currentTab.activeJourney!.copyWith(steps: remainingSteps);
          _tabs[idx] = currentTab.copyWith(
              activeJourney: newJourney, steps: remainingSteps);
        });

        // If no more alarms, stop tracking
        if (!remainingSteps.any((s) => s.isWakeAlarmOn)) {
          _stopWakeAlarm();
        }
      }
    });
  }

  void _openMap(RouteTab route, {JourneyStep? focusStep}) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => MapScreen(
                steps: route.steps,
                focusStep: focusStep,
                currentPosition: _effectiveCurrentPosition)));
  }

  // --- SEARCH LOGIC ---
  Future<void> _fetchSuggestions({
    bool forceHistory = false,
    bool updateLoadingState = true,
  }) async {
    if (forceHistory) {
      final history = await SearchHistoryManager.getHistory();
      if (mounted) {
        setState(() {
          // Friends who share a location head the list of the companion field,
          // so tapping it is enough to see who can be picked.
          _suggestions = <dynamic>[
            if (_activeSearchField == 'friend') ..._friendOriginSuggestions(''),
            ...history,
          ];
          if (updateLoadingState) _isSuggestionsLoading = false;
        });
      }
      return;
    }
    if (updateLoadingState) {
      setState(() => _isSuggestionsLoading = true);
    }
    List<dynamic> results = [];
    final query = _controllerForField(_activeSearchField).text.trim();
    if (query.isNotEmpty || _activeSearchField == 'friend') {
      results.addAll(_localMatchesForField(_activeSearchField, query));
    }
    final history = await SearchHistoryManager.getHistory();
    if (history.isNotEmpty) {
      if (query.isNotEmpty) {
        results.addAll(history
            .where((s) => s.name.toLowerCase().contains(query.toLowerCase())));
      } else {
        results.addAll(history);
      }
    }
    if (mounted) {
      setState(() {
        _suggestions = results;
        if (updateLoadingState) _isSuggestionsLoading = false;
      });
    }
  }

  bool _favoriteMatchesQuery(Favorite favorite, String queryLower) {
    final label = favorite.label.toLowerCase();
    final stationName = favorite.station?.name.toLowerCase() ?? '';
    return label.contains(queryLower) || stationName.contains(queryLower);
  }

  List<Favorite> _matchingFavoritesForQuery(String query) {
    final queryLower = query.toLowerCase();
    return _favorites
        .where((favorite) => _favoriteMatchesQuery(favorite, queryLower))
        .toList();
  }

  List<Station> _matchingSharedFriendPlaces(String query) {
    final queryLower = query.toLowerCase();
    return _sharedFriendPlaces
        .where((place) => place.name.toLowerCase().contains(queryLower))
        .toList();
  }

  TextEditingController _controllerForField(String field) => switch (field) {
        'from' => _fromController,
        'friend' => _friendOriginController,
        _ => _toController,
      };

  /// Friends who share a location show up as places, so the companion's start
  /// can be picked by typing their name just like any station.
  List<Station> _friendOriginSuggestions(String query) {
    return _matchingJointFriends(query)
        .map((friend) => friend.toOriginStation())
        .whereType<Station>()
        .toList();
  }

  /// Matches that need no network round trip, in the order they are shown.
  List<dynamic> _localMatchesForField(String field, String query) => <dynamic>[
        if (field == 'friend') ..._friendOriginSuggestions(query),
        ..._matchingFavoritesForQuery(query),
        ..._matchingSharedFriendPlaces(query),
      ];

  ({double? lat, double? lng}) _suggestionReferencePoint() {
    double? refLat;
    double? refLng;

    if (_activeSearchField == 'from') {
      if (_toStation != null &&
          _toStation!.latitude != null &&
          _toStation!.longitude != null) {
        refLat = _toStation!.latitude;
        refLng = _toStation!.longitude;
      } else if (_effectiveCurrentPosition != null) {
        refLat = _effectiveCurrentPosition!.latitude;
        refLng = _effectiveCurrentPosition!.longitude;
      }
    } else if (_activeSearchField == 'to' || _activeSearchField == 'friend') {
      if (_fromStation != null &&
          _fromStation!.latitude != null &&
          _fromStation!.longitude != null) {
        refLat = _fromStation!.latitude;
        refLng = _fromStation!.longitude;
      } else if (_effectiveCurrentPosition != null) {
        refLat = _effectiveCurrentPosition!.latitude;
        refLng = _effectiveCurrentPosition!.longitude;
      }
    }

    return (lat: refLat, lng: refLng);
  }

  String? _distanceTextForStation(Station station) {
    final ref = _suggestionReferencePoint();
    if (ref.lat == null ||
        ref.lng == null ||
        station.latitude == null ||
        station.longitude == null) {
      return null;
    }

    final distInMeters = Geolocator.distanceBetween(
        ref.lat!, ref.lng!, station.latitude!, station.longitude!);
    final distInKm = distInMeters / 1000.0;
    return "${distInKm.toStringAsFixed(1)} km";
  }

  List<_SuggestionSection> _buildSuggestionSections() {
    final favorites = <Favorite>[];
    final stations = <Station>[];

    for (final item in _suggestions) {
      if (item is Favorite) {
        favorites.add(item);
      } else if (item is Station) {
        stations.add(item);
      }
    }

    final sections = <_SuggestionSection>[];
    if (favorites.isNotEmpty) {
      sections.add(_SuggestionSection(items: favorites));
    }

    for (final station in stations) {
      final city = station.cityGroupLabel;
      final existingSectionIndex = sections.indexWhere(
        (section) => section.title == city,
      );
      if (existingSectionIndex >= 0) {
        sections[existingSectionIndex].items.add(station);
      } else {
        sections
            .add(_SuggestionSection(title: city, items: <dynamic>[station]));
      }
    }

    return sections;
  }

  void _onSearchChanged(String query, String field) {
    final sanitizedQuery = query.trim();
    if (field == 'to') _toIsCapturedCurrentLocation = false;
    setState(() => _activeSearchField = field);
    _scrollToTop();
    _scrollSuggestionsToTop();
    if (sanitizedQuery.isEmpty) {
      _suggestionRequestToken++;
      _fetchSuggestions(forceHistory: true, updateLoadingState: false);
      if (field == 'from') {
        setState(() {
          _fromStation = null;
          _fromUsesCurrentLocation = true;
          _isSuggestionsLoading = false;
        });
        return;
      } else if (field == 'to') {
        setState(() {
          _toStation = null;
          _isSuggestionsLoading = false;
        });
        return;
      } else if (field == 'friend') {
        setState(() {
          _friendOriginStation = null;
          _selectedJointFriend = null;
          _isSuggestionsLoading = false;
        });
        return;
      }
      return;
    }
    if (field == 'from') {
      setState(() {
        _fromStation = null;
        _fromUsesCurrentLocation = _isCurrentLocationText(sanitizedQuery);
      });
    } else if (field == 'friend') {
      setState(() {
        _friendOriginStation = null;
        _selectedJointFriend = null;
      });
    }
    setState(() {
      _suggestions = _localMatchesForField(field, sanitizedQuery);
      _isSuggestionsLoading = sanitizedQuery.length > 2;
    });
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    if (sanitizedQuery.length <= 2) {
      return;
    }
    final requestToken = ++_suggestionRequestToken;
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      double? refLat;
      double? refLng;

      if (field == 'from') {
        if (_toStation != null &&
            _toStation!.latitude != null &&
            _toStation!.longitude != null) {
          refLat = _toStation!.latitude;
          refLng = _toStation!.longitude;
        } else if (_effectiveCurrentPosition != null) {
          refLat = _effectiveCurrentPosition!.latitude;
          refLng = _effectiveCurrentPosition!.longitude;
        }
      } else if (field == 'to' || field == 'friend') {
        if (_fromStation != null &&
            _fromStation!.latitude != null &&
            _fromStation!.longitude != null) {
          refLat = _fromStation!.latitude;
          refLng = _fromStation!.longitude;
        } else if (_effectiveCurrentPosition != null) {
          refLat = _effectiveCurrentPosition!.latitude;
          refLng = _effectiveCurrentPosition!.longitude;
        }
      }

      try {
        final apiResults = await TransportApi.searchStations(
          sanitizedQuery,
          lat: refLat,
          lng: refLng,
          limit: 60,
        );
        if (!mounted || requestToken != _suggestionRequestToken) return;
        final localMatches = _localMatchesForField(field, sanitizedQuery);
        if (mounted) {
          setState(() {
            if (apiResults.isEmpty && localMatches.isEmpty) {
              // Show message if no results at all
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content:
                      Text(AppLocalizations.of(context)!.serviceBusyTryAgain),
                  duration: const Duration(seconds: 2)));
            }
            _suggestions = <dynamic>[
              ...localMatches,
              ...apiResults,
            ];
            _isSuggestionsLoading = false;
          });
        }
      } catch (e) {
        if (!mounted || requestToken != _suggestionRequestToken) return;
        if (mounted) {
          setState(() => _isSuggestionsLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:
                  Text(AppLocalizations.of(context)!.serviceBusyPleaseTryAgain),
              duration: const Duration(seconds: 2)));
        }
      }
    });
  }

  void _selectItem(dynamic item) {
    if (item is Station) {
      _selectStation(item);
    } else if (item is Favorite) {
      _onFavoriteTap(item);
    }
  }

  void _selectStation(Station station) {
    if (_activeSearchField == 'friend') {
      _selectFriendOriginStation(station);
      return;
    }
    SearchHistoryManager.saveStation(station);
    setState(() {
      if (_activeSearchField == 'from') {
        _fromStation = station;
        _fromUsesCurrentLocation = false;
        _fromController.text = station.name;
        if (_toStation == null) {
          _activeSearchField = 'to';
          _suggestions = [];
          _toFocusNode.requestFocus();
          _scrollToTop();
          return;
        }
      } else {
        _toStation = station;
        _toIsCapturedCurrentLocation = false;
        _toController.text = station.name;
      }
      _suggestions = [];
      _activeSearchField = '';
    });
    FocusScope.of(context).unfocus();
  }

  /// A friend's live position is not a place worth keeping in history, so it
  /// takes a separate path from the regular station selection.
  void _selectFriendOriginStation(Station station) {
    JointPlanFriend? friend;
    final friendId = JointPlanFriend.friendIdFromStation(station);
    if (friendId != null) {
      for (final candidate in _jointPlanningFriends) {
        if (candidate.id == friendId) {
          friend = candidate;
          break;
        }
      }
    } else {
      SearchHistoryManager.saveStation(station);
    }
    setState(() {
      _selectedJointFriend = friend;
      _friendOriginStation = station;
      _friendOriginController.text = station.name;
      _suggestions = [];
      _activeSearchField = '';
      _isSuggestionsLoading = false;
    });
    FocusScope.of(context).unfocus();
  }

  void _swapRouteEndpoints() {
    final fromText = _fromController.text;
    final fromStation = _fromStation;
    final fromUsesCurrentLocation = _fromUsesCurrentLocation;
    final currentPosition = _effectiveCurrentPosition;
    final currentLocationText = fromText.trim().isNotEmpty
        ? fromText
        : (_currentAddress ?? AppLocalizations.of(context)!.currentLocation);
    final capturedCurrentLocation =
        fromUsesCurrentLocation && currentPosition != null
            ? Station(
                id: 'gps-snapshot-${currentPosition.latitude},${currentPosition.longitude}',
                name: currentLocationText,
                type: 'location',
                latitude: currentPosition.latitude,
                longitude: currentPosition.longitude,
              )
            : null;

    _suggestionRequestToken++;
    _debounce?.cancel();
    FocusScope.of(context).unfocus();

    setState(() {
      _fromController.text = _toController.text;
      _toController.text =
          fromUsesCurrentLocation ? currentLocationText : fromText;
      _fromStation = _toStation;
      _toStation = capturedCurrentLocation ?? fromStation;
      _fromUsesCurrentLocation = false;
      _toIsCapturedCurrentLocation = fromUsesCurrentLocation;
      _suggestions = [];
      _activeSearchField = '';
      _isSuggestionsLoading = false;
    });
  }

  Future<void> _onFavoriteTap(Favorite fav) async {
    if (!isSupportedFavorite(fav)) {
      await FavoritesManager.deleteFavorite(fav.id);
      if (mounted) {
        await _loadFavorites();
      }
      return;
    }

    // Capture the active field BEFORE async operations or state clearing
    final currentField = _activeSearchField;

    setState(() {
      _suggestions = [];
      _activeSearchField = '';
    });
    FocusScope.of(context).unfocus();
    final target = fav.station;
    if (target == null) {
      _showEditFavoriteDialog(fav);
      return;
    }

    if (currentField == 'friend') {
      _selectFriendOriginStation(target);
      return;
    }

    if (mounted) {
      setState(() {
        if (currentField == 'from') {
          _fromStation = target;
          _fromUsesCurrentLocation = false;
          _fromController.text = target.name;
          if (_toStation == null) {
            _activeSearchField = 'to';
            _toFocusNode.requestFocus();
            _scrollToTop();
          }
        } else if (currentField == 'to') {
          _toStation = target;
          _toIsCapturedCurrentLocation = false;
          _toController.text = target.name;
          // If from is empty, maybe jump there? But usually 'to' is second.
          if (_fromStation == null && _effectiveCurrentPosition == null) {
            _activeSearchField = 'from';
            _fromFocusNode.requestFocus();
          }
        } else {
          if (_fromStation != null || _effectiveCurrentPosition != null) {
            _toStation = target;
            _toIsCapturedCurrentLocation = false;
            _toController.text = target.name;
          } else {
            _fromStation = target;
            _fromUsesCurrentLocation = false;
            _fromController.text = target.name;
            _toFocusNode.requestFocus();
            _scrollToTop();
          }
        }
      });
    }
  }

  void _closeTab(String id) {
    final controller = _routeResultsScrollControllers.remove(id);
    controller?.dispose();
    _activeJourneyScrollControllers.remove(id)?.dispose();
    _routeResultsScrollOffsets.remove(id);
    _routeResultsSortSelections.remove(id);
    _jointRouteContexts.remove(id);
    _resetEarlierAlternativeScans(id);
    setState(() {
      _tabs.removeWhere((t) => t.id == id);
      if (_activeTabId == id) {
        _activeTabId = _tabs.isNotEmpty ? _tabs.last.id : null;
      }
    });
    _stopWakeAlarm();
  }

  bool _journeyMatches(Map<String, dynamic> item, Station from, Station to) {
    return item['from']?['id'] == from.id && item['to']?['id'] == to.id;
  }

  /// How often the active-journey refresh callback has been invoked.
  @visibleForTesting
  int debugActiveJourneyRefreshCount = 0;

  /// How often the route-results refresh callback has been invoked.
  @visibleForTesting
  int debugRouteResultsRefreshCount = 0;

  /// Replaces the open tabs with [tabs] and activates one of them, so tests can
  /// reach the route views without driving a live search first.
  @visibleForTesting
  void debugOpenRouteTabs(List<RouteTab> tabs, {String? activeId}) {
    setState(() {
      _tabs
        ..clear()
        ..addAll(tabs);
      _activeTabId = activeId ?? (tabs.isEmpty ? null : tabs.first.id);
    });
  }

  ScrollController _activeJourneyScrollControllerFor(String routeId) {
    return _activeJourneyScrollControllers.putIfAbsent(
      routeId,
      ScrollController.new,
    );
  }

  /// The scroll position behind whichever route view is on screen right now.
  ///
  /// Only one of the two views is mounted for the active tab, so at most one of
  /// these controllers ever has clients.
  ScrollPosition? _activeRoutePullPosition() {
    final routeId = _activeTabId;
    if (routeId == null) return null;
    for (final controllers in <Map<String, ScrollController>>[
      _activeJourneyScrollControllers,
      _routeResultsScrollControllers,
    ]) {
      final controller = controllers[routeId];
      if (controller != null &&
          controller.hasClients &&
          controller.positions.length == 1) {
        return controller.position;
      }
    }
    return null;
  }

  /// Metrics that describe the journey as if it were parked at the very top.
  ///
  /// [RefreshIndicator] only arms while `extentBefore` is zero, and the whole
  /// point of the header pull is to refresh without moving the journey, so the
  /// pull reports `pixels: 0` instead of the real offset. Everything else
  /// mirrors the live position, which keeps the indicator's arm distance
  /// identical to the in-list gesture.
  ScrollMetrics _tabBarPullMetrics(ScrollPosition position) {
    return FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: position.maxScrollExtent,
      pixels: 0,
      viewportDimension: position.viewportDimension,
      axisDirection: AxisDirection.down,
      devicePixelRatio: position.devicePixelRatio,
    );
  }

  // The fixed tab strip lives outside the journey's scroll view, so dragging it
  // can never produce a real overscroll. Instead we hand the RefreshIndicator
  // the same ScrollNotifications the in-list gesture would produce. That keeps
  // the stock circular indicator, its arm/cancel thresholds and the existing
  // onRefresh callback, and it never touches the journey's scroll offset.
  void _handleTabBarVerticalDragStart(DragStartDetails details) {
    // The pull only begins once the drag actually moves downwards, so taps and
    // upward drags on the strip stay inert.
    _tabBarPullPosition = null;
  }

  void _handleTabBarVerticalDragUpdate(DragUpdateDetails details) {
    final delta = details.delta.dy;
    if (delta == 0) return;

    var position = _tabBarPullPosition;
    if (position == null) {
      if (delta <= 0) return;
      position = _activeRoutePullPosition();
      final notificationContext = position?.context.notificationContext;
      if (position == null || notificationContext == null) return;
      _tabBarPullPosition = position;
      ScrollStartNotification(
        metrics: _tabBarPullMetrics(position),
        context: notificationContext,
        dragDetails: DragStartDetails(
          globalPosition: details.globalPosition,
          localPosition: details.localPosition,
          sourceTimeStamp: details.sourceTimeStamp,
        ),
      ).dispatch(notificationContext);
    }

    final notificationContext = position.context.notificationContext;
    if (notificationContext == null) return;
    OverscrollNotification(
      metrics: _tabBarPullMetrics(position),
      context: notificationContext,
      dragDetails: details,
      // Negative overscroll means "dragged past the top", which is exactly what
      // pulling the strip downwards represents.
      overscroll: -delta,
    ).dispatch(notificationContext);
  }

  void _handleTabBarVerticalDragEnd(DragEndDetails details) => _endTabBarPull();

  void _handleTabBarVerticalDragCancel() => _endTabBarPull();

  /// Hands the release back to [RefreshIndicator]: a pull past its threshold
  /// refreshes, anything shorter is cancelled. Same rule as the in-list pull.
  void _endTabBarPull() {
    final position = _tabBarPullPosition;
    _tabBarPullPosition = null;
    if (position == null) return;
    final notificationContext = position.context.notificationContext;
    if (notificationContext == null) return;
    ScrollEndNotification(
      metrics: _tabBarPullMetrics(position),
      context: notificationContext,
    ).dispatch(notificationContext);
  }

  ScrollController _routeResultsScrollControllerFor(String routeId) {
    return _routeResultsScrollControllers.putIfAbsent(
      routeId,
      () {
        final controller = ScrollController(
          initialScrollOffset: _routeResultsScrollOffsets[routeId] ?? 0,
        );
        controller.addListener(() {
          if (!controller.hasClients) return;
          _routeResultsScrollOffsets[routeId] = controller.offset;
        });
        return controller;
      },
    );
  }

  String? _savedConnectionKeyForRoute(RouteTab route) {
    final from = route.origin;
    final active = route.activeJourney;
    if (from == null || active == null) return null;
    return savedJourneyConnectionKeyFor(
      journey: active,
      from: from,
      to: route.destination,
    );
  }

  bool _isRouteSaved(RouteTab route) {
    final key = _savedConnectionKeyForRoute(route);
    if (key != null) {
      return _savedJourneys.any((item) => item['connectionKey'] == key);
    }

    final from = route.origin;
    return from != null &&
        _savedJourneys
            .any((item) => _journeyMatches(item, from, route.destination));
  }

  Future<void> _toggleSavedRoute(RouteTab route) async {
    final from = route.origin;
    final activeJourney = route.activeJourney;
    if (from == null ||
        activeJourney == null ||
        _savingRouteIds.contains(route.id)) {
      return;
    }

    setState(() {
      _savingRouteIds.add(route.id);
    });

    try {
      final persistedKey = activeJourney.savedConnectionKey;
      final existingSavedItem = persistedKey == null
          ? null
          : _savedJourneys.cast<Map<String, dynamic>?>().firstWhere(
                (item) => item?['connectionKey'] == persistedKey,
                orElse: () => null,
              );
      final bool saved;
      if (existingSavedItem != null) {
        await SearchHistoryManager.removeSavedJourneyByItem(
          item: existingSavedItem,
        );
        saved = false;
      } else {
        saved = await SearchHistoryManager.toggleSavedJourney(
          from: from,
          to: route.destination,
          journeyData: activeJourney.rawSource,
          departure: activeJourney.plannedDeparture ?? activeJourney.departure,
          arrival: activeJourney.plannedArrival ?? activeJourney.arrival,
        );
      }
      await _loadHistoryData();

      if (!mounted) return;
      final connectionKey = saved
          ? SearchHistoryManager.buildSavedJourneyConnectionKey(
              from: from,
              to: route.destination,
              departure:
                  activeJourney.plannedDeparture ?? activeJourney.departure,
              arrival: activeJourney.plannedArrival ?? activeJourney.arrival,
              journeyData: activeJourney.rawSource,
            )
          : null;
      setState(() {
        final index = _tabs.indexWhere((tab) => tab.id == route.id);
        if (index == -1) return;
        final current = _tabs[index];
        Journey update(Journey journey) =>
            _isSameJourneyEntry(journey, activeJourney)
                ? journey.copyWith(
                    savedConnectionKey: connectionKey,
                    clearSavedConnectionKey: !saved,
                  )
                : journey;
        _tabs[index] = current.copyWith(
          activeJourney: current.activeJourney == null
              ? null
              : update(current.activeJourney!),
          candidates: current.candidates?.map(update).toList(),
          stack: current.stack.map(update).toList(),
        );
      });
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(saved ? l10n.connectionSaved : l10n.connectionUnsaved)));
    } finally {
      if (mounted) {
        setState(() {
          _savingRouteIds.remove(route.id);
        });
      }
    }
  }

  Future<void> _openSavedJourney(Map<String, dynamic> item) async {
    final from = Station.fromJson(item['from']);
    final to = Station.fromJson(item['to']);
    final rawJourney = item['journey'];

    if (rawJourney is! Map) {
      _applyRouteHistorySelection(item);
      return;
    }

    final journey = Map<String, dynamic>.from(rawJourney);
    final tabId = _addJourneyTab(
      singleJourneyData: journey,
      savedConnectionKey: item['connectionKey'] is String
          ? item['connectionKey'] as String
          : null,
      origin: from,
      destination: to,
      title: to.name,
      subtitle: AppLocalizations.of(context)!.details,
    );

    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;
    final tab = _tabs.cast<RouteTab?>().firstWhere(
          (t) => t?.id == tabId,
          orElse: () => null,
        );
    if (tab != null && tab.activeJourney != null) {
      unawaited(_refreshActiveJourney(tab));
    }
  }

  String? _savedJourneyTimeLabel(Map<String, dynamic> item) {
    final depStr = item['departureTime'];
    final arrStr = item['arrivalTime'];
    if (depStr is! String || arrStr is! String) return null;
    final dep = DateTime.tryParse(depStr)?.toLocal();
    final arr = DateTime.tryParse(arrStr)?.toLocal();
    if (dep == null || arr == null) return null;
    return "${DateFormat('EEE HH:mm').format(dep)} - ${DateFormat('HH:mm').format(arr)}";
  }

  String? _savedJourneyUiKey(Map<String, dynamic> item) {
    final key = item['connectionKey'];
    if (key is String && key.isNotEmpty) return key;

    final from = item['from'];
    final to = item['to'];
    final dep = item['departureTime'];
    final arr = item['arrivalTime'];
    final fromId = from is Map ? from['id'] : null;
    final toId = to is Map ? to['id'] : null;
    if (fromId is String &&
        fromId.isNotEmpty &&
        toId is String &&
        toId.isNotEmpty &&
        dep is String &&
        arr is String) {
      return '$fromId::$toId::$dep::$arr';
    }
    return null;
  }

  List<int> _savedJourneyReminderMinutesList(Map<String, dynamic> item) {
    final normalized = <int>{};
    final listValue = item['leaveReminderMinutesList'];
    if (listValue is List) {
      for (final value in listValue) {
        if (value is int && value > 0) {
          normalized.add(value);
        } else if (value is num && value > 0) {
          normalized.add(value.toInt());
        } else if (value is String) {
          final parsed = int.tryParse(value);
          if (parsed != null && parsed > 0) normalized.add(parsed);
        }
      }
    }

    // Backward compatibility with older saved entries that stored one value.
    if (normalized.isEmpty) {
      final value = item['leaveReminderMinutes'];
      if (value is int && value > 0) {
        normalized.add(value);
      } else if (value is num && value > 0) {
        normalized.add(value.toInt());
      } else if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null && parsed > 0) normalized.add(parsed);
      }
    }

    final reminders = normalized.toList()..sort((a, b) => b.compareTo(a));
    return reminders;
  }

  DateTime? _savedJourneyDepartureLocal(Map<String, dynamic> item) {
    final depStr = item['departureTime'];
    if (depStr is! String) return null;
    return DateTime.tryParse(depStr)?.toLocal();
  }

  DateTime? _savedJourneyArrivalLocal(Map<String, dynamic> item) {
    final arrStr = item['arrivalTime'];
    if (arrStr is! String) return null;
    return DateTime.tryParse(arrStr)?.toLocal();
  }

  bool _isSavedJourneyCompleted(Map<String, dynamic> item) {
    final now = DateTime.now();
    final arrival = _savedJourneyArrivalLocal(item);
    if (arrival != null) return now.isAfter(arrival);
    final departure = _savedJourneyDepartureLocal(item);
    if (departure != null) return now.isAfter(departure);
    return false;
  }

  bool _isLegacySavedJourney(Map<String, dynamic> item) {
    final hasConnectionKey = item['connectionKey'] is String &&
        (item['connectionKey'] as String).isNotEmpty;
    final hasDeparture = item['departureTime'] is String;
    final hasArrival = item['arrivalTime'] is String;
    final hasJourney = item['journey'] is Map;
    return !(hasConnectionKey && hasDeparture && hasArrival && hasJourney);
  }

  bool _sameSavedJourneyEntry(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final keyA = _savedJourneyUiKey(a);
    final keyB = _savedJourneyUiKey(b);
    if (keyA != null && keyB != null) return keyA == keyB;
    return a['from']?['id'] == b['from']?['id'] &&
        a['to']?['id'] == b['to']?['id'] &&
        a['departureTime'] == b['departureTime'] &&
        a['arrivalTime'] == b['arrivalTime'];
  }

  int _savedJourneyReminderNotificationId(String key, int minutes) {
    return (key.hashCode ^ (minutes * 97)) & 0x7fffffff;
  }

  int _savedJourneyLiveCountdownNotificationId(String key, int minutes) {
    return (key.hashCode ^ (minutes * 193) ^ 0x2fffffff) & 0x7fffffff;
  }

  String _formatCountdown(Duration duration) {
    final totalSeconds = duration.inSeconds.clamp(0, 999999);
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    final hh = hours.toString().padLeft(2, '0');
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  String _savedJourneyReminderTriggerKey(String key, int minutes) {
    return '$key::$minutes';
  }

  DateTime? _savedJourneyReminderTriggerLocal(
    Map<String, dynamic> item, {
    required int minutes,
  }) {
    final departure = _savedJourneyDepartureLocal(item);
    if (departure == null) return null;
    return departure.subtract(Duration(minutes: minutes));
  }

  List<({int leadMinutes, int waitMinutes})> _savedJourneyReminderOptions(
      Map<String, dynamic> item) {
    final departure = _savedJourneyDepartureLocal(item);
    if (departure == null) {
      return const [
        (leadMinutes: 5, waitMinutes: 5),
        (leadMinutes: 15, waitMinutes: 15),
        (leadMinutes: 30, waitMinutes: 30),
      ];
    }

    final now = DateTime.now();
    final remainingMinutes = departure.difference(now).inMinutes;
    if (remainingMinutes <= 0) return const [];

    List<int> waits;
    if (remainingMinutes >= 30) {
      waits = const [30, 15, 5];
    } else if (remainingMinutes >= 20) {
      waits = const [20, 15, 5];
    } else if (remainingMinutes >= 15) {
      waits = const [15, 10, 5];
    } else if (remainingMinutes >= 10) {
      waits = const [10, 5, 3];
    } else if (remainingMinutes >= 5) {
      waits = const [5, 3, 2];
    } else if (remainingMinutes >= 3) {
      waits = const [3, 2, 1];
    } else if (remainingMinutes == 2) {
      waits = const [2, 1];
    } else {
      waits = const [1];
    }

    final options = <({int leadMinutes, int waitMinutes})>[];
    for (final wait in waits) {
      if (wait > remainingMinutes) continue;
      options.add(savedJourneyReminderOptionFromWait(wait));
    }
    return options;
  }

  bool _hasActiveSavedJourneyLiveCountdowns() {
    final now = DateTime.now();
    for (final item in _savedJourneys) {
      final reminderMinutes = _savedJourneyReminderMinutesList(item);
      for (final minutes in reminderMinutes) {
        final triggerAt =
            _savedJourneyReminderTriggerLocal(item, minutes: minutes);
        if (triggerAt != null && triggerAt.isAfter(now)) {
          return true;
        }
      }
    }
    return false;
  }

  Future<void> _cancelSavedJourneyReminderNotification(
    String key, {
    int? minutes,
  }) async {
    if (minutes != null) {
      await _notificationsPlugin.cancel(
          id: _savedJourneyReminderNotificationId(key, minutes));
      return;
    }
    for (final candidate in const [1, 2, 3, 5, 10, 15, 20, 30]) {
      await _notificationsPlugin.cancel(
          id: _savedJourneyReminderNotificationId(key, candidate));
    }
  }

  Future<void> _cancelSavedJourneyLiveCountdownNotification(
    String key, {
    int? minutes,
  }) async {
    if (minutes != null) {
      await _notificationsPlugin.cancel(
          id: _savedJourneyLiveCountdownNotificationId(key, minutes));
      return;
    }
    for (final candidate in const [1, 2, 3, 5, 10, 15, 20, 30]) {
      await _notificationsPlugin.cancel(
          id: _savedJourneyLiveCountdownNotificationId(key, candidate));
    }
  }

  Future<void> _showSavedJourneyLiveCountdownNotification(
    Map<String, dynamic> item,
    DateTime triggerAt,
    int minutes,
  ) async {
    final key = _savedJourneyUiKey(item);
    if (key == null) return;
    final triggerKey = _savedJourneyReminderTriggerKey(key, minutes);

    final now = DateTime.now();
    if (!triggerAt.isAfter(now)) return;
    final countdownText = _formatCountdown(triggerAt.difference(now));

    final cached = _savedJourneyLiveCountdownTexts[triggerKey];
    if (cached == countdownText) return;
    _savedJourneyLiveCountdownTexts[triggerKey] = countdownText;

    final fromMap = item['from'];
    final toMap = item['to'];
    final fromName = fromMap is Map ? fromMap['name']?.toString() ?? '' : '';
    final toName =
        toMap is Map ? toMap['name']?.toString() ?? 'Route' : 'Route';
    final routeLabel = fromName.isEmpty ? toName : '$fromName -> $toName';

    final androidDetails = AndroidNotificationDetails(
      NotificationManager.leaveCountdownChannelId,
      'Saved Route Reminders',
      channelDescription: 'Live countdown reminders for saved routes',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      playSound: false,
      enableVibration: false,
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(),
      linux: const LinuxNotificationDetails(),
    );

    await _notificationsPlugin.show(
      id: _savedJourneyLiveCountdownNotificationId(key, minutes),
      title: 'Leave in $countdownText',
      body: '$routeLabel (timer: ${minutes}min)',
      notificationDetails: details,
    );
  }

  Future<void> _refreshSavedJourneyLiveCountdowns() async {
    final now = DateTime.now();
    final activeTriggerKeys = <String>{};

    for (final item in _savedJourneys) {
      final key = _savedJourneyUiKey(item);
      if (key == null) continue;
      final reminderMinutes = _savedJourneyReminderMinutesList(item);
      for (final minutes in reminderMinutes) {
        final triggerAt =
            _savedJourneyReminderTriggerLocal(item, minutes: minutes);
        if (triggerAt == null) continue;
        final triggerKey = _savedJourneyReminderTriggerKey(key, minutes);

        if (triggerAt.isAfter(now)) {
          activeTriggerKeys.add(triggerKey);
          _savedJourneyTriggeredReminderKeys.remove(triggerKey);
          await _showSavedJourneyLiveCountdownNotification(
            item,
            triggerAt,
            minutes,
          );
        } else {
          _savedJourneyLiveCountdownTexts.remove(triggerKey);
          if (_savedJourneyTriggeredReminderKeys.add(triggerKey)) {
            unawaited(_fireSavedJourneyReminder(item: item, minutes: minutes));
          }
        }
      }
    }

    final staleKeys = _savedJourneyLiveCountdownTexts.keys
        .where((key) => !activeTriggerKeys.contains(key))
        .toList();
    for (final triggerKey in staleKeys) {
      _savedJourneyLiveCountdownTexts.remove(triggerKey);
      final parts = triggerKey.split('::');
      if (parts.length != 2) continue;
      final minutes = int.tryParse(parts[1]);
      if (minutes == null) continue;
      await _cancelSavedJourneyLiveCountdownNotification(
        parts[0],
        minutes: minutes,
      );
    }
  }

  void _syncSavedJourneyLiveCountdownTicker() {
    if (_hasActiveSavedJourneyLiveCountdowns()) {
      _savedJourneyLiveCountdownTicker ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(_refreshSavedJourneyLiveCountdowns()),
      );
      unawaited(_refreshSavedJourneyLiveCountdowns());
      return;
    }

    _savedJourneyLiveCountdownTicker?.cancel();
    _savedJourneyLiveCountdownTicker = null;
    final triggerKeys = _savedJourneyLiveCountdownTexts.keys.toList();
    _savedJourneyLiveCountdownTexts.clear();
    for (final triggerKey in triggerKeys) {
      final parts = triggerKey.split('::');
      if (parts.length != 2) continue;
      final minutes = int.tryParse(parts[1]);
      if (minutes == null) continue;
      unawaited(_cancelSavedJourneyLiveCountdownNotification(parts[0],
          minutes: minutes));
    }
  }

  void _syncSavedJourneyReminderTimers(List<Map<String, dynamic>> journeys) {
    final activeKeys = <String>{};
    for (final journey in journeys) {
      final key = _savedJourneyUiKey(journey);
      if (key == null) continue;
      activeKeys.add(key);
      _scheduleSavedJourneyReminders(journey);
    }

    final staleKeys = _savedJourneyReminderTimers.keys
        .where((key) => !activeKeys.contains(key))
        .toList();
    for (final key in staleKeys) {
      _savedJourneyReminderTimers.remove(key)?.cancel();
      unawaited(_cancelSavedJourneyReminderNotification(key));
      unawaited(_cancelSavedJourneyLiveCountdownNotification(key));
      _savedJourneyLiveCountdownTexts
          .removeWhere((triggerKey, _) => triggerKey.startsWith('$key::'));
      _savedJourneyTriggeredReminderKeys
          .removeWhere((entry) => entry.startsWith('$key::'));
    }

    _savedReminderPickerVisibleFor.removeWhere((k) => !activeKeys.contains(k));
    _savedCompletedDeleteVisibleFor.removeWhere((k) => !activeKeys.contains(k));
    _syncSavedJourneyLiveCountdownTicker();
  }

  void _syncSavedJourneyStatusMonitoring(List<Map<String, dynamic>> journeys) {
    final activeKeys =
        journeys.map(_savedJourneyUiKey).whereType<String>().toSet();
    _savedJourneyLastStatusSignatures
        .removeWhere((key, _) => !activeKeys.contains(key));

    if (journeys.isEmpty) {
      _savedJourneyStatusPollTimer?.cancel();
      _savedJourneyStatusPollTimer = null;
      return;
    }

    _savedJourneyStatusPollTimer ??= Timer.periodic(
      const Duration(minutes: 4),
      (_) => unawaited(_checkSavedJourneyStatuses()),
    );

    final now = DateTime.now();
    final shouldCheckNow = _lastSavedJourneyStatusCheck == null ||
        now.difference(_lastSavedJourneyStatusCheck!) >
            const Duration(seconds: 45);
    if (shouldCheckNow) {
      unawaited(_checkSavedJourneyStatuses());
    }
  }

  String _savedJourneyRealtimeSignature(Journey journey) {
    final rides = journey.steps.where((step) => step.type == 'ride').map((s) {
      return [
        s.tripId?.trim() ?? '',
        s.line.trim().toLowerCase(),
        s.startStationName,
        s.destinationName,
        s.departureTime,
        s.arrivalTime,
        s.departureDelay?.toString() ?? '',
        s.arrivalDelay?.toString() ?? '',
        s.platform ?? '',
        s.arrivalPlatform ?? '',
        s.isCancelled ? '1' : '0',
      ].join('|');
    }).join('||');

    return [
      journey.departure.toUtc().toIso8601String(),
      journey.arrival.toUtc().toIso8601String(),
      rides,
    ].join('::');
  }

  String _describeSavedJourneyChange({
    required Journey savedJourney,
    required Journey freshJourney,
  }) {
    final freshRideSteps =
        freshJourney.steps.where((step) => step.type == 'ride').toList();
    bool hasCancellation = false;
    bool hasDelay = false;
    bool hasPlatformChange = false;

    for (final oldStep in savedJourney.steps.where((s) => s.type == 'ride')) {
      final nowStep = _findRealtimeMatchForStep(oldStep, freshRideSteps);
      if (nowStep == null) continue;

      if (nowStep.isCancelled && !oldStep.isCancelled) {
        hasCancellation = true;
      }
      final depDelayChanged =
          (nowStep.departureDelay ?? 0) != (oldStep.departureDelay ?? 0);
      final arrDelayChanged =
          (nowStep.arrivalDelay ?? 0) != (oldStep.arrivalDelay ?? 0);
      if (depDelayChanged || arrDelayChanged) {
        hasDelay = true;
      }
      final platformChanged =
          (nowStep.platform ?? '').trim() != (oldStep.platform ?? '').trim() ||
              (nowStep.arrivalPlatform ?? '').trim() !=
                  (oldStep.arrivalPlatform ?? '').trim();
      if (platformChanged) {
        hasPlatformChange = true;
      }
    }

    if (hasCancellation) return 'Cancellation update';
    if (hasDelay) return 'Delay update';
    if (hasPlatformChange) return 'Platform update';
    return 'Schedule update';
  }

  Future<({bool stillPossible, String signature, String detail})>
      _computeSavedJourneyStatus(Map<String, dynamic> item) async {
    final fromJson = item['from'];
    final toJson = item['to'];
    final rawJourney = item['journey'];
    final departure = _savedJourneyDepartureLocal(item);
    if (fromJson is! Map || toJson is! Map || rawJourney is! Map) {
      return (
        stillPossible: false,
        signature: 'invalid',
        detail: 'Connection no longer possible'
      );
    }
    if (departure == null) {
      return (
        stillPossible: false,
        signature: 'missing-departure',
        detail: 'Connection no longer possible'
      );
    }

    final now = DateTime.now();
    if (departure.isBefore(now.subtract(const Duration(hours: 2)))) {
      return (
        stillPossible: true,
        signature: 'past-departure',
        detail: 'No relevant updates'
      );
    }

    final from = Station.fromJson(Map<String, dynamic>.from(fromJson));
    final to = Station.fromJson(Map<String, dynamic>.from(toJson));
    Journey savedJourney;
    try {
      savedJourney = _createJourney(
        Map<String, dynamic>.from(rawJourney),
        destinationNameOverride: to.name,
      );
    } catch (_) {
      return (
        stillPossible: false,
        signature: 'invalid-saved-journey',
        detail: 'Connection no longer possible'
      );
    }

    final refWhen = departure.subtract(const Duration(minutes: 20));
    final freshData = await TransportApi.searchJourneys(
      from,
      to,
      nahverkehrOnly: widget.onlyNahverkehr,
      when: refWhen,
      isArrival: false,
      results: 20,
    );

    final freshJourneys = <Journey>[];
    for (final data in freshData) {
      try {
        freshJourneys.add(
          _createJourney(data, destinationNameOverride: to.name),
        );
      } catch (_) {
        // Skip invalid candidate
      }
    }

    final matched = _findStrictJourneyMatch(savedJourney, freshJourneys);
    if (matched == null) {
      return (
        stillPossible: false,
        signature: 'unavailable',
        detail: 'Connection no longer possible'
      );
    }

    final merged = _mergeRealtimeIntoJourney(savedJourney, matched);
    final signature = _savedJourneyRealtimeSignature(merged);
    final detail = _describeSavedJourneyChange(
      savedJourney: savedJourney,
      freshJourney: merged,
    );
    return (stillPossible: true, signature: signature, detail: detail);
  }

  Future<void> _notifySavedJourneyStatusChange({
    required String routeKey,
    required Map<String, dynamic> item,
    required bool stillPossible,
    required String detail,
  }) async {
    final fromMap = item['from'];
    final toMap = item['to'];
    final fromName = fromMap is Map ? fromMap['name']?.toString() ?? '' : '';
    final toName = toMap is Map ? toMap['name']?.toString() ?? '' : '';
    if (toName.isEmpty) return;

    await NotificationManager.requestPermissions();

    final androidDetails = AndroidNotificationDetails(
      'saved_route_status_channel',
      'Saved Route Status',
      channelDescription:
          'Updates when saved routes change or become unavailable',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(),
      linux: const LinuxNotificationDetails(),
    );

    final routeLabel = compactSavedRouteLabel(fromName, toName);
    final statusText = stillPossible ? 'Still possible' : 'No longer possible';
    // Keep body concise on Android while still showing the key status reason.
    final compactDetail = _ellipsize(detail, _savedRouteStatusDetailMaxLength);
    final message = routeLabel.isEmpty
        ? '$compactDetail · $statusText'
        : '$routeLabel · $compactDetail · $statusText';
    await _notificationsPlugin.show(
      id: savedRouteStatusNotificationIdForKey(routeKey),
      title: 'Saved route changed',
      body: message,
      notificationDetails: details,
    );
  }

  Future<void> _checkSavedJourneyStatuses() async {
    if (_isCheckingSavedJourneyStatuses) return;
    if (_savedJourneys.isEmpty) return;

    _isCheckingSavedJourneyStatuses = true;
    _lastSavedJourneyStatusCheck = DateTime.now();
    try {
      final journeys = List<Map<String, dynamic>>.from(_savedJourneys);
      for (final item in journeys) {
        final key = _savedJourneyUiKey(item);
        if (key == null) continue;

        try {
          final status = await _computeSavedJourneyStatus(item);
          final currentStatusSignature = status.stillPossible
              ? 'possible:${status.signature}'
              : 'unavailable';
          final previousStatusSignature =
              _savedJourneyLastStatusSignatures[key];
          final isFirstObservation = previousStatusSignature == null;
          _savedJourneyLastStatusSignatures[key] = currentStatusSignature;

          if (status.stillPossible) {
            final rawJourney = item['journey'];
            if (rawJourney is! Map) continue;

            Journey savedJourney;
            try {
              savedJourney = _createJourney(
                Map<String, dynamic>.from(rawJourney),
                destinationNameOverride: item['toName']?.toString(),
              );
            } catch (_) {
              continue;
            }
            final savedSignature = _savedJourneyRealtimeSignature(savedJourney);
            final changedFromSaved = status.signature != savedSignature;
            final changedSinceLast =
                previousStatusSignature != currentStatusSignature;
            if (changedSinceLast &&
                (changedFromSaved ||
                    (previousStatusSignature != null &&
                        previousStatusSignature.startsWith('unavailable')))) {
              await _notifySavedJourneyStatusChange(
                routeKey: key,
                item: item,
                stillPossible: true,
                detail: status.detail,
              );
            } else if (isFirstObservation && !changedFromSaved) {
              // Baseline set: no notification for unchanged route.
            }
          } else {
            if (previousStatusSignature != 'unavailable') {
              await _notifySavedJourneyStatusChange(
                routeKey: key,
                item: item,
                stillPossible: false,
                detail: status.detail,
              );
            }
          }
        } catch (e) {
          debugPrint('Saved journey status check failed for one route: $e');
        }
      }
    } finally {
      _isCheckingSavedJourneyStatuses = false;
    }
  }

  ({String title, String body}) _savedJourneyReminderContent(
    Map<String, dynamic> item,
    int minutes,
  ) {
    final fromMap = item['from'];
    final toMap = item['to'];
    final fromName =
        fromMap is Map ? (fromMap['name']?.toString() ?? 'Start') : 'Start';
    final toName = toMap is Map
        ? (toMap['name']?.toString() ?? 'Destination')
        : 'Destination';
    final departure = _savedJourneyDepartureLocal(item);
    final departureLabel =
        departure != null ? DateFormat('HH:mm').format(departure) : '--:--';
    final l10n = _reminderL10n ?? AppLocalizations.of(context)!;
    return (
      title: l10n.leaveSoonTitle,
      body: l10n.leaveSoonBody('$minutes', fromName, toName, departureLabel),
    );
  }

  void _scheduleSavedJourneyReminders(
    Map<String, dynamic> item, {
    bool fireImmediatelyIfDue = false,
  }) async {
    final key = _savedJourneyUiKey(item);
    if (key == null) return;

    _savedJourneyReminderTimers.remove(key)?.cancel();

    final reminderMinutes = _savedJourneyReminderMinutesList(item);
    if (reminderMinutes.isEmpty) {
      unawaited(_cancelSavedJourneyReminderNotification(key));
      unawaited(_cancelSavedJourneyLiveCountdownNotification(key));
      _savedJourneyLiveCountdownTexts
          .removeWhere((triggerKey, _) => triggerKey.startsWith('$key::'));
      _savedJourneyTriggeredReminderKeys
          .removeWhere((triggerKey) => triggerKey.startsWith('$key::'));
      _syncSavedJourneyLiveCountdownTicker();
      return;
    }

    final departure = _savedJourneyDepartureLocal(item);
    if (departure == null) {
      unawaited(_cancelSavedJourneyReminderNotification(key));
      unawaited(_cancelSavedJourneyLiveCountdownNotification(key));
      _savedJourneyLiveCountdownTexts
          .removeWhere((triggerKey, _) => triggerKey.startsWith('$key::'));
      _syncSavedJourneyLiveCountdownTicker();
      return;
    }
    final now = DateTime.now();
    if (departure.isBefore(now)) {
      unawaited(_cancelSavedJourneyReminderNotification(key));
      unawaited(_cancelSavedJourneyLiveCountdownNotification(key));
      _savedJourneyLiveCountdownTexts
          .removeWhere((triggerKey, _) => triggerKey.startsWith('$key::'));
      _syncSavedJourneyLiveCountdownTicker();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final patternName = prefs.getString('vibration_pattern') ?? 'standard';
    final soundId = prefs.getString(WakeAlarmSettings.soundPreferenceKey) ??
        WakeAlarmSettings.defaultSoundId;
    final leaveSoundEnabled =
        prefs.getBool(WakeAlarmSettings.leaveSoundEnabledPreferenceKey) ?? true;
    final leaveVibrationEnabled =
        prefs.getBool(WakeAlarmSettings.leaveVibrationEnabledPreferenceKey) ??
            true;
    final pattern = WakeAlarmSettings.vibrationPatternForId(patternName);
    await NotificationManager.requestPermissions();
    final canScheduleExactAlarms =
        await NotificationManager.requestExactAlarmPermissionIfNeeded();
    final hasFullScreenIntentPermission =
        await NotificationManager.requestFullScreenIntentPermissionIfNeeded();
    await NotificationManager.updateLeaveAlarmChannel(
      pattern,
      soundId: soundId,
      soundEnabled: leaveSoundEnabled,
      vibrationEnabled: leaveVibrationEnabled,
    );
    final androidDetails = NotificationManager.buildLeaveAlarmAndroidDetails(
      vibrationPattern: pattern,
      soundId: soundId,
      fullScreenIntent: hasFullScreenIntentPermission,
      soundEnabled: leaveSoundEnabled,
      vibrationEnabled: leaveVibrationEnabled,
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: NotificationManager.buildLeaveAlarmIosDetails(
        soundId: soundId,
        soundEnabled: leaveSoundEnabled,
      ),
      linux: const LinuxNotificationDetails(),
    );

    bool showedExactAlarmWarning = false;
    for (final minutes in reminderMinutes) {
      final triggerAt = departure.subtract(Duration(minutes: minutes));
      await _cancelSavedJourneyReminderNotification(key, minutes: minutes);

      if (!triggerAt.isAfter(now)) {
        _savedJourneyLiveCountdownTexts
            .remove(_savedJourneyReminderTriggerKey(key, minutes));
        unawaited(_cancelSavedJourneyLiveCountdownNotification(key,
            minutes: minutes));
        if (fireImmediatelyIfDue) {
          unawaited(_fireSavedJourneyReminder(item: item, minutes: minutes));
        }
        continue;
      }

      final content = _savedJourneyReminderContent(item, minutes);
      await NotificationManager.scheduleNotification(
        id: _savedJourneyReminderNotificationId(key, minutes),
        title: content.title,
        body: content.body,
        scheduledAt: triggerAt,
        details: details,
        androidScheduleMode: canScheduleExactAlarms
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );

      if (!canScheduleExactAlarms) {
        showedExactAlarmWarning = true;
      }
    }
    _syncSavedJourneyLiveCountdownTicker();

    if (showedExactAlarmWarning && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.exactAlarmsBlocked),
        ),
      );
    }
  }

  Future<void> _fireSavedJourneyReminder({
    required Map<String, dynamic> item,
    required int minutes,
  }) async {
    final key = _savedJourneyUiKey(item);
    if (key == null) return;
    final triggerKey = _savedJourneyReminderTriggerKey(key, minutes);
    _savedJourneyLiveCountdownTexts.remove(key);
    _savedJourneyTriggeredReminderKeys.add(triggerKey);
    await _cancelSavedJourneyReminderNotification(key, minutes: minutes);
    await _cancelSavedJourneyLiveCountdownNotification(key, minutes: minutes);
    _syncSavedJourneyLiveCountdownTicker();
    final content = _savedJourneyReminderContent(item, minutes);
    final prefs = await SharedPreferences.getInstance();
    final patternName = prefs.getString('vibration_pattern') ?? 'standard';
    final soundId = prefs.getString(WakeAlarmSettings.soundPreferenceKey) ??
        WakeAlarmSettings.defaultSoundId;
    final leaveSoundEnabled =
        prefs.getBool(WakeAlarmSettings.leaveSoundEnabledPreferenceKey) ?? true;
    final leaveVibrationEnabled =
        prefs.getBool(WakeAlarmSettings.leaveVibrationEnabledPreferenceKey) ??
            true;
    final pattern = WakeAlarmSettings.vibrationPatternForId(patternName);
    final toMap = item['to'];
    final toName = toMap is Map
        ? (toMap['name']?.toString() ?? 'Destination')
        : 'Destination';
    await NotificationManager.requestPermissions();
    final hasFullScreenIntentPermission =
        await NotificationManager.requestFullScreenIntentPermissionIfNeeded();
    await _triggerLeaveReminderForegroundAlert(
      soundId: soundId,
      soundEnabled: leaveSoundEnabled,
      vibrationEnabled: leaveVibrationEnabled,
      vibrationPattern: pattern,
    );

    await NotificationManager.updateLeaveAlarmChannel(
      pattern,
      soundId: soundId,
      soundEnabled: leaveSoundEnabled,
      vibrationEnabled: leaveVibrationEnabled,
    );
    final androidDetails = NotificationManager.buildLeaveAlarmAndroidDetails(
      vibrationPattern: pattern,
      soundId: soundId,
      fullScreenIntent: hasFullScreenIntentPermission,
      soundEnabled: leaveSoundEnabled,
      vibrationEnabled: leaveVibrationEnabled,
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: NotificationManager.buildLeaveAlarmIosDetails(
        soundId: soundId,
        soundEnabled: leaveSoundEnabled,
      ),
      linux: const LinuxNotificationDetails(),
    );

    await _notificationsPlugin.show(
      id: _savedJourneyReminderNotificationId(key, minutes),
      title: content.title,
      body: content.body,
      notificationDetails: details,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!
            .leaveInMinutesFor('$minutes', toName)),
      ),
    );
  }

  Future<void> _setSavedJourneyReminder(
    Map<String, dynamic> item,
    int? minutes,
  ) async {
    final previousMinutes = _savedJourneyReminderMinutesList(item);
    final nextMinutes = <int>{...previousMinutes};
    if (minutes == null) {
      nextMinutes.clear();
    } else if (nextMinutes.contains(minutes)) {
      nextMinutes.remove(minutes);
    } else {
      nextMinutes.add(minutes);
    }
    final normalizedNextMinutes = nextMinutes.toList()
      ..sort((a, b) => b.compareTo(a));

    if (minutes != null) {
      await NotificationManager.requestPermissions();
    }

    final updated = await SearchHistoryManager.setSavedJourneyLeaveReminder(
      item: item,
      minutesBeforeDepartureList: normalizedNextMinutes,
    );

    if (!updated) return;

    final selectedKey = _savedJourneyUiKey(item);
    final updatedItem = Map<String, dynamic>.from(item);
    if (normalizedNextMinutes.isEmpty) {
      updatedItem.remove('leaveReminderMinutes');
      updatedItem.remove('leaveReminderMinutesList');
    } else {
      updatedItem['leaveReminderMinutes'] = normalizedNextMinutes.first;
      updatedItem['leaveReminderMinutesList'] = normalizedNextMinutes;
    }
    if (selectedKey != null) {
      _savedJourneyTriggeredReminderKeys
          .removeWhere((entry) => entry.startsWith('$selectedKey::'));
    }

    if (!mounted) return;
    setState(() {
      _savedJourneys = _savedJourneys.map((entry) {
        if (_sameSavedJourneyEntry(entry, item)) {
          return updatedItem;
        }
        return entry;
      }).toList();
    });

    _scheduleSavedJourneyReminders(
      updatedItem,
      fireImmediatelyIfDue: minutes != null && normalizedNextMinutes.isNotEmpty,
    );
    if (selectedKey != null) {
      final removedMinutes =
          previousMinutes.where((value) => !nextMinutes.contains(value));
      for (final removedMinute in removedMinutes) {
        unawaited(_cancelSavedJourneyReminderNotification(selectedKey,
            minutes: removedMinute));
        unawaited(_cancelSavedJourneyLiveCountdownNotification(selectedKey,
            minutes: removedMinute));
      }
    }

    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final selectedSummary = normalizedNextMinutes.isEmpty
        ? l10n.leaveRemindersNone
        : normalizedNextMinutes.map((value) => '${value}m').join(', ');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.leaveRemindersSummary(selectedSummary))),
    );
  }

  Future<void> _deleteSavedJourney(Map<String, dynamic> item) async {
    final removed =
        await SearchHistoryManager.removeSavedJourneyByItem(item: item);
    if (!removed) return;
    await _loadHistoryData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.savedRouteDeleted)),
    );
  }

  void _applyRouteHistorySelection(Map<String, dynamic> item) {
    final from = Station.fromJson(item['from']);
    final to = Station.fromJson(item['to']);
    setState(() {
      _fromStation = from;
      _fromUsesCurrentLocation = false;
      _fromController.text = from.name;
      _toStation = to;
      _toIsCapturedCurrentLocation = false;
      _toController.text = to.name;
    });
    _findRoutes();
  }

  Future<void> _showChat(BuildContext context, String lineName) async {
    final accepted = await CommunitySafetyService.ensureTermsAccepted(
      context,
      entryPoint: Localizations.localeOf(context).languageCode == 'de'
          ? 'Linien-Chats'
          : 'line chats',
    );
    if (!accepted || !context.mounted) return;

    showModalBottomSheet(
        context: context,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) => ChatSheet(lineId: lineName, title: lineName));
  }

  // FIX: Accept full Station object
  void _showAlternatives(BuildContext context, String stationId,
      Station destination, DateTime referenceTime,
      {double? lat,
      double? lng,
      String? stationName,
      String? highlightKey,
      DateTime? earliestDeparture,
      String? currentTripId,
      String? currentLine,
      List<Map<String, dynamic>>? initialResults,
      Journey? branchFrom,
      int? branchRideLegIndex}) {
    Station fromDummy;
    if (lat != null && lng != null) {
      fromDummy = Station(
          id: stationId,
          name: stationName ?? "Origin",
          type: "location",
          latitude: lat,
          longitude: lng);
    } else {
      fromDummy = Station(
          id: stationId, name: stationName ?? "Origin", type: "station");
    }
    Station toDummy = destination;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: _AlternativesSheet(
          from: fromDummy,
          to: toDummy,
          initialTime: referenceTime,
          nahverkehrOnly: widget.onlyNahverkehr,
          highlightKey: highlightKey,
          earliestDeparture: earliestDeparture,
          currentTripId: currentTripId,
          currentLine: currentLine,
          initialResults: initialResults,
          onSelected: (journey, depTime) {
            Navigator.pop(ctx);
            final j = _journeyFromAlternative(
              journey,
              destinationName: toDummy.name,
              branchFrom: branchFrom,
              branchRideLegIndex: branchRideLegIndex,
            );
            setState(() {
              if (_activeTabId != null) {
                final idx = _tabs.indexWhere((t) => t.id == _activeTabId);
                if (idx != -1) {
                  final currentTab = _tabs[idx];
                  final newStack = List<Journey>.from(currentTab.stack);
                  if (!newStack.any((e) =>
                      e.departure == j.departure && e.arrival == j.arrival)) {
                    newStack.add(j);
                  }
                  _tabs[idx] = currentTab.copyWith(
                      activeJourney: j,
                      stack: newStack,
                      steps: j.steps,
                      totalDuration:
                          FormatUtils.formatDuration(j.duration.inMinutes));
                }
              } else {
                _addJourneyTab(
                    singleJourneyData: journey,
                    origin: fromDummy,
                    destination: toDummy,
                    title: AppLocalizations.of(context)!.alternative,
                    subtitle: AppLocalizations.of(context)!
                        .departsAt(DateFormat('HH:mm').format(depTime)));
              }
            });
          },
        ),
      ),
    );
  }

  List<JourneyStep> _processLegs(
    List legs, {
    String? destinationNameOverride,
  }) {
    final List<JourneyStep> steps = [];
    final random = Random();
    List<dynamic> transferBuffer = [];
    DateTime? lastArrival;
    String? lastStationName;
    String? lastStationId;
    String? lastPlatform;
    double? getLat(dynamic loc) => loc != null && loc['location'] != null
        ? loc['location']['latitude']
        : (loc != null ? loc['latitude'] : null);
    double? getLng(dynamic loc) => loc != null && loc['location'] != null
        ? loc['location']['longitude']
        : (loc != null ? loc['longitude'] : null);
    String? stationId(dynamic loc) => loc?['id']?.toString();
    String? stationName(dynamic loc) => loc?['name']?.toString();
    bool isBikeTransferLeg(dynamic leg) =>
        leg is Map && leg['mode']?.toString().toUpperCase() == 'BIKE';
    bool isGenericEndpointName(String? name) {
      final normalized = name?.trim().toUpperCase();
      return normalized == 'END' || normalized == 'DESTINATION';
    }

    String? displayDestinationName(String? name) {
      if (isGenericEndpointName(name) &&
          destinationNameOverride != null &&
          destinationNameOverride.trim().isNotEmpty) {
        return destinationNameOverride;
      }
      return name;
    }

    String bikeInstruction(String? destinationName, {bool isFinal = false}) {
      final isGerman = Localizations.localeOf(context).languageCode == 'de';
      if (isFinal) {
        return isGerman ? 'Mit dem Fahrrad zum Ziel' : 'Bike to destination';
      }
      if (destinationName != null && destinationName.trim().isNotEmpty) {
        return isGerman
            ? 'Mit dem Fahrrad zu $destinationName'
            : 'Bike to $destinationName';
      }
      return isGerman ? 'Fahrrad fahren' : 'Bike';
    }

    // First leg of the block currently buffered, so the resulting step can be
    // traced back to its place in the raw journey.
    int? transferBufferLegIndex;

    void flushTransferBuffer(
        DateTime? nextRideDeparture,
        String? nextStationName,
        String? nextStationId,
        String? nextPlatform,
        double? nextRideStartLat,
        double? nextRideStartLng,
        {bool isFinalWalk = false}) {
      if (transferBuffer.isEmpty &&
          (lastArrival == null || nextRideDeparture == null)) {
        return;
      }
      final isFirstStep = _isBeforeFirstJourneyStep(steps.length);
      DateTime blockStart = (lastArrival != null)
          ? lastArrival
          : (DateTime.tryParse(transferBuffer.first['departure'] ??
                      transferBuffer.first['plannedDeparture'] ??
                      '')
                  ?.toLocal() ??
              DateTime.now());
      DateTime blockEnd = (nextRideDeparture != null)
          ? nextRideDeparture
          : (transferBuffer.isNotEmpty
              ? (DateTime.tryParse(transferBuffer.last['arrival'] ??
                          transferBuffer.last['plannedArrival'] ??
                          '')
                      ?.toLocal() ??
                  blockStart)
              : blockStart);

      int walkMinutes = 0;
      for (var leg in transferBuffer) {
        try {
          walkMinutes += DateTime.parse(leg['arrival'] ?? leg['plannedArrival'])
              .toLocal()
              .difference(
                  DateTime.parse(leg['departure'] ?? leg['plannedDeparture'])
                      .toLocal())
              .inMinutes;
        } catch (e) {/* ignore */}
      }

      int totalGapMinutes = blockEnd.difference(blockStart).inMinutes;
      if (totalGapMinutes < 0) totalGapMinutes = 0;

      int waitMinutes = totalGapMinutes - walkMinutes;
      if (waitMinutes < 0) waitMinutes = 0;
      final isBikeTransfer = transferBuffer.isNotEmpty &&
          transferBuffer.every((leg) => isBikeTransferLeg(leg));

      double? startLat = getLat(
          transferBuffer.isNotEmpty ? transferBuffer.first['origin'] : null);
      if (startLat == null && steps.isNotEmpty) startLat = steps.last.endLat;
      double? startLng = getLng(
          transferBuffer.isNotEmpty ? transferBuffer.first['origin'] : null);
      if (startLng == null && steps.isNotEmpty) startLng = steps.last.endLng;

      double? endLat = nextRideStartLat;
      double? endLng = nextRideStartLng;

      // If we are at the end (no next ride), try to get coordinates from the last transfer leg (e.g. walk to address)
      if (endLat == null && transferBuffer.isNotEmpty) {
        endLat = getLat(transferBuffer.last['destination']);
        endLng = getLng(transferBuffer.last['destination']);
      }

      // Get destination name from transfer buffer if not provided
      String? destName = nextStationName;
      if (destName == null && transferBuffer.isNotEmpty) {
        destName = transferBuffer.last['destination']?['name'];
      }
      destName = displayDestinationName(destName);

      // Determine instruction text based on context
      String instruction;
      bool isWaitInstruction = false;
      final isAtSameStation = _sameTransitStation(
        lastStationId,
        lastStationName,
        nextStationId,
        destName,
      );
      String? nextPlat = nextPlatform;

      // Calculate distance if coordinates are available
      double distanceInMeters = 0;
      if (startLat != null &&
          startLng != null &&
          endLat != null &&
          endLng != null) {
        distanceInMeters =
            Geolocator.distanceBetween(startLat, startLng, endLat, endLng);
      }

      // Logic:
      // - If distance is significant (> 50m), it's a walk, even if short time.
      // - If distance is small (< 50m) but time is short (< 3 min), it's a phantom walk/wait.
      // - If same station name but significant distance (e.g. big station), show Walk.

      bool isSignificantWalk = distanceInMeters > 50;
      bool isPhantomWalk = !isSignificantWalk &&
          walkMinutes < 3 &&
          nextRideDeparture != null &&
          !isFinalWalk;

      // Some providers return a synthetic first-leg micro transfer to the same
      // station/platform area before the first ride. This should not show as a
      // standalone transfer card.
      if (isFirstStep &&
          transferBuffer.isNotEmpty &&
          nextRideDeparture != null) {
        final firstTransfer = transferBuffer.first;
        final lastTransfer = transferBuffer.last;
        final startsAtNextRideStation = _sameTransitStation(
          stationId(firstTransfer['origin']),
          stationName(firstTransfer['origin']),
          nextStationId,
          nextStationName,
        );
        final endsAtNextRideStation = _sameTransitStation(
          stationId(lastTransfer['destination']),
          stationName(lastTransfer['destination']),
          nextStationId,
          nextStationName,
        );
        if (isPhantomWalk &&
            (startsAtNextRideStation || endsAtNextRideStation)) {
          transferBuffer.clear();
          return;
        }
      }

      String fmtPlat(String? p) => p == null
          ? ''
          : (int.tryParse(p) != null
              ? AppLocalizations.of(context)!.platformShort(p)
              : p);

      if (isAtSameStation) {
        isWaitInstruction = !isSignificantWalk;
        if (lastPlatform != null &&
            nextPlat != null &&
            lastPlatform != nextPlat) {
          instruction = AppLocalizations.of(context)!
              .switchPlatform(fmtPlat(lastPlatform), fmtPlat(nextPlat));
        } else if (isSignificantWalk && nextPlat != null) {
          instruction = '${AppLocalizations.of(context)!.walkLabel} '
              '${AppLocalizations.of(context)!.toPlatform(fmtPlat(nextPlat))}';
        } else if (isSignificantWalk) {
          instruction = AppLocalizations.of(context)!.walkLabel;
        } else if (lastPlatform != null &&
            nextPlat != null &&
            lastPlatform == nextPlat) {
          instruction =
              AppLocalizations.of(context)!.waitAt(fmtPlat(lastPlatform));
        } else if (nextPlat != null) {
          instruction = AppLocalizations.of(context)!.waitAt(fmtPlat(nextPlat));
        } else {
          instruction = AppLocalizations.of(context)!.waitAt(destName ?? '');
        }
      } else if (isPhantomWalk) {
        isWaitInstruction = true;
        if (destName != null && !isAtSameStation) {
          instruction = AppLocalizations.of(context)!.transferTo(destName);
          if (nextPlat != null) instruction += " (${fmtPlat(nextPlat)})";
        } else {
          instruction = AppLocalizations.of(context)!.waitForConnection;
          if (nextPlat != null) {
            instruction +=
                " ${AppLocalizations.of(context)!.atPlatform(fmtPlat(nextPlat))}";
          }
        }
      } else if (isBikeTransfer) {
        if (isFirstStep && destName != null) {
          instruction = bikeInstruction(destName);
          if (nextPlat != null) instruction += ", ${fmtPlat(nextPlat)}";
        } else if (isFinalWalk) {
          instruction = bikeInstruction(destName, isFinal: true);
        } else {
          instruction = bikeInstruction(destName);
          if (nextPlat != null) instruction += ", ${fmtPlat(nextPlat)}";
        }
      } else {
        // It is a walk
        if (isFirstStep && destName != null) {
          instruction = AppLocalizations.of(context)!.walkTo(destName);
          if (nextPlat != null) instruction += ", ${fmtPlat(nextPlat)}";
        } else if (isFinalWalk && destName != null) {
          instruction = AppLocalizations.of(context)!.walkToDestination;
        } else if (destName != null) {
          instruction = AppLocalizations.of(context)!.walkTo(destName);
          if (nextPlat != null) instruction += ", ${fmtPlat(nextPlat)}";
          // If we have arrival platform from previous leg, maybe "Walk from Pl. A to Station..."?
          // But 'lastPlatform' is usually associated with 'lastStationName'.
          // If we walked, we likely left the previous station area.
        } else {
          instruction = AppLocalizations.of(context)!.walkLabel;
          if (nextPlat != null) {
            instruction +=
                " ${AppLocalizations.of(context)!.toPlatform(fmtPlat(nextPlat))}";
          }
        }
      }

      steps.add(JourneyStep(
        type: isWaitInstruction ? 'wait' : (isBikeTransfer ? 'bike' : 'walk'),
        line: isBikeTransfer ? 'Bike' : 'Transfer',
        legIndex: transferBufferLegIndex,
        instruction: instruction,
        duration: FormatUtils.formatDuration(totalGapMinutes),
        departureTime:
            "${blockStart.hour.toString().padLeft(2, '0')}:${blockStart.minute.toString().padLeft(2, '0')}",
        arrivalTime:
            "${blockEnd.hour.toString().padLeft(2, '0')}:${blockEnd.minute.toString().padLeft(2, '0')}",
        isWalking: !isBikeTransfer && (walkMinutes > 0 || isSignificantWalk),
        startLat: startLat,
        startLng: startLng,
        endLat: endLat,
        endLng: endLng,
        path: transferBuffer.isNotEmpty
            ? transferBuffer.first['decodedPath']
            : null,
        dateTime: blockStart,
        walkDuration:
            isBikeTransfer ? Duration.zero : Duration(minutes: walkMinutes),
        bikeDuration:
            isBikeTransfer ? Duration(minutes: walkMinutes) : Duration.zero,
        waitDuration: Duration(minutes: waitMinutes > 0 ? waitMinutes : 0),
      ));
      transferBuffer.clear();
      transferBufferLegIndex = null;
    }

    for (var legIndex = 0; legIndex < legs.length; legIndex++) {
      final leg = legs[legIndex];
      if (leg['line'] != null && leg['line']['name'] != null) {
        DateTime? dep, arr;
        DateTime? scheduledDep, scheduledArr;
        bool isCancelled = leg['cancelled'] == true;

        // Parse scheduled times first
        try {
          // Check both standard keys (scheduledDeparture) and V6/HAFAS keys (plannedDeparture)
          final sDep = leg['scheduledDeparture'] ?? leg['plannedDeparture'];
          if (sDep != null) {
            scheduledDep = DateTime.parse(sDep).toLocal();
          }
          final sArr = leg['scheduledArrival'] ?? leg['plannedArrival'];
          if (sArr != null) {
            scheduledArr = DateTime.parse(sArr).toLocal();
          }
        } catch (e) {/* ignore */}

        // Parse real-time times, fallback to scheduled
        try {
          if (leg['departure'] != null) {
            dep = DateTime.parse(leg['departure']).toLocal();
          }
          if (leg['arrival'] != null) {
            arr = DateTime.parse(leg['arrival']).toLocal();
          }
        } catch (e) {/* ignore */}

        // Fallbacks
        dep ??= scheduledDep;
        arr ??= scheduledArr;

        // If still null, we can't show this leg
        if (dep == null || arr == null) continue;

        flushTransferBuffer(
            dep,
            leg['origin']?['name'],
            leg['origin']?['id']?.toString(),
            leg['origin']?['platform']?.toString(),
            getLat(leg['origin']),
            getLng(leg['origin']));

        int? depDelay;
        int? arrDelay;

        // Calculate delays if scheduled times are available AND we have real times
        // If cancelled, delay calculation might be irrelevant or we assume 0 relative to scheduled
        if (scheduledDep != null && !isCancelled) {
          depDelay = dep.difference(scheduledDep).inMinutes;
        }
        if (scheduledArr != null && !isCancelled) {
          arrDelay = arr.difference(scheduledArr).inMinutes;
        }

        // Special handling for Motis: sometimes 'departureDelay' integer is provided directly
        if (depDelay == null && leg['departureDelay'] is int) {
          depDelay = (leg['departureDelay'] as int) ~/
              60; // Motis often uses seconds? Or check API. Usually it's ms or s. Motis V1 is min.
          // actually Motis v1 usually min.
        }

        steps.add(JourneyStep(
          type: 'ride',
          legIndex: legIndex,
          line: leg['line']?['name']?.toString() ?? '?',
          // If cancelled, show as cancelled in instruction or just handle in UI
          instruction:
              "${leg['line']?['name'] ?? '?'} → ${leg['direction'] ?? 'Destination'}",
          duration: FormatUtils.formatDuration(arr.difference(dep).inMinutes),
          departureTime: DateFormat('HH:mm').format(dep),
          arrivalTime: DateFormat('HH:mm').format(arr),
          chatCount: random.nextInt(15),
          startStationId: leg['origin']?['exactStopId']?.toString() ??
              leg['origin']?['id']?.toString(),
          destinationStationId:
              leg['destination']?['exactStopId']?.toString() ??
                  leg['destination']?['id']?.toString(),
          platform: leg['origin']?['platform']?.toString(),
          arrivalPlatform: leg['destination']?['platform']?.toString(),
          departureStopLabel: leg['origin']?['stopLabel']?.toString(),
          arrivalStopLabel: leg['destination']?['stopLabel']?.toString(),
          stopovers: leg['stopovers'],
          startLat: getLat(leg['origin']),
          startLng: getLng(leg['origin']),
          endLat: getLat(leg['destination']),
          endLng: getLng(leg['destination']),
          path: leg['decodedPath'],
          dateTime: dep, // FIX: Store time
          departureDelay: depDelay,
          arrivalDelay: arrDelay,
          isCancelled: isCancelled,
          plannedDeparture: scheduledDep,
          plannedArrival: scheduledArr,
          startStationName: leg['origin']?['name'],
          destinationName: leg['destination']?['name'],
          headsign: leg['direction'],
          tripId: leg['line']?['tripId']?.toString() ??
              leg['line']?['fahrtNr']?.toString() ??
              leg['tripId']?.toString(), // Populating tripId
          isWakeAlarmOn: widget.alwaysWakeMe,
        ));
        lastArrival = arr;
        lastStationName = leg['destination']?['name'];
        lastStationId = leg['destination']?['id']?.toString();
        lastPlatform = leg['destination']?['platform']?.toString();
      } else {
        transferBufferLegIndex ??= legIndex;
        transferBuffer.add(leg);
      }
    }
    flushTransferBuffer(null, null, null, null, null, null, isFinalWalk: true);
    return steps;
  }

  /// Turns a picked alternative into the full trip: the part of [branchFrom]
  /// already under way, then the alternative. The result remembers where it
  /// branched off, so the traveller can step back to the original.
  Journey _journeyFromAlternative(
    Map<String, dynamic> alternative, {
    required String destinationName,
    Journey? branchFrom,
    int? branchRideLegIndex,
  }) {
    if (branchFrom == null || branchRideLegIndex == null) {
      return _createJourney(alternative,
          destinationNameOverride: destinationName);
    }

    final originalLegs = (branchFrom.rawSource['legs'] as List?) ?? const [];
    final prefix = journeyPrefixLegCount(originalLegs, branchRideLegIndex);
    if (prefix <= 0) {
      return _createJourney(alternative,
          destinationNameOverride: destinationName);
    }

    final spliced = spliceAlternativeIntoJourney(
      original: branchFrom.rawSource,
      alternative: alternative,
      rideLegIndex: branchRideLegIndex,
    );
    final journey = _createJourney(
      spliced,
      destinationNameOverride: destinationName,
    );
    // The first ride of the alternative, not the walk or wait leading up to
    // it: that gap still belongs to the original route.
    final branchStepIndex = journey.steps.indexWhere(
      (step) => step.type == 'ride' && (step.legIndex ?? -1) >= prefix,
    );

    return journey.copyWith(
      parentJourney: branchFrom,
      branchStepIndex: branchStepIndex == -1 ? null : branchStepIndex,
    );
  }

  /// Puts the journey this one branched off from back on screen, adding it
  /// back to the tab if it was closed in the meantime.
  void _returnToParentJourney(RouteTab route, Journey child) {
    final parent = child.parentJourney;
    if (parent == null) return;

    setState(() {
      final idx = _tabs.indexWhere((t) => t.id == route.id);
      if (idx == -1) return;
      final tab = _tabs[idx];
      final stack = List<Journey>.from(tab.stack);
      // A branch can look just like its parent - same start, often the same
      // arrival - so only a non-branch entry counts as the original.
      final alreadyThere =
          stack.any((existing) => _isSameJourneyEntry(existing, parent));
      if (!alreadyThere) stack.add(parent);
      _tabs[idx] = tab.copyWith(
        activeJourney: parent,
        stack: stack,
        steps: parent.steps,
        totalDuration: FormatUtils.formatDuration(parent.duration.inMinutes),
      );
    });

    _resetEarlierAlternativeScans(route.id);
    final refreshed = _tabs.cast<RouteTab?>().firstWhere(
          (tab) => tab?.id == route.id,
          orElse: () => null,
        );
    if (refreshed != null) {
      _scheduleEarlierAlternativeScans(refreshed, parent);
    }
  }

  Journey _createJourney(
    Map<String, dynamic> journeyData, {
    String? destinationNameOverride,
    String? savedConnectionKey,
  }) {
    if (journeyData['legs'] == null) throw Exception("No legs data");
    final List legs = journeyData['legs'];
    final List<JourneyStep> steps = _processLegs(
      legs,
      destinationNameOverride: destinationNameOverride,
    );

    DateTime? dep, arr;
    DateTime? pDep, pArr;
    try {
      if (legs.isNotEmpty) {
        final normalizedLegs = legs.cast<Map<String, dynamic>>();
        final firstLeg = normalizedLegs.first;
        final lastLeg = normalizedLegs.last;
        final firstRideLeg = normalizedLegs.firstWhere(
          (l) => l['line'] != null && l['line']['name'] != null,
          orElse: () => firstLeg,
        );

        // Use full-trip boundaries (including pre/post walk legs) whenever
        // available. Fallback to first ride if providers omit leg-level times
        // for non-ride access/egress legs.
        dep = DateTime.parse(
          firstLeg['departure'] ??
              firstLeg['plannedDeparture'] ??
              firstRideLeg['departure'] ??
              firstRideLeg['plannedDeparture'],
        ).toLocal();
        arr = DateTime.parse(
          lastLeg['arrival'] ?? lastLeg['plannedArrival'],
        ).toLocal();
        pDep = DateTime.parse(
          firstLeg['plannedDeparture'] ??
              firstLeg['departure'] ??
              firstRideLeg['plannedDeparture'] ??
              firstRideLeg['departure'],
        ).toLocal();
        pArr = DateTime.parse(
          lastLeg['plannedArrival'] ?? lastLeg['arrival'],
        ).toLocal();
      } else if (journeyData['departure'] != null &&
          journeyData['arrival'] != null) {
        dep = DateTime.parse(journeyData['departure']).toLocal();
        arr = DateTime.parse(journeyData['arrival']).toLocal();
        pDep = DateTime.parse(
                journeyData['plannedDeparture'] ?? journeyData['departure'])
            .toLocal();
        pArr = DateTime.parse(
                journeyData['plannedArrival'] ?? journeyData['arrival'])
            .toLocal();
      }
    } catch (e) {/* ignore */}

    // Calculate transfer count (rides - 1)
    int rides = steps.where((s) => s.type == 'ride').length;
    int transfers = (rides > 0) ? rides - 1 : 0;

    int waitMinutes = 0;
    for (var step in steps) {
      if (step.type == 'wait' || step.type == 'transfer') {
        if (step.waitDuration != null) {
          waitMinutes += step.waitDuration!.inMinutes;
          continue;
        }
        try {
          final parts = step.duration.split(' ');
          if (parts.isNotEmpty) waitMinutes += int.tryParse(parts[0]) ?? 0;
        } catch (e) {/* ignore */}
      }
    }

    int walkMinutes = 0;
    for (var step in steps) {
      if (step.type == 'walk') {
        if (step.walkDuration != null) {
          walkMinutes += step.walkDuration!.inMinutes;
          continue;
        }
        try {
          final parts = step.duration.split(' ');
          if (parts.isNotEmpty) walkMinutes += int.tryParse(parts[0]) ?? 0;
        } catch (e) {/* ignore */}
      }
    }

    int bikeMinutes = 0;
    for (var step in steps) {
      if (step.type == 'bike') {
        if (step.bikeDuration != null) {
          bikeMinutes += step.bikeDuration!.inMinutes;
          continue;
        }
        try {
          final parts = step.duration.split(' ');
          if (parts.isNotEmpty) bikeMinutes += int.tryParse(parts[0]) ?? 0;
        } catch (e) {/* ignore */}
      }
    }

    return Journey(
      steps: steps,
      departure: dep ?? DateTime.now(),
      arrival: arr ?? DateTime.now(),
      plannedDeparture: pDep,
      plannedArrival: pArr,
      savedConnectionKey: savedConnectionKey,
      duration:
          (dep != null && arr != null) ? arr.difference(dep) : Duration.zero,
      transferCount: transfers,
      totalWaitTime: Duration(minutes: waitMinutes),
      rawSource: journeyData,
      source: journeyData['source'] ?? 'unknown',
      totalWalkingDuration: Duration(minutes: walkMinutes),
      totalBikingDuration: Duration(minutes: bikeMinutes),
    );
  }

  String _addJourneyTab(
      {Map<String, dynamic>? singleJourneyData,
      List<Map<String, dynamic>>? candidatesData,
      String title = "",
      String? subtitle,
      Station? origin,
      Station? destination,
      String? savedConnectionKey,
      RouteSearchSettings? searchSettings}) {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    List<Journey> candidates = [];
    Journey? activeJourney;
    Station? dest = destination ?? _toStation;

    if (candidatesData != null) {
      for (var d in candidatesData) {
        try {
          candidates
              .add(_createJourney(d, destinationNameOverride: dest?.name));
        } catch (e) {/* ignore */}
      }
      if (candidates.isNotEmpty && dest == null) {
        final lastLeg = candidates.first.rawSource['legs'].last;
        final destinationMap =
            (lastLeg['destination'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{};
        final destinationId = destinationMap['id']?.toString() ?? '';
        if (destinationId.isEmpty) return id;
        dest = Station(
            id: destinationId,
            name: destinationMap['name']?.toString() ??
                AppLocalizations.of(context)!.destinationLabel,
            type: "station");
      }
    } else if (singleJourneyData != null) {
      try {
        activeJourney = _createJourney(
          singleJourneyData,
          destinationNameOverride: dest?.name,
          savedConnectionKey: savedConnectionKey,
        );
        candidates = [activeJourney];
        final lastLeg = singleJourneyData['legs'].last;
        if (dest == null) {
          final destinationMap =
              (lastLeg['destination'] as Map?)?.cast<String, dynamic>() ??
                  const <String, dynamic>{};
          final destinationId = destinationMap['id']?.toString() ?? '';
          if (destinationId.isEmpty) return id;
          dest = Station(
              id: destinationId,
              name: destinationMap['name']?.toString() ??
                  AppLocalizations.of(context)!.destinationLabel,
              type: "station");
        }
      } catch (_) {
        return id;
      }
    }

    if (dest == null) return id;

    setState(() {
      _tabs.add(RouteTab(
        id: id,
        title:
            title == AppLocalizations.of(context)!.routeLabel || title.isEmpty
                ? dest!.name
                : title,
        subtitle: subtitle ?? AppLocalizations.of(context)!.details,
        eta: activeJourney != null
            ? DateFormat('HH:mm').format(activeJourney.arrival)
            : "--:--",
        totalDuration: activeJourney != null
            ? FormatUtils.formatDuration(activeJourney.duration.inMinutes)
            : "",
        destination: destination ?? dest!,
        origin: origin ?? _fromStation, // Store origin
        steps: activeJourney?.steps ?? [],
        source: activeJourney?.source,
        candidates: candidates,
        activeJourney: activeJourney,
        stack: activeJourney != null ? [activeJourney] : [], // Init stack
        searchSettings: searchSettings ??
            _fallbackRouteSearchSettingsForSavedJourney(
              singleJourneyData ??
                  (candidatesData?.isNotEmpty == true
                      ? candidatesData!.first
                      : const <String, dynamic>{}),
            ),
      ));
      _activeTabId = id;
    });
    unawaited(_updateJourneyDetectionMonitoring());
    final position = _effectiveCurrentPosition;
    if (position != null) {
      unawaited(_handleJourneyDetectionPosition(position));
    }
    return id;
  }

  void _updateTabCandidates(String tabId, List<Map<String, dynamic>> rawData) {
    if (!mounted) return;
    setState(() {
      final idx = _tabs.indexWhere((t) => t.id == tabId);
      if (idx != -1) {
        final currentTab = _tabs[idx];
        final List<Journey> newJourneys = [];
        for (var d in rawData) {
          try {
            newJourneys.add(
              _createJourney(
                d,
                destinationNameOverride: currentTab.destination.name,
              ),
            );
          } catch (e) {/* ignore */}
        }

        // Remove duplicates and sort
        final Map<String, Journey> uniqueMap = {};
        if (currentTab.candidates != null) {
          for (var j in currentTab.candidates!) {
            final key = _journeyListKey(j);
            uniqueMap[key] = j;
          }
        }
        for (var j in newJourneys) {
          final key = _journeyListKey(j);
          final existing = uniqueMap[key];
          uniqueMap[key] = existing == null
              ? j
              : _preferJourneyWithMorePlatformDetail(existing, j);
        }

        final updatedCandidates = uniqueMap.values.toList();
        updatedCandidates.sort((a, b) => a.departure.compareTo(b.departure));
        final platformSignal = updatedCandidates.fold<int>(
          0,
          (sum, journey) => sum + _journeyPlatformSignal(journey),
        );

        var updatedActiveJourney = currentTab.activeJourney;
        var updatedSteps = currentTab.steps;
        var updatedStack = currentTab.stack;
        if (updatedActiveJourney != null) {
          final previousActiveJourney = updatedActiveJourney;
          final preferredActiveJourney = _bestCurrentJourneyVersion(
            updatedActiveJourney,
            updatedCandidates,
          );
          if (!identical(preferredActiveJourney, previousActiveJourney)) {
            updatedActiveJourney = preferredActiveJourney;
            updatedSteps = preferredActiveJourney.steps;
            updatedStack = currentTab.stack
                .map(
                  (journey) => _journeysLikelySameRoute(
                    journey,
                    previousActiveJourney,
                  )
                      ? preferredActiveJourney
                      : journey,
                )
                .toList();
          }
        }

        _tabs[idx] = currentTab.copyWith(
          candidates: updatedCandidates,
          activeJourney: updatedActiveJourney,
          steps: updatedSteps,
          stack: updatedStack,
        );
        TransportApi.addSyntheticDebugLog(
          'ui: candidates updated tab=$tabId count=${updatedCandidates.length} platformSignal=$platformSignal activeSignal=${updatedActiveJourney == null ? 0 : _journeyPlatformSignal(updatedActiveJourney)}',
        );
      }
    });
    unawaited(_updateJourneyDetectionMonitoring());
  }

  void _replaceTabCandidates(
    String tabId,
    List<Map<String, dynamic>> rawData, {
    RouteSearchSettings? searchSettings,
  }) {
    if (!mounted) return;
    setState(() {
      final idx = _tabs.indexWhere((t) => t.id == tabId);
      if (idx == -1) return;
      final currentTab = _tabs[idx];
      final nextJourneys = <Journey>[];
      for (final data in rawData) {
        try {
          nextJourneys.add(
            _createJourney(
              data,
              destinationNameOverride: currentTab.destination.name,
            ),
          );
        } catch (_) {}
      }
      if (nextJourneys.isEmpty) return;
      _tabs[idx] = currentTab.copyWith(
        candidates: nextJourneys,
        searchSettings: searchSettings,
      );
    });
  }

  Future<void> _rerunRouteTabSearch(
    RouteTab route,
    RouteSearchSettings searchSettings, {
    RouteSortOption? preferredSort,
  }) async {
    if (_isLoadingRoute) return;
    final originStation = route.origin ?? _fromStation;
    if (originStation == null) return;

    final rerunToken = ++_nextRouteSearchToken;
    setState(() {
      _activeRouteSearchToken = rerunToken;
      _isLoadingRoute = true;
      _activeRouteLoadPhases = <String>{};
      if (preferredSort != null) {
        _routeResultsSortSelections[route.id] = preferredSort;
      }
    });

    var hasVisibleResults = false;
    try {
      void handlePartialResults(List<Map<String, dynamic>> partial) {
        if (partial.isEmpty ||
            !mounted ||
            _isRouteSearchCancelled(rerunToken)) {
          return;
        }
        hasVisibleResults = true;
        _replaceTabCandidates(
          route.id,
          partial,
          searchSettings: searchSettings,
        );
      }

      final results = await _searchJourneysForSettings(
        originStation,
        route.destination,
        settings: searchSettings,
        onPartialResults: handlePartialResults,
        onLoadStateChanged: (phases) =>
            _setRouteLoadPhasesForToken(rerunToken, phases),
        shouldContinue: () => !_isRouteSearchCancelled(rerunToken),
      );

      if (_isRouteSearchCancelled(rerunToken) || !mounted) return;
      if (results.isNotEmpty) {
        hasVisibleResults = true;
        _replaceTabCandidates(
          route.id,
          results,
          searchSettings: searchSettings,
        );
      } else {
        final message = searchSettings.isArrival
            ? 'No routes found for that arrival time.'
            : 'No routes found for that departure time.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (error) {
      if (mounted && !_isRouteSearchCancelled(rerunToken)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              hasVisibleResults
                  ? 'Could not finish updating these routes.'
                  : 'Could not update these routes right now.',
            ),
          ),
        );
      }
    } finally {
      _disposeRouteSearch(rerunToken);
    }
  }

  Future<void> _findRoutes() async {
    _cancelActiveBackgroundRouteSearch();
    if (_isLoadingRoute) return;
    TransportApi.clearSyntheticDebugLog();
    TransportApi.addSyntheticDebugLog('ui: find routes tapped');
    final l10n = AppLocalizations.of(context)!;
    final searchToken = ++_nextRouteSearchToken;
    setState(() {
      _activeRouteSearchToken = searchToken;
      _isLoadingRoute = true;
    });

    Station? from = _fromStation;
    if (from == null) {
      if (_fromUsesCurrentLocation ||
          _isCurrentLocationText(_fromController.text)) {
        Position? pos = _effectiveCurrentPosition;
        if (pos == null) {
          try {
            pos = await Geolocator.getCurrentPosition()
                .timeout(const Duration(seconds: 3));
          } catch (e) {/* ignore */}
        }
        if (_isRouteSearchCancelled(searchToken) || !mounted) return;
        if (pos != null) {
          final locationName = await _currentLocationName(pos);
          if (_isRouteSearchCancelled(searchToken) || !mounted) return;
          // Keep GPS coordinates for routing, but retain the resolved place
          // name so recents and frequent journeys do not show a placeholder.
          from = Station(
              id: 'gps',
              name: locationName,
              type: 'location',
              latitude: pos.latitude,
              longitude: pos.longitude);
          TransportApi.addSyntheticDebugLog(
            'ui: using current location ${pos.latitude},${pos.longitude}',
          );
        } else {
          TransportApi.addSyntheticDebugLog('ui: current location unavailable');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.locationNotAvailable)));
          }
          return;
        }
      } else {
        try {
          final results =
              await TransportApi.searchStations(_fromController.text);
          if (_isRouteSearchCancelled(searchToken) || !mounted) return;
          if (results.isNotEmpty) {
            from = results.first;
            _fromStation = from;
            TransportApi.addSyntheticDebugLog(
              'ui: resolved from=${from.name} (${from.id})',
            );
          } else {
            TransportApi.addSyntheticDebugLog('ui: failed to resolve from');
            throw l10n.startNotFound;
          }
        } catch (e) {
          TransportApi.addSyntheticDebugLog('ui: from lookup error=$e');
          if (!_isRouteSearchCancelled(searchToken) && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(
                    AppLocalizations.of(context)!.errorPrefix(e.toString()))));
          }
          return;
        }
      }
    }
    if (_toStation == null) {
      if (_toController.text.isNotEmpty) {
        try {
          final results = await TransportApi.searchStations(_toController.text);
          if (_isRouteSearchCancelled(searchToken) || !mounted) return;
          if (results.isNotEmpty) {
            _toStation = results.first;
            TransportApi.addSyntheticDebugLog(
              'ui: resolved to=${_toStation!.name} (${_toStation!.id})',
            );
          } else {
            TransportApi.addSyntheticDebugLog('ui: failed to resolve to');
            throw l10n.destinationNotFound;
          }
        } catch (e) {
          TransportApi.addSyntheticDebugLog('ui: to lookup error=$e');
          if (!_isRouteSearchCancelled(searchToken) && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(
                    AppLocalizations.of(context)!.errorPrefix(e.toString()))));
          }
          return;
        }
      } else {
        return;
      }
    }
    final Station resolvedFrom = from;

    String? currentTabId;
    var hasDisplayedResults = false;
    var disposeSearchOnExit = true;
    var timedOutWaitingForFinal = false;
    try {
      DateTime when;
      if (_selectedDate != null) {
        when = DateTime(
            _selectedDate!.year,
            _selectedDate!.month,
            _selectedDate!.day,
            _selectedTime?.hour ?? 0,
            _selectedTime?.minute ?? 0);
      } else {
        when = DateTime.now();
      }
      // If "Arrive By" is set but no date selected, "Now" usually implies "Depart Now", so we use departure=Now effectively.
      // But searchJourneys handles 'when'.
      TransportApi.addSyntheticDebugLog(
        'ui: search request from=${resolvedFrom.name} to=${_toStation!.name} when=${when.toIso8601String()} arriveBy=$_isArrival',
      );
      final searchSettings =
          _routeSearchSettingsForRequest(when, isArrival: _isArrival);
      if (_jointPlanningEnabled) {
        await _findJointRoutes(
          myOrigin: resolvedFrom,
          destination: _toStation!,
          settings: searchSettings,
          searchToken: searchToken,
        );
        return;
      }
      void handlePartialResults(List<Map<String, dynamic>> partial) {
        if (!mounted || _isRouteSearchCancelled(searchToken)) {
          TransportApi.addSyntheticDebugLog(
            'ui: partial ignored mounted=$mounted cancelled=${_isRouteSearchCancelled(searchToken)}',
          );
          return;
        }
        if (partial.isEmpty) {
          TransportApi.addSyntheticDebugLog(
            'ui: partial ignored empty (no tab creation)',
          );
          return;
        }
        hasDisplayedResults = true;
        if (currentTabId == null) {
          currentTabId = _addJourneyTab(
              candidatesData: partial,
              origin: resolvedFrom,
              destination: _toStation,
              searchSettings: searchSettings);
          TransportApi.addSyntheticDebugLog(
            'ui: created tab id=$currentTabId token=$searchToken partial=${partial.length}',
          );
        } else {
          TransportApi.addSyntheticDebugLog(
            'ui: update tab id=$currentTabId token=$searchToken partial=${partial.length}',
          );
          _updateTabCandidates(currentTabId!, partial);
        }
        _releaseBlockingRouteLoad(searchToken);
      }

      Future<void> handleFinalResults(
        List<Map<String, dynamic>> res, {
        bool late = false,
      }) async {
        if (_isRouteSearchCancelled(searchToken) || !mounted) return;

        if (res.isNotEmpty) {
          hasDisplayedResults = true;
          if (currentTabId != null) {
            TransportApi.addSyntheticDebugLog(
              'ui: ${late ? 'late ' : ''}final update tab id=$currentTabId token=$searchToken results=${res.length}',
            );
            _updateTabCandidates(currentTabId!, res);
          } else {
            currentTabId = _addJourneyTab(
                candidatesData: res,
                origin: resolvedFrom,
                destination: _toStation,
                searchSettings: searchSettings);
            TransportApi.addSyntheticDebugLog(
              'ui: created tab from ${late ? 'late ' : ''}final id=$currentTabId token=$searchToken results=${res.length}',
            );
            _releaseBlockingRouteLoad(searchToken);
          }
          if (_isRouteSearchCancelled(searchToken)) return;
          await SearchHistoryManager.saveJourney(resolvedFrom, _toStation!);
          if (_isRouteSearchCancelled(searchToken)) return;
          await SearchHistoryManager.saveRecentJourney(
              resolvedFrom, _toStation!);
          if (_isRouteSearchCancelled(searchToken) || !mounted) return;
          await _loadHistoryData(); // Refresh UI
        } else if (currentTabId == null && mounted && !late) {
          TransportApi.addSyntheticDebugLog('ui: no routes found');
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(AppLocalizations.of(context)!.noRoutesFoundBusy)));
        }
      }

      late final Future<List<Map<String, dynamic>>> searchFuture;
      searchFuture = _searchJourneysForSettings(
        resolvedFrom,
        _toStation!,
        settings: searchSettings,
        onLoadStateChanged: (phases) =>
            _setRouteLoadPhasesForToken(searchToken, phases),
        shouldContinue: () => !_isRouteSearchCancelled(searchToken),
        onPartialResults: handlePartialResults,
      );

      final res = await searchFuture.timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          timedOutWaitingForFinal = true;
          disposeSearchOnExit = false;
          TransportApi.addSyntheticDebugLog(
            'ui: search timed out token=$searchToken visibleResults=$hasDisplayedResults; waiting for late final',
          );
          _releaseBlockingRouteLoad(searchToken);
          if (mounted && !hasDisplayedResults) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(l10n.requestTimedOut)));
          }
          searchFuture
              .then((lateResults) => handleFinalResults(
                    lateResults,
                    late: true,
                  ))
              .catchError((error) {
            TransportApi.addSyntheticDebugLog(
              'ui: late search error token=$searchToken error=$error',
            );
          }).whenComplete(() {
            TransportApi.addSyntheticDebugLog(
              'ui: late search finished token=$searchToken',
            );
            _disposeRouteSearch(searchToken);
          });
          return const <Map<String, dynamic>>[];
        },
      );

      if (timedOutWaitingForFinal) return;
      await handleFinalResults(res);
    } on TimeoutException catch (_) {
      _cancelledRouteSearchTokens.add(searchToken);
      TransportApi.addSyntheticDebugLog(
        'ui: search timed out token=$searchToken visibleResults=$hasDisplayedResults',
      );
      if (!_isRouteSearchCancelled(searchToken) &&
          mounted &&
          !hasDisplayedResults) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.requestTimedOut)));
      }
    } catch (e) {
      TransportApi.addSyntheticDebugLog(
          'ui: search error token=$searchToken $e');
      if (!_isRouteSearchCancelled(searchToken) && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)!.serviceBusyMoment)));
      }
    } finally {
      TransportApi.addSyntheticDebugLog(
          'ui: search finished token=$searchToken');
      if (disposeSearchOnExit) {
        _disposeRouteSearch(searchToken);
      }
    }
  }

  Future<void> _findJointRoutes({
    required Station myOrigin,
    required Station destination,
    required RouteSearchSettings settings,
    required int searchToken,
  }) async {
    final german = Localizations.localeOf(context).languageCode == 'de';
    final friendOrigin = _friendOriginStation;
    if (friendOrigin == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(german
              ? 'Wähle zuerst, wo deine Begleitung startet.'
              : 'Choose where your companion starts first.'),
        ));
      }
      _releaseBlockingRouteLoad(searchToken);
      return;
    }

    // Only a shared live position can go out of date; a place that was typed
    // in stays valid until the user changes it.
    final friend = _selectedJointFriend;
    if (friend != null && friend.isStale()) {
      final ageNote = _friendLocationAgeNote(friend, german: german);
      final useStaleLocation = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(german ? 'Standort ist älter' : 'Location may be stale'),
          content: Text(german
              ? '$ageNote Soll der geteilte Standort von ${friend.name} trotzdem als Start verwendet werden?'
              : '$ageNote Use what ${friend.name} shared as the starting point anyway?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(german ? 'Abbrechen' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(german ? 'Trotzdem verwenden' : 'Use anyway'),
            ),
          ],
        ),
      );
      if (useStaleLocation != true || !mounted) {
        _releaseBlockingRouteLoad(searchToken);
        return;
      }
    }

    final friendName = friend?.name ??
        (friendOrigin.name.trim().isNotEmpty
            ? friendOrigin.name.trim()
            : (german ? 'deine Begleitung' : 'your companion'));
    final preferences = _jointJourneyPreferences;

    try {
      final searches = await Future.wait([
        _searchJourneysForSettings(
          myOrigin,
          destination,
          settings: settings,
          results: 20,
          shouldContinue: () => !_isRouteSearchCancelled(searchToken),
        ),
        _searchJourneysForSettings(
          friendOrigin,
          destination,
          settings: settings,
          results: 20,
          shouldContinue: () => !_isRouteSearchCancelled(searchToken),
        ),
      ]).timeout(const Duration(seconds: 35));
      if (!mounted || _isRouteSearchCancelled(searchToken)) return;

      final mine = <Journey>[];
      final theirs = <Journey>[];
      for (final raw in searches[0]) {
        try {
          mine.add(_createJourney(
            raw,
            destinationNameOverride: destination.name,
          ));
        } catch (_) {
          // A malformed provider alternative should not abort joint ranking.
        }
      }
      for (final raw in searches[1]) {
        try {
          theirs.add(_createJourney(
            raw,
            destinationNameOverride: destination.name,
          ));
        } catch (_) {
          // A malformed provider alternative should not abort joint ranking.
        }
      }

      // Start at the chosen setting and, only if that finds nothing, stretch
      // the budget over the journeys already fetched. Looking beyond those is
      // left to the user.
      final outcome = JointJourneyPlanner.rankProgressively(
        myJourneys: mine,
        friendJourneys: theirs,
        window: JointSearchWindow(
          baseTogetherness: preferences.togetherness,
        ),
        isArrival: settings.isArrival,
      );
      _releaseBlockingRouteLoad(searchToken);
      _addJointJourneyTab(
        outcome: outcome,
        friendId: friend?.id,
        friendName: friendName,
        origin: myOrigin,
        friendOrigin: friendOrigin,
        destination: destination,
        searchSettings: settings,
        myJourneys: mine,
        friendJourneys: theirs,
      );
    } on TimeoutException {
      _releaseBlockingRouteLoad(searchToken);
      if (mounted && !_isRouteSearchCancelled(searchToken)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(german
              ? 'Die gemeinsame Routensuche hat zu lange gedauert.'
              : 'The joint route search took too long.'),
        ));
      }
    }
  }

  void _addJointJourneyTab({
    required JointSearchOutcome outcome,
    required String? friendId,
    required String friendName,
    required Station origin,
    required Station friendOrigin,
    required Station destination,
    required RouteSearchSettings searchSettings,
    required List<Journey> myJourneys,
    required List<Journey> friendJourneys,
  }) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final candidates = _jointTabCandidates(outcome.options);
    setState(() {
      _jointRouteContexts[id] = _JointRouteContext(
        options: outcome.options,
        friendId: friendId,
        friendName: friendName,
        destinationName: destination.name,
        window: outcome.window,
        myOrigin: origin,
        friendOrigin: friendOrigin,
        destination: destination,
        searchSettings: searchSettings,
        myJourneys: myJourneys,
        friendJourneys: friendJourneys,
        exhausted: outcome.needsMoreDepartures && !outcome.window.canFetchMore,
      );
      _tabs.add(RouteTab(
        id: id,
        title: destination.name,
        subtitle: friendName,
        eta: '--:--',
        totalDuration: '',
        destination: destination,
        origin: origin,
        steps: const [],
        candidates: candidates,
        stack: const [],
        searchSettings: searchSettings,
      ));
      _activeTabId = id;
    });
  }

  /// The candidate list a joint tab shows behind the shared options.
  List<Journey> _jointTabCandidates(List<JointJourneyOption> options) {
    final candidates = <Journey>[];
    final seen = <String>{};
    for (final option in options) {
      if (seen.add(_journeyListKey(option.myJourney))) {
        candidates.add(option.myJourney);
      }
    }
    return candidates;
  }

  void _applyJointOutcome(
    String tabId,
    JointSearchOutcome outcome, {
    List<Journey>? myJourneys,
    List<Journey>? friendJourneys,
    bool? exhausted,
    bool isExpanding = false,
  }) {
    final context = _jointRouteContexts[tabId];
    if (context == null) return;
    setState(() {
      _jointRouteContexts[tabId] = context.copyWith(
        options: outcome.options,
        window: outcome.window,
        myJourneys: myJourneys,
        friendJourneys: friendJourneys,
        isExpanding: isExpanding,
        exhausted: exhausted,
      );
      final index = _tabs.indexWhere((tab) => tab.id == tabId);
      if (index == -1) return;
      _tabs[index] = _tabs[index].copyWith(
        candidates: _jointTabCandidates(outcome.options),
      );
    });
  }

  /// One press of "look further": first re-score the journeys already loaded
  /// with a wider budget, and only fetch another page of departures when that
  /// cannot turn up anything better.
  Future<void> _expandJointSearch(String tabId) async {
    final joint = _jointRouteContexts[tabId];
    if (joint == null || joint.isExpanding || !joint.canExpand) return;
    final german = Localizations.localeOf(context).languageCode == 'de';

    final widened = JointJourneyPlanner.rankProgressively(
      myJourneys: joint.myJourneys,
      friendJourneys: joint.friendJourneys,
      window: joint.window,
      previousOptions: joint.options,
      isArrival: joint.searchSettings.isArrival,
    );
    if (!widened.needsMoreDepartures) {
      _applyJointOutcome(tabId, widened);
      return;
    }
    if (!widened.window.canFetchMore) {
      _applyJointOutcome(tabId, widened, exhausted: true);
      return;
    }

    final earlier = widened.window.nextFetchIsEarlier;
    // Show the widened budget while fetching, so the header and the list agree
    // even if the request fails.
    setState(() {
      _jointRouteContexts[tabId] = joint.copyWith(
        options: widened.options,
        window: widened.window,
        isExpanding: true,
      );
    });

    try {
      final fetched = await Future.wait([
        _fetchMoreJointJourneys(
          origin: joint.myOrigin,
          destination: joint.destination,
          existing: joint.myJourneys,
          settings: joint.searchSettings,
          earlier: earlier,
        ),
        _fetchMoreJointJourneys(
          origin: joint.friendOrigin,
          destination: joint.destination,
          existing: joint.friendJourneys,
          settings: joint.searchSettings,
          earlier: earlier,
        ),
      ]).timeout(const Duration(seconds: 35));
      if (!mounted || !_jointRouteContexts.containsKey(tabId)) return;

      final mine = _mergeJourneyCandidates(joint.myJourneys, fetched[0]);
      final theirs = _mergeJourneyCandidates(joint.friendJourneys, fetched[1]);
      final window = widened.window.fetched();
      final outcome = JointJourneyPlanner.rankProgressively(
        myJourneys: mine,
        friendJourneys: theirs,
        window: window,
        previousOptions: joint.options,
        isArrival: joint.searchSettings.isArrival,
      );
      final foundNothingNew =
          outcome.needsMoreDepartures && !outcome.window.canFetchMore;
      _applyJointOutcome(
        tabId,
        outcome,
        myJourneys: mine,
        friendJourneys: theirs,
        exhausted: foundNothingNew || !outcome.window.canExpand,
      );
    } on TimeoutException {
      if (!mounted) return;
      final current = _jointRouteContexts[tabId];
      if (current != null) {
        setState(() {
          _jointRouteContexts[tabId] = current.copyWith(isExpanding: false);
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(german
            ? 'Die Suche nach weiteren Verbindungen hat zu lange gedauert.'
            : 'Looking for more connections took too long.'),
      ));
    } catch (error, stackTrace) {
      AppError.log(
        error,
        stackTrace: stackTrace,
        source: 'RoutesTab._expandJointSearch',
      );
      if (!mounted) return;
      final current = _jointRouteContexts[tabId];
      if (current != null) {
        setState(() {
          _jointRouteContexts[tabId] = current.copyWith(isExpanding: false);
        });
      }
    }
  }

  /// One more page of departures for a single person, just past the edge of
  /// what is already loaded.
  Future<List<Journey>> _fetchMoreJointJourneys({
    required Station origin,
    required Station destination,
    required List<Journey> existing,
    required RouteSearchSettings settings,
    required bool earlier,
  }) async {
    if (existing.isEmpty) return const [];
    final boundary = existing
        .map((journey) => journey.plannedDeparture ?? journey.departure)
        .reduce((a, b) =>
            earlier ? (a.isBefore(b) ? a : b) : (a.isAfter(b) ? a : b));
    final reference = earlier
        ? boundary.subtract(const Duration(hours: 2))
        : boundary.add(const Duration(seconds: 1));

    final raw = await _searchJourneysForSettings(
      origin,
      destination,
      settings: settings.copyWith(when: reference, isArrival: false),
      results: _jointExpansionResultCount,
    );

    final journeys = <Journey>[];
    for (final entry in raw) {
      try {
        journeys.add(_createJourney(
          entry,
          destinationNameOverride: destination.name,
        ));
      } catch (_) {
        // A malformed provider alternative should not abort the expansion.
      }
    }
    journeys.removeWhere((journey) {
      final departure = journey.plannedDeparture ?? journey.departure;
      return earlier
          ? !departure.isBefore(boundary)
          : departure.isBefore(reference);
    });
    return journeys;
  }

  String _jointPlanMessage(
    JointJourneyOption option, {
    required String friendName,
    required String destinationName,
    required bool german,
  }) {
    final format = DateFormat('HH:mm');
    final friendRides = option.friendJourney.steps
        .where((step) => step.type == 'ride')
        .map((step) => step.line.trim())
        .where((line) => line.isNotEmpty)
        .join(' → ');
    final shared = option.sharedDuration.inMinutes;
    final friendDeparture = format.format(option.friendJourney.departure);
    final friendArrival = format.format(option.friendJourney.arrival);
    if (german) {
      return 'Gemeinsamer Routenvorschlag nach $destinationName: '
          '$shared Min. zusammen. Deine Route: $friendDeparture–$friendArrival'
          '${friendRides.isEmpty ? '' : ' · $friendRides'}. '
          'Bitte prüfe die Verbindung vor der Abfahrt noch einmal in Trans.';
    }
    return 'Shared route suggestion to $destinationName: '
        '$shared min together. Your route: $friendDeparture–$friendArrival'
        '${friendRides.isEmpty ? '' : ' · $friendRides'}. '
        'Please check the connection in Trans again before departure.';
  }

  Future<void> _triggerVibration() async {
    if (kIsWeb) return;
    if (!await ForegroundHaptics.hasVibrator()) return;

    final prefs = await SharedPreferences.getInstance();
    final wakeVibrationEnabled =
        prefs.getBool(WakeAlarmSettings.wakeVibrationEnabledPreferenceKey) ??
            true;
    if (!wakeVibrationEnabled) return;
    final patternName = prefs.getString('vibration_pattern') ?? 'standard';
    final intensity = prefs.getInt('vibration_intensity') ?? 128;
    final pattern = WakeAlarmSettings.vibrationPatternForId(patternName);

    await ForegroundHaptics.vibratePattern(
      pattern,
      intensity: intensity,
    );
  }

  Future<void> _triggerLeaveReminderForegroundAlert({
    required String soundId,
    required bool soundEnabled,
    required bool vibrationEnabled,
    required List<int> vibrationPattern,
  }) async {
    if (kIsWeb) return;

    if (soundEnabled) {
      final sound = WakeAlarmSettings.soundForId(soundId);
      await WakeAlarmPreviewPlayer.play(sound);
    }

    if (!vibrationEnabled) return;
    if (!await ForegroundHaptics.hasVibrator()) return;

    final prefs = await SharedPreferences.getInstance();
    final intensity = prefs.getInt('vibration_intensity') ?? 128;
    await ForegroundHaptics.vibratePattern(
      vibrationPattern,
      intensity: intensity,
    );
  }

  Future<void> _showNotification() async {
    final prefs = await SharedPreferences.getInstance();
    final patternName = prefs.getString('vibration_pattern') ?? 'standard';
    final soundId = prefs.getString(WakeAlarmSettings.soundPreferenceKey) ??
        WakeAlarmSettings.defaultSoundId;
    final wakeSoundEnabled =
        prefs.getBool(WakeAlarmSettings.wakeSoundEnabledPreferenceKey) ?? true;
    final wakeVibrationEnabled =
        prefs.getBool(WakeAlarmSettings.wakeVibrationEnabledPreferenceKey) ??
            true;
    final pattern = WakeAlarmSettings.vibrationPatternForId(patternName);
    final androidDetails = NotificationManager.buildWakeAlarmAndroidDetails(
      vibrationPattern: pattern,
      soundId: soundId,
      fullScreenIntent: true,
      soundEnabled: wakeSoundEnabled,
      vibrationEnabled: wakeVibrationEnabled,
    );
    final iosDetails = NotificationManager.buildWakeAlarmIosDetails(
      soundId: soundId,
      soundEnabled: wakeSoundEnabled,
    );
    final details =
        NotificationDetails(android: androidDetails, iOS: iosDetails);
    await _notificationsPlugin.show(
        id: 0,
        title: 'Wake Up!',
        body: 'Approaching your stop!',
        notificationDetails: details);
  }

  void _showEditFavoriteDialog(Favorite fav) async {
    await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _EditFavoriteDialog(favorite: fav));
    if (mounted) _loadFavorites();
  }

  void _addNewFavorite() {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    _showEditFavoriteDialog(Favorite(id: id, label: '', type: 'station'));
  }

  @override
  @override
  Widget build(BuildContext context) {
    final bool canSearch = canStartRouteSearch(
      hasOrigin: _fromStation != null ||
          _fromUsesCurrentLocation ||
          _fromController.text.trim().isNotEmpty,
      hasDestination:
          _toStation != null || _toController.text.trim().isNotEmpty,
      jointPlanningEnabled: _jointPlanningEnabled,
      hasCompanionOrigin: _friendOriginStation != null,
    );
    final colors = TransColors.of(context);
    final topPadding = MediaQuery.of(context).padding.top + 10;

    // Find active tab for secondary row
    RouteTab? activeTab;
    if (_activeTabId != null) {
      try {
        activeTab = _tabs.firstWhere((t) => t.id == _activeTabId);
      } catch (e) {/* ignore */}
    }

    return Column(children: [
      SizedBox(height: topPadding),
      if (_isWakeAlarmSet && _gpsAccuracy != null && _gpsAccuracy! > 100)
        Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            color: Colors.amber,
            child: Text(AppLocalizations.of(context)!.weakGps,
                textAlign: TextAlign.center)),

      // Main Tab Bar
      if (_tabs.isNotEmpty)
        // Pulling down on the strip refreshes the route below without asking
        // the user to scroll the journey back to the top first. The vertical
        // recogniser only claims the gesture once the drag beats the touch
        // slop, so the strip keeps scrolling sideways and the chips, close
        // buttons and "+" keep their taps.
        GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: _handleTabBarVerticalDragStart,
            onVerticalDragUpdate: _handleTabBarVerticalDragUpdate,
            onVerticalDragEnd: _handleTabBarVerticalDragEnd,
            onVerticalDragCancel: _handleTabBarVerticalDragCancel,
            child: SizedBox(
                height: 60,
                child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _tabs.length + 1,
                    itemBuilder: (ctx, idx) {
                      if (idx == _tabs.length) {
                        return Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: () =>
                                    setState(() => _activeTabId = null)));
                      }
                      return _buildTabItem(_tabs[idx], colors);
                    }))),

      // Secondary Tab Row (Alternatives)
      if (activeTab != null &&
          activeTab.stack.length > 1 &&
          activeTab.isStackExpanded)
        _buildSecondaryTabs(activeTab, colors),

      Expanded(
          child: _activeTabId == null
              ? _buildSearchView(canSearch, colors)
              : _buildActiveRouteView(activeTab!)),
    ]);
  }

  Widget _buildTabItem(RouteTab tab, TransColors colors) {
    final isActive = tab.id == _activeTabId;
    final stackCount = tab.stack.length;
    final showStack = stackCount > 1;
    // User mockup shows 3 lines. "Subtabs" likely means alternatives.
    // If only 1 journey is open, do we show 1 line?
    // "just change how many lines there are based on how many subtabs there are".
    // If 1 tab, 1 subtab?
    // Usually "Stack" implies > 1.
    // But if secondary row shows selected item, maybe we always show count.
    // Let's assume stackCount > 0.

    return GestureDetector(
      onTap: () {
        setState(() {
          if (_activeTabId == tab.id) {
            // Toggle expansion if already active
            final idx = _tabs.indexWhere((t) => t.id == tab.id);
            if (idx != -1) {
              _tabs[idx] = tab.copyWith(isStackExpanded: !tab.isStackExpanded);
            }
          } else {
            _activeTabId = tab.id;
            // Ensure it opens expanded? yes, default is true.
          }
        });
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                // Left padding is intentionally omitted here: it is part of the
                // close button's tap target instead, so taps next to the small
                // "x" still close the tab.
                padding: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: isActive ? colors.navBarSelected : colors.cardBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Close Button (Left)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _closeTab(tab.id),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
                        child: Icon(Icons.close,
                            size: 14,
                            color: isActive ? Colors.white70 : Colors.grey),
                      ),
                    ),
                    Icon(Icons.directions,
                        size: 16, color: isActive ? Colors.white : Colors.grey),
                    const SizedBox(width: 6),
                    Text(
                      tab.title,
                      style: TextStyle(
                        color: isActive ? Colors.white : Colors.grey,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (showStack) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10), // Indent to clear rounded corners
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(
                      min(stackCount, 5),
                      (index) => Expanded(
                        child: Container(
                          height: 3,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color:
                                colors.navBarSelected, // Theme color (Purple)
                            borderRadius: BorderRadius.circular(1.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSecondaryTabs(RouteTab tab, TransColors colors) {
    final stack = tab.stack;
    return Container(
      height: 50,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: stack.length,
        separatorBuilder: (ctx, idx) => const SizedBox(width: 8),
        itemBuilder: (ctx, idx) {
          final journey = stack[idx];
          final active = tab.activeJourney;
          final isSelected =
              active != null && _isSameJourneyEntry(active, journey);

          final timeStr =
              "${DateFormat('HH:mm').format(journey.departure)} - ${DateFormat('HH:mm').format(journey.arrival)}";

          return GestureDetector(
              onTap: () {
                setState(() {
                  final tIdx = _tabs.indexWhere((t) => t.id == tab.id);
                  if (tIdx != -1) {
                    _tabs[tIdx] = tab.copyWith(
                      activeJourney: journey,
                      steps: journey.steps,
                      totalDuration: FormatUtils.formatDuration(
                          journey.duration.inMinutes),
                    );
                  }
                });
                // Step indices belong to one journey, so the hints start over.
                _resetEarlierAlternativeScans(tab.id);
                _scheduleEarlierAlternativeScans(tab, journey);
              },
              child: Container(
                // Left padding lives inside the close button's tap target so
                // taps near the small "x" still remove the alternative.
                padding: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: isSelected ? colors.navBarSelected : colors.cardBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Subtabs also have Close button?
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        // Remove this journey from stack
                        setState(() {
                          final tIdx = _tabs.indexWhere((t) => t.id == tab.id);
                          if (tIdx != -1) {
                            final newStack = List<Journey>.from(stack);
                            newStack.removeAt(idx);

                            Journey? newActive = tab.activeJourney;
                            if (newActive != null &&
                                _isSameJourneyEntry(newActive, journey)) {
                              // If we closed the active one, pick another (e.g. last or first)
                              newActive =
                                  newStack.isNotEmpty ? newStack.last : null;
                            }

                            // If stack empty, close tab? Or just clear active?
                            // User: "show routes manually opens". If all closed, tab might close.
                            if (newStack.isEmpty) {
                              _closeTab(tab.id);
                            } else {
                              _tabs[tIdx] = tab.copyWith(
                                stack: newStack,
                                activeJourney: newActive,
                                steps: newActive?.steps ?? [],
                                totalDuration: newActive != null
                                    ? FormatUtils.formatDuration(
                                        newActive.duration.inMinutes)
                                    : "",
                                clearActiveJourney: newActive == null,
                              );
                            }
                          }
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
                        child: Icon(Icons.close,
                            size: 14,
                            color: isSelected ? Colors.white70 : Colors.grey),
                      ),
                    ),
                    Text(
                      timeStr,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ));
        },
      ),
    );
  }

  Widget _buildSearchView(bool canSearch, TransColors colors) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isGerman = Localizations.localeOf(context).languageCode == 'de';
    return GestureDetector(
      onTap: () {
        // Tapping the surrounding page is an explicit way to leave search.
        // Keep taps inside fields and suggestion rows handled by their own
        // controls, as users would expect.
        if (_activeSearchField.isNotEmpty || _suggestions.isNotEmpty) {
          _collapseSearchSuggestions();
        } else {
          FocusScope.of(context).unfocus();
        }
      },
      behavior: HitTestBehavior.translucent,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: EdgeInsets.only(bottom: 100 + keyboardHeight),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: colors.cardBg.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white10)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPlanModeHeader(colors, isGerman: isGerman),
                    const SizedBox(height: 20),
                    if (_jointPlanningEnabled) ...[
                      KeyedSubtree(
                        key: _friendFieldKey,
                        child: _buildTextField(
                          AppLocalizations.of(context)!.friendStartLabel,
                          _friendOriginController,
                          _friendOriginFocusNode,
                          _friendOriginStation != null,
                          'friend',
                          hint: AppLocalizations.of(context)!.friendStartHint,
                          themeTinted: true,
                        ),
                      ),
                      if (_activeSearchField == 'friend')
                        _buildSuggestionsList(),
                      if (_selectedJointFriend?.isStale() == true)
                        Padding(
                          padding: const EdgeInsets.only(top: 8, left: 4),
                          child: Row(
                            key: const ValueKey('joint-stale-location'),
                            children: [
                              const Icon(Icons.schedule,
                                  size: 14, color: Colors.orange),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _friendLocationAgeNote(
                                    _selectedJointFriend!,
                                    german: isGerman,
                                  ),
                                  style: const TextStyle(
                                    color: Colors.orange,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (!canSearch && _friendOriginStation == null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8, left: 4),
                          child: Text(
                            isGerman
                                ? 'Wähle noch, wo deine Begleitung startet.'
                                : 'Still missing where your companion starts.',
                            key: const ValueKey('joint-missing-origin-hint'),
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                    ],
                    KeyedSubtree(
                      key: _fromFieldKey,
                      child: _buildTextField(
                          AppLocalizations.of(context)!.fromLabel,
                          _fromController,
                          _fromFocusNode,
                          _fromStation != null,
                          'from',
                          hint: (_fromStation == null &&
                                  _effectiveCurrentPosition != null)
                              ? AppLocalizations.of(context)!.currentLocation
                              : AppLocalizations.of(context)!
                                  .fromStationOrAddress),
                    ),
                    if (_activeSearchField == 'from') _buildSuggestionsList(),
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 12),
                            KeyedSubtree(
                              key: _toFieldKey,
                              child: _buildTextField(
                                  AppLocalizations.of(context)!.toLabel,
                                  _toController,
                                  _toFocusNode,
                                  _toStation != null,
                                  'to',
                                  hint: AppLocalizations.of(context)!
                                      .toStationOrAddress),
                            ),
                          ],
                        ),
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: 32,
                          child: Center(
                            child: Tooltip(
                              message: 'Swap from and to',
                              child: Semantics(
                                button: true,
                                label: 'Swap from and to',
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _swapRouteEndpoints,
                                  child: SizedBox(
                                    width: 48,
                                    height: 32,
                                    child: Align(
                                      alignment: Alignment.topCenter,
                                      child: SizedBox(
                                        width: 24,
                                        height: 12,
                                        child: Transform.translate(
                                          offset: const Offset(0, 8),
                                          child: Transform.scale(
                                            scale: 1.5,
                                            child: Icon(
                                              Icons.swap_vert_rounded,
                                              color: colors.effectiveSeed,
                                              size: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_activeSearchField == 'to') _buildSuggestionsList(),
                    const SizedBox(height: 20),
                    Text(AppLocalizations.of(context)!.tripTime,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: colors.sectionHeader)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                          color: colors.timeContainerBg,
                          borderRadius: BorderRadius.circular(16)),
                      child: Row(
                        children: [
                          GestureDetector(
                              onTap: () =>
                                  setState(() => _isArrival = !_isArrival),
                              child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                      color: colors.timeToggleBg,
                                      borderRadius: BorderRadius.circular(12)),
                                  child: Text(
                                      _isArrival
                                          ? AppLocalizations.of(context)!
                                              .arriveBy
                                          : AppLocalizations.of(context)!
                                              .departAt,
                                      style: TextStyle(
                                          color: colors.timeToggleText,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                          letterSpacing: 0.5)))),
                          const SizedBox(width: 12),
                          Expanded(
                              child: GestureDetector(
                                  onTap: () async {
                                    final now = DateTime.now();
                                    final picked = await showDatePicker(
                                        context: context,
                                        initialDate: _selectedDate ?? now,
                                        firstDate: now
                                            .subtract(const Duration(days: 30)),
                                        lastDate:
                                            now.add(const Duration(days: 90)));
                                    if (picked != null) {
                                      setState(() {
                                        _selectedDate = picked;
                                        _selectedTime ??= TimeOfDay.now();
                                      });
                                      if (!mounted) return;
                                      final t = await showTimePicker(
                                          context: context,
                                          initialTime: _selectedTime!);
                                      if (t != null) {
                                        setState(() => _selectedTime = t);
                                      }
                                    }
                                  },
                                  child: _selectedDate != null
                                      ? Row(children: [
                                          Icon(Icons.calendar_today,
                                              size: 16,
                                              color: colors.sectionHeader),
                                          const SizedBox(width: 6),
                                          Text(
                                              "${_selectedDate!.day}.${_selectedDate!.month}  ${_selectedTime?.format(context) ?? ''}",
                                              style: TextStyle(
                                                  color: colors.textPrimary,
                                                  fontWeight: FontWeight.bold))
                                        ])
                                      : Row(children: [
                                          Icon(Icons.calendar_today,
                                              size: 16,
                                              color: colors.sectionHeader),
                                          const SizedBox(width: 6),
                                          Text(
                                              AppLocalizations.of(context)!.now,
                                              style: TextStyle(
                                                  color: colors.textPrimary,
                                                  fontWeight: FontWeight.bold))
                                        ]))),
                          if (_showBikeSearchToggle) ...[
                            const SizedBox(width: 8),
                            Tooltip(
                              message: _bikeSearchToggleEnabledForDevice
                                  ? (isGerman
                                      ? 'Fahrrad-Routing aktiviert'
                                      : 'Bike routing enabled')
                                  : (isGerman
                                      ? 'Fahrrad-Routing deaktiviert'
                                      : 'Bike routing disabled'),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () =>
                                    _setBikeSearchToggleEnabledForDevice(
                                  !_bikeSearchToggleEnabledForDevice,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: _bikeSearchToggleEnabledForDevice
                                        ? colors.effectiveSeed.withValues(
                                            alpha: 0.18,
                                          )
                                        : colors.timeToggleBg,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.pedal_bike,
                                    size: 18,
                                    color: _bikeSearchToggleEnabledForDevice
                                        ? colors.effectiveSeed
                                        : colors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          if (_selectedDate != null)
                            IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () => setState(() {
                                      _selectedDate = null;
                                      _selectedTime = null;
                                    })),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: Builder(builder: (context) {
                          return ElevatedButton(
                              onPressed: _isLoadingRoute
                                  ? _cancelRouteSearch
                                  : (canSearch ? _findRoutes : null),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: colors.searchBtnBg,
                                  foregroundColor: colors.searchBtnText,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16))),
                              child: _isLoadingRoute
                                  ? Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: colors.searchBtnText)),
                                        const SizedBox(width: 12),
                                        Text(
                                            AppLocalizations.of(context)!
                                                .cancel,
                                            style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold))
                                      ],
                                    )
                                  : Text(
                                      _jointPlanningEnabled
                                          ? (isGerman
                                              ? 'Gemeinsame Route finden'
                                              : 'Find a shared route')
                                          : AppLocalizations.of(context)!
                                              .findRoutes,
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold)));
                        })),
                    if (kDebugMode) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          spacing: 8,
                          alignment: WrapAlignment.end,
                          children: [
                            TextButton.icon(
                              onPressed: _showPlatformLookupDialog,
                              icon: const Icon(Icons.train_outlined, size: 18),
                              label: const Text('Platform Check'),
                            ),
                            TextButton.icon(
                              onPressed: _copySyntheticDebugLogs,
                              icon: const Icon(Icons.bug_report_outlined,
                                  size: 18),
                              label: const Text('Copy Debug Logs'),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Text(AppLocalizations.of(context)!.favorites,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: colors.sectionHeader)),
                    const SizedBox(height: 8),
                    SizedBox(
                        height: 80,
                        child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _favorites.length + 1,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 12),
                            itemBuilder: (ctx, idx) {
                              if (idx == _favorites.length) {
                                return GestureDetector(
                                    onTap: _addNewFavorite,
                                    child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Container(
                                              width: 48,
                                              height: 48,
                                              decoration: BoxDecoration(
                                                  color: colors.favAddBg,
                                                  shape: BoxShape.circle),
                                              child: Icon(Icons.add,
                                                  color: colors.favAddIcon)),
                                          const SizedBox(height: 4),
                                          Text(
                                              AppLocalizations.of(context)!.add,
                                              style: TextStyle(fontSize: 10))
                                        ]));
                              }
                              final fav = _favorites[idx];
                              final icon = _favoriteIcon(fav);
                              return GestureDetector(
                                  onTap: () => _onFavoriteTap(fav),
                                  onLongPress: () =>
                                      _showEditFavoriteDialog(fav),
                                  child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Container(
                                            width: 48,
                                            height: 48,
                                            decoration: BoxDecoration(
                                                color: colors.favStationBg,
                                                shape: BoxShape.circle),
                                            child: Icon(icon,
                                                color: colors.favStationIcon,
                                                size: 20)),
                                        const SizedBox(height: 4),
                                        Text(fav.label,
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: colors.favText))
                                      ]));
                            })),
                    _buildRouteHistorySection(colors),
                    _buildSavedJourneys(colors),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRouteHistorySection(TransColors colors) {
    if (_frequentJourneys.isEmpty && _recentJourneys.isEmpty) {
      return const SizedBox.shrink();
    }

    final showingFrequent = _historyView == RouteHistoryView.frequent;
    final journeys = showingFrequent ? _frequentJourneys : _recentJourneys;

    return Container(
      margin: const EdgeInsets.only(top: 16, left: 16, right: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                      showingFrequent
                          ? AppLocalizations.of(context)!.frequentJourneys
                          : 'Recent routes',
                      style: TextStyle(
                          color: colors.sectionHeader,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ),
              ),
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                    color: colors.cardBg,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: colors.divider)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildHistoryToggleChip(
                        colors: colors,
                        label: 'Frequent',
                        selected: showingFrequent,
                        onTap: () => setState(
                            () => _historyView = RouteHistoryView.frequent)),
                    _buildHistoryToggleChip(
                        colors: colors,
                        label: 'Recent',
                        selected: !showingFrequent,
                        onTap: () => setState(
                            () => _historyView = RouteHistoryView.recent)),
                  ],
                ),
              ),
            ],
          ),
          if (journeys.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: colors.cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10)),
              child: Text(AppLocalizations.of(context)!.noRecentRoutesYet,
                  style: TextStyle(color: colors.searchHintText)),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: journeys.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, idx) => _buildRouteHistoryCard(
                  colors: colors,
                  item: journeys[idx],
                  icon: showingFrequent ? Icons.bolt : Icons.history),
            ),
        ],
      ),
    );
  }

  Widget _buildSavedJourneys(TransColors colors) {
    if (_savedJourneys.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();
    final savedToShow = List<Map<String, dynamic>>.from(_savedJourneys)
      ..sort((a, b) {
        final aDone = _isSavedJourneyCompleted(a);
        final bDone = _isSavedJourneyCompleted(b);
        if (aDone != bDone) return aDone ? 1 : -1;
        final aDep = _savedJourneyDepartureLocal(a) ?? now;
        final bDep = _savedJourneyDepartureLocal(b) ?? now;
        return aDep.compareTo(bDep);
      });

    return Container(
      margin: const EdgeInsets.only(top: 16, left: 16, right: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Row(
              children: [
                Text(AppLocalizations.of(context)!.savedRoutesTitle,
                    style: TextStyle(
                        color: colors.sectionHeader,
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
                const SizedBox(width: 8),
                Text(AppLocalizations.of(context)!.savedRoutesAutoDelete,
                    style:
                        TextStyle(color: colors.searchHintText, fontSize: 11)),
              ],
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: savedToShow.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, idx) {
              final item = savedToShow[idx];
              final cardKey = _savedJourneyUiKey(item) ?? 'saved-$idx';
              final isCompleted = _isSavedJourneyCompleted(item);
              final isLegacy = _isLegacySavedJourney(item);
              final departure = _savedJourneyDepartureLocal(item);
              final hasStarted =
                  departure != null && !DateTime.now().isBefore(departure);
              final showingReminderPicker =
                  _savedReminderPickerVisibleFor.contains(cardKey);
              final showingCompletedDelete =
                  _savedCompletedDeleteVisibleFor.contains(cardKey);
              final reminderOptions = _savedJourneyReminderOptions(item);
              return _buildSavedJourneyCard(
                colors: colors,
                item: item,
                showingReminderPicker: showingReminderPicker,
                showingCompletedDelete: showingCompletedDelete,
                isCompleted: isCompleted,
                selectedReminderMinutes:
                    _savedJourneyReminderMinutesList(item).toSet(),
                reminderOptions: reminderOptions,
                onTap: () {
                  if (showingCompletedDelete) {
                    setState(() {
                      _savedCompletedDeleteVisibleFor.remove(cardKey);
                    });
                    return;
                  }
                  if (showingReminderPicker) {
                    setState(() {
                      _savedReminderPickerVisibleFor.remove(cardKey);
                    });
                    return;
                  }
                  if (isCompleted) return;
                  _openSavedJourney(item);
                },
                onLongPress: () {
                  if (savedJourneyLongPressShowsDelete(
                    isCompleted: isCompleted,
                    isLegacy: isLegacy,
                    hasStarted: hasStarted,
                  )) {
                    setState(() {
                      _savedReminderPickerVisibleFor.remove(cardKey);
                      _savedCompletedDeleteVisibleFor
                        ..clear()
                        ..add(cardKey);
                    });
                    return;
                  }
                  setState(() {
                    _savedCompletedDeleteVisibleFor.remove(cardKey);
                    _savedReminderPickerVisibleFor
                      ..clear()
                      ..add(cardKey);
                  });
                },
                onReminderSelected: (minutes) {
                  _setSavedJourneyReminder(item, minutes);
                },
                onCloseReminderPicker: () {
                  setState(() {
                    _savedReminderPickerVisibleFor.remove(cardKey);
                  });
                },
                onDeletePressed: () {
                  _deleteSavedJourney(item);
                },
                onCloseCompletedDelete: () {
                  setState(() {
                    _savedCompletedDeleteVisibleFor.remove(cardKey);
                  });
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSavedJourneyCard({
    required TransColors colors,
    required Map<String, dynamic> item,
    required bool showingReminderPicker,
    required bool showingCompletedDelete,
    required bool isCompleted,
    required Set<int> selectedReminderMinutes,
    required List<({int leadMinutes, int waitMinutes})> reminderOptions,
    required VoidCallback onTap,
    required VoidCallback onLongPress,
    required ValueChanged<int?> onReminderSelected,
    required VoidCallback onCloseReminderPicker,
    required VoidCallback onDeletePressed,
    required VoidCallback onCloseCompletedDelete,
  }) {
    final from = Station.fromJson(item['from']);
    final to = Station.fromJson(item['to']);

    Widget buildReminderButton(({int leadMinutes, int waitMinutes}) option) {
      final selected = selectedReminderMinutes.contains(option.leadMinutes);
      final accent = colors.navBarSelected;
      final fg = selected
          ? (accent.computeLuminance() > 0.5 ? Colors.black : Colors.white)
          : accent;

      return Expanded(
        child: GestureDetector(
          onTap: () => onReminderSelected(option.leadMinutes),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            alignment: Alignment.center,
            height: 36,
            decoration: BoxDecoration(
              color: selected ? accent : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: accent,
                width: 1.2,
              ),
            ),
            child: Text(
              '${option.waitMinutes}min',
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: isCompleted
                ? colors.cardBg.withValues(alpha: 0.55)
                : colors.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10)),
        child: showingCompletedDelete
            ? Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: onDeletePressed,
                      child: Container(
                        alignment: Alignment.center,
                        height: 36,
                        decoration: BoxDecoration(
                          color: colors.iconDelete,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          AppLocalizations.of(context)!.delete,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: onCloseCompletedDelete,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: colors.searchHintText),
                      ),
                      child: Icon(
                        Icons.close,
                        color: colors.searchHintText,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              )
            : showingReminderPicker
                ? Row(
                    children: [
                      ...reminderOptions.expand((option) => [
                            buildReminderButton(option),
                            const SizedBox(width: 8),
                          ]),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: onCloseReminderPicker,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: colors.searchHintText),
                          ),
                          child: Icon(
                            Icons.close,
                            color: colors.searchHintText,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: (isCompleted
                                      ? colors.searchHintText
                                      : colors.navBarSelected)
                                  .withValues(alpha: 0.2),
                              shape: BoxShape.circle),
                          child: Icon(Icons.bookmark,
                              color: isCompleted
                                  ? colors.searchHintText
                                  : colors.navBarSelected,
                              size: 18)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(to.name,
                                style: TextStyle(
                                    color: isCompleted
                                        ? colors.textSecondary
                                        : colors.textPrimary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14)),
                            const SizedBox(height: 2),
                            Text(
                                _savedJourneyTimeLabel(item) ??
                                    AppLocalizations.of(context)!
                                        .fromStation(from.name),
                                style: TextStyle(
                                    color: isCompleted
                                        ? colors.textSecondary
                                        : colors.searchHintText,
                                    fontSize: 12)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          color: colors.searchHintText, size: 20)
                    ],
                  ),
      ),
    );
  }

  Widget _buildHistoryToggleChip(
      {required TransColors colors,
      required String label,
      required bool selected,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color: selected ? colors.chipActiveBg : Colors.transparent,
            borderRadius: BorderRadius.circular(999)),
        child: Text(label,
            style: TextStyle(
                color: selected ? colors.chipActiveFg : colors.chipFg,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                fontSize: 12)),
      ),
    );
  }

  Widget _buildRouteHistoryCard(
      {required TransColors colors,
      required Map<String, dynamic> item,
      required IconData icon,
      VoidCallback? onTap,
      String? subtitleOverride}) {
    final from = Station.fromJson(item['from']);
    final to = Station.fromJson(item['to']);

    return GestureDetector(
      onTap: onTap ?? () => _applyRouteHistorySelection(item),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: colors.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10)),
        child: Row(
          children: [
            Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: colors.navBarSelected.withValues(alpha: 0.2),
                    shape: BoxShape.circle),
                child: Icon(icon, color: colors.navBarSelected, size: 18)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(to.name,
                      style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(
                      subtitleOverride ??
                          AppLocalizations.of(context)!.fromStation(from.name),
                      style: TextStyle(
                          color: colors.searchHintText, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: colors.searchHintText, size: 20)
          ],
        ),
      ),
    );
  }

  JointPlanFriend? _jointFriendForStation(Station station) {
    final friendId = JointPlanFriend.friendIdFromStation(station);
    if (friendId == null) return null;
    for (final friend in _jointPlanningFriends) {
      if (friend.id == friendId) return friend;
    }
    return null;
  }

  Widget _buildSuggestionsList() {
    if (!_isSuggestionsLoading && _suggestions.isEmpty) {
      return const SizedBox.shrink();
    }
    final colors = TransColors.of(context);
    final isGerman = Localizations.localeOf(context).languageCode == 'de';
    final sections = _buildSuggestionSections();
    return GestureDetector(
      onTap: () {
        // Capture taps on the list container (including scrolling area)
        // to prevent them from bubbling up to the main view's tap handler
        // which closes the keyboard.
      },
      child: Container(
          constraints: const BoxConstraints(maxHeight: 250),
          margin: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(
              color: colors.cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10)),
          child: Material(
            // Wrap in Material for InkWell/Hover effects
            type: MaterialType.transparency,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.hardEdge,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_isSuggestionsLoading) const SizedBox.shrink(),
              Flexible(
                child: ListView.builder(
                  controller: _suggestionsScrollController,
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: sections.length,
                  itemBuilder: (ctx, idx) {
                    final section = sections[idx];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (section.title != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                            child: Text(
                              section.title!,
                              style: TextStyle(
                                color: colors.searchHintText,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ...section.items.asMap().entries.map((entry) {
                          final item = entry.value;
                          final isLastItem = idx == sections.length - 1 &&
                              entry.key == section.items.length - 1;

                          Widget tile;
                          if (item is Favorite) {
                            tile = ListTile(
                              leading: Icon(_favoriteIcon(item),
                                  size: 16, color: Colors.orange),
                              title: Text(item.label,
                                  style: TextStyle(
                                      color: colors.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold)),
                              onTap: () => _selectItem(item),
                              hoverColor: Colors.white10,
                            );
                          } else {
                            final station = item as Station;
                            final friendForStation =
                                _jointFriendForStation(station);
                            IconData leadingIcon = Icons.place;
                            if (friendForStation != null) {
                              leadingIcon = Icons.person_pin_circle;
                            } else if (station.type == 'address') {
                              leadingIcon = Icons.home_work;
                            } else if (station.type == 'stop') {
                              leadingIcon = Icons.train;
                            }

                            final distanceText =
                                _distanceTextForStation(station);
                            final subtitleText = friendForStation != null
                                ? (isGerman
                                    ? 'Geteilter Standort · ${JointFriendChips.freshnessLabel(friendForStation, german: true)}'
                                    : 'Shared location · ${JointFriendChips.freshnessLabel(friendForStation, german: false)}')
                                : station.locationSummary;

                            tile = ListTile(
                              leading: Icon(leadingIcon,
                                  size: 16,
                                  color: friendForStation != null
                                      ? colors.effectiveSeed
                                      : Colors.grey),
                              title: Text(station.name,
                                  style: TextStyle(
                                      color: colors.textPrimary, fontSize: 14)),
                              subtitle: subtitleText != null
                                  ? Text(subtitleText,
                                      style: TextStyle(
                                          color: colors.searchHintText,
                                          fontSize: 11))
                                  : null,
                              trailing: distanceText != null
                                  ? Text(distanceText,
                                      style: TextStyle(
                                          color: colors.searchHintText,
                                          fontSize: 12))
                                  : null,
                              onTap: () => _selectItem(station),
                              hoverColor: Colors.white10,
                              onLongPress: () {
                                final newFav = Favorite(
                                    id: DateTime.now()
                                        .millisecondsSinceEpoch
                                        .toString(),
                                    label: station.name,
                                    type: 'station',
                                    station: station);
                                _showEditFavoriteDialog(newFav);
                              },
                            );
                          }

                          if (isLastItem) return tile;

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              tile,
                              const Divider(height: 1, color: Colors.white10),
                            ],
                          );
                        }),
                      ],
                    );
                  },
                ),
              ),
            ]),
          )),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller,
      FocusNode focusNode, bool isSelected, String fieldKey,
      {String hint = "", bool themeTinted = false}) {
    final colors = TransColors.of(context);
    Color iconColor = colors.searchInputIcon;
    final inputFill = themeTinted
        ? Color.alphaBlend(
            colors.effectiveSeed.withValues(alpha: 0.13),
            colors.searchInputFill,
          )
        : colors.searchInputFill;
    final themedBorder = BorderSide(
      color: colors.effectiveSeed.withValues(alpha: 0.32),
    );

    String effectiveHint = hint;
    bool isLocationHint = false;

    if (fieldKey == 'from' &&
        _fromStation == null &&
        _effectiveCurrentPosition != null) {
      effectiveHint =
          _currentAddress ?? AppLocalizations.of(context)!.currentLocation;
      isLocationHint = true;
    }

    final isCapturedCurrentLocation =
        fieldKey == 'to' && _toIsCapturedCurrentLocation;
    final usesFriendLocation =
        fieldKey == 'friend' && _selectedJointFriend != null;

    if (usesFriendLocation) {
      iconColor = colors.effectiveSeed;
    } else if (isCapturedCurrentLocation) {
      iconColor = Colors.blue;
    } else if (isSelected) {
      iconColor = Colors.greenAccent;
    } else if ((fieldKey == 'from' &&
            ((_fromStation?.id == 'gps') ||
                (isLocationHint &&
                    effectiveHint !=
                        AppLocalizations.of(context)!.fromStationOrAddress))) ||
        isCapturedCurrentLocation) {
      iconColor = Colors.blue;
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text(label.toUpperCase(),
              style: TextStyle(
                  fontSize: 10,
                  color: themeTinted ? colors.effectiveSeed : Colors.grey,
                  fontWeight: FontWeight.bold))),
      TextField(
          key: ValueKey('route-search-field-$fieldKey'),
          controller: controller,
          focusNode: focusNode,
          onChanged: (val) => _onSearchChanged(val, fieldKey),
          onTap: () {
            if (fieldKey == 'from' &&
                controller.text.isEmpty &&
                isLocationHint &&
                _currentAddress != null) {
              controller.text = _currentAddress!;
              _fromUsesCurrentLocation = true;
              // Select all text so user can easily overwrite it
              controller.selection = TextSelection(
                  baseOffset: 0, extentOffset: controller.text.length);
              _onSearchChanged(_currentAddress!, fieldKey);
            } else if (fieldKey == 'from' &&
                controller.text == _currentAddress) {
              _fromUsesCurrentLocation = true;
              // If already populated with current address, select all on tap
              controller.selection = TextSelection(
                  baseOffset: 0, extentOffset: controller.text.length);
            }
            setState(() => _activeSearchField = fieldKey);
            _fetchSuggestions();
            _scrollToTop();
          },
          style: TextStyle(color: colors.searchInputText),
          decoration: InputDecoration(
              filled: true,
              fillColor: inputFill,
              prefixIcon: fieldKey == 'from'
                  ? IconButton(
                      tooltip: AppLocalizations.of(context)!.refreshLocation,
                      onPressed: _isRefreshingLocation
                          ? null
                          : () => _refreshCurrentLocationManually(),
                      icon: _isRefreshingLocation
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: iconColor,
                              ),
                            )
                          : Icon(Icons.my_location, color: iconColor, size: 20),
                    )
                  : Icon(
                      fieldKey == 'friend'
                          ? (usesFriendLocation
                              ? Icons.person_pin_circle
                              : Icons.person_search)
                          : isCapturedCurrentLocation
                              ? Icons.my_location
                              : Icons.location_on,
                      color: iconColor,
                      size: 20,
                    ),
              suffixIcon: (controller.text.isNotEmpty || isSelected)
                  ? IconButton(
                      icon: Icon(Icons.close,
                          size: 16, color: colors.searchHintText),
                      onPressed: () {
                        controller.clear();
                        _onSearchChanged('', fieldKey);
                      },
                    )
                  : null,
              hintText: effectiveHint,
              hintStyle: TextStyle(
                  color: isLocationHint
                      ? Colors.blue.withValues(alpha: 0.8)
                      : colors.searchHintText),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: themeTinted ? themedBorder : BorderSide.none),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: themeTinted ? themedBorder : BorderSide.none),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: themeTinted
                      ? BorderSide(
                          color: colors.effectiveSeed,
                          width: 1.5,
                        )
                      : BorderSide.none)))
    ]);
  }

  Future<void> _loadMoreRoutes(RouteTab route, {required bool earlier}) async {
    _cancelActiveBackgroundRouteSearch();
    if (_isLoadingRoute) return;
    final loadToken = ++_nextRouteSearchToken;

    // Determine reference time
    DateTime refDate;
    bool isArrival;
    DateTime? earlierBoundary;
    final requestedResults =
        earlier ? _routeLoadEarlierResultCount : _routeLoadMoreResultCount;

    if (earlier) {
      if (route.candidates == null || route.candidates!.isEmpty) return;
      earlierBoundary = route.candidates!
          .map((journey) => journey.plannedDeparture ?? journey.departure)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      refDate = earlierBoundary.subtract(const Duration(hours: 2));
      isArrival = false;
    } else {
      if (route.candidates == null || route.candidates!.isEmpty) return;
      refDate = route.candidates!
          .map((journey) => journey.plannedDeparture ?? journey.departure)
          .reduce((a, b) => a.isAfter(b) ? a : b)
          .add(const Duration(seconds: 1));
      isArrival = false; // Find connections departing after the last one
    }

    TransportApi.addSyntheticDebugLog(
      'route-load-more: start tab=${route.id} direction=${earlier ? 'earlier' : 'later'} '
      'currentCount=${route.candidates?.length ?? 0} ref=${refDate.toIso8601String()} '
      'earlierBoundary=${earlierBoundary?.toIso8601String() ?? 'n/a'} results=$requestedResults',
    );

    setState(() {
      _activeRouteSearchToken = loadToken;
      _isLoadingRoute = true;
      _activeRouteLoadPhases = <String>{};
    });

    try {
      final Station? originStation = route.origin ?? _fromStation;
      if (originStation == null) throw Exception("Origin station lost");
      final visibleResults = Completer<void>();

      void appendResults(List<Map<String, dynamic>> partial) {
        if (partial.isEmpty || !mounted || _isRouteSearchCancelled(loadToken)) {
          return;
        }
        final rawCount = partial.length;
        final List<Journey> newJourneys = [];
        for (var d in partial) {
          try {
            newJourneys.add(
              _createJourney(d,
                  destinationNameOverride: route.destination.name),
            );
          } catch (e) {/* ignore */}
        }
        if (earlier && earlierBoundary != null) {
          newJourneys.removeWhere((journey) {
            final departure = journey.plannedDeparture ?? journey.departure;
            return !departure.isBefore(earlierBoundary!);
          });
        } else if (!earlier) {
          newJourneys.removeWhere((journey) {
            final departure = journey.plannedDeparture ?? journey.departure;
            return departure.isBefore(refDate);
          });
        }
        if (newJourneys.isEmpty) {
          _releaseBlockingRouteLoad(loadToken);
          if (!visibleResults.isCompleted) {
            visibleResults.complete();
          }
          return;
        }

        final idx = _tabs.indexWhere((t) => t.id == route.id);
        if (idx != -1) {
          final currentRoute = _tabs[idx];
          final currentCandidates =
              currentRoute.candidates ?? const <Journey>[];
          final oldCount = currentCandidates.length;
          final updatedCandidates = _mergeJourneyCandidates(
            currentCandidates,
            newJourneys,
          );
          final oldSignature = _journeyRefreshSignature(currentCandidates);
          final newSignature = _journeyRefreshSignature(updatedCandidates);
          final oldPlatformSignal = currentCandidates.fold<int>(
            0,
            (sum, journey) => sum + _journeyPlatformSignal(journey),
          );
          final newPlatformSignal = updatedCandidates.fold<int>(
            0,
            (sum, journey) => sum + _journeyPlatformSignal(journey),
          );
          if (oldSignature != newSignature ||
              oldPlatformSignal != newPlatformSignal) {
            setState(() {
              _tabs[idx] = currentRoute.copyWith(candidates: updatedCandidates);
            });
            TransportApi.addSyntheticDebugLog(
              'route-load-more: partial tab=${route.id} direction=${earlier ? 'earlier' : 'later'} '
              'raw=$rawCount usable=${newJourneys.length}',
            );
            TransportApi.addSyntheticDebugLog(
              'route-load-more: candidates tab=${route.id} direction=${earlier ? 'earlier' : 'later'} '
              'old=$oldCount new=${updatedCandidates.length} delta=${updatedCandidates.length - oldCount}',
            );
          }
        }
        _releaseBlockingRouteLoad(loadToken);
        if (!visibleResults.isCompleted) {
          visibleResults.complete();
        }
      }

      unawaited(
        _searchJourneysForSettings(
          originStation,
          route.destination,
          settings: route.searchSettings.copyWith(
            when: refDate,
            isArrival: isArrival,
          ),
          onLoadStateChanged: (phases) =>
              _setRouteLoadPhasesForToken(loadToken, phases),
          shouldContinue: () => !_isRouteSearchCancelled(loadToken),
          onPartialResults: appendResults,
          results: requestedResults,
        ).then((newResults) {
          if (_isRouteSearchCancelled(loadToken) || !mounted) return;
          appendResults(newResults);
          if (!visibleResults.isCompleted) {
            visibleResults.complete();
          }
        }).catchError((error) {
          if (!visibleResults.isCompleted) {
            visibleResults.completeError(error);
          }
        }).whenComplete(() {
          _disposeRouteSearch(loadToken);
        }),
      );

      await visibleResults.future;
    } catch (e) {
      TransportApi.addSyntheticDebugLog(
        'route-load-more: error tab=${route.id} direction=${earlier ? 'earlier' : 'later'} error=$e',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)!
                .couldNotLoadMoreRoutes(e.toString()))));
      }
    } finally {
      TransportApi.addSyntheticDebugLog(
        'route-load-more: finish tab=${route.id} direction=${earlier ? 'earlier' : 'later'}',
      );
      _releaseBlockingRouteLoad(loadToken);
    }
  }

  Future<void> _refreshRoutes(RouteTab route) async {
    debugRouteResultsRefreshCount += 1;
    if (_isLoadingRoute) return;

    // We want to reset pagination and reload the initial search window.
    final refreshToken = ++_nextRouteSearchToken;
    setState(() {
      _activeRouteSearchToken = refreshToken;
      _isLoadingRoute = true;
      _activeRouteLoadPhases = <String>{};
    });

    try {
      final Station? originStation = route.origin ?? _fromStation;
      if (originStation == null) throw Exception("Origin station lost");
      final previousCandidates = route.candidates ?? const <Journey>[];
      final previousSignature = _journeyRefreshSignature(previousCandidates);
      bool hasRefreshResults = false;
      bool hasChanged = false;

      void handleResults(List<Map<String, dynamic>> partial) {
        if (partial.isEmpty ||
            !mounted ||
            _isRouteSearchCancelled(refreshToken)) {
          return;
        }
        final List<Journey> newJourneys = [];
        for (var d in partial) {
          try {
            newJourneys.add(
              _createJourney(d,
                  destinationNameOverride: route.destination.name),
            );
          } catch (e) {/* ignore */}
        }

        // handleResults may run multiple times (partial + final). We keep the
        // latest comparison so the completion toast reflects the final visible
        // candidate list after refresh settles.
        final newSignature = _journeyRefreshSignature(
          _mergeJourneyCandidates(previousCandidates, newJourneys),
        );
        hasChanged = previousSignature != newSignature;
        hasRefreshResults = true;

        setState(() {
          final idx = _tabs.indexWhere((t) => t.id == route.id);
          if (idx != -1) {
            final currentRoute = _tabs[idx];
            final updatedCandidates = _mergeJourneyCandidates(
              currentRoute.candidates ?? const <Journey>[],
              newJourneys,
            );
            final activeJourney = currentRoute.activeJourney == null
                ? null
                : _bestCurrentJourneyVersion(
                    currentRoute.activeJourney!,
                    updatedCandidates,
                  );
            _tabs[idx] = currentRoute.copyWith(
              candidates: updatedCandidates,
              activeJourney: activeJourney,
              steps: activeJourney?.steps ?? currentRoute.steps,
            );
          }
        });
      }

      final newResults = await _searchJourneysForSettings(
        originStation,
        route.destination,
        settings: route.searchSettings,
        results: 5,
        onLoadStateChanged: (phases) =>
            _setRouteLoadPhasesForToken(refreshToken, phases),
        shouldContinue: () => !_isRouteSearchCancelled(refreshToken),
        onPartialResults: handleResults,
      );
      if (_isRouteSearchCancelled(refreshToken) || !mounted) return;

      handleResults(newResults);
      if (!_isRouteSearchCancelled(refreshToken) && mounted) {
        _showRouteRefreshToast(
          hasRefreshResults
              ? (hasChanged
                  ? "Route refresh finished: alternatives updated."
                  : "Route refresh finished: no changes.")
              : "Route refresh finished.",
        );
      }
    } catch (e) {
      if (mounted && !_isRouteSearchCancelled(refreshToken)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)!
                .couldNotRefreshRoutes(e.toString()))));
      }
    } finally {
      _disposeRouteSearch(refreshToken);
    }
  }

  JourneyStep? _findRealtimeMatchForStep(
      JourneyStep step, List<JourneyStep> freshRideSteps) {
    JourneyStep? match;

    if (step.tripId != null && step.tripId!.isNotEmpty) {
      match = freshRideSteps.cast<JourneyStep?>().firstWhere(
          (candidate) => candidate!.tripId == step.tripId,
          orElse: () => null);
    }

    match ??= freshRideSteps.cast<JourneyStep?>().firstWhere(
        (candidate) =>
            candidate!.plannedDeparture == step.plannedDeparture &&
            candidate.plannedArrival == step.plannedArrival,
        orElse: () => null);

    match ??= freshRideSteps.cast<JourneyStep?>().firstWhere(
        (candidate) =>
            candidate!.line.trim().toLowerCase() ==
                step.line.trim().toLowerCase() &&
            candidate.startStationName == step.startStationName &&
            candidate.destinationName == step.destinationName,
        orElse: () => null);

    return match;
  }

  Journey _mergeRealtimeIntoJourney(Journey existing, Journey fresh) {
    return _mergeJourneyWithFreshRealtime(existing, fresh);
  }

  bool _sameRideIdentity(JourneyStep current, JourneyStep candidate) {
    final currentTripId = current.tripId?.trim();
    final candidateTripId = candidate.tripId?.trim();
    if ((currentTripId?.isNotEmpty ?? false) &&
        (candidateTripId?.isNotEmpty ?? false)) {
      return currentTripId == candidateTripId;
    }

    if (current.plannedDeparture != null &&
        current.plannedArrival != null &&
        candidate.plannedDeparture != null &&
        candidate.plannedArrival != null) {
      return current.plannedDeparture == candidate.plannedDeparture &&
          current.plannedArrival == candidate.plannedArrival &&
          current.startStationName == candidate.startStationName &&
          current.destinationName == candidate.destinationName;
    }

    return current.line.trim().toLowerCase() ==
            candidate.line.trim().toLowerCase() &&
        current.startStationName == candidate.startStationName &&
        current.destinationName == candidate.destinationName &&
        current.headsign == candidate.headsign;
  }

  Journey? _findStrictJourneyMatch(
      Journey currentJourney, List<Journey> candidates) {
    final currentRideSteps =
        currentJourney.steps.where((step) => step.type == 'ride').toList();

    for (final candidate in candidates) {
      final candidateRideSteps =
          candidate.steps.where((step) => step.type == 'ride').toList();

      if (candidateRideSteps.length != currentRideSteps.length) continue;

      if (currentJourney.plannedDeparture != null &&
          candidate.plannedDeparture != null &&
          candidate.plannedDeparture != currentJourney.plannedDeparture) {
        continue;
      }

      if (currentJourney.plannedArrival != null &&
          candidate.plannedArrival != null &&
          candidate.plannedArrival != currentJourney.plannedArrival) {
        continue;
      }

      bool allRideStepsMatch = true;
      for (int i = 0; i < currentRideSteps.length; i++) {
        if (!_sameRideIdentity(currentRideSteps[i], candidateRideSteps[i])) {
          allRideStepsMatch = false;
          break;
        }
      }

      if (allRideStepsMatch) return candidate;
    }

    return null;
  }

  Journey? _findRealtimeJourneyMatch(
      Journey currentJourney, List<Journey> candidates) {
    final strictMatch = _findStrictJourneyMatch(currentJourney, candidates);
    if (strictMatch != null) return strictMatch;

    final currentRideSteps =
        currentJourney.steps.where((step) => step.type == 'ride').toList();
    if (currentRideSteps.isEmpty) return null;

    // Providers can add or remove transfer/walk legs as realtime information
    // changes. When that happens the old strict, whole-itinerary comparison
    // rejects the very same vehicle. Match all ride identities instead, while
    // retaining a tight scheduled-departure guard for services without IDs.
    for (final candidate in candidates) {
      final candidateRideSteps =
          candidate.steps.where((step) => step.type == 'ride').toList();
      if (candidateRideSteps.length != currentRideSteps.length) continue;

      final allRidesMatch = List.generate(currentRideSteps.length, (index) {
        return _sameRideIdentity(
          currentRideSteps[index],
          candidateRideSteps[index],
        );
      }).every((matches) => matches);
      if (!allRidesMatch) continue;

      final scheduledDifference =
          (candidate.plannedDeparture ?? candidate.departure)
              .difference(
                  currentJourney.plannedDeparture ?? currentJourney.departure)
              .abs();
      if (scheduledDifference <= const Duration(minutes: 5)) {
        return candidate;
      }
    }

    return null;
  }

  /// Refresh the selected vehicle directly when it has a MOTIS trip id. This
  /// does not depend on the service appearing in a limited route-search page.
  /// The route-search refresh below remains the fallback for v6-only trips and
  /// also refreshes walking/transfer alternatives.
  bool _liveTripStopMatches(
    Map<String, dynamic> stop,
    String? targetId,
    String? targetName,
  ) {
    final stopId = stop['id']?.toString();
    if (targetId != null && targetId.isNotEmpty && stopId == targetId) {
      return true;
    }
    final stopName = stop['name']?.toString().trim().toLowerCase();
    return targetName != null &&
        targetName.isNotEmpty &&
        stopName == targetName.trim().toLowerCase();
  }

  /// Narrows a whole-trip response to the selected ride's boarding and
  /// alighting stops. MOTIS `/trip` reports the vehicle's complete run, while
  /// a route step can begin at any intermediate stop.
  Journey? _journeyForStepFromLiveTrip(
    Map<String, dynamic> liveTrip,
    JourneyStep selectedStep, {
    required String destinationName,
  }) {
    final selectedTripId = selectedStep.tripId?.trim();
    if (selectedTripId == null || selectedTripId.isEmpty) return null;

    final rawLegs = liveTrip['legs'];
    if (rawLegs is! List) return null;
    for (final rawLeg in rawLegs.whereType<Map>()) {
      final leg = Map<String, dynamic>.from(rawLeg);
      final line = (leg['line'] as Map?)?.cast<String, dynamic>();
      final tripId = line?['tripId']?.toString().trim();
      if (tripId != selectedTripId) continue;

      final stopovers = leg['stopovers'];
      if (stopovers is! List) continue;
      final events = <Map<String, dynamic>>[
        {
          'stop': leg['origin'],
          'departure': leg['departure'],
          'arrival': leg['arrival'],
          'plannedDeparture': leg['plannedDeparture'],
          'plannedArrival': leg['plannedArrival'],
        },
        ...stopovers.whereType<Map>().map(Map<String, dynamic>.from),
        {
          'stop': leg['destination'],
          'departure': leg['departure'],
          'arrival': leg['arrival'],
          'plannedDeparture': leg['plannedDeparture'],
          'plannedArrival': leg['plannedArrival'],
        },
      ];

      int? fromIndex;
      int? toIndex;
      for (var index = 0; index < events.length; index++) {
        final event = events[index];
        final stop = (event['stop'] as Map?)?.cast<String, dynamic>();
        if (stop == null) continue;
        if (fromIndex == null &&
            _liveTripStopMatches(
              stop,
              selectedStep.startStationId,
              selectedStep.startStationName,
            )) {
          fromIndex = index;
          continue;
        }
        if (fromIndex != null &&
            _liveTripStopMatches(
              stop,
              selectedStep.destinationStationId,
              selectedStep.destinationName,
            )) {
          toIndex = index;
          break;
        }
      }
      // A `/trip` response includes every stop on the vehicle's run. Only use
      // it when both ends of this specific ride can be located in order; using
      // the untrimmed response would show stops before boarding and after
      // alighting.
      if (fromIndex == null || toIndex == null || toIndex <= fromIndex) {
        continue;
      }

      final fromEvent = events[fromIndex];
      final toEvent = events[toIndex];

      final fromStop =
          (fromEvent['stop'] as Map?)?.cast<String, dynamic>() ?? const {};
      leg['origin'] = Map<String, dynamic>.from(fromStop);
      leg['departure'] = fromEvent['departure'] ?? fromEvent['arrival'];
      leg['plannedDeparture'] =
          fromEvent['plannedDeparture'] ?? fromEvent['plannedArrival'];

      final toStop =
          (toEvent['stop'] as Map?)?.cast<String, dynamic>() ?? const {};
      leg['destination'] = Map<String, dynamic>.from(toStop);
      leg['arrival'] = toEvent['arrival'] ?? toEvent['departure'];
      leg['plannedArrival'] =
          toEvent['plannedArrival'] ?? toEvent['plannedDeparture'];
      leg['stopovers'] = events.sublist(fromIndex + 1, toIndex);

      return _createJourney(
        {
          'legs': [leg],
          'source': liveTrip['source'] ?? 'motis',
        },
        destinationNameOverride: destinationName,
      );
    }
    return null;
  }

  Future<Journey?> _refreshActiveJourneyFromLiveTrips(
    Journey journey, {
    required String destinationName,
  }) async {
    if (journey.source != 'motis' && journey.source != 'motis_synthetic') {
      return null;
    }

    final tripIds = journey.steps
        .where((step) => step.type == 'ride')
        .map((step) => step.tripId?.trim() ?? '')
        .where((tripId) => tripId.isNotEmpty)
        .toSet();
    if (tripIds.isEmpty) return null;

    var updated = journey;
    var foundMatchingVehicle = false;
    final liveTrips = await Future.wait(
      tripIds.map(TransportApi.fetchLiveTripJourney),
    );
    for (final liveTrip in liveTrips) {
      if (liveTrip == null) continue;
      try {
        for (final selectedStep
            in updated.steps.where((step) => step.type == 'ride')) {
          final freshTrip = _journeyForStepFromLiveTrip(
            liveTrip,
            selectedStep,
            destinationName: destinationName,
          );
          if (freshTrip == null) continue;
          final merged = _mergeJourneyWithFreshRealtime(
            updated,
            freshTrip,
            // A trip response covers the vehicle's full run, not necessarily
            // the user's complete door-to-door itinerary.
            updateJourneyBounds: false,
            replaceRawSource: false,
          );
          if (!identical(merged, updated)) {
            foundMatchingVehicle = true;
            updated = merged;
          }
        }
      } catch (_) {
        // A malformed trip response must not prevent the plan-search fallback.
      }
    }
    return foundMatchingVehicle ? updated : null;
  }

  Future<void> _refreshActiveJourney(
    RouteTab route, {
    bool showCompletionFeedback = true,
  }) async {
    debugActiveJourneyRefreshCount += 1;
    if (_isLoadingRoute || route.activeJourney == null) return;

    final refreshToken = ++_nextRouteSearchToken;
    _activePlatformEnrichmentKeys
        .removeWhere((key) => key.startsWith('${route.id}|'));
    _completedActivePlatformEnrichmentKeys
        .removeWhere((key) => key.startsWith('${route.id}|'));
    setState(() {
      _activeRouteSearchToken = refreshToken;
      _isLoadingRoute = true;
      _activeRouteLoadPhases = <String>{};
    });

    try {
      final Station? originStation = route.origin ?? _fromStation;
      if (originStation == null) throw Exception("Origin station lost");
      final previousJourney = route.activeJourney!;
      final previousSignature = _savedJourneyRealtimeSignature(previousJourney);
      bool hasMatchedUpdate = false;
      String? completionMessage;

      final directTripUpdate = await _refreshActiveJourneyFromLiveTrips(
        previousJourney,
        destinationName: route.destination.name,
      );
      if (_isRouteSearchCancelled(refreshToken) || !mounted) return;
      if (directTripUpdate != null) {
        final directSignature =
            _savedJourneyRealtimeSignature(directTripUpdate);
        setState(() {
          final idx = _tabs.indexWhere((t) => t.id == route.id);
          if (idx == -1 || _tabs[idx].activeJourney == null) return;
          final latest = _tabs[idx];
          final currentActive = latest.activeJourney!;
          final refreshedActive = _mergeJourneyWithFreshRealtime(
            currentActive,
            directTripUpdate,
            updateJourneyBounds: false,
            replaceRawSource: false,
          );
          _tabs[idx] = latest.copyWith(
            activeJourney: refreshedActive,
            steps: refreshedActive.steps,
            candidates: latest.candidates
                ?.map((candidate) => _journeysLikelySameRoute(
                      candidate,
                      currentActive,
                    )
                        ? _mergeJourneyWithFreshRealtime(
                            candidate,
                            directTripUpdate,
                            updateJourneyBounds: false,
                            replaceRawSource: false,
                          )
                        : candidate)
                .toList(),
            stack: latest.stack
                .map((stackedJourney) => _journeysLikelySameRoute(
                      stackedJourney,
                      currentActive,
                    )
                        ? _mergeJourneyWithFreshRealtime(
                            stackedJourney,
                            directTripUpdate,
                            updateJourneyBounds: false,
                            replaceRawSource: false,
                          )
                        : stackedJourney)
                .toList(),
          );
        });
        hasMatchedUpdate = true;
        completionMessage = directSignature != previousSignature
            ? 'Route refresh finished: ${_describeSavedJourneyChange(savedJourney: previousJourney, freshJourney: directTripUpdate)}.'
            : 'Route refresh finished: no changes.';
      }

      // Use planned departure time as the anchor for refresh
      final DateTime refDate =
          previousJourney.plannedDeparture ?? previousJourney.departure;

      void handleResults(List<Map<String, dynamic>> partial) {
        if (partial.isEmpty ||
            !mounted ||
            _isRouteSearchCancelled(refreshToken)) {
          return;
        }
        final idx = _tabs.indexWhere((t) => t.id == route.id);
        if (idx == -1) return;
        final currentRoute = _tabs[idx];
        if (currentRoute.activeJourney == null) return;

        final List<Journey> newJourneys = [];
        for (var d in partial) {
          try {
            newJourneys.add(
              _createJourney(
                d,
                destinationNameOverride: currentRoute.destination.name,
              ),
            );
          } catch (e) {/* ignore */}
        }

        // Find the best match
        final matched = _findRealtimeJourneyMatch(
          currentRoute.activeJourney!,
          newJourneys,
        );

        if (matched != null) {
          final upd =
              _mergeRealtimeIntoJourney(currentRoute.activeJourney!, matched);
          _activePlatformEnrichmentKeys
              .removeWhere((key) => key.startsWith('${route.id}|'));
          _completedActivePlatformEnrichmentKeys
              .removeWhere((key) => key.startsWith('${route.id}|'));
          final updatedSignature = _savedJourneyRealtimeSignature(upd);
          final hasChanged = updatedSignature != previousSignature;
          setState(() {
            final freshIdx = _tabs.indexWhere((t) => t.id == route.id);
            if (freshIdx != -1) {
              final latest = _tabs[freshIdx];
              final newStack = List<Journey>.from(latest.stack);
              final stackIdx = newStack.indexWhere((j) =>
                  j.plannedDeparture ==
                      currentRoute.activeJourney!.plannedDeparture &&
                  j.plannedArrival ==
                      currentRoute.activeJourney!.plannedArrival);
              if (stackIdx != -1) {
                newStack[stackIdx] = upd;
              }

              _tabs[freshIdx] = latest.copyWith(
                  activeJourney: upd,
                  steps: upd.steps,
                  stack: newStack,
                  totalDuration:
                      FormatUtils.formatDuration(upd.duration.inMinutes));
            }
          });
          hasMatchedUpdate = true;
          unawaited(_enrichActiveJourneyPlatforms(route.id, upd));
          completionMessage = hasChanged
              ? "Route refresh finished: ${_describeSavedJourneyChange(savedJourney: previousJourney, freshJourney: matched)}."
              : "Route refresh finished: no changes.";
        }
      }

      final newResults = await _searchJourneysForSettings(
        originStation,
        route.destination,
        settings: route.searchSettings.copyWith(
          // Start well before the selected service. In particular, this keeps
          // pull-to-refresh from missing it when several alternatives precede
          // it in the provider response.
          when: refDate.subtract(const Duration(hours: 1)),
          isArrival: false,
        ),
        // We only need a compact window around the active trip to merge live updates.
        results: _activeJourneyRefreshWindowSize,
        onLoadStateChanged: (phases) =>
            _setRouteLoadPhasesForToken(refreshToken, phases),
        shouldContinue: () => !_isRouteSearchCancelled(refreshToken),
        onPartialResults: handleResults,
      );
      if (_isRouteSearchCancelled(refreshToken) || !mounted) return;

      handleResults(newResults);
      if (showCompletionFeedback &&
          mounted &&
          !_isRouteSearchCancelled(refreshToken)) {
        _showRouteRefreshToast(
          completionMessage ??
              (hasMatchedUpdate
                  ? "Route refresh finished."
                  : "Route refresh finished: no matching update found."),
        );
      }
    } catch (e) {
      if (showCompletionFeedback &&
          mounted &&
          !_isRouteSearchCancelled(refreshToken)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                AppLocalizations.of(context)!.refreshFailed(e.toString()))));
      }
    } finally {
      _disposeRouteSearch(refreshToken);
    }
  }

  Future<void> _showRouteSortAdjustSheet(
    RouteTab route,
    RouteSortOption sort,
  ) async {
    final defaults = await _loadRouteSearchDefaults();
    if (!mounted) return;

    var draft = route.searchSettings;
    final l10n = AppLocalizations.of(context)!;
    final colors = TransColors.of(context);

    String title;
    String subtitle;
    switch (sort) {
      case RouteSortOption.earliestDeparture:
        title = l10n.earliestDep;
        subtitle = l10n.sortSheetEarliestDepHint;
        break;
      case RouteSortOption.earliestArrival:
        title = l10n.earliestArr;
        subtitle = l10n.sortSheetEarliestArrHint;
        break;
      case RouteSortOption.shortestDuration:
        title = l10n.fastest;
        subtitle = l10n.sortSheetFastestHint;
        break;
      case RouteSortOption.leastTransfers:
        title = l10n.leastTransfers;
        subtitle = l10n.sortSheetLeastTransfersHint;
        break;
      case RouteSortOption.shortestWait:
        title = l10n.leastWait;
        subtitle = l10n.sortSheetLeastWaitHint;
        break;
      case RouteSortOption.leastWalking:
        title = l10n.leastWalking;
        subtitle = l10n.sortSheetLeastWalkingHint;
        break;
    }

    final updatedSettings = await showModalBottomSheet<RouteSearchSettings>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            Future<void> pickDateTime({required bool isArrival}) async {
              final pickedDate = await showDatePicker(
                context: sheetContext,
                initialDate: draft.when,
                firstDate: DateTime.now().subtract(const Duration(days: 1)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (pickedDate == null || !sheetContext.mounted) return;
              final pickedTime = await showTimePicker(
                context: sheetContext,
                initialTime: TimeOfDay.fromDateTime(draft.when),
              );
              if (pickedTime == null) return;
              setSheetState(() {
                draft = draft.copyWith(
                  when: DateTime(
                    pickedDate.year,
                    pickedDate.month,
                    pickedDate.day,
                    pickedTime.hour,
                    pickedTime.minute,
                  ),
                  isArrival: isArrival,
                );
              });
            }

            Widget buildSliderTile({
              required String label,
              required String valueText,
              required double value,
              required double min,
              required double max,
              required int divisions,
              required ValueChanged<double> onChanged,
              required VoidCallback onReset,
            }) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$label: $valueText',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Slider(
                    value: value,
                    min: min,
                    max: max,
                    divisions: divisions,
                    activeColor: colors.effectiveSeed,
                    thumbColor: colors.effectiveSeed,
                    onChanged: onChanged,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: onReset,
                      child: Text(l10n.useAppDefault),
                    ),
                  ),
                ],
              );
            }

            Widget editor;
            switch (sort) {
              case RouteSortOption.earliestDeparture:
                editor = ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.departureTimeLabel),
                  subtitle: Text(
                    DateFormat('EEE, MMM d • HH:mm').format(draft.when),
                  ),
                  trailing: const Icon(Icons.schedule),
                  onTap: () => pickDateTime(isArrival: false),
                );
                break;
              case RouteSortOption.earliestArrival:
                editor = ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.arrivalTimeLabel),
                  subtitle: Text(
                    DateFormat('EEE, MMM d • HH:mm').format(draft.when),
                  ),
                  trailing: const Icon(Icons.schedule),
                  onTap: () => pickDateTime(isArrival: true),
                );
                break;
              case RouteSortOption.shortestDuration:
                final effectiveSpeed =
                    draft.pedestrianSpeedKmh ?? defaults.pedestrianSpeedKmh;
                editor = buildSliderTile(
                  label: l10n.walkingSpeedLabel,
                  valueText: '${effectiveSpeed.toStringAsFixed(1)} km/h',
                  value: effectiveSpeed,
                  min: 2,
                  max: 10,
                  divisions: 80,
                  onChanged: (value) => setSheetState(() {
                    draft = draft.copyWith(
                      pedestrianSpeedKmh: (value * 10).round() / 10,
                    );
                  }),
                  onReset: () => setSheetState(() {
                    draft = draft.copyWith(clearPedestrianSpeedKmh: true);
                  }),
                );
                break;
              case RouteSortOption.leastTransfers:
                final effectiveMinTransfer = draft.minTransferTimeMinutes ??
                    defaults.minTransferTimeMinutes;
                editor = buildSliderTile(
                  label: l10n.minimumTransferTimeLabel,
                  valueText: '$effectiveMinTransfer min',
                  value: effectiveMinTransfer.toDouble(),
                  min: 0,
                  max: 30,
                  divisions: 30,
                  onChanged: (value) => setSheetState(() {
                    draft = draft.copyWith(
                      minTransferTimeMinutes: value.round(),
                    );
                  }),
                  onReset: () => setSheetState(() {
                    draft = draft.copyWith(clearMinTransferTimeMinutes: true);
                  }),
                );
                break;
              case RouteSortOption.shortestWait:
                final effectivePadding = draft.additionalTransferTimeMinutes ??
                    defaults.additionalTransferTimeMinutes;
                editor = buildSliderTile(
                  label: l10n.transferPaddingLabel,
                  valueText: '$effectivePadding min',
                  value: effectivePadding.toDouble(),
                  min: 0,
                  max: 30,
                  divisions: 30,
                  onChanged: (value) => setSheetState(() {
                    draft = draft.copyWith(
                      additionalTransferTimeMinutes: value.round(),
                    );
                  }),
                  onReset: () => setSheetState(() {
                    draft = draft.copyWith(
                      clearAdditionalTransferTimeMinutes: true,
                    );
                  }),
                );
                break;
              case RouteSortOption.leastWalking:
                final effectiveMaxWalking = draft.maxWalkingTimeMinutes ??
                    defaults.maxWalkingTimeMinutes;
                editor = buildSliderTile(
                  label: l10n.maximumWalkingTimeLabel,
                  valueText: '$effectiveMaxWalking min',
                  value: effectiveMaxWalking.toDouble(),
                  min: 5,
                  max: 120,
                  divisions: 23,
                  onChanged: (value) => setSheetState(() {
                    draft = draft.copyWith(
                      maxWalkingTimeMinutes: value.round(),
                    );
                  }),
                  onReset: () => setSheetState(() {
                    draft = draft.copyWith(clearMaxWalkingTimeMinutes: true);
                  }),
                );
                break;
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  20,
                  20,
                  20 + MediaQuery.of(sheetContext).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: TextStyle(color: colors.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    editor,
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.of(sheetContext).pop(draft),
                        child: Text(l10n.applyToThisRoutesView),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (updatedSettings == null || !mounted) return;
    await _rerunRouteTabSearch(
      route,
      updatedSettings,
      preferredSort: sort,
    );
  }

  /// How many upcoming rides are checked for an earlier departure: two when a
  /// route is opened, and the window then slides forward one ride at a time.
  static const int _earlierAlternativeLookahead = 2;

  /// An alternative has to be at least this much earlier to be worth a hint.
  static const Duration _earlierAlternativeMinGain = Duration(minutes: 3);

  static const Duration _earlierAlternativeSearchWindow = Duration(minutes: 60);

  void _resetEarlierAlternativeScans(String tabId) {
    _earlierAlternativeScanKeys.removeWhere((key) => key.startsWith('$tabId|'));
    _earlierAlternativeSteps.remove(tabId);
    _seenAlternativeHints.removeWhere((key) => key.startsWith('$tabId|'));
    _preloadedAlternatives.removeWhere((key, _) => key.startsWith('$tabId|'));
  }

  String _alternativeHintKey(String tabId, int stepIndex) =>
      '$tabId|$stepIndex';

  void _markAlternativeHintSeen(String tabId, int stepIndex) {
    if (!mounted) return;
    setState(() {
      _seenAlternativeHints.add(_alternativeHintKey(tabId, stepIndex));
    });
  }

  /// Earliest departure that is still reachable: the arrival of the ride that
  /// brings the traveller to this stop, or now for the first ride. Walking time
  /// at the transfer is deliberately not deducted.
  DateTime earliestCatchableDeparture(List<JourneyStep> steps, int stepIndex) {
    final now = DateTime.now();
    for (var i = stepIndex - 1; i >= 0; i--) {
      if (steps[i].type != 'ride') continue;
      final previousArrival = steps[i].plannedArrival;
      if (previousArrival == null) return now;
      return previousArrival.isAfter(now) ? previousArrival : now;
    }
    return now;
  }

  /// Keeps the next few upcoming rides checked. Called when a route is opened
  /// and on every active-journey tick, so once a ride has departed the ride
  /// after it gets its turn.
  void _scheduleEarlierAlternativeScans(RouteTab route, Journey journey) {
    final targets = earlierAlternativeScanTargets(
      journey.steps,
      DateTime.now(),
      lookahead: _earlierAlternativeLookahead,
    );
    for (final stepIndex in targets) {
      final key = '${route.id}|${_journeyListKey(journey)}|$stepIndex';
      if (!_earlierAlternativeScanKeys.add(key)) continue;
      unawaited(_scanEarlierAlternativeForStep(route, journey, stepIndex));
    }
  }

  Future<void> _scanEarlierAlternativeForStep(
    RouteTab route,
    Journey journey,
    int stepIndex,
  ) async {
    try {
      final found = await _findEarlierCatchableRide(route, journey, stepIndex);
      if (found == null || !mounted) return;
      setState(() {
        (_earlierAlternativeSteps[route.id] ??= <int, String>{})[stepIndex] =
            found;
      });
      TransportApi.addSyntheticDebugLog(
        'ui: earlier alternative tab=${route.id} step=$stepIndex '
        'line=${journey.steps[stepIndex].line} key=$found',
      );
    } catch (error) {
      TransportApi.addSyntheticDebugLog(
        'ui: earlier alternative scan failed tab=${route.id} '
        'step=$stepIndex error=$error',
      );
    }
  }

  /// Ride key of the earliest departure that is still catchable and arrives no
  /// later than the current plan - the one that buys the most buffer. Null when
  /// switching would not help. The results are kept for the sheet.
  Future<String?> _findEarlierCatchableRide(
    RouteTab route,
    Journey journey,
    int stepIndex,
  ) async {
    final step = journey.steps[stepIndex];
    final departure = step.plannedDeparture ?? step.dateTime;
    if (departure == null) return null;

    final stationId = step.startStationId;
    final hasCoordinates = step.startLat != null && step.startLng != null;
    if ((stationId == null || stationId.isEmpty) && !hasCoordinates) {
      return null;
    }

    // Mirrors what the Alt sheet searches, so a lit-up button always has
    // something behind it when it is tapped.
    final from = Station(
      id: stationId ?? '',
      name: step.startStationName ?? 'Origin',
      type: hasCoordinates ? 'location' : 'station',
      latitude: step.startLat,
      longitude: step.startLng,
    );

    final results = await TransportApi.searchJourneys(
      from,
      route.destination,
      nahverkehrOnly: widget.onlyNahverkehr,
      when: departure.subtract(_earlierAlternativeSearchWindow),
      isArrival: false,
      results: 8,
      // Only departure and arrival times decide the hint.
      enrichPlatforms: false,
      enrichCoupledLines: false,
    );

    final earliestCatchable =
        earliestCatchableDeparture(journey.steps, stepIndex);
    final latestArrival = journey.plannedArrival ?? journey.arrival;

    String? bestKey;
    DateTime? bestDeparture;
    for (final raw in results) {
      if (alternativeIsSameRide(
        raw,
        tripId: step.tripId,
        line: step.line,
        departure: departure,
      )) {
        continue;
      }
      final alternativeDeparture = alternativeJourneyBoardingLocal(raw);
      final alternativeArrival = alternativeJourneyArrivalLocal(raw);
      if (alternativeDeparture == null || alternativeArrival == null) continue;
      if (!earlierAlternativeQualifies(
        plannedDeparture: departure,
        alternativeDeparture: alternativeDeparture,
        alternativeArrival: alternativeArrival,
        earliestCatchable: earliestCatchable,
        latestArrival: latestArrival,
        minGain: _earlierAlternativeMinGain,
      )) {
        continue;
      }
      if (bestDeparture != null &&
          !alternativeDeparture.isBefore(bestDeparture)) {
        continue;
      }
      bestKey = alternativeRideKey(raw);
      bestDeparture = alternativeDeparture;
    }

    if (bestKey != null) {
      // The button will invite a tap, so have the whole sheet ready: the
      // backward search above plus the departures from here on.
      unawaited(_preloadAlternatives(route, stepIndex, from, departure,
          earlier: results));
    }
    return bestKey;
  }

  /// Fills the sheet's list ahead of time, so opening it shows something at
  /// once instead of a spinner.
  Future<void> _preloadAlternatives(
    RouteTab route,
    int stepIndex,
    Station from,
    DateTime departure, {
    required List<Map<String, dynamic>> earlier,
  }) async {
    try {
      final forward = await TransportApi.searchJourneys(
        from,
        route.destination,
        nahverkehrOnly: widget.onlyNahverkehr,
        when: departure,
        isArrival: false,
        results: 12,
        enrichPlatforms: false,
        enrichCoupledLines: false,
      );
      _preloadedAlternatives[_alternativeHintKey(route.id, stepIndex)] =
          mergeAlternativeJourneys(earlier, forward);
    } catch (error) {
      TransportApi.addSyntheticDebugLog(
        'ui: alternatives preload failed tab=${route.id} '
        'step=$stepIndex error=$error',
      );
    }
  }

  Future<void> _enrichActiveJourneyPlatforms(
    String tabId,
    Journey selectedJourney,
  ) async {
    final departure =
        selectedJourney.plannedDeparture ?? selectedJourney.departure;
    final arrival = selectedJourney.plannedArrival ?? selectedJourney.arrival;
    final enrichmentKey = '$tabId|${departure.millisecondsSinceEpoch}|'
        '${arrival.millisecondsSinceEpoch}|${_firstRideTripId(selectedJourney)}';
    if (_completedActivePlatformEnrichmentKeys.contains(enrichmentKey)) return;
    if (!_activePlatformEnrichmentKeys.add(enrichmentKey)) return;

    try {
      var appliedAnyUpdate = false;
      bool applyEnrichedRaw(
        Map<String, dynamic> enrichedRaw, {
        required bool logNoImprovement,
      }) {
        if (!mounted) return false;

        final idx = _tabs.indexWhere((t) => t.id == tabId);
        if (idx == -1) return false;
        final currentRoute = _tabs[idx];
        final currentActive = currentRoute.activeJourney;
        if (currentActive == null ||
            !_journeysLikelySameRoute(currentActive, selectedJourney)) {
          return false;
        }

        final enrichedJourney = _createJourney(
          enrichedRaw,
          destinationNameOverride: currentRoute.destination.name,
        );
        final preferredActive = _preferJourneyWithMorePlatformDetail(
          currentActive,
          enrichedJourney,
        );
        if (identical(preferredActive, currentActive)) {
          if (logNoImprovement) {
            TransportApi.addSyntheticDebugLog(
              'ui: active platform enrich no improvement tab=$tabId activeSignal=${_journeyPlatformSignal(currentActive)} enrichedSignal=${_journeyPlatformSignal(enrichedJourney)}',
            );
          }
          return false;
        }

        setState(() {
          final latestIdx = _tabs.indexWhere((t) => t.id == tabId);
          if (latestIdx == -1) return;
          final latest = _tabs[latestIdx];
          final latestActive = latest.activeJourney;
          if (latestActive == null ||
              !_journeysLikelySameRoute(latestActive, selectedJourney)) {
            return;
          }

          final updatedCandidates = latest.candidates
              ?.map(
                (candidate) => _journeysLikelySameRoute(
                  candidate,
                  preferredActive,
                )
                    ? _preferJourneyWithMorePlatformDetail(
                        candidate,
                        preferredActive,
                      )
                    : candidate,
              )
              .toList();
          final updatedStack = latest.stack
              .map(
                (journey) => _journeysLikelySameRoute(journey, preferredActive)
                    ? _preferJourneyWithMorePlatformDetail(
                        journey,
                        preferredActive,
                      )
                    : journey,
              )
              .toList();

          TransportApi.addSyntheticDebugLog(
            'ui: active platform enrich applied tab=$tabId activeSignal=${_journeyPlatformSignal(preferredActive)}',
          );
          _tabs[latestIdx] = latest.copyWith(
            activeJourney: preferredActive,
            steps: preferredActive.steps,
            candidates: updatedCandidates,
            stack: updatedStack,
          );
        });
        appliedAnyUpdate = true;
        return true;
      }

      final enrichedRaw = await TransportApi.enrichJourneyWithPlatforms(
        Map<String, dynamic>.from(selectedJourney.rawSource),
        preferBahnForRail: true,
        fastBahnRailOnly: true,
        onProgress: (enrichedSoFar) {
          applyEnrichedRaw(
            enrichedSoFar,
            logNoImprovement: false,
          );
        },
      );
      applyEnrichedRaw(
        enrichedRaw,
        logNoImprovement: !appliedAnyUpdate,
      );
      _completedActivePlatformEnrichmentKeys.add(enrichmentKey);
    } catch (error) {
      TransportApi.addSyntheticDebugLog(
        'ui: active platform enrich failed tab=$tabId error=$error',
      );
    } finally {
      _activePlatformEnrichmentKeys.remove(enrichmentKey);
    }
  }

  Widget _buildActiveRouteView(RouteTab route) {
    final jointContext = _jointRouteContexts[route.id];
    if (route.activeJourney == null && jointContext != null) {
      final jointFriendId = jointContext.friendId;
      return JointRouteResultsView(
        key: ValueKey<String>('joint-route-results-${route.id}'),
        friendName: jointContext.friendName,
        destinationName: jointContext.destinationName,
        options: jointContext.options,
        window: jointContext.window,
        isExpanding: jointContext.isExpanding,
        onExpand: jointContext.canExpand
            ? () => unawaited(_expandJointSearch(route.id))
            : null,
        onBack: () => _closeTab(route.id),
        onSelect: (option) {
          setState(() {
            final index = _tabs.indexWhere((tab) => tab.id == route.id);
            if (index == -1) return;
            final current = _tabs[index];
            final stack = List<Journey>.from(current.stack);
            if (!stack.any((journey) =>
                _journeysLikelySameRoute(journey, option.myJourney))) {
              stack.add(option.myJourney);
            }
            _tabs[index] = current.copyWith(
              activeJourney: option.myJourney,
              steps: option.myJourney.steps,
              stack: stack,
              subtitle:
                  '${option.sharedDuration.inMinutes} min · ${jointContext.friendName}',
              totalDuration: FormatUtils.formatDuration(
                  option.myJourney.duration.inMinutes),
            );
          });
          unawaited(_enrichActiveJourneyPlatforms(
            route.id,
            option.myJourney,
          ));
        },
        onShare: jointFriendId == null
            ? null
            : (option) => SupabaseService.sendPrivateMessage(
                  jointFriendId,
                  _jointPlanMessage(
                    option,
                    friendName: jointContext.friendName,
                    destinationName: jointContext.destinationName,
                    german:
                        Localizations.localeOf(context).languageCode == 'de',
                  ),
                ),
      );
    }
    if (route.activeJourney == null &&
        route.candidates != null &&
        route.candidates!.isNotEmpty) {
      return RouteResultsView(
        key: ValueKey<String>('route-results-${route.id}'),
        candidates: route.candidates!,
        onSelect: (journey) {
          Journey? selectedJourneyForEnrichment;
          setState(() {
            final idx = _tabs.indexWhere((t) => t.id == route.id);
            if (idx != -1) {
              final currentRoute = _tabs[idx];
              final selectedJourney = _bestCurrentJourneyVersion(
                journey,
                currentRoute.candidates ?? route.candidates!,
              );
              selectedJourneyForEnrichment = selectedJourney;
              final currentStack = List<Journey>.from(currentRoute.stack);
              if (!currentStack.any(
                (existing) => _journeysLikelySameRoute(
                  existing,
                  selectedJourney,
                ),
              )) {
                currentStack.add(selectedJourney);
              }

              TransportApi.addSyntheticDebugLog(
                'ui: selected journey tab=${route.id} platformSignal=${_journeyPlatformSignal(selectedJourney)}',
              );
              _tabs[idx] = currentRoute.copyWith(
                activeJourney: selectedJourney,
                stack: currentStack,
                steps: selectedJourney.steps,
                totalDuration: FormatUtils.formatDuration(
                  selectedJourney.duration.inMinutes,
                ),
              );
            }
          });
          if (selectedJourneyForEnrichment != null) {
            unawaited(_enrichActiveJourneyPlatforms(
              route.id,
              selectedJourneyForEnrichment!,
            ));
            _resetEarlierAlternativeScans(route.id);
            _scheduleEarlierAlternativeScans(
              route,
              selectedJourneyForEnrichment!,
            );
          }
        },
        onBack: () => _closeTab(route.id),
        onLoadEarlier: () => _loadMoreRoutes(route, earlier: true),
        onLoadLater: () => _loadMoreRoutes(route, earlier: false),
        onRefresh: () => _refreshRoutes(route),
        origin: route.origin,
        destination: route.destination,
        showTrainNumbers: widget.showTrainNumbers, // Pass the setting
        loadingIndicatorColor: _routeLoadingColor(TransColors.of(context)),
        isBackgroundLoading: _activeRouteLoadPhases.isNotEmpty,
        initialSort: _routeResultsSortSelections[route.id] ??
            _routeResultsSortOrder.first,
        sortOrder: _routeResultsSortOrder,
        onSortChanged: (sort) => _routeResultsSortSelections[route.id] = sort,
        onSortOrderChanged: (order) {
          unawaited(_saveRouteResultsSortOrder(order));
        },
        onSortDoubleTapped: (sort) => _showRouteSortAdjustSheet(route, sort),
        scrollController: _routeResultsScrollControllerFor(route.id),
      );
    }

    final colors = TransColors.of(context);
    final totalWalkingMinutes =
        route.activeJourney?.totalWalkingDuration.inMinutes ?? 0;
    final totalBikingMinutes =
        route.activeJourney?.totalBikingDuration.inMinutes ?? 0;
    final hasWalkingSummary = totalWalkingMinutes > 0;
    final hasBikingSummary = totalBikingMinutes > 0;
    final totalWalkingDurationLabel =
        FormatUtils.formatDuration(totalWalkingMinutes);
    final totalBikingDurationLabel =
        FormatUtils.formatDuration(totalBikingMinutes);
    final activeJourney = route.activeJourney;
    if (activeJourney != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_enrichActiveJourneyPlatforms(route.id, activeJourney));
      });
    }
    return RefreshIndicator(
      color: _routeLoadingColor(colors),
      onRefresh: () => _refreshActiveJourney(route),
      child: ListView(
          controller: _activeJourneyScrollControllerFor(route.id),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          children: [
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: LayoutBuilder(builder: (context, constraints) {
                  final showBackButton = jointContext != null ||
                      (route.candidates != null &&
                          route.candidates!.length > 1);
                  final isCompactHeader = constraints.maxWidth < 430;
                  final timeLabel = route.activeJourney != null
                      ? "${DateFormat('HH:mm').format(route.activeJourney!.departure)} - ${DateFormat('HH:mm').format(route.activeJourney!.arrival)}"
                      : route.subtitle;
                  final isSavingRoute = _savingRouteIds.contains(route.id);

                  Widget timeText({double fontSize = 24}) => FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(timeLabel,
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                              fontSize: fontSize,
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary)));

                  void handleBack() => setState(() {
                        final idx = _tabs.indexWhere((t) => t.id == route.id);
                        if (idx != -1) {
                          _tabs[idx] = route.copyWith(clearActiveJourney: true);
                        }
                      });

                  final actions =
                      Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                        icon: isSavingRoute
                            ? SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      colors.navBarSelected),
                                ),
                              )
                            : Icon(
                                _isRouteSaved(route)
                                    ? Icons.bookmark
                                    : Icons.bookmark_border,
                                color: colors.navBarSelected),
                        onPressed: route.origin == null ||
                                route.activeJourney == null ||
                                isSavingRoute
                            ? null
                            : () => _toggleSavedRoute(route)),
                    IconButton(
                        icon: const Icon(Icons.map, color: Colors.blue),
                        onPressed: () => _openMap(route)),
                  ]);

                  final durationChip = Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.timer_outlined,
                            size: 16, color: Colors.green),
                        const SizedBox(width: 4),
                        Text(route.totalDuration,
                            style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold)),
                        if (hasWalkingSummary) ...[
                          const SizedBox(width: 10),
                          Container(
                              width: 1, height: 14, color: Colors.white24),
                          const SizedBox(width: 10),
                          Icon(Icons.directions_walk,
                              size: 16, color: colors.stepTransferText),
                          const SizedBox(width: 4),
                          Text(totalWalkingDurationLabel,
                              style: TextStyle(
                                  color: colors.stepTransferText,
                                  fontWeight: FontWeight.bold)),
                        ],
                        if (hasBikingSummary) ...[
                          const SizedBox(width: 10),
                          Container(
                              width: 1, height: 14, color: Colors.white24),
                          const SizedBox(width: 10),
                          Icon(Icons.pedal_bike,
                              size: 16, color: colors.stepTransferText),
                          const SizedBox(width: 4),
                          Text(totalBikingDurationLabel,
                              style: TextStyle(
                                  color: colors.stepTransferText,
                                  fontWeight: FontWeight.bold)),
                        ]
                      ]));

                  if (isCompactHeader) {
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            if (showBackButton)
                              IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: const Icon(Icons.arrow_back),
                                  onPressed: handleBack),
                            if (showBackButton) const SizedBox(width: 8),
                            Expanded(child: timeText()),
                          ]),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(
                                child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: actions)),
                            const SizedBox(width: 8),
                            Flexible(
                                child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerRight,
                                    child: durationChip))
                          ])
                        ]);
                  }

                  return Row(children: [
                    if (showBackButton)
                      IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.arrow_back),
                          onPressed: handleBack),
                    if (showBackButton) const SizedBox(width: 8),
                    Expanded(child: timeText()),
                    const SizedBox(width: 8),
                    actions,
                    const SizedBox(width: 8),
                    durationChip
                  ]);
                })),
            for (int i = 0; i < route.steps.length; i++) ...[
              if (route.activeJourney?.branchStepIndex == i &&
                  route.activeJourney?.parentJourney != null)
                _buildReturnToParentButton(context, route),
              _StepCard(
                  step: route.steps[i],
                  isFirst: i == 0,
                  hasEarlierAlternative:
                      _earlierAlternativeSteps[route.id]?.containsKey(i) ??
                          false,
                  alternativeHintSeen: _seenAlternativeHints
                      .contains(_alternativeHintKey(route.id, i)),
                  onAlternativeHintSeen: () =>
                      _markAlternativeHintSeen(route.id, i),
                  finalDestinationId: route.destination.id,
                  onShowStopDepartures: ({
                    required String stopId,
                    required String stopName,
                    required DateTime date,
                    String? preferredPlatform,
                  }) =>
                      _showStopDeparturesForStop(
                        stopId: stopId,
                        stopName: stopName,
                        date: date,
                        preferredPlatform: preferredPlatform,
                      ),
                  onOpenAlternatives: (stationId, time,
                          {double? lat, double? lng, String? name}) =>
                      _showAlternatives(context, stationId, route.destination, time,
                          lat: lat,
                          lng: lng,
                          stationName: name,
                          highlightKey: _earlierAlternativeSteps[route.id]?[i],
                          earliestDeparture:
                              earliestCatchableDeparture(route.steps, i),
                          currentTripId: route.steps[i].tripId,
                          currentLine: route.steps[i].line,
                          initialResults: _preloadedAlternatives[
                              _alternativeHintKey(route.id, i)],
                          branchFrom: route.activeJourney,
                          branchRideLegIndex: route.steps[i].legIndex),
                  onIntermediateAlarmLongPress: (stopName,
                          {required int stopIndex,
                          double? targetLat,
                          double? targetLng,
                          double? originLat,
                          double? originLng}) =>
                      _toggleIntermediateStopAlarm(
                        route,
                        route.steps[i],
                        stopIndex: stopIndex,
                        stopName: stopName,
                        targetLat: targetLat,
                        targetLng: targetLng,
                        originLat: originLat,
                        originLng: originLng,
                      ),
                  onChat: (line) => _showChat(context, line),
                  onAlarmToggle: () => _toggleStepAlarm(route, route.steps[i]),
                  onMapTap: () => _openMap(route, focusStep: route.steps[i]),
                  alarmStopsBefore: _alarmStopsBefore,
                  showTrainNumbers: widget.showTrainNumbers),
            ],
          ]),
    );
  }

  /// Sits between the part of the trip that is still the original route and the
  /// alternative picked for the rest, and steps back out of the alternative.
  Widget _buildReturnToParentButton(BuildContext context, RouteTab route) {
    final journey = route.activeJourney;
    final parent = journey?.parentJourney;
    if (journey == null || parent == null) return const SizedBox.shrink();

    final colors = TransColors.of(context);
    final label = '${DateFormat('HH:mm').format(parent.departure)} - '
        '${DateFormat('HH:mm').format(parent.arrival)}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Align(
        alignment: Alignment.center,
        child: TextButton.icon(
          onPressed: () => _returnToParentJourney(route, journey),
          style: TextButton.styleFrom(
            foregroundColor: colors.effectiveSeed,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: const Icon(Icons.undo, size: 16),
          label: Text(
            AppLocalizations.of(context)!.backToOriginalRoute(label),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

/// Preview switch for the sheet: with no real suggestion, the first
/// alternative is marked so the highlight can be looked at on any route.
/// Off - the sheet only marks what the check actually found.
const bool kPreviewHighlightSuggestedAlternative = false;

/// Preview switch for the running border: every Alt button animates, whether
/// or not something was found. Off - only rides with an earlier, still
/// catchable alternative are marked.
const bool kPreviewAnimateEveryAltButton = false;

class _StepCard extends StatefulWidget {
  final JourneyStep step;
  final bool isFirst;

  /// An earlier departure for this ride exists that still reaches the
  /// destination in time, so switching buys transfer buffer.
  final bool hasEarlierAlternative;

  /// The traveller has already opened the alternatives for this ride.
  final bool alternativeHintSeen;

  /// Called when they open them, so the hint stops asking for attention.
  final VoidCallback? onAlternativeHintSeen;
  final String finalDestinationId;
  final Future<void> Function({
    required String stopId,
    required String stopName,
    required DateTime date,
    String? preferredPlatform,
  }) onShowStopDepartures;
  final Function(String, DateTime, {double? lat, double? lng, String? name})
      onOpenAlternatives;
  final Function(
    String, {
    required int stopIndex,
    double? targetLat,
    double? targetLng,
    double? originLat,
    double? originLng,
  }) onIntermediateAlarmLongPress;
  final Function(String) onChat;
  final VoidCallback onAlarmToggle;
  final VoidCallback onMapTap;
  final int alarmStopsBefore;
  final bool showTrainNumbers;

  const _StepCard({
    required this.step,
    this.isFirst = false,
    this.hasEarlierAlternative = false,
    this.alternativeHintSeen = false,
    this.onAlternativeHintSeen,
    required this.finalDestinationId,
    required this.onShowStopDepartures,
    required this.onOpenAlternatives,
    required this.onIntermediateAlarmLongPress,
    required this.onChat,
    required this.onAlarmToggle,
    required this.onMapTap,
    required this.alarmStopsBefore,
    required this.showTrainNumbers,
  });

  @override
  State<_StepCard> createState() => _StepCardState();
}

class _StepCardState extends State<_StepCard> {
  bool _isExpanded = false;

  bool get _hasCustomAlarmTarget => widget.step.alarmTargetName != null;

  bool _coordsMatch(double? firstLat, double? firstLng, double? secondLat,
      double? secondLng) {
    if (firstLat == null ||
        firstLng == null ||
        secondLat == null ||
        secondLng == null) {
      return false;
    }
    const epsilon = 0.00001;
    return (firstLat - secondLat).abs() < epsilon &&
        (firstLng - secondLng).abs() < epsilon;
  }

  bool _isIntermediateAlarmSelected({
    required int stopIndex,
    required String displayName,
    required double? stopLat,
    required double? stopLng,
  }) {
    final step = widget.step;
    if (!step.isWakeAlarmOn) return false;

    if (_hasCustomAlarmTarget) {
      if (_coordsMatch(
        step.alarmTargetLat,
        step.alarmTargetLng,
        stopLat,
        stopLng,
      )) {
        return true;
      }
      return step.alarmTargetName == displayName;
    }

    if (widget.alarmStopsBefore <= 0) return false;
    final stopovers = step.stopovers;
    if (stopovers == null || stopovers.isEmpty) return false;
    final targetIndex = stopovers.length - widget.alarmStopsBefore;
    return stopIndex == targetIndex;
  }

  Widget _buildStopDetailChip(
    BuildContext context, {
    required String detail,
    bool constrainWidth = true,
  }) {
    final colors = TransColors.of(context);
    final detailText = Text(
      detail,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: colors.textPrimary,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.chipBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.white10,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (constrainWidth)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: detailText,
            )
          else
            detailText,
        ],
      ),
    );
  }

  Widget _buildTrailingTimeAndStopDetailWidget(
    BuildContext context, {
    required Widget timeWidget,
    String? stopDetail,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (stopDetail != null) ...[
          _buildStopDetailChip(
            context,
            detail: stopDetail,
          ),
          const SizedBox(width: 8),
        ],
        timeWidget,
      ],
    );
  }

  Widget _buildRealtimeTime(
    BuildContext context, {
    required String actualTime,
    required DateTime? plannedTime,
    required int? delayMinutes,
    required TextStyle style,
    bool includeDelayLabel = true,
  }) {
    final colors = TransColors.of(context);
    final plannedLabel =
        plannedTime == null ? null : DateFormat('HH:mm').format(plannedTime);
    final hasDelay = delayMinutes != null && delayMinutes != 0;
    final actualStyle = style.copyWith(
      // Green suggested that a displayed time was a special “on-time” state.
      // Keep ordinary times neutral; only changed realtime digits are red.
      color: colors.textPrimary,
    );

    if (!hasDelay || plannedLabel == null) {
      return Text(
        actualTime,
        textAlign: TextAlign.right,
        style: actualStyle,
      );
    }

    final changedStart = realtimeChangedSuffixStart(plannedLabel, actualTime);
    final unchangedPrefix = actualTime.substring(0, changedStart);
    final changedSuffix = actualTime.substring(changedStart);
    return Text.rich(
      TextSpan(
        style: actualStyle,
        children: [
          if (unchangedPrefix.isNotEmpty) TextSpan(text: unchangedPrefix),
          TextSpan(
            text: changedSuffix,
            style: style.copyWith(color: colors.delayLate),
          ),
          if (includeDelayLabel)
            TextSpan(
              text: ' (${formatRealtimeDelay(delayMinutes)})',
              style: style.copyWith(color: colors.delayLate),
            ),
        ],
      ),
      textAlign: TextAlign.right,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    final step = widget.step;
    final stepHeadsign = (step.headsign ?? '').trim();
    final directionPrefix =
        Localizations.localeOf(context).languageCode == 'de' ? 'nach' : 'to';
    final bool isWait = step.type == 'wait';
    final bool isBike = step.type == 'bike';
    final isTransfer =
        step.type == 'transfer' || isWait || step.type == 'walk' || isBike;

    if (isTransfer) {
      Widget iconWidget =
          Icon(Icons.directions_walk, color: colors.stepTransferText);
      if (isWait) iconWidget = Icon(Icons.man, color: colors.stepTransferText);
      if (isBike) {
        iconWidget = Icon(Icons.pedal_bike, color: colors.stepTransferText);
      }

      final bool hasWalking =
          step.walkDuration != null && step.walkDuration!.inMinutes > 0;
      final bool canTap = !isWait || hasWalking;

      return GestureDetector(
          onTap: canTap ? widget.onMapTap : null,
          child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: colors.stepTransferBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.stepTransferBorder)),
              child: Row(children: [
                iconWidget,
                const SizedBox(width: 16),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(step.instruction,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary)),

                      // Show Breakdown if available
                      if (isBike && step.bikeDuration != null)
                        Text(
                            "Bike ${FormatUtils.formatDuration(step.bikeDuration!.inMinutes)}",
                            style: TextStyle(
                                color: colors.stepTransferText, fontSize: 12))
                      else if (step.walkDuration != null &&
                          step.waitDuration != null &&
                          !isWait)
                        RichText(
                            text: TextSpan(
                                style: TextStyle(
                                    color: colors.stepTransferText,
                                    fontSize: 12),
                                children: [
                              if (step.walkDuration!.inMinutes > 0)
                                TextSpan(
                                    text:
                                        "Walk ${FormatUtils.formatDuration(step.walkDuration!.inMinutes)}"),
                              if (step.walkDuration!.inMinutes > 0 &&
                                  step.waitDuration!.inMinutes > 0)
                                const TextSpan(text: "  •  "),
                              if (step.waitDuration!.inMinutes > 0)
                                TextSpan(
                                    text:
                                        "Wait ${FormatUtils.formatDuration(step.waitDuration!.inMinutes)}"),
                            ]))
                      else
                        Text(step.duration,
                            style: TextStyle(
                                color: colors.stepTransferText, fontSize: 12))
                    ]))
              ])));
    }

    return Card(
        margin: EdgeInsets.only(bottom: 16, top: widget.isFirst ? 0 : 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
        color: colors.stepCardBg,
        child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
                tilePadding: const EdgeInsets.fromLTRB(16, 8, 0, 8),
                onExpansionChanged: (val) => setState(() => _isExpanded = val),
                title: Builder(builder: (context) {
                  final dest = (step.destinationName ??
                      step.instruction.split('→').last.trim());
                  // Check if destination is practically the headsign (End of Line)
                  // Use simple string containment or equality check
                  final isEnd = dest.isNotEmpty &&
                      stepHeadsign.isNotEmpty &&
                      (stepHeadsign
                              .toLowerCase()
                              .contains(dest.toLowerCase()) ||
                          dest
                              .toLowerCase()
                              .contains(stepHeadsign.toLowerCase()));
                  final displayDest =
                      isEnd ? AppLocalizations.of(context)!.endOfLine : dest;
                  final displayLine = formatRideDisplayLine(
                    line: step.line,
                    platform: null,
                    arrivalPlatform: step.arrivalPlatform,
                    tripId: step.tripId,
                    showTrainNumbers: widget.showTrainNumbers,
                  );
                  final isCoupledService = displayLine.contains(' / ');

                  // Keep the line compact and let the destination use all
                  // remaining space. Giving both labels flex space leaves a
                  // short line number with an unused half of the row.
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Icons use a geometric rather than typographic
                      // baseline, so nudge the vehicle glyph down to sit on
                      // the same visual line as the route number.
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Icon(
                          _rideModeIconForLine(step.line),
                          size: 18,
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: isCoupledService ? 132 : 72,
                        ),
                        child: Text(
                          displayLine,
                          maxLines: isCoupledService ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.arrow_right_alt,
                          size: 24, color: colors.textPrimary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          displayDest,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: colors.textPrimary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Manual Arrow on Top Line with Rotation
                      Baseline(
                        baseline: 16,
                        baselineType: TextBaseline.alphabetic,
                        child: AnimatedRotation(
                            turns: _isExpanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: Icon(Icons.keyboard_arrow_down,
                                color: _isExpanded
                                    ? colors.effectiveSeed
                                    : colors.textSecondary)),
                      ),
                    ],
                  );
                }),
                trailing:
                    const SizedBox.shrink(), // Hide default centered arrow
                subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      // Info Line: Headsign • Duration
                      Text(
                          stepHeadsign.isEmpty
                              ? step.duration
                              : "$directionPrefix $stepHeadsign  •  ${step.duration}",
                          style: TextStyle(color: colors.textSecondary)),

                      const SizedBox(height: 12), // Spacer before actions

                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (step.startStationId != null &&
                                      step.dateTime != null) ...[
                                    _buildActionChip(
                                      context,
                                      Icons.alt_route,
                                      AppLocalizations.of(context)!.altShort,
                                      highlighted:
                                          kPreviewAnimateEveryAltButton ||
                                              widget.hasEarlierAlternative,
                                      // The line stops circling once the
                                      // traveller has looked; the tint stays as
                                      // a reminder that an option is there.
                                      animated: kPreviewAnimateEveryAltButton ||
                                          (widget.hasEarlierAlternative &&
                                              !widget.alternativeHintSeen),
                                      onTap: () {
                                        widget.onAlternativeHintSeen?.call();
                                        widget.onOpenAlternatives(
                                          step.startStationId!,
                                          step.dateTime!,
                                          lat: step.startLat,
                                          lng: step.startLng,
                                        );
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  _buildActionChip(
                                    context,
                                    Icons.vibration,
                                    step.isWakeAlarmOn
                                        ? AppLocalizations.of(context)!.alarmOn
                                        : AppLocalizations.of(context)!.wakeMe,
                                    isActive: step.isWakeAlarmOn &&
                                        !_hasCustomAlarmTarget,
                                    outlined: step.isWakeAlarmOn &&
                                        _hasCustomAlarmTarget,
                                    onTap: widget.onAlarmToggle,
                                  ),
                                  const SizedBox(width: 8),
                                  _buildActionChip(
                                    context,
                                    Icons.chat_bubble_outline,
                                    AppLocalizations.of(context)!.chat,
                                    onTap: () => widget.onChat(step.line),
                                  ),
                                  if (combinePlatformAndStopLabel(
                                    step.platform,
                                    step.departureStopLabel,
                                    stationName: step.startStationName,
                                    isRail: _lineLooksRailForPlatformLabel(
                                      step.line,
                                    ),
                                  )
                                      case final collapsedStopDetail?) ...[
                                    const SizedBox(width: 8),
                                    _buildStopDetailChip(
                                      context,
                                      detail: collapsedStopDetail,
                                      constrainWidth: false,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 300),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: step.isCancelled
                                  ? Text(
                                      '${step.departureTime} - ${step.arrivalTime} ${AppLocalizations.of(context)!.cancelledL10n}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: colors.textSecondary,
                                        decoration: TextDecoration.lineThrough,
                                      ),
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _buildRealtimeTime(
                                          context,
                                          actualTime: step.departureTime,
                                          plannedTime: step.plannedDeparture,
                                          delayMinutes: step.departureDelay,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const Text(' - '),
                                        _buildRealtimeTime(
                                          context,
                                          actualTime: step.arrivalTime,
                                          plannedTime: step.plannedArrival,
                                          delayMinutes: step.arrivalDelay,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      )
                    ]),
                children: [
                  if (step.startStationName != null)
                    Container(
                        decoration: BoxDecoration(
                            color:
                                colors.stepStopoversBg.withValues(alpha: 0.5)),
                        child: GestureDetector(
                            onLongPress: step.startStationId != null
                                ? () => widget.onShowStopDepartures(
                                      stopId: step.startStationId!,
                                      stopName: step.startStationName!,
                                      date: step.plannedDeparture ??
                                          step.dateTime ??
                                          DateTime.now(),
                                      preferredPlatform: step.platform,
                                    )
                                : null,
                            child: ListTile(
                                dense: true,
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 20),
                                minLeadingWidth: 18,
                                leading: const Icon(Icons.login,
                                    size: 14, color: Colors.green),
                                title: Text(
                                    _formatBoardingText(
                                      AppLocalizations.of(context)!,
                                      stationName: step.startStationName ?? '',
                                      platform: step.platform,
                                      stopLabel: step.departureStopLabel,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: colors.textPrimary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold)),
                                trailing: _buildTrailingTimeAndStopDetailWidget(
                                  context,
                                  timeWidget: _buildRealtimeTime(
                                    context,
                                    actualTime: step.departureTime,
                                    plannedTime: step.plannedDeparture,
                                    delayMinutes: step.departureDelay,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  stopDetail: combinePlatformAndStopLabel(
                                    step.platform,
                                    step.departureStopLabel,
                                    stationName: step.startStationName,
                                    isRail: _lineLooksRailForPlatformLabel(
                                      step.line,
                                    ),
                                  ),
                                )))),
                  if (step.stopovers != null && step.stopovers!.isNotEmpty)
                    Container(
                        decoration:
                            BoxDecoration(color: colors.stepStopoversBg),
                        child: ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: step.stopovers!.length,
                            itemBuilder: (ctx, idx) {
                              double? asDouble(dynamic value) {
                                if (value is num) return value.toDouble();
                                if (value == null) return null;
                                return double.tryParse(value.toString());
                              }

                              final stop = step.stopovers![idx];
                              final name = stop['stop']['name'];
                              final stopId = stop['stop']['id'];
                              final platform =
                                  stop['platform'] ?? stop['stop']?['platform'];
                              final stopLabel =
                                  stop['stop']?['stopLabel']?.toString();
                              final String displayName =
                                  _formatIntermediateStopTitle(
                                (name ?? '').toString(),
                                platform: platform?.toString(),
                                stopLabel: stopLabel,
                              );
                              final plannedDep = stop['plannedDeparture'] ??
                                  stop['scheduledDeparture'] ??
                                  stop['plannedArrival'] ??
                                  stop['scheduledArrival'];
                              final actualDep =
                                  stop['departure'] ?? stop['arrival'];
                              final stopLat = asDouble(
                                  stop['stop']?['location']?['latitude']);
                              final stopLng = asDouble(
                                  stop['stop']?['location']?['longitude']);
                              double? previousLat = step.startLat;
                              double? previousLng = step.startLng;
                              if (idx > 0) {
                                final previousStop = step.stopovers![idx - 1];
                                previousLat = asDouble(previousStop['stop']
                                        ?['location']?['latitude']) ??
                                    previousLat;
                                previousLng = asDouble(previousStop['stop']
                                        ?['location']?['longitude']) ??
                                    previousLng;
                              }
                              String actualTimeText = "--:--";
                              DateTime? plannedTime;
                              int? delayMinutes;
                              DateTime? exactStopDate;

                              if (plannedDep != null) {
                                final p = DateTime.parse(plannedDep).toLocal();
                                plannedTime = p;
                                exactStopDate = p;
                                actualTimeText =
                                    "${p.hour.toString().padLeft(2, '0')}:${p.minute.toString().padLeft(2, '0')}";
                                if (actualDep != null) {
                                  final a = DateTime.parse(actualDep).toLocal();
                                  actualTimeText =
                                      "${a.hour.toString().padLeft(2, '0')}:${a.minute.toString().padLeft(2, '0')}";
                                  delayMinutes = a.difference(p).inMinutes;
                                }
                              }
                              final isAlarmSelected =
                                  _isIntermediateAlarmSelected(
                                stopIndex: idx,
                                displayName: name as String? ?? displayName,
                                stopLat: stopLat,
                                stopLng: stopLng,
                              );
                              return GestureDetector(
                                  onLongPress: stopId != null
                                      ? () => widget.onShowStopDepartures(
                                            stopId: stopId as String,
                                            stopName: name ?? displayName,
                                            date: exactStopDate ??
                                                widget.step.dateTime ??
                                                DateTime.now(),
                                            preferredPlatform:
                                                platform?.toString(),
                                          )
                                      : null,
                                  child: ListTile(
                                      dense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 20),
                                      minLeadingWidth: 12,
                                      leading: const Icon(Icons.circle,
                                          size: 8, color: Colors.grey),
                                      title: Text(displayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              color: colors.textPrimary,
                                              fontSize: 13)),
                                      trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _buildTrailingTimeAndStopDetailWidget(
                                              context,
                                              timeWidget: _buildRealtimeTime(
                                                context,
                                                actualTime: actualTimeText,
                                                plannedTime: plannedTime,
                                                delayMinutes: delayMinutes,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                ),
                                              ),
                                              stopDetail:
                                                  combinePlatformAndStopLabel(
                                                platform?.toString(),
                                                stopLabel,
                                                stationName: name?.toString() ??
                                                    displayName,
                                                isRail:
                                                    _lineLooksRailForPlatformLabel(
                                                  step.line,
                                                ),
                                              ),
                                            ),
                                            if (exactStopDate != null)
                                              GestureDetector(
                                                onLongPress: () => widget
                                                    .onIntermediateAlarmLongPress(
                                                  name ?? displayName,
                                                  stopIndex: idx,
                                                  targetLat: stopLat,
                                                  targetLng: stopLng,
                                                  originLat: previousLat,
                                                  originLng: previousLng,
                                                ),
                                                child: IconButton(
                                                  onPressed: () =>
                                                      widget.onOpenAlternatives(
                                                    stopId as String,
                                                    exactStopDate!,
                                                    lat: stop['stop']
                                                            ['location']
                                                        ?['latitude'],
                                                    lng: stop['stop']
                                                            ['location']
                                                        ?['longitude'],
                                                    name: name,
                                                  ),
                                                  style: IconButton.styleFrom(
                                                    minimumSize:
                                                        const Size(28, 28),
                                                    padding: EdgeInsets.zero,
                                                    tapTargetSize:
                                                        MaterialTapTargetSize
                                                            .shrinkWrap,
                                                    backgroundColor:
                                                        isAlarmSelected
                                                            ? colors
                                                                .chipActiveBg
                                                            : Colors
                                                                .transparent,
                                                  ),
                                                  icon: Icon(
                                                    isAlarmSelected
                                                        ? Icons.vibration
                                                        : Icons.alt_route,
                                                    size: 16,
                                                    color: isAlarmSelected
                                                        ? colors.chipActiveFg
                                                        : Colors.blue,
                                                  ),
                                                ),
                                              )
                                          ])));
                            }))
                  else
                    Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                            AppLocalizations.of(context)!.noIntermediateStops)),
                  // Always show the link to the final destination as the last item
                  Container(
                      decoration: BoxDecoration(color: colors.stepStopoversBg),
                      child: GestureDetector(
                          onLongPress: step.startStationId != null
                              ? () {
                                  // Derive destination station ID if possible via stopovers last entry
                                  String? lastStopoverId;
                                  if (step.stopovers != null &&
                                      step.stopovers!.isNotEmpty) {
                                    lastStopoverId = step.stopovers!
                                        .last['stop']?['id'] as String?;
                                  }
                                  final destId = lastStopoverId ??
                                      step.destinationStationId ??
                                      step.startStationId!;
                                  final destDate = step.plannedArrival ??
                                      step.dateTime ??
                                      DateTime.now();
                                  widget.onShowStopDepartures(
                                    stopId: destId,
                                    stopName:
                                        step.destinationName ?? 'Destination',
                                    date: destDate,
                                    preferredPlatform: step.arrivalPlatform,
                                  );
                                }
                              : null,
                          child: ListTile(
                            dense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 20),
                            minLeadingWidth: 18,
                            leading: const Icon(Icons.flag,
                                size: 14, color: Colors.red),
                            title: Text(
                                _formatAlightingText(
                                  AppLocalizations.of(context)!,
                                  stationName:
                                      step.destinationName ?? 'Destination',
                                  platform: step.arrivalPlatform,
                                  stopLabel: step.arrivalStopLabel,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold)),
                            trailing: _buildTrailingTimeAndStopDetailWidget(
                              context,
                              timeWidget: _buildRealtimeTime(
                                context,
                                actualTime: step.arrivalTime,
                                plannedTime: step.plannedArrival,
                                delayMinutes: step.arrivalDelay,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              stopDetail: combinePlatformAndStopLabel(
                                step.arrivalPlatform,
                                step.arrivalStopLabel,
                                stationName: step.destinationName,
                                isRail: _lineLooksRailForPlatformLabel(
                                  step.line,
                                ),
                              ),
                            ),
                          )))
                ])));
  }

  Widget _buildActionChip(BuildContext context, IconData icon, String label,
      {bool isActive = false,
      bool outlined = false,
      bool highlighted = false,
      bool animated = false,
      required VoidCallback onTap}) {
    final colors = TransColors.of(context);
    // A highlighted chip keeps a faint wash of the theme colour so it reads as
    // marked even while the running border is on the far side of the button.
    final background = isActive
        ? colors.chipActiveBg
        : (highlighted
            ? colors.effectiveSeed.withValues(alpha: 0.25)
            : colors.chipBg);
    return GestureDetector(
        onTap: onTap,
        child: RunningBorder(
            active: animated,
            color: colors.effectiveSeed,
            child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(20),
                    border: outlined
                        ? Border.all(color: colors.chipActiveBg, width: 1.4)
                        : null),
                child: Row(children: [
                  Icon(icon,
                      size: 14,
                      color: isActive ? colors.chipActiveFg : colors.chipFg),
                  const SizedBox(width: 6),
                  Text(label,
                      style: TextStyle(
                          color: isActive ? colors.chipActiveFg : colors.chipFg,
                          fontSize: 12))
                ]))));
  }
}

class _EditFavoriteDialog extends StatefulWidget {
  final Favorite favorite;
  const _EditFavoriteDialog({required this.favorite});
  @override
  State<_EditFavoriteDialog> createState() => _EditFavoriteDialogState();
}

class _EditFavoriteDialogState extends State<_EditFavoriteDialog> {
  late TextEditingController _labelCtrl;
  final TextEditingController _searchCtrl = TextEditingController();
  Station? _selectedStation;
  int? _selectedIconCode;
  List<Station> _suggestions = [];
  Timer? _debounce;
  bool _isLoading = false;
  int _searchRequestToken = 0;

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: widget.favorite.label);
    _selectedStation = widget.favorite.station;
    _selectedIconCode = widget.favorite.iconCode;
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isNew = widget.favorite.id.isEmpty;
    final colors = TransColors.of(context);
    final media = MediaQuery.of(context);
    final topInset = max(12.0, media.padding.top + 8);
    final availableHeight =
        media.size.height - media.viewInsets.bottom - topInset - 12;
    final dialogMaxHeight = max(260.0, availableHeight);
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: EdgeInsets.fromLTRB(16, topInset, 16, 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: colors.cardBg,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 400, maxHeight: dialogMaxHeight),
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    isNew
                        ? AppLocalizations.of(context)!.addFavorite
                        : AppLocalizations.of(context)!.editFavorite,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary)),
                const SizedBox(height: 20),
                TextField(
                    controller: _labelCtrl,
                    decoration: InputDecoration(
                        labelText:
                            AppLocalizations.of(context)!.favoriteLabelHint)),
                const SizedBox(height: 10),
                SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                        children: kAvailableFavoriteIcons.map((icon) {
                      final isSelected = _selectedIconCode == icon.codePoint;
                      return GestureDetector(
                          onTap: () => setState(
                              () => _selectedIconCode = icon.codePoint),
                          child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                  color: isSelected
                                      ? colors.navBarSelected
                                      : colors.chipBg,
                                  shape: BoxShape.circle),
                              child: Icon(icon,
                                  size: 20,
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.grey)));
                    }).toList())),
                const SizedBox(height: 10),
                if (_selectedStation != null)
                  ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.train, color: Colors.indigo),
                      title: Text(_selectedStation!.name,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() {
                                _selectedStation = null;
                                _searchCtrl.clear();
                                _suggestions = [];
                              })))
                else ...[
                  TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                        labelText:
                            AppLocalizations.of(context)!.searchStationName,
                        prefixIcon: const Icon(Icons.search),
                        suffix: SizedBox(
                            width: 16,
                            height: 16,
                            child: _isLoading
                                ? const CircularProgressIndicator(
                                    strokeWidth: 2)
                                : null)),
                    onChanged: (val) {
                      final sanitizedQuery = val.trim();
                      if (_debounce?.isActive ?? false) _debounce!.cancel();
                      if (sanitizedQuery.isEmpty) {
                        _searchRequestToken++;
                        if (mounted) setState(() => _suggestions = []);
                        return;
                      }
                      final requestToken = ++_searchRequestToken;
                      _debounce =
                          Timer(const Duration(milliseconds: 400), () async {
                        if (!mounted) return;
                        setState(() => _isLoading = true);
                        try {
                          final res = await TransportApi.searchStations(
                            sanitizedQuery,
                          ).timeout(const Duration(seconds: 10));
                          if (requestToken != _searchRequestToken) return;
                          if (mounted) {
                            setState(() {
                              _suggestions = res;
                              _isLoading = false;
                            });
                          }
                        } catch (e) {
                          if (requestToken != _searchRequestToken) return;
                          if (mounted) setState(() => _isLoading = false);
                        }
                      });
                    },
                  ),
                  if (_suggestions.isNotEmpty)
                    Container(
                        height: 150,
                        margin: const EdgeInsets.only(top: 8),
                        decoration: BoxDecoration(
                            border: Border.all(color: Colors.white10),
                            borderRadius: BorderRadius.circular(8)),
                        child: ListView.builder(
                            itemCount: _suggestions.length,
                            itemBuilder: (context, idx) {
                              final s = _suggestions[idx];
                              return ListTile(
                                  dense: true,
                                  title: Text(s.name),
                                  onTap: () {
                                    if (!mounted) return;
                                    setState(() {
                                      _selectedStation = s;
                                      _suggestions = [];
                                      if (_labelCtrl.text.isEmpty) {
                                        _labelCtrl.text = s.name;
                                      }
                                    });
                                  });
                            }))
                ],
                const SizedBox(height: 20),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  if (!isNew &&
                      widget.favorite.id != 'home' &&
                      widget.favorite.id != 'work')
                    TextButton(
                        onPressed: () async {
                          await FavoritesManager.deleteFavorite(
                              widget.favorite.id);
                          if (context.mounted) Navigator.pop(context, true);
                        },
                        child: Text(AppLocalizations.of(context)!.delete,
                            style: TextStyle(color: Colors.red))),
                  const SizedBox(width: 8),
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(AppLocalizations.of(context)!.cancel)),
                  ElevatedButton(
                      onPressed: () async {
                        if (_labelCtrl.text.isNotEmpty) {
                          final newFav = Favorite(
                              id: isNew
                                  ? DateTime.now()
                                      .millisecondsSinceEpoch
                                      .toString()
                                  : widget.favorite.id,
                              label: _labelCtrl.text,
                              type: kSupportedFavoriteType,
                              station: _selectedStation,
                              iconCode: _selectedIconCode);
                          await FavoritesManager.saveFavorite(newFav);
                          if (context.mounted) Navigator.pop(context, true);
                        }
                      },
                      child: Text(AppLocalizations.of(context)!.save))
                ])
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AlternativesSheet extends StatefulWidget {
  final Station from;
  final Station to;
  final DateTime initialTime;
  final bool nahverkehrOnly;

  /// Ride key of the earlier connection that made the Alt button light up; it
  /// is marked where it sits in the list.
  final String? highlightKey;

  /// Departure before which the traveller cannot be at the stop, because the
  /// ride that brings them there has not arrived yet. Those connections stay
  /// in the list - knowing how often the line runs is worth something - they
  /// are only dimmed and never recommended.
  final DateTime? earliestDeparture;

  /// The ride this sheet was opened from. It is filtered out, because the trip
  /// the traveller is already on is not an alternative to itself.
  final String? currentTripId;
  final String? currentLine;

  /// Results the background check already fetched. They are shown right away
  /// and replaced as soon as the fresh search comes back.
  final List<Map<String, dynamic>>? initialResults;
  final Function(Map<String, dynamic> journeyData, DateTime depTime) onSelected;

  const _AlternativesSheet({
    required this.from,
    required this.to,
    required this.initialTime,
    required this.nahverkehrOnly,
    required this.onSelected,
    this.highlightKey,
    this.earliestDeparture,
    this.currentTripId,
    this.currentLine,
    this.initialResults,
  });

  @override
  State<_AlternativesSheet> createState() => _AlternativesSheetState();
}

class _AlternativesSheetState extends State<_AlternativesSheet> {
  /// Set once the traveller asked for the earlier departures that the cap
  /// keeps out of the way.
  bool _showAllEarlier = false;

  final List<Map<String, dynamic>> _results = [];
  bool _isLoading = true;
  bool _isMoreLoading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    final preloaded = widget.initialResults;
    if (preloaded != null && preloaded.isNotEmpty) {
      // Straight to the list; the refresh below fills in what the background
      // check left out.
      _results.addAll(mergeAlternativeJourneys(const [], preloaded));
      _isLoading = false;
      _isMoreLoading = true;
    }
    _fetchInitial();
  }

  Future<void> _fetchInitial() async {
    // Preloaded rows stay on screen while the fresh search runs behind them.
    if (mounted && _results.isEmpty) setState(() => _isLoading = true);
    try {
      void processResults(List<Map<String, dynamic>> res) {
        if (!mounted || res.isEmpty) return;
        setState(() {
          final merged = mergeAlternativeJourneys(_results, res);
          _results
            ..clear()
            ..addAll(merged);
          _isLoading = false;
          _error = null;
        });
      }

      // What can still be taken comes first. A search anchored an hour back
      // spends its itineraries on that hour and can stop before it ever
      // reaches the planned departure.
      final forward = await TransportApi.searchJourneys(
        widget.from,
        widget.to,
        nahverkehrOnly: widget.nahverkehrOnly,
        when: widget.initialTime,
        isArrival: false,
        results: 12,
        onPartialResults: processResults,
      );
      processResults(forward);

      // Then the ones before it, for the sense of how often the line runs.
      List<Map<String, dynamic>> earlier = await TransportApi.searchJourneys(
        widget.from,
        widget.to,
        nahverkehrOnly: widget.nahverkehrOnly,
        when: widget.initialTime.subtract(const Duration(hours: 1)),
        isArrival: false,
        results: 8,
        onPartialResults: processResults,
      );
      processResults(earlier);

      // Nothing preceding at all (infrequent line): reach further back.
      if (!_hasPreceding(_results)) {
        earlier = await TransportApi.searchJourneys(
          widget.from,
          widget.to,
          nahverkehrOnly: widget.nahverkehrOnly,
          when: widget.initialTime.subtract(const Duration(hours: 4)),
          isArrival: false,
          results: 15,
          onPartialResults: processResults,
        );
        processResults(earlier);
      }
    } catch (e, st) {
      AppError.log(e,
          stackTrace: st, source: 'AlternativesSheet._fetchInitial');
      if (mounted) {
        setState(() {
          _error = e;
          _isLoading = false;
        });
      }
    } finally {
      if (mounted) setState(() => _isMoreLoading = false);
    }
  }

  bool _hasPreceding(List<Map<String, dynamic>> results) {
    return results.any((j) => _getDepTime(j)
        .isBefore(widget.initialTime.subtract(const Duration(seconds: 15))));
  }

  Future<void> _fetch(DateTime time, bool isArrival) async {
    if (mounted) setState(() => _isMoreLoading = true);
    try {
      void processResults(List<Map<String, dynamic>> res) {
        if (!mounted || res.isEmpty) return;
        setState(() {
          final merged = mergeAlternativeJourneys(_results, res);
          _results
            ..clear()
            ..addAll(merged);
          _isLoading = false;
          _isMoreLoading = false;
          _error = null;
        });
      }

      final results = await TransportApi.searchJourneys(
        widget.from,
        widget.to,
        nahverkehrOnly: widget.nahverkehrOnly,
        when: time,
        isArrival: isArrival,
        results: 10,
        onPartialResults: processResults,
      );

      processResults(results);
    } catch (e, st) {
      AppError.log(e, stackTrace: st, source: 'AlternativesSheet._fetch');
      if (mounted) {
        setState(() {
          _error = e;
          _isLoading = false;
          _isMoreLoading = false;
        });
      }
    }
  }

  /// Boarding time of the first ride - the same time the route view shows, so
  /// the two do not disagree by the minute a leading walk leg costs.
  DateTime _getDepTime(Map<String, dynamic> j) {
    return alternativeJourneyBoardingLocal(j) ?? DateTime.now();
  }

  void _loadEarlier() {
    if (_results.isEmpty) return;
    final selectable = _selectableResults();
    final capped = limitEarlierAlternatives(
      selectable,
      reference: widget.initialTime,
    ).length;
    if (!_showAllEarlier && capped < selectable.length) {
      setState(() => _showAllEarlier = true);
      return;
    }
    // Everything loaded from here on is earlier, so the cap stays lifted.
    _showAllEarlier = true;
    _fetch(
        _getDepTime(_results.first).subtract(const Duration(seconds: 1)), true);
  }

  void _loadLater() {
    if (_results.isEmpty) return;
    _fetch(_getDepTime(_results.last).add(const Duration(seconds: 1)), false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    final l10n = AppLocalizations.of(context)!;
    final errorMessage = _error == null
        ? null
        : AppError.userMessage(
            context,
            _error!,
            fallback: l10n.noRoutesFoundBusy,
          );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2))),
        ),
        Text(l10n.alternatives,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary)),
        const SizedBox(height: 8),
        if (_isLoading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_error != null && _results.isEmpty)
          Expanded(
              child: Center(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(errorMessage ?? l10n.noRoutesFoundBusy,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colors.textPrimary)),
                        const SizedBox(height: 12),
                        TextButton.icon(
                            onPressed: _fetchInitial,
                            icon: const Icon(Icons.refresh),
                            label: Text(l10n.retry))
                      ]))))
        else if (_results.isEmpty)
          Expanded(child: Center(child: Text(l10n.noRoutesFound)))
        else
          Expanded(
            child: Builder(builder: (ctx) {
              final selectable = _selectableResults();
              // At most three earlier departures up front; "Frühere
              // Verbindungen" reveals the rest and then keeps loading back.
              final visible = _showAllEarlier
                  ? selectable
                  : limitEarlierAlternatives(
                      selectable,
                      reference: widget.initialTime,
                    );
              const leadingCount = 1;
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: visible.length + leadingCount + 1,
                itemBuilder: (ctx, idx) {
                  if (idx == 0) {
                    return TextButton.icon(
                        style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12)),
                        onPressed: _isMoreLoading ? null : _loadEarlier,
                        icon: const Icon(Icons.history, size: 18),
                        label: Text(l10n.loadEarlier));
                  }
                  if (idx == visible.length + leadingCount) {
                    return TextButton.icon(
                        style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12)),
                        onPressed: _isMoreLoading ? null : _loadLater,
                        icon: const Icon(Icons.update, size: 18),
                        label: Text(l10n.loadLater));
                  }

                  final journey = visible[idx - leadingCount];
                  return _buildJourneyTile(
                    context,
                    journey,
                    highlighted:
                        alternativeRideKey(journey) == _highlightedKey(),
                    reachable: _isReachable(journey),
                  );
                },
              );
            }),
          ),
        if (_isMoreLoading && _results.isNotEmpty)
          const LinearProgressIndicator(),
      ],
    );
  }

  /// The suggested connection is the one the automatic check found; while the
  /// preview switch is on, the first result stands in for it so the styling
  /// can be looked at on any route.
  /// A connection that leaves before the traveller can be at the stop is shown
  /// for orientation, but greyed out.
  bool _isReachable(Map<String, dynamic> journey) {
    final cutoff = widget.earliestDeparture;
    if (cutoff == null) return true;
    return !_getDepTime(journey).isBefore(cutoff);
  }

  String? _highlightedKey() {
    if (widget.highlightKey != null) return widget.highlightKey;
    if (!kPreviewHighlightSuggestedAlternative) return null;
    final reachable = _selectableResults().where(_isReachable);
    if (reachable.isEmpty) return null;
    return alternativeRideKey(reachable.first);
  }

  /// Results worth offering: only the ride the traveller is already on drops
  /// out, and each remaining ride appears once even if it continues in several
  /// ways.
  List<Map<String, dynamic>> _selectableResults() {
    final offered = _results.where((journey) => !alternativeIsSameRide(
          journey,
          tripId: widget.currentTripId,
          line: widget.currentLine,
          departure: widget.initialTime,
        ));

    // Sorted by boarding time, which is what the rows show. The raw results
    // are ordered by journey start, so a leading walk leg would otherwise put
    // rows out of order.
    final collapsed = collapseAlternativesByRide(offered)
      ..sort((a, b) => _getDepTime(a).compareTo(_getDepTime(b)));
    return collapsed;
  }

  Widget _buildJourneyTile(
    BuildContext context,
    Map<String, dynamic> journey, {
    required bool highlighted,
    bool reachable = true,
  }) {
    final colors = TransColors.of(context);
    final legs = (journey['legs'] as List).cast<Map<String, dynamic>>();
    if (legs.isEmpty) return const SizedBox.shrink();
    final firstRide =
        legs.firstWhere((l) => l['line'] != null, orElse: () => legs.first);
    final line =
        firstRide['line'] != null ? firstRide['line']['name'] : 'Walk/Transfer';
    final dir = firstRide['direction'] ?? 'Destination';
    final depTime = _getDepTime(journey);

    int delayMin = 0;
    if (firstRide['departureDelay'] != null) {
      delayMin = ((firstRide['departureDelay'] as num) / 60).round();
    } else if (firstRide['plannedDeparture'] != null &&
        firstRide['departure'] != null) {
      final planned = DateTime.parse(firstRide['plannedDeparture']).toLocal();
      final actual = DateTime.parse(firstRide['departure']).toLocal();
      delayMin = actual.difference(planned).inMinutes;
    }

    final tile = ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: highlighted
            ? colors.effectiveSeed.withValues(alpha: 0.25)
            : colors.chipBg,
        child: Icon(Icons.alt_route,
            color: highlighted ? colors.effectiveSeed : colors.chipFg,
            size: 20),
      ),
      title: Row(
        children: [
          Expanded(
              child: Text(AppLocalizations.of(context)!.toDirection(line, dir),
                  style: const TextStyle(fontWeight: FontWeight.bold))),
          if (depTime.isBefore(
              widget.initialTime.subtract(const Duration(minutes: 1))))
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4)),
                child: Text(AppLocalizations.of(context)!.previous,
                    style: TextStyle(
                        color: Colors.blue,
                        fontSize: 9,
                        fontWeight: FontWeight.bold)))
        ],
      ),
      subtitle: Text.rich(TextSpan(children: [
        TextSpan(
            text: AppLocalizations.of(context)!
                .departsAt(DateFormat('HH:mm').format(depTime)),
            style: TextStyle(color: colors.textSecondary)),
        if (delayMin > 0)
          TextSpan(
              text:
                  " ${AppLocalizations.of(context)!.lateByMinutes(delayMin.toString())}",
              style: const TextStyle(
                  color: Colors.orange, fontWeight: FontWeight.bold)),
      ])),
      onTap: () => widget.onSelected(journey, depTime),
    );

    // Still tappable: the traveller may know something the plan does not.
    return reachable ? tile : Opacity(opacity: 0.45, child: tile);
  }
}
