import 'package:flutter_test/flutter_test.dart';
import 'package:trans/models/joint_journey.dart';
import 'package:trans/models/journey.dart';

final _emptyJourney = Journey(
  steps: const [],
  departure: DateTime(2026, 8, 30, 8),
  arrival: DateTime(2026, 8, 30, 9),
  duration: const Duration(hours: 1),
  transferCount: 0,
  totalWaitTime: Duration.zero,
  rawSource: const {},
  source: 'test',
);

void main() {
  group('detour budget', () {
    test('matches the named stops exactly', () {
      expect(
        JointJourneyPreferences.detourBudgetFor(0),
        closeTo(JointJourneyPreferences.fastDetourBudget, 0.0001),
      );
      expect(
        JointJourneyPreferences.detourBudgetFor(0.5),
        closeTo(JointJourneyPreferences.balancedDetourBudget, 0.0001),
      );
      expect(
        JointJourneyPreferences.detourBudgetFor(1),
        closeTo(JointJourneyPreferences.togetherDetourBudget, 0.0001),
      );
    });

    test('grows with every step towards together', () {
      var previous = JointJourneyPreferences.detourBudgetFor(0);
      for (var step = 1; step <= 20; step++) {
        final current = JointJourneyPreferences.detourBudgetFor(step / 20);
        expect(current, greaterThan(previous));
        previous = current;
      }
    });

    test('clamps positions outside the track', () {
      expect(
        JointJourneyPreferences.detourBudgetFor(-2),
        closeTo(JointJourneyPreferences.fastDetourBudget, 0.0001),
      );
      expect(
        JointJourneyPreferences.detourBudgetFor(4),
        closeTo(JointJourneyPreferences.togetherDetourBudget, 0.0001),
      );
    });
  });

  group('preferences from a slider position', () {
    test('reproduces the named presets', () {
      final fast = JointJourneyPreferences.fromTogetherness(0);
      expect(fast.maxExtraTravelMinutes,
          const JointJourneyPreferences.fast().maxExtraTravelMinutes);
      expect(fast.maxExtraTransfers,
          const JointJourneyPreferences.fast().maxExtraTransfers);
      expect(
        fast.detourMinutesPerSharedMinute,
        closeTo(
          const JointJourneyPreferences.fast().detourMinutesPerSharedMinute,
          0.0001,
        ),
      );

      final together = JointJourneyPreferences.fromTogetherness(1);
      expect(together.maxExtraTravelMinutes,
          const JointJourneyPreferences.together().maxExtraTravelMinutes);
      expect(together.maxExtraTransfers,
          const JointJourneyPreferences.together().maxExtraTransfers);
    });

    test('allows more detour the further the slider moves', () {
      final low = JointJourneyPreferences.fromTogetherness(0.2);
      final high = JointJourneyPreferences.fromTogetherness(0.8);
      expect(
          high.maxExtraTravelMinutes, greaterThan(low.maxExtraTravelMinutes));
      expect(high.detourMinutesPerSharedMinute,
          greaterThan(low.detourMinutesPerSharedMinute));
    });

    test('names the closest stop for labels', () {
      expect(JointJourneyPreferences.fromTogetherness(0.1).nearestIntent,
          JointJourneyIntent.fast);
      expect(JointJourneyPreferences.fromTogetherness(0.4).nearestIntent,
          JointJourneyIntent.balanced);
      expect(JointJourneyPreferences.fromTogetherness(0.9).nearestIntent,
          JointJourneyIntent.together);
    });

    test('recognises when it sits on a stop', () {
      expect(
        JointJourneyPreferences.fromTogetherness(0.5)
            .isAtStop(JointJourneyIntent.balanced),
        isTrue,
      );
      expect(
        JointJourneyPreferences.fromTogetherness(0.62)
            .isAtStop(JointJourneyIntent.balanced),
        isFalse,
      );
    });
  });

  group('search window', () {
    test('starts at the chosen setting', () {
      const window = JointSearchWindow(baseTogetherness: 0.5);
      expect(window.togetherness, 0.5);
      expect(window.isWidened, isFalse);
      expect(window.canExpand, isTrue);
    });

    test('stretches the budget in steps and then stops', () {
      var window = const JointSearchWindow(baseTogetherness: 0.5);
      window = window.widened();
      expect(window.togetherness, 0.75);
      expect(window.isWidened, isTrue);

      window = window.widened();
      expect(window.togetherness, 1);
      expect(window.canWidenBudget, isFalse,
          reason: 'the budget cannot go past Together');
    });

    test('has no budget headroom when it starts at together', () {
      const window = JointSearchWindow(baseTogetherness: 1);
      expect(window.canWidenBudget, isFalse);
      expect(window.canFetchMore, isTrue);
      expect(window.canExpand, isTrue);
    });

    test('fetches later departures first, then earlier ones', () {
      var window = const JointSearchWindow(baseTogetherness: 1);
      expect(window.nextFetchIsEarlier, isFalse);

      window = window.fetched();
      expect(window.nextFetchIsEarlier, isTrue);
      expect(window.canFetchMore, isTrue);

      window = window.fetched();
      expect(window.canFetchMore, isFalse);
      expect(window.canExpand, isFalse);
    });

    test('stretching the budget does not spend fetch steps', () {
      final window =
          const JointSearchWindow(baseTogetherness: 0).widened().widened();
      expect(window.fetchSteps, 0);
      expect(window.budgetSteps, 2);
    });
  });

  group('option cost reporting', () {
    JointJourneyOption option({
      required double detour,
      required double gain,
    }) =>
        JointJourneyOption(
          myJourney: _emptyJourney,
          friendJourney: _emptyJourney,
          sharedSegments: const [],
          sharedDuration: const Duration(minutes: 30),
          sharedRideDuration: const Duration(minutes: 30),
          sharedWalkDuration: Duration.zero,
          sharedWaitDuration: Duration.zero,
          baselineSharedDuration: Duration.zero,
          myExtraMinutes: 0,
          friendExtraMinutes: 0,
          myExtraTransfers: 0,
          friendExtraTransfers: 0,
          detourMinutes: detour,
          sharedGainMinutes: gain,
          netTogetherMinutes: gain - detour,
        );

    test('reports the exchange rate an option actually achieved', () {
      expect(option(detour: 10, gain: 20).detourPerSharedMinute, 0.5);
    });

    test('has no rate when nothing was given up', () {
      final free = option(detour: 0, gain: 12);
      expect(free.isFree, isTrue);
      expect(free.detourPerSharedMinute, isNull);
    });
  });
}
