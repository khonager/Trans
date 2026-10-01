import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:trans/l10n/app_localizations.dart';
import 'package:trans/models/journey.dart';
import 'package:trans/models/station.dart';
import 'package:trans/services/route_options_service.dart';
import 'package:trans/services/transport_api.dart';

class DirectLinesPanel extends StatefulWidget {
  final Station origin;
  final Station destination;
  final DateTime start;

  const DirectLinesPanel({
    super.key,
    required this.origin,
    required this.destination,
    required this.start,
  });

  @override
  State<DirectLinesPanel> createState() => _DirectLinesPanelState();
}

class _DirectLinesPanelState extends State<DirectLinesPanel> {
  bool _expanded = false;
  bool _loading = false;
  Object? _error;
  List<DirectLineOption>? _lines;

  @override
  void didUpdateWidget(covariant DirectLinesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.origin.id != widget.origin.id ||
        oldWidget.destination.id != widget.destination.id ||
        oldWidget.start != widget.start) {
      _lines = null;
      _error = null;
      if (_expanded) _load();
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final lines = await findDirectLines(
        origin: widget.origin,
        destination: widget.destination,
        start: widget.start,
      );
      if (mounted) setState(() => _lines = lines);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final windowFormat = DateFormat('dd.MM HH:mm');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.directions_bus_outlined),
            title: Text(l10n.directLines),
            subtitle: Text(l10n.directLinesWindow(
              windowFormat.format(widget.start),
              windowFormat.format(widget.start.add(const Duration(hours: 2))),
            )),
            trailing: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
            onTap: () {
              setState(() => _expanded = !_expanded);
              if (_expanded && _lines == null) _load();
            },
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _loading
                  ? const LinearProgressIndicator()
                  : _error != null
                      ? TextButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: Text(l10n.retry),
                        )
                      : _lines == null || _lines!.isEmpty
                          ? Text(l10n.noDirectLinesFound)
                          : ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 180),
                              child: SingleChildScrollView(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final line in _lines!)
                                        Tooltip(
                                          message:
                                              '${line.direction} · ${DateFormat.Hm().format(line.arrival)}',
                                          child: Chip(
                                            label: Text(
                                              '${line.line}  ${DateFormat.Hm().format(line.departure)}',
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
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
