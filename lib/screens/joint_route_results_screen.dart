import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:trans/config/app_theme.dart';
import 'package:trans/models/joint_journey.dart';
import 'package:trans/widgets/togetherness_slider.dart';

class JointRouteResultsScreen extends StatelessWidget {
  final String friendName;
  final String destinationName;
  final List<JointJourneyOption> options;
  final JointSearchWindow window;
  final Future<void> Function(JointJourneyOption option)? onShare;

  const JointRouteResultsScreen({
    super.key,
    required this.friendName,
    required this.destinationName,
    required this.options,
    this.window = const JointSearchWindow(baseTogetherness: 0.5),
    this.onShare,
  });

  bool _isGerman(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'de';

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    final german = _isGerman(context);
    return Scaffold(
      backgroundColor: colors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: colors.appBarBg,
        foregroundColor: colors.appBarTitle,
        title: Text(german ? 'Gemeinsam planen' : 'Plan together'),
      ),
      body: JointRouteResultsView(
        friendName: friendName,
        destinationName: destinationName,
        options: options,
        window: window,
        onSelect: (option) => Navigator.of(context).pop(option),
        onShare: onShare,
        showHeader: false,
      ),
    );
  }
}

class JointRouteResultsView extends StatelessWidget {
  final String friendName;
  final String destinationName;
  final List<JointJourneyOption> options;
  final JointSearchWindow window;
  final ValueChanged<JointJourneyOption> onSelect;
  final Future<void> Function(JointJourneyOption option)? onShare;
  final VoidCallback? onBack;

  /// Widens the search by one step. Null when nothing more can be found.
  final VoidCallback? onExpand;
  final bool isExpanding;
  final bool showHeader;

  const JointRouteResultsView({
    super.key,
    required this.friendName,
    required this.destinationName,
    required this.options,
    required this.onSelect,
    this.window = const JointSearchWindow(baseTogetherness: 0.5),
    this.onShare,
    this.onBack,
    this.onExpand,
    this.isExpanding = false,
    this.showHeader = true,
  });

  JointJourneyPreferences get preferences => window.preferences;

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    final german = Localizations.localeOf(context).languageCode == 'de';
    final expandControl = _ExpandControl(
      onExpand: onExpand,
      isExpanding: isExpanding,
      window: window,
      german: german,
    );
    final list = options.isEmpty
        ? _EmptyState(
            friendName: friendName,
            window: window,
            expandControl: expandControl,
          )
        : ListView.builder(
            key: const ValueKey('joint-route-results-list'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            // One extra row keeps "look further" at the end of the list, the
            // place users reach after ruling the shown options out.
            itemCount: options.length + 1,
            itemBuilder: (context, index) {
              if (index == options.length) {
                return Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: expandControl,
                );
              }
              return _OptionCard(
                option: options[index],
                friendName: friendName,
                destinationName: destinationName,
                rank: index,
                onSelect: () => onSelect(options[index]),
                onShare: onShare == null
                    ? null
                    : () => _share(
                          context,
                          option: options[index],
                          german: german,
                        ),
              );
            },
          );
    if (!showHeader) return list;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
          child: Row(
            children: [
              IconButton(
                key: const ValueKey('joint-results-back'),
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                color: colors.textPrimary,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      german
                          ? '${options.length} gemeinsame Routen'
                          : '${options.length} shared routes',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      german
                          ? 'mit $friendName · ${TogethernessSlider.stopLabel(preferences.nearestIntent, german: true)}${window.isWidened ? ' · erweitert' : ''}'
                          : 'with $friendName · ${TogethernessSlider.stopLabel(preferences.nearestIntent, german: false)}${window.isWidened ? ' · widened' : ''}',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(child: list),
      ],
    );
  }

  Future<void> _share(
    BuildContext context, {
    required JointJourneyOption option,
    required bool german,
  }) async {
    try {
      await onShare!(option);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(german
            ? 'Plan wurde an $friendName gesendet.'
            : 'Plan sent to $friendName.'),
      ));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(german
            ? 'Der Plan konnte nicht gesendet werden.'
            : 'The plan could not be sent.'),
      ));
    }
  }
}

class _EmptyState extends StatelessWidget {
  final String friendName;
  final JointSearchWindow window;
  final Widget expandControl;

