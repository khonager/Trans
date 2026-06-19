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
import 'package:trans/models/favorite.dart';
import 'package:trans/services/transport_api.dart';
import 'package:trans/services/community_safety_service.dart';
import 'package:trans/services/supabase_service.dart';
import 'package:trans/services/history_manager.dart';
import 'package:trans/services/favorites_manager.dart';
import 'package:trans/services/favorites_policy.dart';
import 'package:trans/services/notification_manager.dart';
import 'package:trans/services/foreground_haptics.dart';
import 'package:trans/services/wake_alarm_preview_player.dart';
import 'package:trans/services/wake_alarm_settings.dart';
import 'package:trans/utils/favorite_icons.dart';
import 'package:trans/widgets/chat_sheet.dart';
import 'package:trans/widgets/stop_departures_sheet.dart';
import 'package:trans/config/app_theme.dart';
import 'package:trans/utils/app_error.dart';
import 'package:trans/utils/format_utils.dart';
import '../../l10n/app_localizations.dart';
import '../map_screen.dart';
import 'route_results_view.dart';

const int _activeJourneyRefreshWindowSize = 8;

enum RouteHistoryView { frequent, recent }

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

String? _extractStopDetailCode(String label, {required bool isRail}) {
  final normalized = label.trim();
  if (normalized.isEmpty) return null;

  final typeKeywords = isRail
      ? '(?:gleis|schiene|platform|track)'
      : '(?:bussteig|bussteige|steig|platz|haltestelle|bstg\\.?)';

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
  if (extractedCode != null) {
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

@visibleForTesting
List<Map<String, dynamic>> mergeAlternativeJourneys(
  Iterable<Map<String, dynamic>> existing,
  Iterable<Map<String, dynamic>> incoming,
) {
  final merged = <Map<String, dynamic>>[];
  final seenIds = <String>{};

  void addJourney(Map<String, dynamic> journey) {
    final departure = alternativeJourneyDisplayDepartureLocal(journey);
    if (departure == null) return;

    final arrival = (() {
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
    })();
    if (arrival == null) return;

    final id =
        '${departure.millisecondsSinceEpoch}_${arrival.millisecondsSinceEpoch}';
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
  return journeys
      .map((j) =>
          "${j.plannedDeparture ?? j.departure}_${j.plannedArrival ?? j.arrival}_${j.steps.length}")
      .join("||");
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
    if ((step.platform ?? '').trim().isNotEmpty) score += 2;
    if ((step.arrivalPlatform ?? '').trim().isNotEmpty) score += 1;
    if ((step.departureStopLabel ?? '').trim().isNotEmpty) score += 1;
    if ((step.arrivalStopLabel ?? '').trim().isNotEmpty) score += 1;
  }
  return score;
}

String _firstRideLineKey(Journey journey) {
  for (final step in journey.steps) {
    if (step.type != 'ride') continue;
    return step.line
        .toUpperCase()
        .replaceAll(RegExp(r'\s*\(\d+\)'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
  return '';
}

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
  if (incomingScore > existingScore) return incoming;
  return existing;
}

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
    best = _preferJourneyWithMorePlatformDetail(best, candidate);
  }
  return best;
}

bool _journeyHasDeparturePlatformsForEveryRide(Journey journey) {
  final rideSteps = journey.steps.where((step) => step.type == 'ride').toList();
  if (rideSteps.isEmpty) return true;
  return rideSteps.every((step) => (step.platform ?? '').trim().isNotEmpty);
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

  const RoutesTab({
    super.key,
    required this.currentPosition,
    required this.onlyNahverkehr,
    this.showTrainNumbers = false,
    required this.alwaysWakeMe,
  });

  @override
  State<RoutesTab> createState() => RoutesTabState();
}

class RoutesTabState extends State<RoutesTab> with WidgetsBindingObserver {
  final List<RouteTab> _tabs = [];
  String? _activeTabId;

  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _toController = TextEditingController();

  final FocusNode _fromFocusNode = FocusNode();
  final FocusNode _toFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _suggestionsScrollController = ScrollController();

  Station? _fromStation;
  Station? _toStation;

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
  double? _gpsAccuracy;
  List<Favorite> _favorites = [];
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
  final Map<String, double> _routeResultsScrollOffsets = <String, double>{};
  final Map<String, RouteSortOption> _routeResultsSortSelections =
      <String, RouteSortOption>{};
  bool _isCheckingSavedJourneyStatuses = false;
  DateTime? _lastSavedJourneyStatusCheck;
  RouteHistoryView _historyView = RouteHistoryView.frequent;

  Position? get _effectiveCurrentPosition =>
      _manualCurrentPosition ?? widget.currentPosition;

  @override
  void initState() {
    super.initState();
    _fetchSuggestions(forceHistory: true);
    _loadFavorites();
    _loadDeviceRoutePreferences();
    SupabaseService.settingsRefreshNotifier
        .addListener(_handleDeviceRouteSettingsRefresh);
    _initNotifications();
    WidgetsBinding.instance.addObserver(this);
    _fromFocusNode.addListener(_onFocusChange);
    _toFocusNode.addListener(_onFocusChange);
    _resolveCurrentAddress();
    _loadHistoryData();
  }

  Future<void> _loadDeviceRoutePreferences() async {
    final prefs = await SharedPreferences.getInstance();
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
    });
  }

  void _handleDeviceRouteSettingsRefresh() {
    unawaited(_loadDeviceRoutePreferences());
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
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_loadDeviceRoutePreferences());
    }
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
        _scrollToTop();
      }
    } else if (_toFocusNode.hasFocus) {
      _focusDebounce?.cancel();
      if (_activeSearchField != 'to') {
        setState(() {
          _activeSearchField = 'to';
          _fetchSuggestions(forceHistory: _toController.text.isEmpty);
        });
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
    _fromController.dispose();
    _toController.dispose();
    _fromFocusNode.dispose();
    _toFocusNode.dispose();
    _scrollController.dispose();
    _suggestionsScrollController.dispose();
    for (final controller in _routeResultsScrollControllers.values) {
      controller.dispose();
    }
    _debounce?.cancel();
    _focusDebounce?.cancel();
    _gpsStream?.cancel();
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
      setState(() {
        _activeSearchField = '';
        _suggestions = [];
        FocusScope.of(context).unfocus();
      });
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
      _scrollToTop();
    }
    if (_wasKeyboardVisible && !isVisible) {
      // Keyboard JUST closed
      if (_fromFocusNode.hasFocus || _toFocusNode.hasFocus) {
        FocusScope.of(context).unfocus();
      }
    }
    _wasKeyboardVisible = isVisible;
  }

  void _scrollToTop() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(0.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut);
      }
    });
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
    if (mounted) setState(() => _favorites = favs);
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
      SnackBar(content: Text('Wake alert set for $stopName')),
    );
  }

  void _stopWakeAlarm() {
    _gpsStream?.cancel();
    _gpsStream = null;
    SupabaseService.clearJourneyStatus();
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
          _suggestions = history;
          if (updateLoadingState) _isSuggestionsLoading = false;
        });
      }
      return;
    }
    if (updateLoadingState) {
      setState(() => _isSuggestionsLoading = true);
    }
    List<dynamic> results = [];
    final query = (_activeSearchField == 'from'
            ? _fromController.text
            : _toController.text)
        .trim();
    if (query.isNotEmpty) {
      final matchingFavs = _matchingFavoritesForQuery(query);
      results.addAll(matchingFavs);
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
    } else if (_activeSearchField == 'to') {
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
      }
      return;
    }
    if (field == 'from') {
      setState(() {
        _fromStation = null;
        _fromUsesCurrentLocation = _isCurrentLocationText(sanitizedQuery);
      });
    }
    final matchingFavs = _matchingFavoritesForQuery(sanitizedQuery);
    setState(() {
      _suggestions = matchingFavs;
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
      } else if (field == 'to') {
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
        final matchingFavs = _matchingFavoritesForQuery(sanitizedQuery);
        if (mounted) {
          setState(() {
            if (apiResults.isEmpty && matchingFavs.isEmpty) {
              // Show message if no results at all
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content:
                      Text(AppLocalizations.of(context)!.serviceBusyTryAgain),
                  duration: const Duration(seconds: 2)));
            }
            _suggestions = <dynamic>[
              ...matchingFavs,
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
        _toController.text = station.name;
      }
      _suggestions = [];
      _activeSearchField = '';
    });
    FocusScope.of(context).unfocus();
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
          _toController.text = target.name;
          // If from is empty, maybe jump there? But usually 'to' is second.
          if (_fromStation == null && _effectiveCurrentPosition == null) {
            _activeSearchField = 'from';
            _fromFocusNode.requestFocus();
          }
        } else {
          if (_fromStation != null || _effectiveCurrentPosition != null) {
            _toStation = target;
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
    _routeResultsScrollOffsets.remove(id);
    _routeResultsSortSelections.remove(id);
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
    return SearchHistoryManager.buildSavedJourneyConnectionKey(
      from: from,
      to: route.destination,
      departure: active.plannedDeparture ?? active.departure,
      arrival: active.plannedArrival ?? active.arrival,
      journeyData: active.rawSource,
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
      final saved = await SearchHistoryManager.toggleSavedJourney(
        from: from,
        to: route.destination,
        journeyData: activeJourney.rawSource,
        departure: activeJourney.plannedDeparture ?? activeJourney.departure,
        arrival: activeJourney.plannedArrival ?? activeJourney.arrival,
      );
      await _loadHistoryData();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              saved ? 'Connection saved' : 'Connection removed from saved')));
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
    return (
      title: 'Leave soon',
      body: '$minutes min left for $fromName -> $toName ($departureLabel)',
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
        const SnackBar(
          content: Text(
            'Android blocked exact alarms for this reminder. Open "Alarms & reminders" for Trans to make leave alerts reliable.',
          ),
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
      SnackBar(content: Text('Leave in $minutes min for $toName')),
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
    final selectedSummary = normalizedNextMinutes.isEmpty
        ? 'none'
        : normalizedNextMinutes.map((value) => '${value}m').join(', ');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Leave reminders: $selectedSummary')),
    );
  }

  Future<void> _deleteSavedJourney(Map<String, dynamic> item) async {
    final removed =
        await SearchHistoryManager.removeSavedJourneyByItem(item: item);
    if (!removed) return;
    await _loadHistoryData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved route deleted')),
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
      {double? lat, double? lng, String? stationName}) {
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
          onSelected: (journey, depTime) {
            Navigator.pop(ctx);
            final j = _createJourney(
              journey,
              destinationNameOverride: toDummy.name,
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
    bool isFirstStep = true; // Track if this is the first step in the journey
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

    bool sameStationByIdOrName(
        String? leftId, String? leftName, String? rightId, String? rightName) {
      final aId = leftId?.trim();
      final bId = rightId?.trim();
      if (aId != null && aId.isNotEmpty && bId != null && bId.isNotEmpty) {
        return aId == bId;
      }
      final aName = leftName?.trim().toLowerCase();
      final bName = rightName?.trim().toLowerCase();
      if (aName == null || aName.isEmpty || bName == null || bName.isEmpty) {
        return false;
      }
      return aName == bName;
    }

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
      bool isAtSameStation = (lastStationId != null &&
              nextStationId != null &&
              lastStationId == nextStationId) ||
          (lastStationName != null &&
              destName != null &&
              lastStationName == destName);
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
        final startsAtNextRideStation = sameStationByIdOrName(
          stationId(firstTransfer['origin']),
          stationName(firstTransfer['origin']),
          nextStationId,
          nextStationName,
        );
        final endsAtNextRideStation = sameStationByIdOrName(
          stationId(lastTransfer['destination']),
          stationName(lastTransfer['destination']),
          nextStationId,
          nextStationName,
        );
        if (isPhantomWalk &&
            (startsAtNextRideStation || endsAtNextRideStation)) {
          transferBuffer.clear();
          isFirstStep = false;
          return;
        }
      }

      String fmtPlat(String? p) =>
          p == null ? '' : (int.tryParse(p) != null ? 'Pl. $p' : p);

      if (isAtSameStation && !isSignificantWalk) {
        isWaitInstruction = true;
        if (lastPlatform != null &&
            nextPlat != null &&
            lastPlatform != nextPlat) {
          instruction = AppLocalizations.of(context)!
              .switchPlatform(fmtPlat(lastPlatform), fmtPlat(nextPlat));
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
      isFirstStep = false; // After first flush, no longer first step
    }

    for (var leg in legs) {
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
        transferBuffer.add(leg);
      }
    }
    flushTransferBuffer(null, null, null, null, null, null, isFinalWalk: true);
    return steps;
  }

  Journey _createJourney(
    Map<String, dynamic> journeyData, {
    String? destinationNameOverride,
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
      Station? destination}) {
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
      ));
      _activeTabId = id;
    });
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
          // Use GPS directly
          from = Station(
              id: 'gps',
              name: l10n.currentLocation,
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
              destination: _toStation);
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
                destination: _toStation);
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
      searchFuture = TransportApi.searchJourneys(resolvedFrom, _toStation!,
          nahverkehrOnly: widget.onlyNahverkehr,
          when: when,
          isArrival: _isArrival,
          onLoadStateChanged: (phases) =>
              _setRouteLoadPhasesForToken(searchToken, phases),
          shouldContinue: () => !_isRouteSearchCancelled(searchToken),
          onPartialResults: handlePartialResults);

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
    final bool canSearch =
        (_fromStation != null || _effectiveCurrentPosition != null) &&
            _toStation != null;
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
        SizedBox(
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
                })),

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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isActive ? colors.navBarSelected : colors.cardBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Close Button (Left)
                    GestureDetector(
                      onTap: () => _closeTab(tab.id),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
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
          final isSelected = tab.activeJourney == journey;

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
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? colors.navBarSelected : colors.cardBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Subtabs also have Close button?
                    GestureDetector(
                      onTap: () {
                        // Remove this journey from stack
                        setState(() {
                          final tIdx = _tabs.indexWhere((t) => t.id == tab.id);
                          if (tIdx != -1) {
                            final newStack = List<Journey>.from(stack);
                            newStack.removeAt(idx);

                            Journey? newActive = tab.activeJourney;
                            if (newActive == journey) {
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
                        padding: const EdgeInsets.only(right: 6),
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
        FocusScope.of(context).unfocus();
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
                    Row(children: [
                      Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: colors.searchHeaderIconBg,
                              borderRadius: BorderRadius.circular(8)),
                          child: Icon(Icons.search,
                              color: colors.searchHeaderIcon)),
                      const SizedBox(width: 12),
                      Text(AppLocalizations.of(context)!.planJourney,
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary))
                    ]),
                    const SizedBox(height: 20),
                    _buildTextField(
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
                    if (_activeSearchField == 'from') _buildSuggestionsList(),
                    const SizedBox(height: 12),
                    _buildTextField(AppLocalizations.of(context)!.toLabel,
                        _toController, _toFocusNode, _toStation != null, 'to',
                        hint: AppLocalizations.of(context)!.toStationOrAddress),
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
                                      AppLocalizations.of(context)!.findRoutes,
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
              child: Text('No recent routes yet',
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
                Text('Saved routes',
                    style: TextStyle(
                        color: colors.sectionHeader,
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
                const SizedBox(width: 8),
                Text('(auto-delete 24h after arrival)',
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
                        child: const Text(
                          'Delete',
                          style: TextStyle(
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

  Widget _buildSuggestionsList() {
    if (!_isSuggestionsLoading && _suggestions.isEmpty) {
      return const SizedBox.shrink();
    }
    final colors = TransColors.of(context);
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
                            IconData leadingIcon = Icons.place;
                            if (station.type == 'address') {
                              leadingIcon = Icons.home_work;
                            } else if (station.type == 'stop') {
                              leadingIcon = Icons.train;
                            }

                            final distanceText =
                                _distanceTextForStation(station);

                            tile = ListTile(
                              leading: Icon(leadingIcon,
                                  size: 16, color: Colors.grey),
                              title: Text(station.name,
                                  style: TextStyle(
                                      color: colors.textPrimary, fontSize: 14)),
                              subtitle: station.locationSummary != null
                                  ? Text(station.locationSummary!,
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
      {String hint = ""}) {
    final colors = TransColors.of(context);
    Color iconColor = colors.searchInputIcon;

    String effectiveHint = hint;
    bool isLocationHint = false;

    if (fieldKey == 'from' &&
        _fromStation == null &&
        _effectiveCurrentPosition != null) {
      effectiveHint =
          _currentAddress ?? AppLocalizations.of(context)!.currentLocation;
      isLocationHint = true;
    }

    if (isSelected) {
      iconColor = Colors.greenAccent;
    } else if (fieldKey == 'from' &&
        ((_fromStation?.id == 'gps') ||
            (isLocationHint &&
                effectiveHint !=
                    AppLocalizations.of(context)!.fromStationOrAddress))) {
      iconColor = Colors.blue;
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text(label.toUpperCase(),
              style: const TextStyle(
                  fontSize: 10,
                  color: Colors.grey,
                  fontWeight: FontWeight.bold))),
      TextField(
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
              fillColor: colors.searchInputFill,
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
                  : Icon(Icons.location_on, color: iconColor, size: 20),
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
                  borderSide: BorderSide.none)))
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
    DateTime? earlierWindowStart;

    if (earlier) {
      if (route.candidates == null || route.candidates!.isEmpty) return;
      earlierBoundary = route.candidates!
          .map((journey) => journey.plannedDeparture ?? journey.departure)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      earlierWindowStart = earlierBoundary.subtract(const Duration(hours: 2));
      refDate = earlierWindowStart;
      isArrival = false;
    } else {
      if (route.candidates == null || route.candidates!.isEmpty) return;
      refDate = route.candidates!
          .map((journey) => journey.plannedDeparture ?? journey.departure)
          .reduce((a, b) => a.isAfter(b) ? a : b)
          .add(const Duration(minutes: 1));
      isArrival = false; // Find connections departing after the last one
    }

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
        final List<Journey> newJourneys = [];
        for (var d in partial) {
          try {
            newJourneys.add(
              _createJourney(d,
                  destinationNameOverride: route.destination.name),
            );
          } catch (e) {/* ignore */}
        }
        if (earlier && earlierBoundary != null && earlierWindowStart != null) {
          newJourneys.removeWhere((journey) {
            final departure = journey.plannedDeparture ?? journey.departure;
            return !departure.isBefore(earlierBoundary!) ||
                departure.isBefore(earlierWindowStart!);
          });
        }
        if (newJourneys.isEmpty) {
          _releaseBlockingRouteLoad(loadToken);
          if (!visibleResults.isCompleted) {
            visibleResults.complete();
          }
          return;
        }

        setState(() {
          final idx = _tabs.indexWhere((t) => t.id == route.id);
          if (idx != -1) {
            final currentRoute = _tabs[idx];
            final byKey = <String, Journey>{};
            for (final journey in currentRoute.candidates!) {
              byKey[_journeyListKey(journey)] = journey;
            }
            for (final journey in newJourneys) {
              final key = _journeyListKey(journey);
              final existing = byKey[key];
              byKey[key] = existing == null
                  ? journey
                  : _preferJourneyWithMorePlatformDetail(existing, journey);
            }

            final updatedCandidates = byKey.values.toList()
              ..sort((a, b) => a.departure.compareTo(b.departure));
            _tabs[idx] = currentRoute.copyWith(candidates: updatedCandidates);
          }
        });
        _releaseBlockingRouteLoad(loadToken);
        if (!visibleResults.isCompleted) {
          visibleResults.complete();
        }
      }

      unawaited(
        TransportApi.searchJourneys(
          originStation,
          route.destination,
          nahverkehrOnly: widget.onlyNahverkehr,
          when: refDate,
          isArrival: isArrival,
          results: 5,
          onLoadStateChanged: (phases) =>
              _setRouteLoadPhasesForToken(loadToken, phases),
          shouldContinue: () => !_isRouteSearchCancelled(loadToken),
          onPartialResults: appendResults,
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)!
                .couldNotLoadMoreRoutes(e.toString()))));
      }
    } finally {
      _releaseBlockingRouteLoad(loadToken);
    }
  }

  Future<void> _refreshRoutes(RouteTab route) async {
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

      // Keep a small buffer in the past so recently due/late services are still refreshable.
      DateTime refDate = DateTime.now().subtract(const Duration(minutes: 10));
      if (route.candidates != null && route.candidates!.isNotEmpty) {
        final firstCandidateTime = route.candidates!.first.plannedDeparture ??
            route.candidates!.first.departure;
        final candidateRef =
            firstCandidateTime.subtract(const Duration(minutes: 3));
        if (candidateRef.isBefore(refDate)) {
          refDate = candidateRef;
        }
      }

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
        final newSignature = _journeyRefreshSignature(newJourneys);
        hasChanged = previousSignature != newSignature;
        hasRefreshResults = true;

        setState(() {
          final idx = _tabs.indexWhere((t) => t.id == route.id);
          if (idx != -1) {
            final currentRoute = _tabs[idx];
            _tabs[idx] = currentRoute.copyWith(candidates: newJourneys);
          }
        });
      }

      final newResults = await TransportApi.searchJourneys(
        originStation,
        route.destination,
        nahverkehrOnly: widget.onlyNahverkehr,
        when: refDate,
        isArrival: false,
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
    final freshRideSteps =
        fresh.steps.where((step) => step.type == 'ride').toList();

    final mergedSteps = existing.steps.map((step) {
      if (step.type != 'ride') return step;

      final match = _findRealtimeMatchForStep(step, freshRideSteps);
      if (match == null) return step;

      return step.copyWith(
        departureTime: match.departureTime,
        arrivalTime: match.arrivalTime,
        dateTime: match.dateTime,
        startStationId: match.startStationId ?? step.startStationId,
        destinationStationId:
            match.destinationStationId ?? step.destinationStationId,
        platform: match.platform ?? step.platform,
        arrivalPlatform: match.arrivalPlatform ?? step.arrivalPlatform,
        departureStopLabel: match.departureStopLabel ?? step.departureStopLabel,
        arrivalStopLabel: match.arrivalStopLabel ?? step.arrivalStopLabel,
        departureDelay: match.departureDelay,
        arrivalDelay: match.arrivalDelay,
        isCancelled: match.isCancelled,
        plannedDeparture: match.plannedDeparture ?? step.plannedDeparture,
        plannedArrival: match.plannedArrival ?? step.plannedArrival,
      );
    }).toList();

    return existing.copyWith(
      steps: mergedSteps,
      departure: fresh.departure,
      arrival: fresh.arrival,
      duration: fresh.duration,
      plannedDeparture: fresh.plannedDeparture ?? existing.plannedDeparture,
      plannedArrival: fresh.plannedArrival ?? existing.plannedArrival,
      rawSource: fresh.rawSource,
    );
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

  Future<void> _refreshActiveJourney(RouteTab route) async {
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
        final matched =
            _findStrictJourneyMatch(currentRoute.activeJourney!, newJourneys);

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

      final newResults = await TransportApi.searchJourneys(
        originStation,
        route.destination,
        nahverkehrOnly: widget.onlyNahverkehr,
        when: refDate.subtract(const Duration(minutes: 20)),
        isArrival: false,
        // We only need a compact window around the active trip to merge live updates.
        results: _activeJourneyRefreshWindowSize,
        onLoadStateChanged: (phases) =>
            _setRouteLoadPhasesForToken(refreshToken, phases),
        shouldContinue: () => !_isRouteSearchCancelled(refreshToken),
        onPartialResults: handleResults,
      );
      if (_isRouteSearchCancelled(refreshToken) || !mounted) return;

      handleResults(newResults);
      if (mounted && !_isRouteSearchCancelled(refreshToken)) {
        _showRouteRefreshToast(
          completionMessage ??
              (hasMatchedUpdate
                  ? "Route refresh finished."
                  : "Route refresh finished: no matching update found."),
        );
      }
    } catch (e) {
      if (mounted && !_isRouteSearchCancelled(refreshToken)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                AppLocalizations.of(context)!.refreshFailed(e.toString()))));
      }
    } finally {
      _disposeRouteSearch(refreshToken);
    }
  }

  Future<void> _enrichActiveJourneyPlatforms(
    String tabId,
    Journey selectedJourney,
  ) async {
    if (_journeyHasDeparturePlatformsForEveryRide(selectedJourney)) return;
    final enrichmentKey = '$tabId|${_journeyListKey(selectedJourney)}';
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
            RouteSortOption.earliestDeparture,
        onSortChanged: (sort) => _routeResultsSortSelections[route.id] = sort,
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
    if (activeJourney != null &&
        !_journeyHasDeparturePlatformsForEveryRide(activeJourney)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_enrichActiveJourneyPlatforms(route.id, activeJourney));
      });
    }
    return RefreshIndicator(
      color: _routeLoadingColor(colors),
      onRefresh: () => _refreshActiveJourney(route),
      child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          children: [
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: LayoutBuilder(builder: (context, constraints) {
                  final showBackButton =
                      route.candidates != null && route.candidates!.length > 1;
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
            for (int i = 0; i < route.steps.length; i++)
              _StepCard(
                  step: route.steps[i],
                  isFirst: i == 0,
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
                      _showAlternatives(
                          context, stationId, route.destination, time,
                          lat: lat, lng: lng, stationName: name),
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
                  showTrainNumbers: widget.showTrainNumbers)
          ]),
    );
  }
}

