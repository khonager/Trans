import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:trans/config/app_theme.dart';
import 'package:trans/services/transport_api.dart';
import 'package:trans/utils/app_error.dart';

import '../l10n/app_localizations.dart';

enum _ServiceDayFilter { weekday, weekendHoliday }

/// Shows all departures for [stopName] (identified by [stopId]) on [date] in
/// a scrollable bottom-sheet that the user can long-press into from any stop
/// row inside a connection detail view.
class StopDeparturesSheet extends StatefulWidget {
  final String stopId;
  final String stopName;
  final DateTime date;

  const StopDeparturesSheet({
    super.key,
    required this.stopId,
    required this.stopName,
    required this.date,
  });

  static Future<void> show(
    BuildContext context, {
    required String stopId,
    required String stopName,
    required DateTime date,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          StopDeparturesSheet(stopId: stopId, stopName: stopName, date: date),
    );
  }

  @override
  State<StopDeparturesSheet> createState() => _StopDeparturesSheetState();
}

class _StopDeparturesSheetState extends State<StopDeparturesSheet> {
  late Future<List<Map<String, dynamic>>> _future;
  late _ServiceDayFilter _dayFilter;
  late DateTime _viewDate;
  String? _selectedPlatform;

  @override
  void initState() {
    super.initState();
    _dayFilter = _isWeekendOrHoliday(widget.date)
        ? _ServiceDayFilter.weekendHoliday
        : _ServiceDayFilter.weekday;
    _viewDate = _dateForFilter(widget.date, _dayFilter);
    _load();
  }

  void _load() {
    _future = TransportApi.fetchStopDepartures(widget.stopId, date: _viewDate)
        .then((deps) {
      if (!mounted) return deps;
      final platforms = _platformOptions(deps);
      if (_selectedPlatform != null && !platforms.contains(_selectedPlatform)) {
        setState(() => _selectedPlatform = null);
      }
      return deps;
    });
  }