  const _EmptyState({
    required this.friendName,
    required this.window,
    required this.expandControl,
  });

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    final german = Localizations.localeOf(context).languageCode == 'de';
    final canAllowMore = window.preferences.togetherness < 1;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.group_off_outlined, size: 52, color: colors.textSecondary),
          const SizedBox(height: 16),
          Text(
            german
                ? 'Keine sinnvolle gemeinsame Route gefunden'
                : 'No worthwhile shared route found',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            german
                ? 'Jede Route mit $friendName kostet mehr zusätzliche Fahrzeit, als sie an gemeinsamer Zeit bringt.'
                : 'Every route with $friendName costs more extra travel time than it adds time together.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary),
          ),
          if (canAllowMore) ...[
            const SizedBox(height: 10),
            Text(
              german
                  ? 'Schiebe den Regler Richtung „Zusammen“, um größere Umwege zuzulassen.'
                  : 'Move the slider towards “Together” to allow bigger detours.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
          ],
          const SizedBox(height: 18),
          expandControl,
        ],
      ),
    );
  }
}

/// Widens the search one step at a time, the way "load later" extends a
/// regular result list.
class _ExpandControl extends StatelessWidget {
  final VoidCallback? onExpand;
  final bool isExpanding;
  final JointSearchWindow window;
  final bool german;

  const _ExpandControl({
    required this.onExpand,
    required this.isExpanding,
    required this.window,
    required this.german,
  });

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    if (onExpand == null && !isExpanding) {
      return Padding(
        key: const ValueKey('joint-expand-exhausted'),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          german
              ? 'Mehr gemeinsame Zeit ist in diesem Zeitraum nicht zu holen.'
              : 'There is no more time together to find around this time.',
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.textSecondary, fontSize: 12),
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const ValueKey('joint-expand-button'),
            onPressed: isExpanding ? null : onExpand,
            icon: isExpanding
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.effectiveSeed,
                    ),
                  )
                : const Icon(Icons.unfold_more),
            label: Text(
              isExpanding
                  ? (german ? 'Suche weiter …' : 'Looking further…')
                  : (german
                      ? 'Mehr gemeinsame Zeit suchen'
                      : 'Look for more time together'),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.effectiveSeed,
              side: BorderSide(color: colors.effectiveSeed),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          german
              ? 'Erlaubt mehr Umweg und, wenn nötig, weitere Abfahrten.'
              : 'Allows more detour and, if needed, more departures.',
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.textSecondary, fontSize: 11),
        ),
      ],
    );
  }
}

class _OptionCard extends StatelessWidget {
  final JointJourneyOption option;
  final String friendName;
  final String destinationName;
  final int rank;
  final VoidCallback onSelect;
  final Future<void> Function()? onShare;

