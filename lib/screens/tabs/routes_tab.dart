import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vibration/vibration.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:trans/models/station.dart';
import 'package:trans/models/journey.dart';
import 'package:trans/models/favorite.dart';
import 'package:trans/services/transport_api.dart';
import 'package:trans/services/supabase_service.dart';
import 'package:trans/services/history_manager.dart';
import 'package:trans/services/favorites_manager.dart';
import 'package:trans/services/notification_manager.dart';
import 'package:trans/widgets/chat_sheet.dart';
import 'package:trans/config/app_theme.dart';
import 'package:trans/utils/format_utils.dart';
import '../../l10n/app_localizations.dart';
import '../map_screen.dart';
import 'route_results_view.dart';

const List<IconData> kAvailableIcons = [
  Icons.star,
  Icons.home,
  Icons.work,
  Icons.favorite,
  Icons.train,
  Icons.directions_bus,
  Icons.school,
  Icons.person,
  Icons.location_on,
  Icons.shopping_cart,
  Icons.fitness_center,
  Icons.local_cafe,
  Icons.local_airport
];

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

  Station? _fromStation;
  Station? _toStation;

  List<dynamic> _suggestions = [];
  String _activeSearchField = '';
  Timer? _debounce;
  Timer? _focusDebounce; // Delayed focus handling for Web clicks
  bool _isLoadingRoute = false;
  bool _isSuggestionsLoading = false;

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  bool _isArrival = false;

  bool _isWakeAlarmSet = false;
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

  Position? get _effectiveCurrentPosition =>
      _manualCurrentPosition ?? widget.currentPosition;

  @override
  void initState() {
    super.initState();
    _fetchSuggestions(forceHistory: true);
    _loadFavorites();
    _initNotifications();
    WidgetsBinding.instance.addObserver(this);
    _fromFocusNode.addListener(_onFocusChange);
    _toFocusNode.addListener(_onFocusChange);
    _resolveCurrentAddress();
    _loadHistoryData();
  }

  Future<void> _loadHistoryData() async {
    final history = await SearchHistoryManager.getHistory();
    final frequent = await SearchHistoryManager.getFrequentJourneys();
    debugPrint(
        "Loaded history: ${history.length} items, frequent: ${frequent.length} items");
    if (mounted)
      setState(() {
        _frequentJourneys = frequent;
      });
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
              desiredAccuracy: LocationAccuracy.high)
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
    const initSettings = InitializationSettings(android: android, iOS: ios);
    await _notificationsPlugin.initialize(settings: initSettings);
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    _fromFocusNode.dispose();
    _toFocusNode.dispose();
    _scrollController.dispose();
    _debounce?.cancel();
    _focusDebounce?.cancel();
    _gpsStream?.cancel();
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

  Future<void> _loadFavorites() async {
    final favs = await FavoritesManager.getFavorites();
    if (mounted) setState(() => _favorites = favs);
  }

  // --- WAKE ALARM LOGIC ---
  void _toggleStepAlarm(RouteTab route, JourneyStep step) {
    if (route.activeJourney == null) return;

    final updatedSteps = route.activeJourney!.steps.map((s) {
      if (s == step) return s.copyWith(isWakeAlarmOn: !s.isWakeAlarmOn);
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

  void _stopWakeAlarm() {
    _gpsStream?.cancel();
    _gpsStream = null;
    SupabaseService.clearJourneyStatus();
    if (mounted) setState(() => _isWakeAlarmSet = false);
  }

  Future<void> _startWakeAlarm(RouteTab route) async {
    if (route.steps.isEmpty) return;

    // 1. Request Permissions
    await NotificationManager.requestPermissions();
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  AppLocalizations.of(context)!.locationPermissionDenied)));
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)!
                .locationPermissionPermanentlyDenied)));
      return;
    }

    final firstRide = route.steps
        .firstWhere((s) => s.type == 'ride', orElse: () => route.steps.first);

    double? targetLat = firstRide.endLat;
    double? targetLng = firstRide.endLng;

    if (targetLat == null || targetLng == null) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)!.missingDestCoords)));
      return;
    }

    if (mounted) setState(() => _isWakeAlarmSet = true);

    // 2. Configure Background Location (Foreground Service)
    AndroidSettings androidSettings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 50,
      forceLocationManager: true,
      intervalDuration: const Duration(seconds: 10),
      // Foreground Notification to keep service alive
      foregroundNotificationConfig: ForegroundNotificationConfig(
        notificationTitle: AppLocalizations.of(context)!.wakeAlarmTitle,
        notificationText: AppLocalizations.of(context)!.wakeAlarmTracking,
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
    if (defaultTargetPlatform == TargetPlatform.android)
      activeSettings = androidSettings;
    if (defaultTargetPlatform == TargetPlatform.iOS)
      activeSettings = appleSettings;

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

        if (step.stopovers != null && step.stopovers!.isNotEmpty) {
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

          // Turn off alarm for THIS step
          int stepIdx = remainingSteps.indexOf(step);
          if (stepIdx != -1) {
            remainingSteps[stepIdx] = step.copyWith(isWakeAlarmOn: false);
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(AppLocalizations.of(context)!
                    .wakeUpApproaching(step.destinationName ?? 'your stop')),
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
  Future<void> _fetchSuggestions({bool forceHistory = false}) async {
    if (forceHistory) {
      final history = await SearchHistoryManager.getHistory();
      if (mounted) setState(() => _suggestions = history);
      return;
    }
    setState(() => _isSuggestionsLoading = true);
    List<dynamic> results = [];
    final query = _activeSearchField == 'from'
        ? _fromController.text
        : _toController.text;
    if (query.isNotEmpty) {
      final matchingFavs = _favorites
          .where((f) => f.label.toLowerCase().contains(query.toLowerCase()))
          .toList();
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
    if (mounted)
      setState(() {
        _suggestions = results;
        _isSuggestionsLoading = false;
      });
  }

  void _onSearchChanged(String query, String field) {
    setState(() => _activeSearchField = field);
    _fetchSuggestions();
    if (query.isEmpty) {
      if (field == 'from') {
        setState(() {
          _fromStation = null;
          _fromUsesCurrentLocation = true;
          _suggestions = [];
          _isSuggestionsLoading = false;
        });
        return;
      } else if (field == 'to') {
        setState(() {
          _toStation = null;
          _suggestions = [];
          _isSuggestionsLoading = false;
        });
        return;
      }
      return;
    }
    if (field == 'from') {
      setState(() {
        _fromStation = null;
        _fromUsesCurrentLocation = _isCurrentLocationText(query);
      });
    }
    setState(() => _isSuggestionsLoading = true);
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      if (query.length > 2) {
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
          final apiResults = await TransportApi.searchStations(query,
              lat: refLat, lng: refLng);
          if (mounted) {
            setState(() {
              if (apiResults.isEmpty && _suggestions.isEmpty) {
                // Show message if no results at all
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content:
                        Text(AppLocalizations.of(context)!.serviceBusyTryAgain),
                    duration: const Duration(seconds: 2)));
              }
              for (var s in apiResults) {
                bool exists = _suggestions.any((existing) {
                  if (existing is Station) return existing.id == s.id;
                  if (existing is Favorite) return existing.station?.id == s.id;
                  return false;
                });
                if (!exists) _suggestions.add(s);
              }

              // Sort suggestions. First by whether it matches the query (already handled by API returning good matches),
              // then by distance if the names are identical.
              _suggestions.sort((a, b) {
                if (a is Station && b is Station) {
                  if (a.name == b.name &&
                      refLat != null &&
                      refLng != null &&
                      a.latitude != null &&
                      a.longitude != null &&
                      b.latitude != null &&
                      b.longitude != null) {
                    double distA = Geolocator.distanceBetween(
                        refLat, refLng, a.latitude!, a.longitude!);
                    double distB = Geolocator.distanceBetween(
                        refLat, refLng, b.latitude!, b.longitude!);
                    return distA.compareTo(distB);
                  }
                }
                return 0; // Keep original order otherwise
              });

              _isSuggestionsLoading = false;
            });
          }
        } catch (e) {
          if (mounted) {
            setState(() => _isSuggestionsLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(
                    AppLocalizations.of(context)!.serviceBusyPleaseTryAgain),
                duration: const Duration(seconds: 2)));
          }
        }
      } else {
        if (mounted) setState(() => _isSuggestionsLoading = false);
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
    // Capture the active field BEFORE async operations or state clearing
    final currentField = _activeSearchField;

    setState(() {
      _suggestions = [];
      _activeSearchField = '';
    });
    FocusScope.of(context).unfocus();
    Station? target;
    if (fav.type == 'station') {
      target = fav.station;
      if (target == null) {
        _showEditFavoriteDialog(fav);
        return;
      }
    } else if (fav.type == 'friend' && fav.friendId != null) {
      setState(() => _isLoadingRoute = true);
      try {
        final data = await SupabaseService.client
            .from('user_locations')
            .select()
            .eq('user_id', fav.friendId!)
            .maybeSingle();
        if (data != null) {
          final stops = await TransportApi.getNearbyStops(
              data['latitude'], data['longitude']);
          if (mounted && stops.isNotEmpty) target = stops.first;
        }
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text("Error: $e")));
      } finally {
        if (mounted) setState(() => _isLoadingRoute = false);
      }
    }

    if (target != null && mounted) {
      setState(() {
        if (currentField == 'from') {
          _fromStation = target;
          _fromUsesCurrentLocation = false;
          _fromController.text = target!.name;
          if (_toStation == null) {
            _activeSearchField = 'to';
            _toFocusNode.requestFocus();
            _scrollToTop();
          }
        } else if (currentField == 'to') {
          _toStation = target;
          _toController.text = target!.name;
          // If from is empty, maybe jump there? But usually 'to' is second.
          if (_fromStation == null && _effectiveCurrentPosition == null) {
            _activeSearchField = 'from';
            _fromFocusNode.requestFocus();
          }
        } else {
          if (_fromStation != null || _effectiveCurrentPosition != null) {
            _toStation = target;
            _toController.text = target!.name;
          } else {
            _fromStation = target;
            _fromUsesCurrentLocation = false;
            _fromController.text = target!.name;
            _toFocusNode.requestFocus();
            _scrollToTop();
          }
        }
      });
    }
  }

  void _closeTab(String id) {
    setState(() {
      _tabs.removeWhere((t) => t.id == id);
      if (_activeTabId == id)
        _activeTabId = _tabs.isNotEmpty ? _tabs.last.id : null;
    });
    _stopWakeAlarm();
  }

  void _showChat(BuildContext context, String lineName) {
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
            final j = _createJourney(journey);
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

  List<JourneyStep> _processLegs(List legs) {
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

    void flushTransferBuffer(
        DateTime? nextRideDeparture,
        String? nextStationName,
        String? nextStationId,
        String? nextPlatform,
        double? nextRideStartLat,
        double? nextRideStartLng,
        {bool isFinalWalk = false}) {
      if (transferBuffer.isEmpty &&
          (lastArrival == null || nextRideDeparture == null)) return;
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

      String fmtPlat(String? p) =>
          p == null ? '' : (int.tryParse(p) != null ? 'Pl. $p' : p);

      if (isAtSameStation && !isSignificantWalk) {
        isWaitInstruction = true;
        if (lastPlatform != null &&
            nextPlat != null &&
            lastPlatform != nextPlat) {
          instruction =
              AppLocalizations.of(context)!
                  .switchPlatform(fmtPlat(lastPlatform), fmtPlat(nextPlat));
        } else if (lastPlatform != null &&
            nextPlat != null &&
            lastPlatform == nextPlat) {
          instruction =
              AppLocalizations.of(context)!.waitAt(fmtPlat(lastPlatform));
        } else if (nextPlat != null) {
          instruction = AppLocalizations.of(context)!.waitAt(fmtPlat(nextPlat));
        } else {
          instruction =
              AppLocalizations.of(context)!.waitAt(destName ?? '');
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
        type: isWaitInstruction ? 'wait' : 'walk',
        line: 'Transfer',
        instruction: instruction,
        duration: FormatUtils.formatDuration(totalGapMinutes),
        departureTime:
            "${blockStart.hour.toString().padLeft(2, '0')}:${blockStart.minute.toString().padLeft(2, '0')}",
        arrivalTime:
            "${blockEnd.hour.toString().padLeft(2, '0')}:${blockEnd.minute.toString().padLeft(2, '0')}",
        isWalking: walkMinutes > 0 || isSignificantWalk,
        startLat: startLat,
        startLng: startLng,
        endLat: endLat,
        endLng: endLng,
        path: transferBuffer.isNotEmpty
            ? transferBuffer.first['decodedPath']
            : null,
        dateTime: blockStart,
        walkDuration: Duration(minutes: walkMinutes),
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
          startStationId: leg['origin']?['id']?.toString(),
          platform: leg['origin']?['platform']
              ?.toString(), // Ensure origin platform is used here too if I missed it before?
          // Wait, leg['platform'] was used before. I should check if I changed it in previous steps.
          // In step 283 I changed the flushTransferBuffer call, but not the JourneyStep creation for 'ride'.
          // Let's verify line 865 in previous view.
          // It was: platform: leg['platform']?.toString(),
          // I should change it to leg['origin']?['platform']?.toString() AND add arrivalPlatform.
          arrivalPlatform: leg['destination']?['platform']?.toString(),
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
          tripId: leg['line']?['fahrtNr']?.toString() ??
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

  Journey _createJourney(Map<String, dynamic> journeyData) {
    if (journeyData['legs'] == null) throw Exception("No legs data");
    final List legs = journeyData['legs'];
    final List<JourneyStep> steps = _processLegs(legs);

    DateTime? dep, arr;
    DateTime? pDep, pArr;
    try {
      if (legs.isNotEmpty) {
        dep = DateTime.parse(
                legs.first['departure'] ?? legs.first['plannedDeparture'])
            .toLocal();
        arr =
            DateTime.parse(legs.last['arrival'] ?? legs.last['plannedArrival'])
                .toLocal();
        pDep = DateTime.parse(
                legs.first['plannedDeparture'] ?? legs.first['departure'])
            .toLocal();
        pArr =
            DateTime.parse(legs.last['plannedArrival'] ?? legs.last['arrival'])
                .toLocal();
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
        try {
          final parts = step.duration.split(' ');
          if (parts.isNotEmpty) waitMinutes += int.tryParse(parts[0]) ?? 0;
        } catch (e) {/* ignore */}
      }
    }

    int walkMinutes = 0;
    for (var step in steps) {
      if (step.type == 'walk') {
        try {
          final parts = step.duration.split(' ');
          if (parts.isNotEmpty) walkMinutes += int.tryParse(parts[0]) ?? 0;
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
    Station? dest;

    if (candidatesData != null) {
      for (var d in candidatesData) {
        try {
          candidates.add(_createJourney(d));
        } catch (e) {/* ignore */}
      }
      if (candidates.isNotEmpty) {
        final lastLeg = candidates.first.rawSource['legs'].last;
        dest = Station(
            id: lastLeg['destination']['id'],
            name: lastLeg['destination']['name'] ??
                AppLocalizations.of(context)!.destinationLabel,
            type: "station");
      }
    } else if (singleJourneyData != null) {
      try {
        activeJourney = _createJourney(singleJourneyData);
        candidates = [activeJourney];
        final lastLeg = singleJourneyData['legs'].last;
        dest = Station(
            id: lastLeg['destination']['id'],
            name: lastLeg['destination']['name'] ??
                AppLocalizations.of(context)!.destinationLabel,
            type: "station");
      } catch (_) {
        return id;
      }
    }

    if (dest == null) return id;

    if (_toStation != null) dest = _toStation;

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
            newJourneys.add(_createJourney(d));
          } catch (e) {/* ignore */}
        }

        // Remove duplicates and sort
        final Map<String, Journey> uniqueMap = {};
        if (currentTab.candidates != null) {
          for (var j in currentTab.candidates!) {
            final key =
                "${j.departure.millisecondsSinceEpoch}_${j.arrival.millisecondsSinceEpoch}";
            uniqueMap[key] = j;
          }
        }
        for (var j in newJourneys) {
          final key =
              "${j.departure.millisecondsSinceEpoch}_${j.arrival.millisecondsSinceEpoch}";
          if (!uniqueMap.containsKey(key)) uniqueMap[key] = j;
        }

        final updatedCandidates = uniqueMap.values.toList();
        updatedCandidates.sort((a, b) => a.departure.compareTo(b.departure));

        _tabs[idx] = currentTab.copyWith(candidates: updatedCandidates);
      }
    });
  }

  Future<void> _findRoutes() async {
    if (_isLoadingRoute) return;
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
        if (pos != null) {
          // Use GPS directly
          from = Station(
              id: 'gps',
              name: AppLocalizations.of(context)!.currentLocation,
              type: 'location',
              latitude: pos.latitude,
              longitude: pos.longitude);
        } else {
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content:
                    Text(AppLocalizations.of(context)!.locationNotAvailable)));
          return;
        }
      } else {
        setState(() => _isLoadingRoute = true);
        try {
          final results =
              await TransportApi.searchStations(_fromController.text);
          if (results.isNotEmpty) {
            from = results.first;
            _fromStation = from;
          } else {
            throw AppLocalizations.of(context)!.startNotFound;
          }
        } catch (e) {
          if (mounted) {
            setState(() => _isLoadingRoute = false);
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
        setState(() => _isLoadingRoute = true);
        try {
          final results = await TransportApi.searchStations(_toController.text);
          if (results.isNotEmpty) {
            _toStation = results.first;
          } else {
            throw AppLocalizations.of(context)!.destinationNotFound;
          }
        } catch (e) {
          if (mounted) {
            setState(() => _isLoadingRoute = false);
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
    setState(() => _isLoadingRoute = true);
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
      String? currentTabId;
      final res = await TransportApi.searchJourneys(from, _toStation!,
          nahverkehrOnly: widget.onlyNahverkehr,
          when: when,
          isArrival: _isArrival, onPartialResults: (partial) {
        if (mounted && currentTabId == null) {
          setState(() => _isLoadingRoute = false);
          currentTabId = _addJourneyTab(
              candidatesData: partial, origin: from, destination: _toStation);
        }
      }).timeout(const Duration(seconds: 20));

      if (mounted) {
        if (res.isNotEmpty) {
          if (currentTabId != null) {
            _updateTabCandidates(currentTabId!, res);
          } else {
            _addJourneyTab(
                candidatesData: res, origin: from, destination: _toStation);
          }
          SearchHistoryManager.saveJourney(from, _toStation!);
          _loadHistoryData(); // Refresh UI
        } else if (currentTabId == null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(AppLocalizations.of(context)!.noRoutesFoundBusy)));
        }
      }
    } on TimeoutException catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)!.requestTimedOut)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)!.serviceBusyMoment)));
      }
    } finally {
      if (mounted) setState(() => _isLoadingRoute = false);
    }
  }

  List<int> _getVibrationPattern(String patternName) {
    switch (patternName) {
      case 'heartbeat':
        return [0, 100, 100, 250, 600, 100, 100, 250];
      case 'tick':
        return [0, 30];
      case 'mario':
        return [0, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 200];
      case 'fox':
        return [
          0,
          100,
          100,
          100,
          100,
          100,
          100,
          100,
          150,
          100,
          150,
          100,
          150,
          100,
          400
        ];
      case 'imperial':
        return [
          0,
          450,
          150,
          450,
          150,
          450,
          150,
          350,
          100,
          150,
          450,
          150,
          350,
          100,
          150,
          450
        ];
      case 'potter':
        return [
          0,
          150,
          350,
          150,
          100,
          150,
          100,
          150,
          100,
          400,
          300,
          300,
          150,
          400
        ];
      case 'indy':
        return [0, 150, 50, 80, 50, 150, 100, 500, 400, 150, 50, 80, 100, 600];
      case 'mission':
        return [
          0,
          250,
          250,
          250,
          250,
          120,
          120,
          120,
          120,
          250,
          250,
          250,
          250,
          120,
          120,
          120,
          120
        ];
      case 'terminator':
        return [0, 250, 250, 250, 400, 200, 200, 250, 200, 250];
      case 'future':
        return [0, 150, 150, 150, 150, 300, 200, 100, 50, 100, 50, 400];
      case 'eva':
        return [
          0,
          100,
          100,
          100,
          100,
          250,
          100,
          100,
          100,
          100,
          100,
          100,
          250,
          100,
          100
        ];
      case 'pokemon':
        return [0, 100, 100, 100, 100, 300, 150, 100, 100, 300];
      case 'titan':
        return [0, 200, 150, 200, 150, 250, 250, 400, 400, 600];
      case 'bebop':
        return [0, 150, 400, 150, 400, 150, 400, 150, 600, 1000];
      default:
        return [0, 500];
    }
  }

  Future<void> _triggerVibration() async {
    if (kIsWeb) return;
    if (await Vibration.hasVibrator()) {
      final prefs = await SharedPreferences.getInstance();
      final patternName = prefs.getString('vibration_pattern') ?? 'standard';
      final intensity = prefs.getInt('vibration_intensity') ?? 128;
      final pattern = _getVibrationPattern(patternName);

      if (await Vibration.hasAmplitudeControl()) {
        final intensities = List<int>.generate(
          pattern.length,
          (i) => i.isEven ? 0 : intensity,
        );
        Vibration.vibrate(pattern: pattern, intensities: intensities);
      } else {
        Vibration.vibrate(pattern: pattern);
      }
    }
  }

  Future<void> _showNotification() async {
    final prefs = await SharedPreferences.getInstance();
    final patternName = prefs.getString('vibration_pattern') ?? 'standard';
    final pattern = _getVibrationPattern(patternName);
    // Android vibrationPattern uses Int64List in milliseconds
    final androidDetails = AndroidNotificationDetails(
      'wake_alarm_channel',
      'Wake Alarm',
      channelDescription: 'Alarms for arriving at station',
      importance: Importance.max,
      priority: Priority.high,
      enableVibration: true,
      vibrationPattern: Int64List.fromList(pattern),
    );
    final details = NotificationDetails(android: androidDetails);
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
            _toStation != null &&
            !_isLoadingRoute;
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
                  if (idx == _tabs.length)
                    return Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () =>
                                setState(() => _activeTabId = null)));
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
                        _fromStation != null, 'from',
                        hint: (_fromStation == null &&
                                _effectiveCurrentPosition != null)
                            ? AppLocalizations.of(context)!.currentLocation
                            : AppLocalizations.of(context)!.stationOrAddress),
                    if (_activeSearchField == 'from') _buildSuggestionsList(),
                    const SizedBox(height: 12),
                    _buildTextField(AppLocalizations.of(context)!.toLabel,
                        _toController, _toFocusNode, _toStation != null, 'to'),
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
                                      if (t != null)
                                        setState(() => _selectedTime = t);
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
                        child: ElevatedButton(
                            onPressed: canSearch ? _findRoutes : null,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: colors.searchBtnBg,
                                foregroundColor: colors.searchBtnText,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16))),
                            child: _isLoadingRoute
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : Text(AppLocalizations.of(context)!.findRoutes,
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold)))),
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
                              IconData icon = Icons.star;
                              if (fav.type == 'friend') {
                                icon = Icons.person;
                              } else if (fav.label.toLowerCase() == 'home') {
                                icon = Icons.home;
                              } else if (fav.label.toLowerCase() == 'work') {
                                icon = Icons.work;
                              }
                              if (fav.iconCode != null) {
                                icon = kAvailableIcons.firstWhere(
                                    (i) => i.codePoint == fav.iconCode,
                                    orElse: () => Icons.star);
                              }
                              Color bg = fav.type == 'friend'
                                  ? colors.favFriendBg
                                  : colors.favStationBg;
                              Color fg = fav.type == 'friend'
                                  ? colors.favFriendIcon
                                  : colors.favStationIcon;
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
                                                color: bg,
                                                shape: BoxShape.circle),
                                            child: Icon(icon,
                                                color: fg, size: 20)),
                                        const SizedBox(height: 4),
                                        Text(fav.label,
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: colors.favText))
                                      ]));
                            })),
                    _buildFrequentJourneys(colors),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFrequentJourneys(TransColors colors) {
    if (_frequentJourneys.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 16, left: 16, right: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(AppLocalizations.of(context)!.frequentJourneys,
                style: TextStyle(
                    color: colors.sectionHeader,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _frequentJourneys.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, idx) {
              final item = _frequentJourneys[idx];
              final from = Station.fromJson(item['from']);
              final to = Station.fromJson(item['to']);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _fromStation = from;
                    _fromUsesCurrentLocation = false;
                    _fromController.text = from.name;
                    _toStation = to;
                    _toController.text = to.name;
                  });
                  _findRoutes();
                },
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
                              color:
                                  colors.navBarSelected.withValues(alpha: 0.2),
                              shape: BoxShape.circle),
                          child: Icon(Icons.bookmark,
                              color: colors.navBarSelected, size: 18)),
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
                                AppLocalizations.of(context)!
                                    .fromStation(from.name),
                                style: TextStyle(
                                    color: colors.searchHintText,
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
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionsList() {
    if (!_isSuggestionsLoading && _suggestions.isEmpty)
      return const SizedBox.shrink();
    final colors = TransColors.of(context);
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
              if (_isSuggestionsLoading)
                const Padding(
                    padding: EdgeInsets.all(12),
                    child: LinearProgressIndicator(minHeight: 2)),
              // Removed Flexible, rely on constraints + shrinkWrap
              Flexible(
                  // Actually Flexible/Expanded is needed if content exceeds 250px inside Column??
                  // Usually inside a Column with min size, if we want it to scroll, we need constraints.
                  // We have max-height 250 on Container.
                  // If we put ListView directly in Column(min), and list is huge:
                  // ListView(shrinkWrap: true) tries to be infinite? No, it tries to be as big as content.
                  // If content > 250, Container clips? Or errors?
                  // The original code had Flexible.
                  // Let's use Flexible but inside Material?
                  // Wait, Material is around the Column now.
                  // Let's put Material inside the Container, and Column inside Material.
                  // And keep Flexible for safety with scrolling?
                  // User reported "no hover". That implies hit test failure.
                  // Often caused by "invisible" widgets blocking or weird z-index if no Material.
                  // Let's stick to the plan: Remove Flexible IF it was the cause (zero height?), OR ensure it works.
                  // Actually, ListView(shrinkWrap: true) inside Flexible inside Column(min) is tricky.
                  // Better: Container(height: constraint) -> ClipR -> Material -> ListView.
                  // But we want header (Progress) + List.
                  // Let's go with: Container -> Column -> (Progress, Flexible(ListView)).
                  // AND ensure Material is wrapping the ListView items individually or the whole list.
                  // Best practice: Material > ListView.
                  child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _suggestions.length,
                      separatorBuilder: (ctx, idx) =>
                          const Divider(height: 1, color: Colors.white10),
                      itemBuilder: (ctx, idx) {
                        final item = _suggestions[idx];
                        if (item is Favorite) {
                          return ListTile(
                            leading: const Icon(Icons.star,
                                size: 16, color: Colors.orange),
                            title: Text(item.label,
                                style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold)),
                            onTap: () => _selectItem(item),
                            hoverColor: Colors
                                .white10, // Explicit hover color if theme missing
                          );
                        }
                        final station = item as Station;
                        IconData leadingIcon = Icons.place;
                        if (station.type == 'address')
                          leadingIcon = Icons.home_work;

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

                        String? distanceText;
                        if (refLat != null &&
                            refLng != null &&
                            station.latitude != null &&
                            station.longitude != null) {
                          double distInMeters = Geolocator.distanceBetween(
                              refLat,
                              refLng,
                              station.latitude!,
                              station.longitude!);
                          double distInKm = distInMeters / 1000.0;
                          distanceText = "${distInKm.toStringAsFixed(1)} km";
                        }

                        return ListTile(
                            leading:
                                Icon(leadingIcon, size: 16, color: Colors.grey),
                            title: Text(station.name,
                                style: TextStyle(
                                    color: colors.textPrimary, fontSize: 14)),
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
                            });
                      }))
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
                    AppLocalizations.of(context)!.stationOrAddress))) {
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
    if (_isLoadingRoute) return;

    // Determine reference time
    DateTime refDate;
    bool isArrival;

    if (earlier) {
      if (route.candidates == null || route.candidates!.isEmpty) return;
      refDate = route.candidates!.first.departure
          .subtract(const Duration(minutes: 1));
      isArrival =
          true; // Find connections arriving before the first one's departure
    } else {
      if (route.candidates == null || route.candidates!.isEmpty) return;
      refDate =
          route.candidates!.last.departure.add(const Duration(minutes: 1));
      isArrival = false; // Find connections departing after the last one
    }

    setState(() => _isLoadingRoute = true);

    try {
      final Station? originStation = route.origin ?? _fromStation;
      if (originStation == null) throw Exception("Origin station lost");

      void appendResults(List<Map<String, dynamic>> partial) {
        if (partial.isEmpty || !mounted) return;
        final List<Journey> newJourneys = [];
        for (var d in partial) {
          try {
            newJourneys.add(_createJourney(d));
          } catch (e) {/* ignore */}
        }

        setState(() {
          _isLoadingRoute = false;
          final idx = _tabs.indexWhere((t) => t.id == route.id);
          if (idx != -1) {
            final currentRoute = _tabs[idx];
            final currentIds = currentRoute.candidates!
                .map((j) =>
                    "${j.departure.millisecondsSinceEpoch}_${j.arrival.millisecondsSinceEpoch}")
                .toSet();
            final uniqueNew = newJourneys
                .where((j) => !currentIds.contains(
                    "${j.departure.millisecondsSinceEpoch}_${j.arrival.millisecondsSinceEpoch}"))
                .toList();

            if (uniqueNew.isNotEmpty) {
              final updatedCandidates =
                  List<Journey>.from(currentRoute.candidates!);
              updatedCandidates.addAll(uniqueNew);
              updatedCandidates
                  .sort((a, b) => a.departure.compareTo(b.departure));
              _tabs[idx] = currentRoute.copyWith(candidates: updatedCandidates);
            }
          }
        });
      }

      final newResults = await TransportApi.searchJourneys(
        originStation,
        route.destination,
        nahverkehrOnly: widget.onlyNahverkehr,
        when: refDate,
        isArrival: isArrival,
        results: 5,
        onPartialResults: appendResults,
      );

      appendResults(newResults);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)!
                .couldNotLoadMoreRoutes(e.toString()))));
    } finally {
      if (mounted) setState(() => _isLoadingRoute = false);
    }
  }

  Future<void> _refreshRoutes(RouteTab route) async {
    if (_isLoadingRoute) return;

    // We want to reset pagination and reload the initial search window.
    setState(() => _isLoadingRoute = true);

    try {
      final Station? originStation = route.origin ?? _fromStation;
      if (originStation == null) throw Exception("Origin station lost");

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
        if (partial.isEmpty || !mounted) return;
        final List<Journey> newJourneys = [];
        for (var d in partial) {
          try {
            newJourneys.add(_createJourney(d));
          } catch (e) {/* ignore */}
        }

        setState(() {
          _isLoadingRoute = false;
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
        onPartialResults: handleResults,
      );

      handleResults(newResults);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)!
                .couldNotRefreshRoutes(e.toString()))));
    } finally {
      if (mounted) setState(() => _isLoadingRoute = false);
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
            candidate!.line.trim().toLowerCase() == step.line.trim().toLowerCase() &&
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
        platform: match.platform ?? step.platform,
        arrivalPlatform: match.arrivalPlatform ?? step.arrivalPlatform,
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

  Future<void> _refreshActiveJourney(RouteTab route) async {
    if (_isLoadingRoute || route.activeJourney == null) return;

    setState(() => _isLoadingRoute = true);

    try {
      final Station? originStation = route.origin ?? _fromStation;
      if (originStation == null) throw Exception("Origin station lost");

      // Use planned departure time as the anchor for refresh
      final DateTime refDate = route.activeJourney!.plannedDeparture ??
          route.activeJourney!.departure;

      void handleResults(List<Map<String, dynamic>> partial) {
        if (partial.isEmpty || !mounted) return;
        final idx = _tabs.indexWhere((t) => t.id == route.id);
        if (idx == -1) return;
        final currentRoute = _tabs[idx];
        if (currentRoute.activeJourney == null) return;

        final List<Journey> newJourneys = [];
        for (var d in partial) {
          try {
            newJourneys.add(_createJourney(d));
          } catch (e) {/* ignore */}
        }

        // Find the best match
        Journey? matched;

        // 1. Try Trip ID match of first ride
        final oldFirstRide = currentRoute.activeJourney!.steps.firstWhere(
            (s) => s.type == 'ride',
            orElse: () => currentRoute.activeJourney!.steps.first);
        if (oldFirstRide.tripId != null) {
          matched = newJourneys.cast<Journey?>().firstWhere(
              (j) => j!.steps.any(
                  (s) => s.type == 'ride' && s.tripId == oldFirstRide.tripId),
              orElse: () => null);
        }

        // 2. Try exact planned departure/arrival match
        matched ??= newJourneys.cast<Journey?>().firstWhere(
            (j) =>
                j!.plannedDeparture ==
                    currentRoute.activeJourney!.plannedDeparture &&
                j.plannedArrival == currentRoute.activeJourney!.plannedArrival,
            orElse: () => null);

        // 3. Fallback: closest departure time among same first ride line
        if (matched == null && newJourneys.isNotEmpty) {
          final oldJourney = currentRoute.activeJourney!;
          final oldRide = oldJourney.steps.firstWhere((s) => s.type == 'ride',
              orElse: () => oldJourney.steps.first);
          final oldLine = oldRide.line.trim().toLowerCase();

          final withSameLine = newJourneys.where((j) {
            final firstRide = j.steps.firstWhere((s) => s.type == 'ride',
                orElse: () => j.steps.first);
            return oldLine.isNotEmpty &&
                firstRide.line.trim().toLowerCase() == oldLine;
          }).toList();

          final pool = withSameLine.isNotEmpty ? withSameLine : newJourneys;
          pool.sort((a, b) {
            final da = (a.plannedDeparture ?? a.departure)
                .difference(oldJourney.plannedDeparture ?? oldJourney.departure)
                .inSeconds
                .abs();
            final db = (b.plannedDeparture ?? b.departure)
                .difference(oldJourney.plannedDeparture ?? oldJourney.departure)
                .inSeconds
                .abs();
            return da.compareTo(db);
          });
          matched = pool.first;
        }

        if (matched != null) {
          final upd =
              _mergeRealtimeIntoJourney(currentRoute.activeJourney!, matched);
          setState(() {
            _isLoadingRoute = false;
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
        }
      }

      final newResults = await TransportApi.searchJourneys(
        originStation,
        route.destination,
        nahverkehrOnly: widget.onlyNahverkehr,
        when: refDate.subtract(const Duration(minutes: 20)),
        isArrival: false,
        results: 20,
        onPartialResults: handleResults,
      );

      handleResults(newResults);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                AppLocalizations.of(context)!.refreshFailed(e.toString()))));
    } finally {
      if (mounted) setState(() => _isLoadingRoute = false);
    }
  }

  Widget _buildActiveRouteView(RouteTab route) {
    if (route.activeJourney == null &&
        route.candidates != null &&
        route.candidates!.isNotEmpty) {
      return RouteResultsView(
        candidates: route.candidates!,
        onSelect: (journey) {
          setState(() {
            final idx = _tabs.indexWhere((t) => t.id == route.id);
            if (idx != -1) {
              final currentStack = List<Journey>.from(route.stack);
              if (!currentStack.contains(journey)) currentStack.add(journey);

              _tabs[idx] = route.copyWith(
                activeJourney: journey,
                stack: currentStack,
                steps: journey.steps,
                totalDuration:
                    FormatUtils.formatDuration(journey.duration.inMinutes),
              );
            }
          });
        },
        onBack: () => _closeTab(route.id),
        onLoadEarlier: () => _loadMoreRoutes(route, earlier: true),
        onLoadLater: () => _loadMoreRoutes(route, earlier: false),
        onRefresh: () => _refreshRoutes(route),
        showTrainNumbers: widget.showTrainNumbers, // Pass the setting
      );
    }

    final colors = TransColors.of(context);
    return RefreshIndicator(
      onRefresh: () => _refreshActiveJourney(route),
      child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          children: [
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (route.candidates != null &&
                          route.candidates!.length > 1)
                        IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () => setState(() {
                                  final idx =
                                      _tabs.indexWhere((t) => t.id == route.id);
                                  if (idx != -1)
                                    _tabs[idx] = route.copyWith(
                                        clearActiveJourney: true);
                                })),
                      if (route.candidates != null &&
                          route.candidates!.length > 1)
                        const SizedBox(width: 8),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(route.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: colors.textPrimary)),
                            Row(children: [
                              Text(
                                  route.activeJourney != null
                                      ? "${DateFormat('HH:mm').format(route.activeJourney!.departure)} - ${DateFormat('HH:mm').format(route.activeJourney!.arrival)}"
                                      : route.subtitle,
                                  style:
                                      TextStyle(color: colors.textSecondary)),
                              if (route.source != null) ...[
                                const SizedBox(width: 8),
                                Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                        color: route.source == 'motis'
                                            ? Colors.blue.withValues(alpha: 0.2)
                                            : Colors.red.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4)),
                                    child: Row(children: [
                                      Icon(
                                          route.source == 'motis'
                                              ? Icons.public
                                              : Icons.dns,
                                          size: 10,
                                          color: route.source == 'motis'
                                              ? Colors.blue
                                              : Colors.red),
                                      const SizedBox(width: 4),
                                      Text(
                                          route.source == 'motis'
                                              ? 'Transitous'
                                              : 'DB',
                                          style: TextStyle(
                                              color: route.source == 'motis'
                                                  ? Colors.blue
                                                  : Colors.red,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold))
                                    ]))
                              ]
                            ])
                          ])),
                      IconButton(
                          icon: const Icon(Icons.map, color: Colors.blue),
                          onPressed: () => _openMap(route)),
                      const SizedBox(width: 8),
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12)),
                          child: Row(children: [
                            const Icon(Icons.timer_outlined,
                                size: 16, color: Colors.green),
                            const SizedBox(width: 4),
                            Text(route.totalDuration,
                                style: const TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold))
                          ]))
                    ])),
            for (int i = 0; i < route.steps.length; i++)
              _StepCard(
                  step: route.steps[i],
                  isFirst: i == 0,
                  finalDestinationId: route.destination.id,
                  onOpenAlternatives: (stationId, time,
                          {double? lat, double? lng, String? name}) =>
                      _showAlternatives(
                          context, stationId, route.destination, time,
                          lat: lat, lng: lng, stationName: name),
                  onChat: (line) => _showChat(context, line),
                  onAlarmToggle: () => _toggleStepAlarm(route, route.steps[i]),
                  onMapTap: () => _openMap(route, focusStep: route.steps[i]),
                  showTrainNumbers: widget.showTrainNumbers)
          ]),
    );
  }
}