class _StepCard extends StatefulWidget {
  final JourneyStep step;
  final bool isFirst;
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
  }) {
    final colors = TransColors.of(context);
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
          Text(
            detail,
            maxLines: 1,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrailingTimeAndStopDetail(
    BuildContext context, {
    required String timeText,
    required TextStyle timeStyle,
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
        Text(
          timeText,
          textAlign: TextAlign.right,
          style: timeStyle,
        ),
      ],
    );
  }

  Widget _buildCollapsedStopDetailChip(
    BuildContext context, {
    required String detail,
  }) {
    return Flexible(
      child: Align(
        alignment: Alignment.centerRight,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: _buildStopDetailChip(
            context,
            detail: detail,
          ),
        ),
      ),
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

                  // Title: Bus Number -> Destination (Expanded) + Arrow (Right)
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                          child: Row(
                        children: [
                          Icon(
                            _rideModeIconForLine(step.line),
                            size: 18,
                            color: colors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(displayLine,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: colors.textPrimary)),
                          const SizedBox(width: 8),
                          Icon(Icons.arrow_right_alt,
                              size: 24, color: colors.textPrimary),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(
                            displayDest,
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: colors.textPrimary),
                            overflow: TextOverflow.visible,
                          )),
                        ],
                      )),
                      const SizedBox(width: 8),
                      // Manual Arrow on Top Line with Rotation
                      AnimatedRotation(
                          turns: _isExpanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(Icons.keyboard_arrow_down,
                              color: _isExpanded
                                  ? colors.effectiveSeed
                                  : colors.textSecondary)),
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

                      // Action Buttons + Time (Bottom Row)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Actions (Left)
                          Expanded(
                              child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(children: [
                                    _buildActionChip(
                                        context,
                                        Icons.chat_bubble_outline,
                                        AppLocalizations.of(context)!.chat,
                                        onTap: () => widget.onChat(step.line)),
                                    const SizedBox(width: 8),
                                    if (step.startStationId != null &&
                                        step.dateTime != null) ...[
                                      _buildActionChip(
                                          context,
                                          Icons.alt_route,
                                          AppLocalizations.of(context)!
                                              .altShort,
                                          onTap: () =>
                                              widget.onOpenAlternatives(
                                                  step.startStationId!,
                                                  step.dateTime!,
                                                  lat: step.startLat,
                                                  lng: step.startLng)),
                                      const SizedBox(width: 8)
                                    ],
                                    _buildActionChip(
                                        context,
                                        Icons.vibration,
                                        step.isWakeAlarmOn
                                            ? AppLocalizations.of(context)!
                                                .alarmOn
                                            : AppLocalizations.of(context)!
                                                .wakeMe,
                                        isActive: step.isWakeAlarmOn &&
                                            !_hasCustomAlarmTarget,
                                        outlined: step.isWakeAlarmOn &&
                                            _hasCustomAlarmTarget,
                                        onTap: widget.onAlarmToggle)
                                  ]))),
                          const SizedBox(width: 8),

                          // Time (Right)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (combinePlatformAndStopLabel(
                                step.platform,
                                step.departureStopLabel,
                                stationName: step.startStationName,
                                isRail: _lineLooksRailForPlatformLabel(
                                  step.line,
                                ),
                              )
                                  case final collapsedStopDetail?) ...[
                                _buildCollapsedStopDetailChip(
                                  context,
                                  detail: collapsedStopDetail,
                                ),
                                const SizedBox(width: 10),
                              ],
                              Text(
                                  "${step.departureTime} - ${step.arrivalTime}",
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: step.isCancelled
                                          ? colors.textSecondary
                                          : colors.textPrimary,
                                      decoration: step.isCancelled
                                          ? TextDecoration.lineThrough
                                          : null)),
                              if (step.isCancelled)
                                Text(
                                    AppLocalizations.of(context)!.cancelledL10n,
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.red,
                                        fontSize: 12))
                              else if (step.departureDelay != null &&
                                  step.departureDelay != 0)
                                Text(
                                    " (${step.departureDelay! > 0 ? '+' : ''}${step.departureDelay})",
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: step.departureDelay! > 0
                                            ? colors.delayLate
                                            : colors.delayOnTime))
                            ],
                          )
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
                                    style: TextStyle(
                                        color: colors.textPrimary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold)),
                                trailing: _buildTrailingTimeAndStopDetail(
                                  context,
                                  timeText: step.departureTime,
                                  timeStyle: TextStyle(
                                    color: colors.delayOnTime,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
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
                              String timeStr = "--:--";
                              Color timeColor = Colors.grey;
                              DateTime? exactStopDate;

                              if (plannedDep != null) {
                                final p = DateTime.parse(plannedDep).toLocal();
                                exactStopDate = p;
                                timeStr =
                                    "${p.hour.toString().padLeft(2, '0')}:${p.minute.toString().padLeft(2, '0')}";
                                if (actualDep != null) {
                                  final a = DateTime.parse(actualDep).toLocal();
                                  final delay = a.difference(p).inMinutes;
                                  if (delay > 2) {
                                    timeStr += " (+$delay')";
                                    timeColor = colors.delayLate;
                                  } else {
                                    timeColor = colors.delayOnTime;
                                  }
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
                                          style: TextStyle(
                                              color: colors.textPrimary,
                                              fontSize: 13)),
                                      trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _buildTrailingTimeAndStopDetail(
                                              context,
                                              timeText: timeStr,
                                              timeStyle: TextStyle(
                                                color: timeColor,
                                                fontSize: 12,
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
                                style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold)),
                            trailing: Builder(builder: (context) {
                              String timeStr = step.arrivalTime;
                              Color timeColor = colors.delayOnTime;
                              if (step.arrivalDelay != null &&
                                  step.arrivalDelay! > 0) {
                                timeColor = colors.delayLate;
                                timeStr += " (+${step.arrivalDelay})";
                              }
                              return _buildTrailingTimeAndStopDetail(
                                context,
                                timeText: timeStr,
                                timeStyle: TextStyle(
                                  color: timeColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                stopDetail: combinePlatformAndStopLabel(
                                  step.arrivalPlatform,
                                  step.arrivalStopLabel,
                                  stationName: step.destinationName,
                                  isRail: _lineLooksRailForPlatformLabel(
                                    step.line,
                                  ),
                                ),
                              );
                            }),
                          )))
                ])));
  }

  Widget _buildActionChip(BuildContext context, IconData icon, String label,
      {bool isActive = false,
      bool outlined = false,
      required VoidCallback onTap}) {
    final colors = TransColors.of(context);
    return GestureDetector(
        onTap: onTap,
        child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
                color: isActive ? colors.chipActiveBg : colors.chipBg,
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
            ])));
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
  final Function(Map<String, dynamic> journeyData, DateTime depTime) onSelected;

  const _AlternativesSheet({
    required this.from,
    required this.to,
    required this.initialTime,
    required this.nahverkehrOnly,
    required this.onSelected,
  });

  @override
  State<_AlternativesSheet> createState() => _AlternativesSheetState();
}