  const _OptionCard({
    required this.option,
    required this.friendName,
    required this.destinationName,
    required this.rank,
    required this.onSelect,
    this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    final german = Localizations.localeOf(context).languageCode == 'de';
    final format = DateFormat('HH:mm');
    final sharedMinutes = option.sharedDuration.inMinutes;
    final gainMinutes = option.sharedGainMinutes.round();
    final detourMinutes = option.detourMinutes.round();
    final baselineMinutes = option.baselineSharedDuration.inMinutes;
    final rate = option.detourPerSharedMinute;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      color: rank == 0
          ? Color.alphaBlend(
              colors.effectiveSeed.withValues(alpha: 0.08),
              colors.cardBg,
            )
          : colors.cardBg,
      elevation: rank == 0 ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: rank == 0 ? colors.effectiveSeed : colors.divider,
          width: rank == 0 ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    rank == 0
                        ? (german ? 'Bester Vorschlag' : 'Best match')
                        : (german ? 'Weitere Möglichkeit' : 'Another option'),
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: colors.effectiveSeed,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    german
                        ? '$sharedMinutes Min. zusammen'
                        : '$sharedMinutes min together',
                    style: TextStyle(
                      color: colors.searchBtnText,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // What this option is actually worth: what it adds compared to
            // both travelling alone, and what that costs.
            Container(
              key: const ValueKey('joint-option-value'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colors.effectiveSeed.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.isFree
                        ? (german
                            ? '+$gainMinutes Min. zusammen ohne Umweg'
                            : '+$gainMinutes min together at no cost')
                        : (german
                            ? '+$gainMinutes Min. zusammen für +$detourMinutes Min. Reisezeit'
                            : '+$gainMinutes min together for +$detourMinutes min of travel'),
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (rate != null && rate.isFinite) ...[
                    const SizedBox(height: 3),
                    Text(
                      german
                          ? '${NumberFormat('0.0', 'de').format(rate)} Min. Reisezeit je gemeinsamer Minute'
                          : '${NumberFormat('0.0', 'en').format(rate)} min of travel per minute together',
                      style:
                          TextStyle(color: colors.textSecondary, fontSize: 11),
                    ),
                  ],
                  if (baselineMinutes > 0) ...[
                    const SizedBox(height: 3),
                    Text(
                      german
                          ? 'Davon wärt ihr $baselineMinutes Min. ohnehin zusammen unterwegs.'
                          : 'You would already travel $baselineMinutes min of that together anyway.',
                      style:
                          TextStyle(color: colors.textSecondary, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            _PersonRouteRow(
              name: german ? 'Du' : 'You',
              departure: format.format(option.myJourney.departure),
              arrival: format.format(option.myJourney.arrival),
              extraMinutes: option.myExtraMinutes,
              extraTransfers: option.myExtraTransfers,
            ),
            const SizedBox(height: 8),
            _PersonRouteRow(
              name: friendName,
              departure: format.format(option.friendJourney.departure),
              arrival: format.format(option.friendJourney.arrival),
              extraMinutes: option.friendExtraMinutes,
              extraTransfers: option.friendExtraTransfers,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (option.sharedRideDuration.inMinutes > 0)
                  _SharedModeChip(
                    icon: Icons.directions_transit,
                    label: german ? 'Fahren' : 'Ride',
                    minutes: option.sharedRideDuration.inMinutes,
                  ),
                if (option.sharedWaitDuration.inMinutes > 0)
                  _SharedModeChip(
                    icon: Icons.schedule,
                    label: german ? 'Warten' : 'Wait',
                    minutes: option.sharedWaitDuration.inMinutes,
                  ),
                if (option.sharedWalkDuration.inMinutes > 0)
                  _SharedModeChip(
                    icon: Icons.directions_walk,
                    label: german ? 'Laufen' : 'Walk',
                    minutes: option.sharedWalkDuration.inMinutes,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            for (final segment in option.sharedSegments.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  children: [
                    Icon(_modeIcon(segment.mode),
                        size: 16, color: colors.textSecondary),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        '${format.format(segment.start)}–${format.format(segment.end)}'
                        '${segment.label.trim().isEmpty ? '' : ' · ${segment.label}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: colors.textSecondary, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            if (onShare != null) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => onShare!(),
                  icon: const Icon(Icons.send_outlined),
                  label: Text(
                    german ? 'An $friendName senden' : 'Send to $friendName',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.effectiveSeed,
                    side: BorderSide(color: colors.effectiveSeed),
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onSelect,
                icon: const Icon(Icons.check),
                label: Text(german
                    ? 'Diese Route für mich öffnen'
                    : 'Open my part of this route'),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.effectiveSeed,
                  foregroundColor: colors.searchBtnText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _modeIcon(SharedJourneyMode mode) => switch (mode) {
        SharedJourneyMode.ride => Icons.directions_transit,
        SharedJourneyMode.walk => Icons.directions_walk,
        SharedJourneyMode.wait => Icons.schedule,
      };
}

class _PersonRouteRow extends StatelessWidget {
  final String name;
  final String departure;
  final String arrival;
  final int extraMinutes;
  final int extraTransfers;

  const _PersonRouteRow({
    required this.name,
    required this.departure,
    required this.arrival,
    required this.extraMinutes,
    required this.extraTransfers,
  });

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    final german = Localizations.localeOf(context).languageCode == 'de';
    final costs = <String>[];
    if (extraMinutes > 0) {
      costs.add('+$extraMinutes ${german ? 'Min.' : 'min'}');
    }
    if (extraTransfers > 0) {
      costs.add('+$extraTransfers ${german ? 'Umstieg' : 'transfer'}'
          '${extraTransfers == 1 ? '' : german ? 'e' : 's'}');
    }
    return Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: colors.textPrimary, fontWeight: FontWeight.w600)),
        ),
        Text('$departure–$arrival',
            style: TextStyle(color: colors.textPrimary)),
        const Spacer(),
        if (costs.isNotEmpty)
          Flexible(
            child: Text(
              costs.join(', '),
              textAlign: TextAlign.end,
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
          )
        else
          Text(german ? 'kein Umweg' : 'no detour',
              style: const TextStyle(color: Colors.green, fontSize: 12)),
      ],
    );
  }
}

class _SharedModeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final int minutes;

  const _SharedModeChip({
    required this.icon,
    required this.label,
    required this.minutes,
  });

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: colors.effectiveSeed.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: colors.effectiveSeed),
          const SizedBox(width: 5),
          Text('$label · $minutes min',
              style: TextStyle(color: colors.effectiveSeed, fontSize: 12)),
        ],
      ),
    );
  }
}