class _StepCard extends StatefulWidget {
  final JourneyStep step;
  final bool isFirst;
  final String finalDestinationId;
  final Function(String, DateTime, {double? lat, double? lng, String? name})
      onOpenAlternatives;
  final Function(String) onChat;
  final VoidCallback onAlarmToggle;
  final VoidCallback onMapTap;
  final bool showTrainNumbers;

  const _StepCard({
    required this.step,
    this.isFirst = false,
    required this.finalDestinationId,
    required this.onOpenAlternatives,
    required this.onChat,
    required this.onAlarmToggle,
    required this.onMapTap,
    required this.showTrainNumbers,
  });

  @override
  State<_StepCard> createState() => _StepCardState();
}

class _StepCardState extends State<_StepCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    final step = widget.step;
    final bool isWait = step.type == 'wait';
    final isTransfer = step.type == 'transfer' || isWait || step.type == 'walk';

    if (isTransfer) {
      Widget iconWidget =
          Icon(Icons.directions_walk, color: colors.stepTransferText);
      if (isWait) iconWidget = Icon(Icons.man, color: colors.stepTransferText);

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
                      if (step.walkDuration != null &&
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
                  final head = (step.headsign ?? '').trim();
                  // Check if destination is practically the headsign (End of Line)
                  // Use simple string containment or equality check
                  final isEnd = dest.isNotEmpty &&
                      head.isNotEmpty &&
                      (head.toLowerCase().contains(dest.toLowerCase()) ||
                          dest.toLowerCase().contains(head.toLowerCase()));
                  final displayDest =
                      isEnd ? AppLocalizations.of(context)!.endOfLine : dest;

                  // Title: Bus Number -> Destination (Expanded) + Arrow (Right)
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                          child: Row(
                        children: [
                          Builder(builder: (context) {
                            String displayLine = step.line.trim();

                            if (!widget.showTrainNumbers) {
                              final regexParens = RegExp(r'\s*\(\d+\)$');
                              displayLine = displayLine
                                  .replaceAll(regexParens, '')
                                  .trim();

                              if (step.tripId != null) {
                                displayLine = displayLine
                                    .replaceAll(step.tripId!, "")
                                    .trim();
                              }
                            }

                            String suffix = "";
                            if (widget.showTrainNumbers &&
                                step.tripId != null) {
                              if (!displayLine.contains(step.tripId!)) {
                                suffix = " (${step.tripId})";
                              }
                            }

                            return Text("$displayLine$suffix",
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: colors.textPrimary));
                          }),
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
                      Text("${step.headsign ?? ''}  •  ${step.duration}",
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
                                    _buildActionChip(context,
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
                                        isActive: step.isWakeAlarmOn,
                                        onTap: widget.onAlarmToggle)
                                  ]))),
                          const SizedBox(width: 8),

                          // Time (Right)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                  "${step.departureTime} - ${step.arrivalTime}",
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: step.isCancelled
                                          ? colors.textSecondary
                                          : colors.stepTimeText,
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
                        child: ListTile(
                            dense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 20),
                            leading: const Icon(Icons.login,
                                size: 14, color: Colors.green),
                            title: Text(
                                step.platform != null
                                    ? AppLocalizations.of(context)!
                                        .boardAtPlatform(
                                            step.startStationName ?? '',
                                            step.platform!)
                                    : AppLocalizations.of(context)!
                                        .boardAt(step.startStationName ?? ''),
                                style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold)),
                            trailing: Text(step.departureTime,
                                style: TextStyle(
                                    color: colors.stepTimeText,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)))),
                  if (step.stopovers != null && step.stopovers!.isNotEmpty)
                    Container(
                        decoration:
                            BoxDecoration(color: colors.stepStopoversBg),
                        child: ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: step.stopovers!.length,
                            itemBuilder: (ctx, idx) {
                              final stop = step.stopovers![idx];
                              final name = stop['stop']['name'];
                              final stopId = stop['stop']['id'];
                              final platform =
                                  stop['platform'] ?? stop['stop']?['platform'];
                              final String displayName = platform != null
                                  ? "$name (Pl. $platform)"
                                  : name;
                              final plannedDep = stop['plannedDeparture'] ??
                                  stop['scheduledDeparture'] ??
                                  stop['plannedArrival'] ??
                                  stop['scheduledArrival'];
                              final actualDep =
                                  stop['departure'] ?? stop['arrival'];
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
                              return ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 20),
                                  leading: const Icon(Icons.circle,
                                      size: 8, color: Colors.grey),
                                  title: Text(displayName,
                                      style: TextStyle(
                                          color: colors.textPrimary,
                                          fontSize: 13)),
                                  trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(timeStr,
                                            style: TextStyle(
                                                color: timeColor,
                                                fontSize: 12)),
                                        const SizedBox(width: 8),
                                        if (exactStopDate != null)
                                          IconButton(
                                              icon: const Icon(Icons.alt_route,
                                                  size: 16, color: Colors.blue),
                                              // FIX: Pass exact stop time and location if available
                                              onPressed: () =>
                                                  widget.onOpenAlternatives(
                                                      stopId, exactStopDate!,
                                                      lat: stop['stop']
                                                              ['location']
                                                          ?['latitude'],
                                                      lng: stop['stop']
                                                              ['location']
                                                          ?['longitude'],
                                                      name: name))
                                      ]));
                            }))
                  else
                    Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                            AppLocalizations.of(context)!.noIntermediateStops)),
                  // Always show the link to the final destination as the last item
                  Container(
                      decoration: BoxDecoration(color: colors.stepStopoversBg),
                      child: ListTile(
                        dense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 20),
                        leading:
                            const Icon(Icons.flag, size: 14, color: Colors.red),
                        title: Text(
                            step.arrivalPlatform != null
                                ? AppLocalizations.of(context)!
                                    .getOffAtPlatform(
                                        step.destinationName ?? 'Destination',
                                        step.arrivalPlatform!)
                                : AppLocalizations.of(context)!.getOffAt(
                                    step.destinationName ?? 'Destination'),
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
                          return Text(timeStr,
                              style: TextStyle(
                                  color: timeColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13));
                        }),
                      ))
                ])));
  }

  Widget _buildActionChip(BuildContext context, IconData icon, String label,
      {bool isActive = false, required VoidCallback onTap}) {
    final colors = TransColors.of(context);
    return GestureDetector(
        onTap: onTap,
        child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
                color: isActive ? colors.chipActiveBg : colors.chipBg,
                borderRadius: BorderRadius.circular(20)),
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
  late String _currentType;
  Station? _selectedStation;
  String? _selectedFriendId;
  int? _selectedIconCode;
  List<Station> _suggestions = [];
  Timer? _debounce;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: widget.favorite.label);
    _currentType = widget.favorite.type;
    _selectedStation = widget.favorite.station;
    _selectedFriendId = widget.favorite.friendId;
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
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: colors.cardBg,
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(20),
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isNew
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
              Row(children: [
                // ignore: deprecated_member_use
                Expanded(
                    child: RadioListTile<String>(
                        title: Text(AppLocalizations.of(context)!.station),
                        value: 'station',
                        groupValue: _currentType,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (val) =>
                            setState(() => _currentType = val!))),
                // ignore: deprecated_member_use
                Expanded(
                    child: RadioListTile<String>(
                        title: Text(AppLocalizations.of(context)!.friend),
                        value: 'friend',
                        groupValue: _currentType,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (val) =>
                            setState(() => _currentType = val!))),
              ]),
              const SizedBox(height: 10),
              SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                      children: kAvailableIcons.map((icon) {
                    final isSelected = _selectedIconCode == icon.codePoint;
                    return GestureDetector(
                        onTap: () =>
                            setState(() => _selectedIconCode = icon.codePoint),
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
                                color:
                                    isSelected ? Colors.white : Colors.grey)));
                  }).toList())),
              const SizedBox(height: 10),
              if (_currentType == 'station') ...[
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
                      if (_debounce?.isActive ?? false) _debounce!.cancel();
                      if (val.trim().isEmpty) {
                        if (mounted) setState(() => _suggestions = []);
                        return;
                      }
                      _debounce =
                          Timer(const Duration(milliseconds: 400), () async {
                        if (!mounted) return;
                        setState(() => _isLoading = true);
                        try {
                          final res = await TransportApi.searchStations(val)
                              .timeout(const Duration(seconds: 10));
                          if (mounted)
                            setState(() {
                              _suggestions = res;
                              _isLoading = false;
                            });
                        } catch (e) {
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
                                      if (_labelCtrl.text.isEmpty)
                                        _labelCtrl.text = s.name;
                                    });
                                  });
                            }))
                ]
              ],
              if (_currentType == 'friend') ...[
                TextField(
                    decoration: InputDecoration(
                        labelText:
                            AppLocalizations.of(context)!.searchFriendUsername),
                    onSubmitted: (val) async {
                      final res = await SupabaseService.searchUsers(val);
                      if (res.isNotEmpty && mounted) {
                        setState(() {
                          _selectedFriendId = res.first['id'];
                          if (_labelCtrl.text.isEmpty) {
                            _labelCtrl.text = res.first['username'];
                          }
                        });
                      }
                    }),
                if (_selectedFriendId != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(AppLocalizations.of(context)!.friendSelected,
                          style: const TextStyle(color: Colors.green))),
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
                            type: _currentType,
                            station: _selectedStation,
                            friendId: _selectedFriendId,
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
  String? _error;

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
          _results.clear();
          final existingIds = <String>{};
          for (final j in res) {
            final id = _getJId(j);
            if (!existingIds.contains(id)) {
              _results.add(j);
              existingIds.add(id);
            }
          }
          _results.sort((a, b) => _getDepTime(a).compareTo(_getDepTime(b)));

          // Find the "split point": the first connection at or after initialTime
          final splitIdx = _results.indexWhere((j) => _getDepTime(j).isAfter(
              widget.initialTime.subtract(const Duration(minutes: 1))));
          if (splitIdx != -1) {
            // Include one connection BEFORE the split point for context
            final int startIdx = splitIdx > 0 ? splitIdx - 1 : 0;
            final itemsToShow = _results.sublist(startIdx);
            _results.clear();
            _results.addAll(itemsToShow);
          }

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
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
    }
  }

  bool _hasPreceding(List<Map<String, dynamic>> results) {
    return results.any((j) => _getDepTime(j)
        .isBefore(widget.initialTime.subtract(const Duration(seconds: 15))));
  }

  Future<void> _fetch(DateTime time, bool isArrival,
      {bool prepend = false}) async {
    if (mounted) setState(() => _isMoreLoading = true);
    try {
      void processResults(List<Map<String, dynamic>> res) {
        if (!mounted || res.isEmpty) return;
        setState(() {
          final existingIds = _results.map(_getJId).toSet();
          final unique =
              res.where((r) => !existingIds.contains(_getJId(r))).toList();
          if (prepend) {
            _results.insertAll(0, unique);
          } else {
            _results.addAll(unique);
          }
          _results.sort((a, b) => _getDepTime(a).compareTo(_getDepTime(b)));
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
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _isLoading = false;
          _isMoreLoading = false;
        });
    }
  }

  String _getJId(Map<String, dynamic> j) {
    final dep = _getDepTime(j);
    final arr = _getArrTime(j);
    return "${dep.millisecondsSinceEpoch}_${arr.millisecondsSinceEpoch}";
  }

  DateTime _getDepTime(Map<String, dynamic> j) {
    try {
      final legs = (j['legs'] as List).cast<Map<String, dynamic>>();
      final first =
          legs.firstWhere((l) => l['line'] != null, orElse: () => legs.first);
      return DateTime.parse(first['departure'] ?? first['plannedDeparture'])
          .toLocal();
    } catch (e) {
      return DateTime.now();
    }
  }

  DateTime _getArrTime(Map<String, dynamic> j) {
    try {
      final legs = (j['legs'] as List).cast<Map<String, dynamic>>();
      final last = legs.last;
      return DateTime.parse(last['arrival'] ?? last['plannedArrival'])
          .toLocal();
    } catch (e) {
      return DateTime.now();
    }
  }

  void _loadEarlier() {
    if (_results.isEmpty) return;
    _fetch(
        _getDepTime(_results.first).subtract(const Duration(seconds: 1)), true,
        prepend: true);
  }

  void _loadLater() {
    if (_results.isEmpty) return;
    _fetch(_getDepTime(_results.last).add(const Duration(seconds: 1)), false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
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
        Text(AppLocalizations.of(context)!.alternatives,
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
                      child: Text(
                          AppLocalizations.of(context)!
                              .errorPrefix(_error ?? ""),
                          textAlign: TextAlign.center))))
        else if (_results.isEmpty)
          Expanded(
              child: Center(
                  child: Text(AppLocalizations.of(context)!.noRoutesFound)))
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
                      label: Text(AppLocalizations.of(context)!.loadEarlier));
                }
                if (idx == _results.length + 1) {
                  return TextButton.icon(
                      style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12)),
                      onPressed: _isMoreLoading ? null : _loadLater,
                      icon: const Icon(Icons.update, size: 18),
                      label: Text(AppLocalizations.of(context)!.loadLater));
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
                          text: " ${AppLocalizations.of(context)!.lateByMinutes(delayMin.toString())}",
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
