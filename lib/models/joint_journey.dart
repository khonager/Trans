import 'dart:math' as math;

import 'package:trans/models/journey.dart';

const String jointTogethernessPreferenceKey = 'joint_togetherness';

enum JointJourneyIntent { fast, balanced, together }

enum SharedJourneyMode { ride, walk, wait }

/// How much extra travelling a pair accepts for time spent together.
///
/// Instead of fixed presets the planner works with an exchange rate: how many
/// extra travel minutes — counted across both people, with extra transfers
/// converted into minutes — one extra minute together may cost. Every option is
/// measured against what both would do on their own, so the same setting keeps
/// working for a ten minute tram hop and for a three hour intercity trip.
class JointJourneyPreferences {
  /// Exchange rate at the three named slider stops.
  static const double fastDetourBudget = 0.3;
  static const double balancedDetourBudget = 1.2;
  static const double togetherDetourBudget = 4.0;

  /// An extra transfer is worth this many minutes of travel time.
  static const double defaultTransferPenaltyMinutes = 6;

  /// Slider position: 0 keeps everyone fast, 1 keeps everyone together.
  final double togetherness;

  /// Extra travel minutes the pair spends for one extra minute together.
  final double detourMinutesPerSharedMinute;

  /// Hard guard so absurd suggestions never reach the ranking.
  final int maxExtraTravelMinutes;
  final int maxExtraTransfers;

  final double transferPenaltyMinutes;

  /// Weight for a lopsided plan, where one person carries the whole detour.
  final double unfairnessPenaltyWeight;

  const JointJourneyPreferences({
    required this.togetherness,
    required this.detourMinutesPerSharedMinute,
    required this.maxExtraTravelMinutes,
    required this.maxExtraTransfers,
    this.transferPenaltyMinutes = defaultTransferPenaltyMinutes,
    this.unfairnessPenaltyWeight = 0.35,
  });

  const JointJourneyPreferences.fast()
      : this(
          togetherness: 0,
          detourMinutesPerSharedMinute: fastDetourBudget,
          maxExtraTravelMinutes: 10,
          maxExtraTransfers: 1,
        );

  const JointJourneyPreferences.balanced()
      : this(
          togetherness: 0.5,
          detourMinutesPerSharedMinute: balancedDetourBudget,
          maxExtraTravelMinutes: 23,
          maxExtraTransfers: 2,
        );

  const JointJourneyPreferences.together()
      : this(
          togetherness: 1,
          detourMinutesPerSharedMinute: togetherDetourBudget,
          maxExtraTravelMinutes: 35,
          maxExtraTransfers: 3,
        );

  /// Preferences for any slider position between the three named stops.
  factory JointJourneyPreferences.fromTogetherness(double value) {
    final togetherness = value.clamp(0.0, 1.0).toDouble();
    return JointJourneyPreferences(
      togetherness: togetherness,
      detourMinutesPerSharedMinute: detourBudgetFor(togetherness),
      maxExtraTravelMinutes: (10 + 25 * togetherness).round(),
      maxExtraTransfers: 1 + (2 * togetherness).round(),
    );
  }

  factory JointJourneyPreferences.fromIntent(JointJourneyIntent intent) =>
      JointJourneyPreferences.fromTogetherness(togethernessFor(intent));

  /// The budget grows geometrically, so every slider step changes the answer by
  /// a similar proportion rather than by a similar number of minutes.
  static double detourBudgetFor(double togetherness) {
    final value = togetherness.clamp(0.0, 1.0).toDouble();
    if (value <= 0.5) {
      return fastDetourBudget *
          math
              .pow(balancedDetourBudget / fastDetourBudget, value / 0.5)
              .toDouble();
    }
    return balancedDetourBudget *
        math
            .pow(togetherDetourBudget / balancedDetourBudget,
                (value - 0.5) / 0.5)
            .toDouble();
  }

  static double togethernessFor(JointJourneyIntent intent) => switch (intent) {
        JointJourneyIntent.fast => 0,
        JointJourneyIntent.balanced => 0.5,
        JointJourneyIntent.together => 1,
      };

  /// The named stop this setting sits closest to, for labels and analytics.
  JointJourneyIntent get nearestIntent {
    if (togetherness < 0.25) return JointJourneyIntent.fast;
    if (togetherness < 0.75) return JointJourneyIntent.balanced;
    return JointJourneyIntent.together;
  }

  /// True when the setting is at (or extremely close to) a named stop.
  bool isAtStop(JointJourneyIntent intent) =>
      (togetherness - togethernessFor(intent)).abs() < 0.02;
}

