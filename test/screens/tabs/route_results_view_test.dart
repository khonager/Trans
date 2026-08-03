import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trans/config/app_theme.dart';
import 'package:trans/l10n/app_localizations.dart';
import 'package:trans/models/journey.dart';
import 'package:trans/models/station.dart';
import 'package:trans/screens/tabs/route_results_view.dart';

final _destination = Station(id: 'destination', name: 'Destination');

Journey _journey(int minute, {int rideCount = 1}) {
  final departure = DateTime(2026, 8, 1, 10).add(Duration(minutes: minute));
  final arrival = departure.add(const Duration(minutes: 25));
  return Journey(
    steps: List.generate(
      rideCount,
      (index) => JourneyStep(
        type: 'ride',
        line: index == 0
            ? 'route-$minute'
            : 'connection-$minute-$index-express-service',
        instruction: '',
        duration: '25 min',
        departureTime: '10:00',
        arrivalTime: '10:25',
      ),
    ),
    departure: departure,
    arrival: arrival,
    duration: const Duration(minutes: 25),
    transferCount: rideCount - 1,
    totalWaitTime: Duration.zero,
    rawSource: const {},
    source: 'test',
  );
}

Journey _journeyWithPriorities({
  required String label,
  required int walkingMinutes,
  required int waitMinutes,
}) {
  final departure = DateTime(2026, 8, 1, 15);
  return Journey(
    steps: [
      JourneyStep(
        type: 'ride',
        line: label,
        instruction: '',
        duration: '30 min',
        departureTime: '15:00',
        arrivalTime: '15:30',
      ),
    ],
    departure: departure,
    arrival: departure.add(const Duration(minutes: 30)),
    duration: const Duration(minutes: 30),
    transferCount: 0,
    totalWaitTime: Duration(minutes: waitMinutes),
    totalWalkingDuration: Duration(minutes: walkingMinutes),
    rawSource: const {},
    source: 'test',
  );
}

class _RouteResultsHarness extends StatefulWidget {
  final List<Journey> initialCandidates;

  const _RouteResultsHarness({
    super.key,
    required this.initialCandidates,
  });

  @override
  State<_RouteResultsHarness> createState() => _RouteResultsHarnessState();
}

class _RouteResultsHarnessState extends State<_RouteResultsHarness> {
  final ScrollController controller = ScrollController();
  late List<Journey> candidates = widget.initialCandidates;
  Completer<void>? earlierLoad;
  Completer<void>? laterLoad;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _loadEarlier() {
    earlierLoad = Completer<void>();
    return earlierLoad!.future;
  }

  Future<void> _loadLater() {
    laterLoad = Completer<void>();
    return laterLoad!.future;
  }

  void addEarlier(List<Journey> journeys, {bool finishLoad = false}) {
    setState(() => candidates = [...journeys, ...candidates]);
    if (finishLoad) earlierLoad?.complete();
  }

  void addLater(List<Journey> journeys, {bool finishLoad = false}) {
    setState(() => candidates = [...candidates, ...journeys]);
    if (finishLoad) laterLoad?.complete();
  }

  @override
  Widget build(BuildContext context) {
    return RouteResultsView(
      candidates: candidates,
      onSelect: (_) {},
      onBack: () {},
      onLoadEarlier: _loadEarlier,
      onLoadLater: _loadLater,
      destination: _destination,
      scrollController: controller,
    );
  }
}

Future<_RouteResultsHarnessState> _pumpHarness(
  WidgetTester tester,
  GlobalKey<_RouteResultsHarnessState> key,
) async {
  await tester.binding.setSurfaceSize(const Size(500, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: createTheme(const Color(0xFF4F46E5), Brightness.light).copyWith(
        platform: TargetPlatform.android,
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: _RouteResultsHarness(
          key: key,
          initialCandidates: List.generate(10, (index) => _journey(index * 10)),
        ),
      ),
    ),
  );
  await tester.pump();
  return key.currentState!;
}

({String label, double top}) _firstVisibleRouteLabel(
  WidgetTester tester,
  Iterable<Journey> candidates,
) {
  final listRect = tester.getRect(find.byType(ListView));
  for (final journey in candidates) {
    final label = journey.steps.first.line;
    final finder = find.text(label);
    if (finder.evaluate().isEmpty) continue;
    final rect = tester.getRect(finder);
    if (rect.bottom > listRect.top && rect.top < listRect.bottom) {
      return (label: label, top: rect.top);
    }
  }
  throw TestFailure('No visible route label found.');
}