  void _setDayFilter(_ServiceDayFilter filter) {
    if (_dayFilter == filter) return;
    setState(() {
      _dayFilter = filter;
      _viewDate = _dateForFilter(widget.date, filter);
      _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    final l10n = AppLocalizations.of(context)!;

    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.modalHandle.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.stopDeparturesTitle(widget.stopName),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('EEE, d MMM').format(_viewDate),
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _future,
                  builder: (ctx, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 12),
                            Text(
                              l10n.loadingDepartures,
                              style: TextStyle(color: colors.textSecondary),
                            ),
                          ],
                        ),
                      );
                    }

                    if (snap.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            AppError.userMessage(context, snap.error!),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colors.textSecondary),
                          ),
                        ),
                      );
                    }

                    final deps = snap.data ?? const <Map<String, dynamic>>[];
                    final platforms = _platformOptions(deps);
                    final filteredDeps = deps.where((dep) {
                      if (_selectedPlatform == null) return true;
                      return _platformForDeparture(dep) == _selectedPlatform;
                    }).toList();

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _FilterCard(
                                  title: l10n.stopPlatformFilter,
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: [
                                        _FilterChip(
                                          label: l10n.stopPlatformAll,
                                          selected: _selectedPlatform == null,
                                          onTap: () => setState(
                                            () => _selectedPlatform = null,
                                          ),
                                        ),
                                        for (final platform in platforms)
                                          _FilterChip(
                                            label: platform,
                                            selected:
                                                platform == _selectedPlatform,
                                            onTap: () => setState(
                                              () =>
                                                  _selectedPlatform = platform,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _FilterCard(
                                  title: l10n.stopServiceDayFilter,
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _FilterChip(
                                        label: l10n.stopServiceDayWeekday,
                                        selected: _dayFilter ==
                                            _ServiceDayFilter.weekday,
                                        onTap: () => _setDayFilter(
                                          _ServiceDayFilter.weekday,
                                        ),
                                      ),
                                      _FilterChip(
                                        label:
                                            l10n.stopServiceDayWeekendHoliday,
                                        selected: _dayFilter ==
                                            _ServiceDayFilter.weekendHoliday,
                                        onTap: () => _setDayFilter(
                                          _ServiceDayFilter.weekendHoliday,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: filteredDeps.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(
                                      deps.isEmpty
                                          ? l10n.noDeparturesFound
                                          : l10n.noDeparturesForPlatform,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: colors.textSecondary,
                                      ),
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  controller: scrollCtrl,
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    28,
                                  ),
                                  itemCount: filteredDeps.length,
                                  itemBuilder: (ctx, idx) {
                                    return Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 10),
                                      child: _DepartureRow(
                                        dep: filteredDeps[idx],
                                        colors: colors,
                                        l10n: l10n,
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FilterCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _FilterCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.stepStopoversBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.divider.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? colors.chipActiveBg : colors.chipBg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? colors.chipActiveFg : colors.chipFg,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _DepartureRow extends StatelessWidget {
  final Map<String, dynamic> dep;
  final TransColors colors;
  final AppLocalizations l10n;

  const _DepartureRow({
    required this.dep,
    required this.colors,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final parsed = _ParsedDeparture.fromMap(dep);
    final platform = _platformForDeparture(dep);
    final cardBorder = parsed.isCancelled
        ? Colors.red.withValues(alpha: 0.25)
        : colors.divider.withValues(alpha: 0.45);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 56),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: parsed.isCancelled
                  ? Colors.red.withValues(alpha: 0.12)
                  : colors.chipBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              parsed.lineName.isNotEmpty ? parsed.lineName : '—',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: parsed.isCancelled ? Colors.red : colors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                decoration:
                    parsed.isCancelled ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        parsed.direction.isNotEmpty ? parsed.direction : '—',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: parsed.isCancelled
                              ? colors.textSecondary
                              : colors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          decoration: parsed.isCancelled
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                    if (platform != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: colors.searchHeaderIconBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          platform,
                          style: TextStyle(
                            color: colors.searchHeaderIcon,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: parsed.isCancelled
                            ? colors.chipBg
                            : colors.timeContainerBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        parsed.timeStr,
                        style: TextStyle(
                          color: parsed.isCancelled
                              ? colors.textSecondary
                              : (parsed.delayStr == null
                                  ? colors.textPrimary
                                  : parsed.timeColor),
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          decoration: parsed.isCancelled
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                    if (parsed.delayStr != null && !parsed.isCancelled) ...[
                      const SizedBox(width: 8),
                      Text(
                        parsed.delayStr!,
                        style: TextStyle(
                          color: parsed.delayStr == null
                              ? colors.textPrimary
                              : parsed.timeColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    if (parsed.isCancelled) ...[
                      const SizedBox(width: 8),
                      Text(
                        l10n.cancelled,
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ParsedDeparture {
  final String timeStr;
  final String? delayStr;
  final Color timeColor;
  final bool isCancelled;
  final String lineName;
  final String direction;

  const _ParsedDeparture({
    required this.timeStr,
    required this.delayStr,
    required this.timeColor,
    required this.isCancelled,
    required this.lineName,
    required this.direction,
  });

  factory _ParsedDeparture.fromMap(Map<String, dynamic> dep) {
    String timeStr = '--:--';
    String? delayStr;
    Color timeColor = Colors.red;
    bool isCancelled = false;

    final motisDepObj = dep['departure'] as Map<String, dynamic>?;
    final motisPlaceObj = dep['place'] as Map<String, dynamic>?;
    if (motisDepObj != null || motisPlaceObj != null) {
      final scheduled = (motisDepObj?['scheduledTime'] as String?) ??
          (motisPlaceObj?['scheduledDeparture'] as String?) ??
          (motisPlaceObj?['scheduledArrival'] as String?);
      final actual = (motisDepObj?['time'] as String?) ??
          (motisPlaceObj?['departure'] as String?) ??
          (motisPlaceObj?['arrival'] as String?);
      final rawDelay = motisDepObj?['delay'];
      final delay = rawDelay is num
          ? rawDelay.toInt()
          : _calculateDelayMinutes(scheduled, actual);

      isCancelled = (dep['cancelled'] as bool?) ??
          (motisPlaceObj?['cancelled'] as bool?) ??
          false;

      final displayedTime = scheduled ?? actual;
      if (displayedTime != null) {
        final dt = DateTime.parse(displayedTime).toLocal();
        timeStr =
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      if (delay != null && delay != 0) {
        final sign = delay > 0 ? '+' : '';
        delayStr = '$sign$delay\'';
        timeColor = delay > 2 ? Colors.red : Colors.green;
      }
    } else {
      final planned = dep['plannedWhen'] as String?;
      final actual = dep['when'] as String?;
      isCancelled = (dep['cancelled'] as bool?) ?? false;
      final displayedTime = planned ?? actual;
      if (displayedTime != null) {
        final dt = DateTime.parse(displayedTime).toLocal();
        timeStr =
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      final delay = dep['delay'] as int?;
      if (delay != null && delay != 0) {
        final delayMin = (delay / 60).round();
        if (delayMin != 0) {
          final sign = delayMin > 0 ? '+' : '';
          delayStr = '$sign$delayMin\'';
          timeColor = delayMin > 2 ? Colors.red : Colors.green;
        }
      }
    }

    final routeShort = dep['routeShortName'] as String?;
    final headsign = dep['headsign'] as String?;
    final tripTo = dep['tripTo'] as Map<String, dynamic>?;
    final lineObj = dep['line'] as Map<String, dynamic>?;

    return _ParsedDeparture(
      timeStr: timeStr,
      delayStr: delayStr,
      timeColor: timeColor,
      isCancelled: isCancelled,
      lineName: routeShort ??
          (dep['displayName'] as String?) ??
          (lineObj?['name'] as String?) ??
          '',
      direction: headsign ??
          (tripTo?['name'] as String?) ??
          (dep['direction'] as String?) ??
          '',
    );
  }
}

List<String> _platformOptions(List<Map<String, dynamic>> deps) {
  final platforms = deps
      .map(_platformForDeparture)
      .whereType<String>()
      .where((platform) => platform.trim().isNotEmpty)
      .toSet()
      .toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return platforms;
}

String? _platformForDeparture(Map<String, dynamic> dep) {
  final place = dep['place'] as Map<String, dynamic>?;
  final platform = place?['track'] ??
      place?['scheduledTrack'] ??
      dep['platform'] ??
      dep['plannedPlatform'];
  final text = platform?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

bool _isWeekendOrHoliday(DateTime date) =>
    date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;

DateTime _dateForFilter(DateTime anchor, _ServiceDayFilter filter) {
  final base = DateTime(
    anchor.year,
    anchor.month,
    anchor.day,
    anchor.hour,
    anchor.minute,
  );

  if (filter == _ServiceDayFilter.weekendHoliday) {
    if (_isWeekendOrHoliday(base)) return base;
    final delta = (DateTime.saturday - base.weekday + 7) % 7;
    return base.add(Duration(days: delta == 0 ? 7 : delta));
  }

  if (!_isWeekendOrHoliday(base)) return base;
  final delta = (DateTime.monday - base.weekday + 7) % 7;
  return base.add(Duration(days: delta == 0 ? 7 : delta));
}

int? _calculateDelayMinutes(String? scheduled, String? actual) {
  if (scheduled == null || actual == null) return null;
  try {
    return DateTime.parse(actual)
        .difference(DateTime.parse(scheduled))
        .inMinutes;
  } catch (_) {
    return null;
  }
}
