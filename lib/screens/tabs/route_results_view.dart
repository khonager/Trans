import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:trans/config/app_theme.dart';
import 'package:trans/models/journey.dart';
import 'package:trans/models/station.dart';
import 'package:trans/services/supabase_service.dart';
import 'package:trans/utils/app_error.dart';
import 'package:trans/utils/format_utils.dart';
import 'package:trans/widgets/route_share_ticket.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../l10n/app_localizations.dart';

enum RouteSortOption {
  earliestDeparture,
  earliestArrival,
  shortestDuration,
  leastTransfers,
  shortestWait,
  leastWalking,
}

const double _routeResultsBottomInset = 320;

final RegExp _summaryEmbeddedPlatformParenthesesPattern = RegExp(
  r'\s*\((?:pl\.|gl\.|gleis|gleise|steig|bahnsteig|bussteig|bussteige|bstg\.?|platz)\s+[^)]+\)',
  caseSensitive: false,
);

String _stripSummaryPlatformText(String value) {
  return value
      .replaceAll(_summaryEmbeddedPlatformParenthesesPattern, '')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();
}

bool _shouldDisplaySummaryTripId(String? tripId) {
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

bool _summaryLineLooksRail(String line) {
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

IconData _summaryRideModeIcon(String line) {
  return _summaryLineLooksRail(line)
      ? Icons.train_outlined
      : Icons.directions_bus_filled_rounded;
}

class RouteResultsView extends StatefulWidget {
  final List<Journey> candidates;
  final Function(Journey) onSelect;
  final VoidCallback onBack;
  final Future<void> Function()? onLoadEarlier;
  final Future<void> Function()? onLoadLater;
  final Future<void> Function()? onRefresh;
  final Station? origin;
  final Station destination;
  final bool showTrainNumbers;
  final Color? loadingIndicatorColor;
  final bool isBackgroundLoading;
  final RouteSortOption initialSort;
  final ValueChanged<RouteSortOption>? onSortChanged;
  final ValueChanged<RouteSortOption>? onSortLongPressed;
  final ScrollController? scrollController;

  const RouteResultsView({
    super.key,
    required this.candidates,
    required this.onSelect,
    required this.onBack,
    this.onLoadEarlier,
    this.onLoadLater,
    this.onRefresh,
    this.origin,
    required this.destination,
    this.showTrainNumbers = false,
    this.loadingIndicatorColor,
    this.isBackgroundLoading = false,
    this.initialSort = RouteSortOption.earliestDeparture,
    this.onSortChanged,
    this.onSortLongPressed,
    this.scrollController,
  });

  @override
  State<RouteResultsView> createState() => _RouteResultsViewState();
}

class _RouteResultsViewState extends State<RouteResultsView> {
  late RouteSortOption _currentSort;
  late List<Journey> _sortedCandidates;
  bool _isLoadingMoreEarlier = false;
  bool _isLoadingMoreLater = false;

  // Ticket Generation
  final GlobalKey _ticketKey = GlobalKey();
  Journey? _ticketJourney;
  String _userName = "Anon";

  @override
  void initState() {
    super.initState();
    _currentSort = widget.initialSort;
    _sortCandidates();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    final profile = await SupabaseService.getCurrentProfile();
    if (profile != null && profile['username'] != null) {
      if (mounted) {
        setState(() {
          _userName = profile['username'];
        });
      }
    } else {
      // Fallback to metadata if profile fetch fails but user exists
      final user = SupabaseService.currentUser;
      if (user != null && user.userMetadata?['username'] != null) {
        if (mounted) {
          setState(() {
            _userName = user.userMetadata!['username'];
          });
        }
      }
    }
  }

  @override
  void didUpdateWidget(RouteResultsView oldWidget) {
    final previousSortedCandidates = List<Journey>.from(_sortedCandidates);
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSort != widget.initialSort) {
      _currentSort = widget.initialSort;
    }
    _sortCandidates();
    _preserveScrollAfterPrepend(
      previousSortedCandidates,
      _sortedCandidates,
    );
  }

  void _sortCandidates() {
    _sortedCandidates = List.from(widget.candidates);
    switch (_currentSort) {
      case RouteSortOption.earliestDeparture:
        _sortedCandidates.sort((a, b) => a.departure.compareTo(b.departure));
        break;
      case RouteSortOption.earliestArrival:
        _sortedCandidates.sort((a, b) => a.arrival.compareTo(b.arrival));
        break;
      case RouteSortOption.shortestDuration:
        _sortedCandidates.sort((a, b) => a.duration.compareTo(b.duration));
        break;
      case RouteSortOption.leastTransfers:
        _sortedCandidates
            .sort((a, b) => a.transferCount.compareTo(b.transferCount));
        break;
      case RouteSortOption.shortestWait:
        _sortedCandidates
            .sort((a, b) => a.totalWaitTime.compareTo(b.totalWaitTime));
        break;
      case RouteSortOption.leastWalking:
        _sortedCandidates.sort(
            (a, b) => a.totalWalkingDuration.compareTo(b.totalWalkingDuration));
        break;
    }
  }

  void _onSortChanged(RouteSortOption option) {
    setState(() {
      _currentSort = option;
      _sortCandidates();
    });
    widget.onSortChanged?.call(option);
  }

  String _scrollIdentityFor(Journey journey) {
    final departure = journey.plannedDeparture ?? journey.departure;
    final arrival = journey.plannedArrival ?? journey.arrival;
    var firstRideLine = '';
    var firstRideTripId = '';
    for (final step in journey.steps) {
      if (step.type != 'ride') continue;
      firstRideLine = step.line;
      firstRideTripId = step.tripId ?? '';
      break;
    }
    return '${departure.millisecondsSinceEpoch}|'
        '${arrival.millisecondsSinceEpoch}|'
        '$firstRideLine|'
        '$firstRideTripId';
  }

  void _preserveScrollAfterPrepend(
    List<Journey> oldCandidates,
    List<Journey> newCandidates,
  ) {
    final controller = widget.scrollController;
    if (controller == null ||
        !controller.hasClients ||
        oldCandidates.isEmpty ||
        newCandidates.length <= oldCandidates.length) {
      return;
    }

    final oldFirstKey = _scrollIdentityFor(oldCandidates.first);
    final oldFirstNewIndex = newCandidates.indexWhere(
      (journey) => _scrollIdentityFor(journey) == oldFirstKey,
    );
    if (oldFirstNewIndex <= 0) return;

    final offsetBefore = controller.offset;
    final maxScrollExtentBefore = controller.position.maxScrollExtent;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients) return;
      final addedExtent =
          controller.position.maxScrollExtent - maxScrollExtentBefore;
      if (addedExtent <= 0.5) return;
      final targetOffset = (offsetBefore + addedExtent).clamp(
        controller.position.minScrollExtent,
        controller.position.maxScrollExtent,
      );
      controller.jumpTo(targetOffset.toDouble());
    });
  }

  Future<void> _handleLoadEarlier() async {
    if (_isLoadingMoreEarlier) return;
    setState(() => _isLoadingMoreEarlier = true);
    await widget.onLoadEarlier?.call();
    if (mounted) setState(() => _isLoadingMoreEarlier = false);
  }

  Future<void> _handleLoadLater() async {
    if (_isLoadingMoreLater) return;
    setState(() => _isLoadingMoreLater = true);
    await widget.onLoadLater?.call();
    if (mounted) setState(() => _isLoadingMoreLater = false);
  }

  DateTime get _externalSearchTime {
    if (_sortedCandidates.isEmpty) return DateTime.now();
    return _sortedCandidates
        .map((journey) => journey.plannedDeparture ?? journey.departure)
        .reduce((a, b) => a.isBefore(b) ? a : b);
  }

  Future<void> _openExternalPlanner(Uri uri, String label) async {
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $label.')),
      );
    }
  }

  Future<void> _handleCopyJourney(Journey journey) async {
    setState(() => _ticketJourney = journey);

    // Ensure logo is loaded
    if (mounted) {
      await precacheImage(
          const AssetImage('lib/assets/logo_light.png'), context);
    }

    // Allow frame to build so RepaintBoundary can paint the new journey
    await Future.delayed(const Duration(milliseconds: 200));

    try {
      final boundary = _ticketKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        debugPrint("Boundary not found");
        return;
      }

      // Capture image
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        final item = DataWriterItem();
        item.add(Formats.png(byteData.buffer.asUint8List()));
        await SystemClipboard.instance?.write([item]);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.routeTicketCopied),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e, st) {
      if (mounted) {
        AppError.showSnackBar(
          context,
          error: e,
          stackTrace: st,
          source: 'copy route ticket',
          fallback: AppLocalizations.of(context)!.serviceBusyPleaseTryAgain,
        );
      }
    } finally {
      if (mounted) setState(() => _ticketJourney = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    return Stack(
      children: [
        Column(
          children: [
            // Header with Back button and Title
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    color: colors.textPrimary,
                    onPressed: widget.onBack,
                  ),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!
                          .routesFound(widget.candidates.length.toString()),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Sorting Options
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _SortChip(
                    label: AppLocalizations.of(context)!.earliestDep,
                    icon: Icons.schedule,
                    isSelected:
                        _currentSort == RouteSortOption.earliestDeparture,
                    onTap: () =>
                        _onSortChanged(RouteSortOption.earliestDeparture),
                    onLongPress: () => widget.onSortLongPressed?.call(
                      RouteSortOption.earliestDeparture,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _SortChip(
                    label: AppLocalizations.of(context)!.earliestArr,
                    icon: Icons.timer_off,
                    isSelected: _currentSort == RouteSortOption.earliestArrival,
                    onTap: () =>
                        _onSortChanged(RouteSortOption.earliestArrival),
                    onLongPress: () => widget.onSortLongPressed?.call(
                      RouteSortOption.earliestArrival,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _SortChip(
                    label: AppLocalizations.of(context)!.fastest,
                    icon: Icons.flash_on,
                    isSelected:
                        _currentSort == RouteSortOption.shortestDuration,
                    onTap: () =>
                        _onSortChanged(RouteSortOption.shortestDuration),
                    onLongPress: () => widget.onSortLongPressed?.call(
                      RouteSortOption.shortestDuration,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _SortChip(
                    label: AppLocalizations.of(context)!.leastTransfers,
                    icon: Icons.directions_walk,
                    isSelected: _currentSort == RouteSortOption.leastTransfers,
                    onTap: () => _onSortChanged(RouteSortOption.leastTransfers),
                    onLongPress: () => widget.onSortLongPressed?.call(
                      RouteSortOption.leastTransfers,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _SortChip(
                    label: AppLocalizations.of(context)!.leastWait,
                    icon: Icons.hourglass_empty,
                    isSelected: _currentSort == RouteSortOption.shortestWait,
                    onTap: () => _onSortChanged(RouteSortOption.shortestWait),
                    onLongPress: () => widget.onSortLongPressed?.call(
                      RouteSortOption.shortestWait,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _SortChip(
                    label: AppLocalizations.of(context)!.leastWalking,
                    icon: Icons.directions_walk,
                    isSelected: _currentSort == RouteSortOption.leastWalking,
                    onTap: () => _onSortChanged(RouteSortOption.leastWalking),
                    onLongPress: () => widget.onSortLongPressed?.call(
                      RouteSortOption.leastWalking,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.isBackgroundLoading &&
                !_isLoadingMoreEarlier &&
                !_isLoadingMoreLater)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: widget.loadingIndicatorColor,
                  ),
                ),
              ),

            // List of Routes
            Expanded(
              child: RefreshIndicator(
                color: widget.loadingIndicatorColor,
                onRefresh: widget.onRefresh ?? () async {},
                child: ListView.builder(
                  key: PageStorageKey<String>(
                    'route-results-list-${widget.destination.id}',
                  ),
                  controller: widget.scrollController,
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    _routeResultsBottomInset +
                        MediaQuery.paddingOf(context).bottom,
                  ),
                  // Items: "Load Earlier" button + routes + "Load Later" button
                  itemCount: _sortedCandidates.length + 3,
                  itemBuilder: (ctx, idx) {
                    if (idx == 0) {
                      // Load Earlier Button
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: _isLoadingMoreEarlier
                              ? SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: widget.loadingIndicatorColor,
                                  ))
                              : _LoadTrigger(
                                  label:
                                      AppLocalizations.of(context)!.loadEarlier,
                                  icon: Icons.keyboard_arrow_up,
                                  onTap: _handleLoadEarlier,
                                ),
                        ),
                      );
                    }

                    if (idx == _sortedCandidates.length + 1) {
                      // Load Later Button
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: _isLoadingMoreLater
                              ? SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: widget.loadingIndicatorColor,
                                  ))
                              : _LoadTrigger(
                                  label:
                                      AppLocalizations.of(context)!.loadLater,
                                  icon: Icons.keyboard_arrow_down,
                                  onTap: _handleLoadLater,
                                ),
                        ),
                      );
                    }

                    if (idx == _sortedCandidates.length + 2) {
                      final origin = widget.origin;
                      if (origin == null) return const SizedBox.shrink();
                      return _ExternalPlannerActions(
                        origin: origin,
                        destination: widget.destination,
                        when: _externalSearchTime,
                        onOpen: _openExternalPlanner,
                      );
                    }

                    final journey = _sortedCandidates[idx - 1];
                    return _JourneyCard(
                      journey: journey,
                      onTap: () => widget.onSelect(journey),
                      onCopy: () => _handleCopyJourney(journey),
                      showTrainNumbers: widget.showTrainNumbers,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
        // Hidden Ticket Widget for Generation
        Positioned(
          left: -2000,
          top: -2000,
          child: IgnorePointer(
            ignoring: true,
            child: ExcludeSemantics(
              child: UnconstrainedBox(
                alignment: Alignment.topLeft,
                child: RepaintBoundary(
                  key: _ticketKey,
                  child: _ticketJourney != null
                      ? RouteShareTicket(
                          journey: _ticketJourney!,
                          username: _userName,
                          showTrainNumbers: widget.showTrainNumbers,
                        )
                      : const SizedBox(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ExternalPlannerActions extends StatelessWidget {
  final Station origin;
  final Station destination;
  final DateTime when;
  final Future<void> Function(Uri uri, String label) onOpen;

  const _ExternalPlannerActions({
    required this.origin,
    required this.destination,
    required this.when,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        children: [
          Text(
            'Search this connection in',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              _PlannerButton(
                label: 'DB',
                icon: Icons.train,
                onTap: () => onOpen(_buildDbUri(), 'DB'),
              ),
              _PlannerButton(
                label: 'RMV',
                icon: Icons.directions_bus,
                onTap: () => onOpen(_buildRmvUri(), 'RMV'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Uri _buildDbUri() {
    final hashParameters = {
      'sts': 'true',
      'so': _placeName(origin),
      'zo': _placeName(destination),
      'kl': '2',
      'r': '13:16:KLASSENLOS:1',
      if (_dbLocationId(origin) case final originId?) 'soid': originId,
      if (_dbLocationId(destination) case final destinationId?)
        'zoid': destinationId,
      'sot': origin.type == 'address' ? 'ADR' : 'ST',
      'zot': destination.type == 'address' ? 'ADR' : 'ST',
      if (_numericStationId(origin) case final originEva?) 'soei': originEva,
      if (_numericStationId(destination) case final destinationEva?)
        'zoei': destinationEva,
      'hd': when.toIso8601String(),
      'hza': 'D',
      'ar': 'false',
      's': 'true',
      'd': 'false',
      'hz': '[]',
      'fm': 'false',
      'bp': 'false',
    };
    return Uri.https('www.bahn.de', '/buchung/fahrplan/suche')
        .replace(fragment: Uri(queryParameters: hashParameters).query);
  }

  Uri _buildRmvUri() {
    return Uri.https(
      'www.rmv.de',
      '/c/en/timetables/search-for-route-tips/trip-planner',
      {
        'REQ0JourneyStopsS0A': _hafasLocationType(origin),
        'REQ0JourneyStopsSID': _hafasLocationId(origin),
        'REQ0JourneyStopsS0G': _placeName(origin),
        'REQ0JourneyStopsZ0A': _hafasLocationType(destination),
        'REQ0JourneyStopsZID': _hafasLocationId(destination),
        'REQ0JourneyStopsZ0G': _placeName(destination),
        'REQ0JourneyDate': DateFormat('dd.MM.yy').format(when),
        'REQ0JourneyTime': DateFormat('HH:mm').format(when),
        'REQ0HafasSearchForw': '1',
        'context': 'TP',
        'date': DateFormat('dd.MM.yy').format(when),
        'language': 'de_DE',
        'start': '1',
        'time': DateFormat('HH:mm').format(when),
        'timeSel': '1',
      },
    );
  }

  String _placeName(Station station) {
    final city = station.city?.trim();
    final name = station.name.trim();
    if (city == null || city.isEmpty || name.contains(city)) return name;
    return '$city, $name';
  }

  String _hafasLocationType(Station station) {
    if (station.type == 'address') return '2';
    if (station.type == 'location') return '4';
    return '1';
  }

  String _hafasLocationId(Station station) {
    final parts = <String>[
      'A=${_hafasLocationType(station)}',
      'O=${_placeName(station)}',
    ];
    final lng = station.longitude;
    final lat = station.latitude;
    if (lng != null && lat != null) {
      parts.add('X=${(lng * 1000000).round()}');
      parts.add('Y=${(lat * 1000000).round()}');
    }
    return '${parts.join('@')}@';
  }

  String? _dbLocationId(Station station) {
    final lat = station.latitude;
    final lng = station.longitude;
    if (lat == null || lng == null) return null;

    final parts = <String>[
      'A=${_hafasLocationType(station)}',
      'O=${_placeName(station)}',
      'X=${(lng * 1000000).round()}',
      'Y=${(lat * 1000000).round()}',
      'U=80',
      if (_numericStationId(station) case final eva?) 'L=$eva',
      'B=1',
    ];
    return '${parts.join('@')}@';
  }

  String? _numericStationId(Station station) {
    final trimmed = station.id.trim();
    return RegExp(r'^\d+$').hasMatch(trimmed) ? trimmed : null;
  }
}

class _PlannerButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _PlannerButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.textPrimary,
        side: BorderSide(color: colors.textSecondary.withValues(alpha: 0.35)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}

class _LoadTrigger extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _LoadTrigger({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: colors.cardBg
              .withValues(alpha: 0.5), // Semi-transparent glass effect
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: colors.textSecondary),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _SortChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? colors.navBarSelected : colors.chipBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.transparent : Colors.white10,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : colors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : colors.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JourneyCard extends StatelessWidget {
  final Journey journey;
  final VoidCallback onTap;
  final VoidCallback onCopy;
  final bool showTrainNumbers;

  const _JourneyCard({
    required this.journey,
    required this.onTap,
    required this.onCopy,
    this.showTrainNumbers = false,
  });

  Widget _buildRideChip(
    BuildContext context, {
    required IconData icon,
    required String label,
  }) {
    final colors = TransColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.textSecondary),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    final depStr = DateFormat('HH:mm').format(journey.departure);
    final arrStr = DateFormat('HH:mm').format(journey.arrival);
    final durStr = FormatUtils.formatDuration(journey.duration.inMinutes);
    final hasWalkingSummary = journey.totalWalkingDuration.inMinutes > 0;
    final hasBikingSummary = journey.totalBikingDuration.inMinutes > 0;
    final walkStr =
        FormatUtils.formatDuration(journey.totalWalkingDuration.inMinutes);
    final bikeStr =
        FormatUtils.formatDuration(journey.totalBikingDuration.inMinutes);
    final isSynthetic = journey.source == 'motis_synthetic';
    final badgeLabel = isSynthetic
        ? 'TRANS/SYN'
        : (journey.source == 'motis' ? 'TRANS' : 'DB');
    final badgeColor = isSynthetic
        ? Colors.green
        : (journey.source == 'motis' ? Colors.blue : Colors.red);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (journey.isCancelled) ...[
                          Text(
                            "$depStr - $arrStr",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: colors.textSecondary,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 8.0),
                            child: Text(
                              AppLocalizations.of(context)!.cancelled,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        ] else
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: depStr,
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: colors.textPrimary),
                                ),
                                if (journey.departureDelay != 0)
                                  TextSpan(
                                    text:
                                        " ${journey.departureDelay > 0 ? '+' : ''}${journey.departureDelay}",
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: journey.departureDelay > 0
                                          ? Colors.red
                                          : Colors.green,
                                    ),
                                  ),
                                TextSpan(
                                  text: " - ",
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: colors.textPrimary),
                                ),
                                TextSpan(
                                  text: arrStr,
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: colors.textPrimary),
                                ),
                                if (journey.arrivalDelay != 0)
                                  TextSpan(
                                    text:
                                        " ${journey.arrivalDelay > 0 ? '+' : ''}${journey.arrivalDelay}",
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: journey.arrivalDelay > 0
                                          ? Colors.red
                                          : Colors.green,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          durStr,
                          style: const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        if (hasWalkingSummary) ...[
                          const SizedBox(width: 10),
                          Container(
                            width: 1,
                            height: 14,
                            color: Colors.white24,
                          ),
                          const SizedBox(width: 10),
                          Icon(
                            Icons.directions_walk,
                            size: 14,
                            color: colors.stepTransferText,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            walkStr,
                            style: TextStyle(
                              color: colors.stepTransferText,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                        if (hasBikingSummary) ...[
                          const SizedBox(width: 10),
                          Container(
                            width: 1,
                            height: 14,
                            color: Colors.white24,
                          ),
                          const SizedBox(width: 10),
                          Icon(
                            Icons.pedal_bike,
                            size: 14,
                            color: colors.stepTransferText,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            bikeStr,
                            style: TextStyle(
                              color: colors.stepTransferText,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      AppLocalizations.of(context)!
                          .transfersCount(journey.transferCount.toString()),
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Source badge
                    Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4)),
                        child: Text(badgeLabel,
                            style: TextStyle(
                                color: badgeColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold))),
                    const SizedBox(height: 8),
                    // Copy Button
                    InkWell(
                      onTap: onCopy,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: colors.cardBg.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Icon(Icons.copy,
                            size: 14, color: colors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Line Summary (first 3 lines)
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                alignment: WrapAlignment.start,
                spacing: 6,
                runSpacing: 6,
                children: journey.steps
                    .where((s) => s.type == 'ride')
                    .take(4)
                    .map((step) {
                  String displayLine = step.line.trim();
                  final displayableTripId =
                      _shouldDisplaySummaryTripId(step.tripId)
                          ? step.tripId!.trim()
                          : null;
                  // Clean train numbers if disabled
                  if (!showTrainNumbers) {
                    final regexParens = RegExp(r'\s*\(\d+\)$');
                    displayLine =
                        displayLine.replaceAll(regexParens, '').trim();
                    if (step.tripId != null) {
                      displayLine =
                          displayLine.replaceAll(step.tripId!, "").trim();
                    }
                  } else {
                    // Ensure it's there if enabled
                    if (displayableTripId != null &&
                        !displayLine.contains(displayableTripId)) {
                      displayLine += " ($displayableTripId)";
                    }
                  }
                  displayLine = _stripSummaryPlatformText(displayLine);
                  return _buildRideChip(
                    context,
                    icon: _summaryRideModeIcon(step.line),
                    label: displayLine,
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