void main() {
  testWidgets(
      'delayed earlier batches preserve the route visible after the user scrolls',
      (tester) async {
    final key = GlobalKey<_RouteResultsHarnessState>();
    final state = await _pumpHarness(tester, key);

    await tester.tap(find.text('Load Earlier'));
    await tester.pump();
    state.controller.jumpTo(430);
    await tester.pump();

    final before = _firstVisibleRouteLabel(tester, state.candidates);
    state.addEarlier(
      [_journey(-30, rideCount: 4), _journey(-20), _journey(-10, rideCount: 3)],
      finishLoad: true,
    );
    await tester.pump(); // measure the variable-height phone cards

    // The measurement frame still paints the old viewport. There must not be
    // a one-frame estimate/jump before the exact correction is available.
    expect(
      tester.getTopLeft(find.text(before.label)).dy,
      closeTo(before.top, 0.5),
    );
    expect(find.text('route--30'), findsNothing);

    await tester.pump(); // paint the expanded list at its corrected offset
    await tester.pumpAndSettle();

    final afterFirstBatch = tester.getTopLeft(find.text(before.label)).dy;
    expect(afterFirstBatch, closeTo(before.top, 0.5));

    // A provider may deliver another partial batch after the load trigger has
    // already returned. Preserve whichever route the user moved to meanwhile.
    state.controller.jumpTo(state.controller.offset + 180);
    await tester.pump();
    final beforeSecondBatch = _firstVisibleRouteLabel(tester, state.candidates);
    state
        .addEarlier([_journey(-50, rideCount: 2), _journey(-40, rideCount: 4)]);
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text(beforeSecondBatch.label)).dy,
      closeTo(beforeSecondBatch.top, 0.5),
    );
  });

  testWidgets('later results append without changing the current viewport',
      (tester) async {
    final key = GlobalKey<_RouteResultsHarnessState>();
    final state = await _pumpHarness(tester, key);

    state.controller.jumpTo(state.controller.position.maxScrollExtent);
    await tester.pump();
    await tester.tap(find.text('Load Later'));
    await tester.pump();

    // Move away from the trigger while the request is pending.
    state.controller.jumpTo(state.controller.offset - 300);
    await tester.pump();
    final offsetBefore = state.controller.offset;
    final before = _firstVisibleRouteLabel(tester, state.candidates);

    state.addLater(
      [_journey(100, rideCount: 4), _journey(110), _journey(120, rideCount: 3)],
      finishLoad: true,
    );
    await tester.pumpAndSettle();

    expect(state.controller.offset, closeTo(offsetBefore, 0.5));
    expect(
      tester.getTopLeft(find.text(before.label)).dy,
      closeTo(before.top, 0.5),
    );
  });

  testWidgets('ordered sort priorities break ties in the configured order',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final shortWait = _journeyWithPriorities(
      label: 'short-wait',
      walkingMinutes: 20,
      waitMinutes: 0,
    );
    final shortWalk = _journeyWithPriorities(
      label: 'short-walk',
      walkingMinutes: 5,
      waitMinutes: 12,
    );

    await tester.pumpWidget(MaterialApp(
      theme: createTheme(const Color(0xFF4F46E5), Brightness.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: RouteResultsView(
          candidates: [shortWait, shortWalk],
          onSelect: (_) {},
          onBack: () {},
          destination: _destination,
          sortOrder: const [
            RouteSortOption.earliestDeparture,
            RouteSortOption.leastWalking,
            RouteSortOption.shortestWait,
            RouteSortOption.earliestArrival,
            RouteSortOption.shortestDuration,
            RouteSortOption.leastTransfers,
          ],
        ),
      ),
    ));
    await tester.pump();

    expect(
      tester.getTopLeft(find.text('short-walk')).dy,
      lessThan(tester.getTopLeft(find.text('short-wait')).dy),
    );
  });

  testWidgets('long-press dragging a sort chip updates its priority',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    List<RouteSortOption>? reordered;
    RouteSortOption? selected;

    await tester.pumpWidget(MaterialApp(
      theme: createTheme(const Color(0xFF4F46E5), Brightness.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: RouteResultsView(
          candidates: [_journey(0)],
          onSelect: (_) {},
          onBack: () {},
          destination: _destination,
          onSortOrderChanged: (value) => reordered = value,
          onSortChanged: (value) => selected = value,
        ),
      ),
    ));
    await tester.pump();

    final dragged = find.byKey(
      const ValueKey<String>('route-sort-earliestArrival'),
    );
    final target = find.byKey(
      const ValueKey<String>('route-sort-earliestDeparture'),
    );
    final targetCenter = tester.getCenter(target);
    final gesture = await tester.startGesture(tester.getCenter(dragged));
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.moveTo(targetCenter);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(reordered?.first, RouteSortOption.earliestArrival);
    expect(selected, RouteSortOption.earliestArrival);
  });
}
