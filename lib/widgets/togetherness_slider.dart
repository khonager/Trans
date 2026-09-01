import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:trans/config/app_theme.dart';
import 'package:trans/models/joint_journey.dart';

/// Continuous control for the joint planner trade-off.
///
/// The three named stops (fast, balanced, together) are positions on one track
/// instead of separate buttons, because the underlying setting is a single
/// exchange rate: how much extra travelling a minute together may cost.
class TogethernessSlider extends StatelessWidget {
  /// Steps of 0.05, so all three named stops sit exactly on the track.
  static const int divisions = 20;

  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final bool german;
  final bool showSummary;

  const TogethernessSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    required this.german,
    this.showSummary = true,
  });

  static const List<JointJourneyIntent> _stops = JointJourneyIntent.values;

  static String stopLabel(JointJourneyIntent intent, {required bool german}) =>
      switch (intent) {
        JointJourneyIntent.fast => german ? 'Schnell' : 'Fast',
        JointJourneyIntent.balanced => german ? 'Ausgewogen' : 'Balanced',
        JointJourneyIntent.together => german ? 'Zusammen' : 'Together',
      };

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    final preferences = JointJourneyPreferences.fromTogetherness(value);
    final nearest = preferences.nearestIntent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          german
              ? 'Gemeinsame Zeit: ${stopLabel(nearest, german: true)}'
              : 'Time together: ${stopLabel(nearest, german: false)}',
          style: TextStyle(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          german
              ? 'Wie viel Umweg ist gemeinsame Zeit wert?'
              : 'How much detour is time together worth?',
          style: TextStyle(fontSize: 12, color: colors.textSecondary),
        ),
        Slider(
          key: const ValueKey('togetherness-slider'),
          value: value.clamp(0.0, 1.0),
          divisions: divisions,
          activeColor: colors.effectiveSeed,
          thumbColor: colors.effectiveSeed,
          label: stopLabel(nearest, german: german),
          semanticFormatterCallback: (_) => stopLabel(nearest, german: german),
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final intent in _stops)
              _StopLabel(
                intent: intent,
                german: german,
                isActive: nearest == intent,
                onTap: () =>
                    onChanged(JointJourneyPreferences.togethernessFor(intent)),
              ),
          ],
        ),
        if (showSummary) ...[
          const SizedBox(height: 10),
          TogethernessSummary(preferences: preferences, german: german),
        ],
      ],
    );
  }
}

class _StopLabel extends StatelessWidget {
  final JointJourneyIntent intent;
  final bool german;
  final bool isActive;
  final VoidCallback onTap;

  const _StopLabel({
    required this.intent,
    required this.german,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    return GestureDetector(
      key: ValueKey('togetherness-stop-${intent.name}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Text(
          TogethernessSlider.stopLabel(intent, german: german),
          style: TextStyle(
            fontSize: 11,
            fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
            color: isActive ? colors.effectiveSeed : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Plain-language read-out of what the current setting buys.
class TogethernessSummary extends StatelessWidget {
  final JointJourneyPreferences preferences;
  final bool german;

  const TogethernessSummary({
    super.key,
    required this.preferences,
    required this.german,
  });

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    final rate = NumberFormat('0.0', german ? 'de' : 'en')
        .format(preferences.detourMinutesPerSharedMinute);
    final lines = <(IconData, String)>[
      (
        Icons.swap_horiz,
        german
            ? 'Bis zu $rate Min. Fahrzeit für jede zusätzliche Minute zusammen'
            : 'Up to $rate min of travel for each extra minute together',
      ),
      (
        Icons.schedule,
        german
            ? 'Höchstens +${preferences.maxExtraTravelMinutes} Min. pro Person'
            : 'At most +${preferences.maxExtraTravelMinutes} min per person',
      ),
      (
        Icons.alt_route,
        german
            ? 'Höchstens ${preferences.maxExtraTransfers} zusätzliche Umstiege pro Person'
            : 'At most ${preferences.maxExtraTransfers} extra transfers per person',
      ),
    ];

    return Column(
      key: const ValueKey('togetherness-summary'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(line.$1, size: 13, color: colors.textSecondary),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    line.$2,
                    style:
                        TextStyle(color: colors.textSecondary, fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
