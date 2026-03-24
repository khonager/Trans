import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:trans/config/app_theme.dart';
import 'package:trans/services/transport_api.dart';
import 'package:trans/utils/app_error.dart';
import '../l10n/app_localizations.dart';

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

  /// Convenience helper: shows the sheet and returns when it is dismissed.
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
  // Which date we are currently viewing (user can swipe to adjacent days)
  late DateTime _viewDate;

  @override
  void initState() {
    super.initState();
    _viewDate = widget.date;
    _load();
  }

  void _load() {
    _future = TransportApi.fetchStopDepartures(widget.stopId, date: _viewDate);
  }

  void _changeDay(int delta) {
    setState(() {
      _viewDate = _viewDate.add(Duration(days: delta));
      _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    final l10n = AppLocalizations.of(context)!;
    final dateLabel = DateFormat('EEE, d MMM yyyy').format(_viewDate);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: colors.scaffoldBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: colors.textSecondary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header row
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.stopDeparturesTitle(widget.stopName),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Date navigation row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          color: colors.textSecondary,
                          onPressed: () => _changeDay(-1),
                        ),
                        Text(
                          dateLabel,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          color: colors.textSecondary,
                          onPressed: () => _changeDay(1),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Content
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
                    final deps = snap.data ?? [];
                    if (deps.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            l10n.noDeparturesFound,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colors.textSecondary),
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.only(bottom: 32),
                      itemCount: deps.length,
                      itemBuilder: (ctx, idx) {
                        return _DepartureRow(dep: deps[idx], colors: colors);
                      },
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

class _DepartureRow extends StatelessWidget {
  final Map<String, dynamic> dep;
  final TransColors colors;

  const _DepartureRow({required this.dep, required this.colors});

  @override
  Widget build(BuildContext context) {
    String timeStr = '--:--';
    String? delayStr;
    Color timeColor = colors.textPrimary;
    bool isCancelled = false;

    final motisDepObj = dep['departure'] as Map<String, dynamic>?;
    final motisPlaceObj = dep['place'] as Map<String, dynamic>?;
    if (motisDepObj != null || motisPlaceObj != null) {
      final scheduled =
          (motisDepObj?['scheduledTime'] as String?) ??
          (motisPlaceObj?['scheduledDeparture'] as String?) ??
          (motisPlaceObj?['scheduledArrival'] as String?);
      final actual =
          (motisDepObj?['time'] as String?) ??
          (motisPlaceObj?['departure'] as String?) ??
          (motisPlaceObj?['arrival'] as String?);
      final rawDelay = motisDepObj?['delay'];
      final delay = rawDelay is num
          ? rawDelay.toInt()
          : _calculateDelayMinutes(scheduled, actual);
      isCancelled =
          (dep['cancelled'] as bool?) ??
          (motisPlaceObj?['cancelled'] as bool?) ??
          false;

      if (scheduled != null) {
        final dt = DateTime.parse(scheduled).toLocal();
        timeStr =
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } else if (actual != null) {
        final dt = DateTime.parse(actual).toLocal();
        timeStr =
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      if (delay != null && delay != 0) {
        final sign = delay > 0 ? '+' : '';
        delayStr = '$sign$delay\'';
        timeColor = delay > 2 ? colors.delayLate : colors.delayOnTime;
      }
    } else {
      // v6 format
      final planned = dep['plannedWhen'] as String?;
      final actual = dep['when'] as String?;
      isCancelled = (dep['cancelled'] as bool?) ?? false;
      if (planned != null) {
        final dt = DateTime.parse(planned).toLocal();
        timeStr =
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } else if (actual != null) {
        final dt = DateTime.parse(actual).toLocal();
        timeStr =
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      final delay = dep['delay'] as int?;
      if (delay != null && delay != 0) {
        final delaySecs = delay;
        final delayMin = (delaySecs / 60).round();
        if (delayMin != 0) {
          final sign = delayMin > 0 ? '+' : '';
          delayStr = '$sign$delayMin\'';
          timeColor = delayMin > 2 ? colors.delayLate : colors.delayOnTime;
        }
      }
    }

    String lineName = '';
    String direction = '';

    final routeShort = dep['routeShortName'] as String?;
    final headsign = dep['headsign'] as String?;
    if (routeShort != null || headsign != null) {
      lineName = routeShort ?? (dep['displayName'] as String?) ?? '';
      direction =
          headsign ??
          (dep['tripTo'] as Map<String, dynamic>?)?['name'] as String? ??
          '';
    } else {
      final lineObj = dep['line'] as Map<String, dynamic>?;
      lineName = (lineObj?['name'] as String?) ?? '';
      direction = (dep['direction'] as String?) ?? '';
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colors.textSecondary.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isCancelled
                ? Colors.red.withValues(alpha: 0.15)
                : colors.chipBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            lineName.isNotEmpty ? lineName : '—',
            style: TextStyle(
              color: isCancelled ? Colors.red : colors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 13,
              decoration: isCancelled ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
        title: Text(
          direction.isNotEmpty ? direction : '—',
          style: TextStyle(
            color: isCancelled ? colors.textSecondary : colors.textPrimary,
            fontSize: 14,
            decoration: isCancelled ? TextDecoration.lineThrough : null,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              timeStr,
              style: TextStyle(
                color: isCancelled ? colors.textSecondary : timeColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
                decoration: isCancelled ? TextDecoration.lineThrough : null,
              ),
            ),
            if (delayStr != null && !isCancelled)
              Text(delayStr, style: TextStyle(color: timeColor, fontSize: 11)),
            if (isCancelled)
              Text(
                'FÄLLT AUS',
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

int? _calculateDelayMinutes(String? scheduled, String? actual) {
  if (scheduled == null || actual == null) return null;
  try {
    return DateTime.parse(actual).difference(DateTime.parse(scheduled)).inMinutes;
  } catch (_) {
    return null;
  }
}
