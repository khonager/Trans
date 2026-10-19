import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:trans/config/app_theme.dart';
import 'package:trans/models/journey.dart';
import 'package:trans/models/station.dart';
import 'package:trans/services/transport_api.dart';

class AppendRouteSheet extends StatefulWidget {
  final Station origin;
  final DateTime routeArrival;
  final Future<List<Journey>> Function(Station destination, DateTime when)
      search;
  final void Function(Journey journey, Station destination) onAppend;

  const AppendRouteSheet({
    super.key,
    required this.origin,
    required this.routeArrival,
    required this.search,
    required this.onAppend,
  });

  @override
  State<AppendRouteSheet> createState() => _AppendRouteSheetState();
}

class _AppendRouteSheetState extends State<AppendRouteSheet> {
  final _destinationController = TextEditingController();
  Timer? _debounce;
  Station? _destination;
  late DateTime _when = widget.routeArrival;
  List<Station> _suggestions = [];
  List<Journey> _results = [];
  bool _loadingStations = false;
  bool _loadingRoutes = false;
  bool _searched = false;
  String? _error;
  int _request = 0;
  int _stationRequest = 0;

  bool get _german => Localizations.localeOf(context).languageCode == 'de';

  void _setWhen(DateTime value) {
    ++_request;
    setState(() {
      _when = value;
      _results = [];
      _searched = false;
      _loadingRoutes = false;
      _error = null;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _destinationController.dispose();
    super.dispose();
  }

  void _destinationChanged(String value) {
    _debounce?.cancel();
    final request = ++_stationRequest;
    ++_request;
    setState(() {
      _destination = null;
      _suggestions = [];
      _results = [];
      _searched = false;
      _error = null;
      _loadingStations = value.trim().length >= 2;
      _loadingRoutes = false;
    });
    if (value.trim().length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final found = await TransportApi.searchStations(value.trim());
        if (!mounted || request != _stationRequest) return;
        setState(() {
          _suggestions = found.take(7).toList();
          _loadingStations = false;
        });
      } catch (_) {
        if (!mounted || request != _stationRequest) return;
        setState(() => _loadingStations = false);
      }
    });
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: widget.routeArrival.subtract(const Duration(days: 1)),
      lastDate: widget.routeArrival.add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
    );
    if (time == null || !mounted) return;
    _setWhen(DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ));
  }

  Future<void> _search() async {
    final destination = _destination;
    if (destination == null) return;
    final request = ++_request;
    FocusScope.of(context).unfocus();
    setState(() {
      _loadingRoutes = true;
      _searched = false;
      _error = null;
      _results = [];
    });
    try {
      final results = await widget.search(destination, _when);
      if (!mounted || request != _request) return;
      results.sort((a, b) => a.departure.compareTo(b.departure));
      setState(() {
        _results = results;
        _loadingRoutes = false;
        _searched = true;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _loadingRoutes = false;
        _error = _german
            ? 'Routen konnten nicht geladen werden.'
            : 'Could not load routes.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    final formatter = DateFormat('EEE d MMM, HH:mm');
    return SafeArea(
      top: false,
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.textSecondary,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
              child: Row(children: [
                Expanded(
                  child: Text(
                    _german ? 'Route hinzufügen' : 'Add to route',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _german ? 'Schließen' : 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  Text(_german ? 'Ab' : 'From',
                      style: TextStyle(color: colors.textSecondary)),
                  const SizedBox(height: 4),
                  Text(widget.origin.name,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 16),
                  TextField(
                    key: const ValueKey('append-route-destination'),
                    controller: _destinationController,
                    onChanged: _destinationChanged,
                    style: TextStyle(color: colors.textPrimary),
                    decoration: InputDecoration(
                      labelText: _german ? 'Neues Ziel' : 'New destination',
                      prefixIcon: const Icon(Icons.place_outlined),
                      suffixIcon: _loadingStations
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  for (final station in _suggestions)
                    ListTile(
                      dense: true,
                      title: Text(station.name),
                      onTap: () {
                        _debounce?.cancel();
                        ++_stationRequest;
                        setState(() {
                          _destination = station;
                          _destinationController.text = station.name;
                          _suggestions = [];
                        });
                        FocusScope.of(context).unfocus();
                      },
                    ),
                  const SizedBox(height: 18),
                  Text(_german ? 'Abfahrt ab' : 'Depart from',
                      style: TextStyle(color: colors.textSecondary)),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    key: const ValueKey('append-route-time'),
                    onPressed: _pickDateTime,
                    icon: const Icon(Icons.schedule),
                    label: Text(formatter.format(_when)),
                  ),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final (label, minutes) in [
                        (_german ? '15 Min. früher' : '15 min earlier', -15),
                        (_german ? 'Bei Ankunft' : 'At arrival', 0),
                        ('+10 min', 10),
                        ('+30 min', 30),
                      ])
                        ActionChip(
                          label: Text(label),
                          onPressed: () => _setWhen(widget.routeArrival
                              .add(Duration(minutes: minutes))),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const ValueKey('append-route-search'),
                    onPressed:
                        _destination == null || _loadingRoutes ? null : _search,
                    icon: const Icon(Icons.search),
                    label: Text(_german ? 'Routen suchen' : 'Find routes'),
                  ),
                  if (_loadingRoutes)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_error!,
                          style: const TextStyle(color: Colors.red)),
                    ),
                  if (_searched && _results.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_german
                          ? 'Keine Routen gefunden.'
                          : 'No routes found.'),
                    ),
                  for (final journey in _results) ...[
                    const SizedBox(height: 10),
                    _resultCard(journey, colors),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultCard(Journey journey, TransColors colors) {
    final catchable = !journey.departure.isBefore(widget.routeArrival);
    final gap = journey.departure.difference(widget.routeArrival).inMinutes;
    final lines = journey.steps
        .where((step) => step.type == 'ride')
        .map((step) => step.line)
        .join('  ·  ');
    return Card(
      color: colors.cardBg,
      child: InkWell(
        key: ValueKey(
            'append-route-result-${journey.departure.millisecondsSinceEpoch}'),
        onTap: catchable && _destination != null
            ? () => widget.onAppend(journey, _destination!)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(
                    '${DateFormat('HH:mm').format(journey.departure)} – '
                    '${DateFormat('HH:mm').format(journey.arrival)}',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                ),
                Icon(Icons.add_circle_outline,
                    color: catchable
                        ? colors.effectiveSeed
                        : colors.textSecondary),
              ]),
              if (lines.isNotEmpty)
                Text(lines, style: TextStyle(color: colors.textSecondary)),
              const SizedBox(height: 4),
              Text(
                catchable
                    ? (_german ? '$gap Min. Aufenthalt' : '$gap min break')
                    : (_german
                        ? 'Abfahrt vor Ankunft der bisherigen Route'
                        : 'Departs before the current route arrives'),
                style: TextStyle(color: colors.stepTransferText),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
