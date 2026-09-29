import 'package:flutter_test/flutter_test.dart';
import 'package:trans/models/journey.dart';
import 'package:trans/models/station.dart';
import 'package:trans/screens/tabs/routes_tab.dart';
import 'package:trans/services/journey_detection_service.dart';

final _day = DateTime(2026, 8, 31, 8);

Journey _journey(String line, {int startMinute = 0}) {
  final departure = _day.add(Duration(minutes: startMinute));
  final arrival = departure.add(const Duration(minutes: 30));
  return Journey(
    steps: [
      JourneyStep(
        type: 'ride',
        line: line,
        instruction: '',
        duration: '30 min',
        departureTime: '08:00',
        arrivalTime: '08:30',
        tripId: 'trip-$line-$startMinute',
        dateTime: departure,
        plannedDeparture: departure,
        plannedArrival: arrival,
      ),
    ],
    departure: departure,
    arrival: arrival,
    duration: const Duration(minutes: 30),
    transferCount: 0,
    totalWaitTime: Duration.zero,
    rawSource: const {},
    source: 'test',
  );
}

RouteTab _tab({
  required String id,
  String destination = 'Central',
  List<Journey>? candidates,
  List<Journey> stack = const [],
  Journey? activeJourney,
  String? companionName,
}) =>
    RouteTab(
      id: id,
      title: destination,
      subtitle: '',
      eta: '',
      totalDuration: '',
      destination: Station(id: 'stop:$destination', name: destination),
      steps: const [],
      candidates: candidates,
      stack: stack,
      activeJourney: activeJourney,
      companionName: companionName,
      searchSettings: RouteSearchSettings(when: _day, isArrival: false),
    );

void main() {
  group('which journeys may count as the user travelling', () {
    test("a companion's tab never becomes a candidate", () {
      final mine = _journey('RE 1');
      final theirs = _journey('S 8', startMinute: 5);

      final candidates = journeyDetectionCandidates(
        tabs: [
          _tab(id: 'mine', activeJourney: mine, candidates: [mine]),
          _tab(
            id: 'theirs',
            companionName: 'Alex',
            activeJourney: theirs,
            candidates: [theirs],
          ),
        ],
      );

      expect(candidates, hasLength(1));
      expect(candidates.single.journey, same(mine));
      expect(candidates.single.tabId, 'mine');
    });

    test('the opened journey ranks above the rest of the result list', () {
      final selected = _journey('RE 1');
      final alternative = _journey('RB 2', startMinute: 10);

      final candidates = journeyDetectionCandidates(
        tabs: [
          _tab(
            id: 'tab',
            activeJourney: selected,
            stack: [selected],
            candidates: [selected, alternative],
          ),
        ],
      );

      final bySource = {
        for (final candidate in candidates)
          candidate.journey.steps.first.line: candidate.source,
      };
      expect(bySource['RE 1'], JourneyDetectionSource.selected);
      expect(bySource['RB 2'], JourneyDetectionSource.searchResult);
    });

    test('one journey open in two tabs is counted once, at its best source',
        () {
      final journey = _journey('RE 1');

      final candidates = journeyDetectionCandidates(
        tabs: [
          _tab(id: 'search', candidates: [journey]),
          _tab(id: 'opened', activeJourney: journey, candidates: [journey]),
        ],
      );

      expect(candidates, hasLength(1),
          reason: 'duplicates would split the confidence margin');
      expect(candidates.single.source, JourneyDetectionSource.selected);
      expect(candidates.single.tabId, 'opened');
    });

    test('a journey the position contradicted stays suppressed', () {
      final journey = _journey('RE 1');
      final key = '${'tab'}:${journeyListKeyForTesting(journey)}';

      final candidates = journeyDetectionCandidates(
        tabs: [
          _tab(id: 'tab', candidates: [journey])
        ],
        suppressedKeys: {key},
      );

      expect(candidates, isEmpty);
    });

    test('saved connections are candidates even with no tab open', () {
      final saved = _journey('RE 1');

      final candidates = journeyDetectionCandidates(
        tabs: const [],
        savedCandidates: savedJourneyDetectionCandidates(
          [
            {
              'connectionKey': 'saved-1',
              'to': {'id': 'stop:Offenbach', 'name': 'Offenbach'},
              'journey': const {'legs': []},
            },
          ],
          (_, __) => saved,
        ),
      );

      expect(candidates.single.source, JourneyDetectionSource.saved);
      expect(candidates.single.key, 'saved:saved-1');
      expect(candidates.single.destinationName, 'Offenbach');
      expect(candidates.single.tabId, isNull);
    });

    test('an open tab wins over the same connection from the saved list', () {
      final journey = _journey('RE 1');

      final candidates = journeyDetectionCandidates(
        tabs: [_tab(id: 'tab', activeJourney: journey)],
        savedCandidates: savedJourneyDetectionCandidates(
          [
            {
              'connectionKey': 'saved-1',
              'to': {'id': 'stop:Central', 'name': 'Central'},
              'journey': const {'legs': []},
            },
          ],
          (_, __) => journey,
        ),
      );

      expect(candidates, hasLength(1));
      expect(candidates.single.source, JourneyDetectionSource.selected);
    });
  });

  group('saved journeys that cannot be used', () {
    test('skips entries without a stored journey or destination', () {
      final candidates = savedJourneyDetectionCandidates(
        [
          {
            'connectionKey': 'no-journey',
            'to': const {'name': 'Central'}
          },
          {
            'connectionKey': 'no-destination',
            'journey': const {'legs': []}
          },
          {
            'connectionKey': 'blank-destination',
            'to': const {'name': ''},
            'journey': const {'legs': []},
          },
        ],
        (_, __) => _journey('RE 1'),
      );

      expect(candidates, isEmpty);
    });

    test('skips entries the app can no longer parse', () {
      final candidates = savedJourneyDetectionCandidates(
        [
          {
            'connectionKey': 'legacy',
            'to': const {'name': 'Central'},
            'journey': const {'legs': []},
          },
        ],
        (_, __) => null,
      );

      expect(candidates, isEmpty);
    });
  });
}
