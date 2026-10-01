import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trans/l10n/app_localizations.dart';
import 'package:trans/models/journey.dart';
import 'package:trans/models/station.dart';
import 'package:trans/services/route_options_service.dart';
import 'package:trans/services/transport_api.dart';

class KnownLinesPanel extends StatefulWidget {
  final Station origin;
  final Station destination;
  final List<Journey> candidates;
  final DateTime sampleDate;
  final Future<List<String>> Function({
    required Station origin,
    required Station destination,
    required DateTime date,
  })? discoverLines;

  const KnownLinesPanel({
    super.key,
    required this.origin,
    required this.destination,
    required this.candidates,
    required this.sampleDate,
    this.discoverLines,
  });

  @override
  State<KnownLinesPanel> createState() => _KnownLinesPanelState();
}

class _KnownLinesPanelState extends State<KnownLinesPanel> {
  bool _expanded = false;
  Set<String> _known = {};
  Set<String> _discovered = {};
  bool _loadingDiscovery = false;
  String? _checkedDateKey;
  int _discoveryGeneration = 0;
  late final Future<SharedPreferences> _preferences =
      SharedPreferences.getInstance();
  Future<void> _sync = Future.value();

  String get _key => 'known_route_lines_v1:'
      '${jsonEncode([widget.origin.id, widget.destination.id])}';

  @override
  void initState() {
    super.initState();
    _syncKnownLines();
  }

  @override
  void didUpdateWidget(covariant KnownLinesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pairChanged = oldWidget.origin.id != widget.origin.id ||
        oldWidget.destination.id != widget.destination.id;
    final dateChanged = oldWidget.sampleDate.year != widget.sampleDate.year ||
        oldWidget.sampleDate.month != widget.sampleDate.month ||
        oldWidget.sampleDate.day != widget.sampleDate.day;
    if (pairChanged) {
      _known = {};
    }
    if (pairChanged || dateChanged) {
      _discovered = {};
      _loadingDiscovery = false;
      _checkedDateKey = null;
      _discoveryGeneration++;
    }
    if (oldWidget.candidates != widget.candidates || pairChanged) {
      _syncKnownLines();
    }
    if (_expanded && (pairChanged || dateChanged)) {
      _discover();
    }
  }

  void _syncKnownLines() {
    final key = _key;
    final observed = {
      ...availableFirstLines(widget.candidates),
      ..._discovered,
    };
    _sync = _sync.then((_) async {
      final prefs = await _preferences;
      final saved = prefs.getStringList(key) ?? const <String>[];
      final merged = sortLineNames({...saved, ...observed});
      if (merged.length != saved.length || !merged.toSet().containsAll(saved)) {
        await prefs.setStringList(key, merged);
      }
      if (mounted && key == _key) {
        setState(() => _known = merged.toSet());
      }
    }).catchError((Object _) {});
  }