class _AlternativesSheetState extends State<_AlternativesSheet> {
  final List<Map<String, dynamic>> _results = [];
  bool _isLoading = true;
  bool _isMoreLoading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _fetchInitial();
  }

  Future<void> _fetchInitial() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      void processResults(List<Map<String, dynamic>> res) {
        if (!mounted || res.isEmpty) return;
        setState(() {
          final merged = mergeAlternativeJourneys(const [], res);
          _results
            ..clear()
            ..addAll(merged);
          _isLoading = false;
          _error = null;
        });
      }

      // We want to see the "Next" connections AND exactly one before it.
      // We'll search starting from 1 hour ago first.
      List<Map<String, dynamic>> results = await TransportApi.searchJourneys(
        widget.from,
        widget.to,
        nahverkehrOnly: widget.nahverkehrOnly,
        when: widget.initialTime.subtract(const Duration(hours: 1)),
        isArrival: false,
        results: 12,
        onPartialResults: processResults,
      );

      processResults(results);

      // If no preceding found (infrequent line), try 4 hours back.
      if (results.isEmpty || !_hasPreceding(results)) {
        results = await TransportApi.searchJourneys(
          widget.from,
          widget.to,
          nahverkehrOnly: widget.nahverkehrOnly,
          when: widget.initialTime.subtract(const Duration(hours: 4)),
          isArrival: false,
          results: 15,
          onPartialResults: processResults,
        );
        processResults(results);
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

  DateTime _getDepTime(Map<String, dynamic> j) {
    return alternativeJourneyDisplayDepartureLocal(j) ?? DateTime.now();
  }

  void _loadEarlier() {
    if (_results.isEmpty) return;
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
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _results.length + 2,
              itemBuilder: (ctx, idx) {
                if (idx == 0) {
                  return TextButton.icon(
                      style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12)),
                      onPressed: _isMoreLoading ? null : _loadEarlier,
                      icon: const Icon(Icons.history, size: 18),
                      label: Text(l10n.loadEarlier));
                }
                if (idx == _results.length + 1) {
                  return TextButton.icon(
                      style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12)),
                      onPressed: _isMoreLoading ? null : _loadLater,
                      icon: const Icon(Icons.update, size: 18),
                      label: Text(l10n.loadLater));
                }

                final journey = _results[idx - 1];
                final legs =
                    (journey['legs'] as List).cast<Map<String, dynamic>>();
                if (legs.isEmpty) return const SizedBox.shrink();
                final firstRide = legs.firstWhere((l) => l['line'] != null,
                    orElse: () => legs.first);
                final line = firstRide['line'] != null
                    ? firstRide['line']['name']
                    : 'Walk/Transfer';
                final dir = firstRide['direction'] ?? 'Destination';
                final depTime = _getDepTime(journey);

                int delayMin = 0;
                if (firstRide['departureDelay'] != null) {
                  delayMin =
                      ((firstRide['departureDelay'] as num) / 60).round();
                } else if (firstRide['plannedDeparture'] != null &&
                    firstRide['departure'] != null) {
                  final planned =
                      DateTime.parse(firstRide['plannedDeparture']).toLocal();
                  final actual =
                      DateTime.parse(firstRide['departure']).toLocal();
                  delayMin = actual.difference(planned).inMinutes;
                }

                return ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  leading: CircleAvatar(
                    backgroundColor: colors.chipBg,
                    child:
                        Icon(Icons.alt_route, color: colors.chipFg, size: 20),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                          child: Text(
                              AppLocalizations.of(context)!
                                  .toDirection(line, dir),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold))),
                      if (depTime.isBefore(widget.initialTime
                          .subtract(const Duration(minutes: 1))))
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
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
                              color: Colors.orange,
                              fontWeight: FontWeight.bold)),
                  ])),
                  onTap: () => widget.onSelected(journey, depTime),
                );
              },
            ),
          ),
        if (_isMoreLoading && _results.isNotEmpty)
          const LinearProgressIndicator(),
      ],
    );
  }
}