/// How far a joint search has been widened.
///
/// Widening happens in two stages, cheapest first: the budget is stretched
/// over the journeys already loaded, and only when that cannot produce
/// anything better are more departures fetched. That keeps "look further" from
/// turning into a burst of provider requests.
class JointSearchWindow {
  /// How often the budget may be stretched beyond the chosen setting.
  static const int maxBudgetSteps = 4;

  /// How many extra departure pages may be fetched per person.
  static const int maxFetchSteps = 2;

  static const double budgetStep = 0.25;

  /// Where the slider was when the search started.
  final double baseTogetherness;
  final int budgetSteps;
  final int fetchSteps;

  const JointSearchWindow({
    required this.baseTogetherness,
    this.budgetSteps = 0,
    this.fetchSteps = 0,
  });

  double get togetherness =>
      (baseTogetherness + budgetStep * budgetSteps).clamp(0.0, 1.0).toDouble();

  JointJourneyPreferences get preferences =>
      JointJourneyPreferences.fromTogetherness(togetherness);

  bool get canWidenBudget => budgetSteps < maxBudgetSteps && togetherness < 1;

  bool get canFetchMore => fetchSteps < maxFetchSteps;

  bool get canExpand => canWidenBudget || canFetchMore;

  /// True once the search reaches beyond what the slider asked for.
  bool get isWidened => budgetSteps > 0 || fetchSteps > 0;

  /// Later departures first, then earlier ones.
  bool get nextFetchIsEarlier => fetchSteps.isOdd;

  JointSearchWindow widened() => JointSearchWindow(
        baseTogetherness: baseTogetherness,
        budgetSteps: budgetSteps + 1,
        fetchSteps: fetchSteps,
      );

  JointSearchWindow fetched() => JointSearchWindow(
        baseTogetherness: baseTogetherness,
        budgetSteps: budgetSteps,
        fetchSteps: fetchSteps + 1,
      );
}

/// Result of ranking at a widening window.
class JointSearchOutcome {
  final List<JointJourneyOption> options;
  final JointSearchWindow window;

  /// True when stretching the budget could not improve on what is shown, so
  /// only more departures can.
  final bool needsMoreDepartures;

  const JointSearchOutcome({
    required this.options,
    required this.window,
    required this.needsMoreDepartures,
  });
}

class SharedJourneySegment {
  final SharedJourneyMode mode;
  final DateTime start;
  final DateTime end;
  final String label;

  const SharedJourneySegment({
    required this.mode,
    required this.start,
    required this.end,
    required this.label,
  });

  Duration get duration => end.difference(start);
}

class JointJourneyOption {
  final Journey myJourney;
  final Journey friendJourney;
  final List<SharedJourneySegment> sharedSegments;
  final Duration sharedDuration;
  final Duration sharedRideDuration;
  final Duration sharedWalkDuration;
  final Duration sharedWaitDuration;

  /// Time the two would already spend together if both simply took their own
  /// best route. Only what an option adds on top of this is worth a detour.
  final Duration baselineSharedDuration;

  final int myExtraMinutes;
  final int friendExtraMinutes;
  final int myExtraTransfers;
  final int friendExtraTransfers;

  /// Extra travel time both people pay together, with extra transfers counted
  /// as minutes. Fairness is not part of this — it is a plain time figure the
  /// UI can show.
  final double detourMinutes;

  /// Shared minutes gained over the baseline pairing.
  final double sharedGainMinutes;

  /// Gain after paying for the detour at the chosen exchange rate, in minutes
  /// together. This is the ranking score and stays comparable across journeys
  /// of any length.
  final double netTogetherMinutes;

  const JointJourneyOption({
    required this.myJourney,
    required this.friendJourney,
    required this.sharedSegments,
    required this.sharedDuration,
    required this.sharedRideDuration,
    required this.sharedWalkDuration,
    required this.sharedWaitDuration,
    required this.baselineSharedDuration,
    required this.myExtraMinutes,
    required this.friendExtraMinutes,
    required this.myExtraTransfers,
    required this.friendExtraTransfers,
    required this.detourMinutes,
    required this.sharedGainMinutes,
    required this.netTogetherMinutes,
  });

  /// Travel minutes spent per minute together gained, or null when the option
  /// costs nothing at all.
  double? get detourPerSharedMinute {
    if (detourMinutes <= 0) return null;
    if (sharedGainMinutes <= 0) return double.infinity;
    return detourMinutes / sharedGainMinutes;
  }

  bool get isFree => detourMinutes <= 0;
}