  Future<void> _discover() async {
    final generation = _discoveryGeneration;
    final dateKey = '$_key:${widget.sampleDate.year}-'
        '${widget.sampleDate.month}-${widget.sampleDate.day}';
    if (_loadingDiscovery || _checkedDateKey == dateKey) return;
    _checkedDateKey = dateKey;
    setState(() => _loadingDiscovery = true);
    try {
      final lines = await (widget.discoverLines?.call(
            origin: widget.origin,
            destination: widget.destination,
            date: widget.sampleDate,
          ) ??
          discoverDirectFirstLines(
            origin: widget.origin,
            destination: widget.destination,
            date: widget.sampleDate,
          ));
      if (!mounted ||
          _checkedDateKey != dateKey ||
          generation != _discoveryGeneration) {
        return;
      }
      setState(() => _discovered.addAll(lines));
      _syncKnownLines();
    } catch (_) {
      // The known lines still work when a timetable provider is unavailable.
      if (mounted && generation == _discoveryGeneration) {
        _checkedDateKey = null;
      }
    } finally {
      if (mounted && generation == _discoveryGeneration) {
        setState(() => _loadingDiscovery = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final lines = sortLineNames({
      ..._known,
      ..._discovered,
      ...availableFirstLines(widget.candidates),
    });
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.directions_bus_outlined),
            title: Text(l10n.usefulLines),
            subtitle: Text(l10n.usefulLinesExplanation),
            trailing: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
            onTap: () {
              setState(() => _expanded = !_expanded);
              if (_expanded) _discover();
            },
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_loadingDiscovery) const LinearProgressIndicator(),
                  if (lines.isEmpty && !_loadingDiscovery)
                    Text(l10n.noUsefulLinesFound),
                  if (lines.isNotEmpty)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: SingleChildScrollView(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final line in lines) Chip(label: Text(line)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class OnBoardOptionsSheet extends StatefulWidget {
  final JourneyStep step;
  final Station destination;
  final DateTime currentPlanArrival;
  final bool nahverkehrOnly;
  final void Function(OnBoardOption option, Map<String, dynamic> fullRide)
      onSelected;
  final void Function(RideStop stop, Map<String, dynamic> fullRide) onStayOn;

  const OnBoardOptionsSheet({
    super.key,
    required this.step,
    required this.destination,
    required this.currentPlanArrival,
    required this.nahverkehrOnly,
    required this.onSelected,
    required this.onStayOn,
  });

  @override
  State<OnBoardOptionsSheet> createState() => _OnBoardOptionsSheetState();
}

class _OnBoardOptionsSheetState extends State<OnBoardOptionsSheet> {
  Map<String, dynamic>? _rideLeg;
  List<RideStop> _stops = [];
  int _nextStopIndex = 1;
  List<OnBoardOption> _options = [];
  bool _loadingTrip = true;
  bool _loadingOptions = false;
  int _searchToken = 0;

  @override
  void initState() {
    super.initState();
    _loadTrip();
  }

  Future<void> _loadTrip() async {
    Map<String, dynamic>? leg;
    final tripId = widget.step.tripId;
    if (tripId != null && tripId.isNotEmpty) {
      final live = await TransportApi.fetchLiveTripJourney(tripId);
      final legs = (live?['legs'] as List?)?.whereType<Map>();
      if (legs != null) {
        for (final raw in legs) {
          final candidate = Map<String, dynamic>.from(raw);
          final boarding = widget.step.startStationId;
          final trimmed = boarding == null
              ? null
              : rideLegFromBoardingStop(candidate, boarding);
          if (candidate['line'] != null && trimmed != null) {
            leg = trimmed;
            break;
          }
        }
      }
    }
    leg ??= _fallbackRideLeg();
    final stops = leg == null ? <RideStop>[] : rideStopsFromLeg(leg);
    if (!mounted) return;
    final now = DateTime.now().subtract(const Duration(minutes: 1));
    final next = stops.indexWhere((stop) => stop.arrival.isAfter(now));
    setState(() {
      _rideLeg = leg;
      _stops = stops;
      _nextStopIndex = next < 1
          ? 1
          : next >= stops.length
              ? stops.length - 1
              : next;
      _loadingTrip = false;
    });
    if (stops.length > 1) _search();
  }

  Map<String, dynamic>? _fallbackRideLeg() {
    final step = widget.step;
    if (step.startStationId == null || step.destinationStationId == null) {
      return null;
    }
    return {
      'origin': {
        'id': step.startStationId,
        'name': step.startStationName,
        'location': {'latitude': step.startLat, 'longitude': step.startLng},
      },
      'destination': {
        'id': step.destinationStationId,
        'name': step.destinationName,
        'location': {'latitude': step.endLat, 'longitude': step.endLng},
      },
      'departure': step.dateTime?.toIso8601String(),
      'arrival': step.plannedArrival?.toIso8601String(),
      'stopovers': step.stopovers ?? const [],
      'line': {'name': step.line, 'tripId': step.tripId},
    };
  }

  Future<void> _search() async {
    final token = ++_searchToken;
    setState(() {
      _options = [];
      _loadingOptions = true;
    });
    final found = await findOnBoardOptions(
      stops: _stops,
      nextStopIndex: _nextStopIndex,
      destination: widget.destination,
      currentTripId: widget.step.tripId,
      currentLine: widget.step.line,
      nahverkehrOnly: widget.nahverkehrOnly,
      shouldContinue: () => mounted && token == _searchToken,
      onProgress: (options) {
        if (mounted && token == _searchToken) {
          setState(() => _options = options);
        }
      },
    );
    if (mounted && token == _searchToken) {
      setState(() {
        _options = found;
        _loadingOptions = false;
      });
    }
  }

  String _arrivalLabel(DateTime arrival) {
    final l10n = AppLocalizations.of(context)!;
    final delta = widget.currentPlanArrival.difference(arrival).inMinutes;
    final comparison = delta > 0
        ? l10n.minutesEarlier(delta)
        : delta < 0
            ? l10n.minutesLater(-delta)
            : l10n.sameArrivalTime;
    return '${DateFormat.Hm().format(arrival)} · $comparison';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final directStop = _stops.skip(_nextStopIndex).cast<RideStop?>().firstWhere(
          (stop) => stop != null && stop.id == widget.destination.id,
          orElse: () => null,
        );
    final bestChange = _options.isEmpty ? null : _options.first;
    final bestIsDirect = directStop != null &&
        (bestChange == null || directStop.arrival.isBefore(bestChange.arrival));
    final bestArrival = bestIsDirect ? directStop.arrival : bestChange?.arrival;
    final changeRecommended = bestArrival != null &&
        bestArrival.isBefore(
          widget.currentPlanArrival.subtract(const Duration(minutes: 2)),
        );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.onThisBus, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Card(
              child: ListTile(
                leading: Icon(_loadingTrip || _loadingOptions
                    ? Icons.more_horiz
                    : changeRecommended
                        ? Icons.bolt
                        : Icons.check_circle_outline),
                title: Text(_loadingTrip || _loadingOptions
                    ? l10n.checkingOnBoardOptions
                    : changeRecommended
                        ? bestIsDirect
                            ? l10n.stayOnUntil(directStop.name)
                            : l10n.getOffAt(bestChange!.alight.name)
                        : l10n.stayWithCurrentPlan),
                subtitle: Text(_loadingTrip || _loadingOptions
                    ? l10n.onBoardCurrentPlan(
                        DateFormat.Hm().format(widget.currentPlanArrival),
                      )
                    : changeRecommended
                        ? _arrivalLabel(bestArrival)
                        : l10n.onBoardCurrentPlan(
                            DateFormat.Hm().format(widget.currentPlanArrival),
                          )),
              ),
            ),
            const SizedBox(height: 12),
            if (_loadingTrip)
              const LinearProgressIndicator()
            else if (_stops.length < 2)
              Text(l10n.onBoardStopsUnavailable)
            else ...[
              DropdownButtonFormField<int>(
                initialValue: _nextStopIndex,
                decoration: InputDecoration(labelText: l10n.nextStop),
                isExpanded: true,
                items: [
                  for (var i = 1; i < _stops.length; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text(
                        '${_stops[i].name} · ${DateFormat.Hm().format(_stops[i].arrival)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (index) {
                  if (index == null) return;
                  setState(() => _nextStopIndex = index);
                  _search();
                },
              ),
              const SizedBox(height: 12),
              if (directStop != null)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.directions_bus),
                    title: Text(l10n.stayOnUntil(directStop.name)),
                    subtitle: Text(_arrivalLabel(directStop.arrival)),
                    onTap: () => widget.onStayOn(directStop, _rideLeg!),
                  ),
                ),
              if (_loadingOptions) const LinearProgressIndicator(),
              Expanded(
                child: _options.isEmpty && !_loadingOptions
                    ? Center(child: Text(l10n.noOnBoardChangesFound))
                    : ListView.builder(
                        itemCount: _options.length,
                        itemBuilder: (context, index) {
                          final option = _options[index];
                          final firstRide =
                              (option.onwardJourney['legs'] as List)
                                  .whereType<Map>()
                                  .firstWhere(
                                    (leg) => leg['line'] != null,
                                    orElse: () => const {},
                                  );
                          final line = (firstRide['line'] as Map?)?['name'];
                          return Card(
                            child: ListTile(
                              leading: const Icon(Icons.alt_route),
                              title: Text(l10n.getOffAt(option.alight.name)),
                              subtitle: Text(
                                '${_arrivalLabel(option.arrival)}'
                                '${line == null ? '' : ' · $line'}'
                                ' · ${l10n.transfersCount(option.transfers.toString())}',
                              ),
                              onTap: () => widget.onSelected(option, _rideLeg!),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
