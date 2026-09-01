import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trans/config/app_theme.dart';
import 'package:trans/models/joint_plan_friend.dart';
import 'package:trans/widgets/joint_friend_chips.dart';

const _seed = Color(0xFFEC4899);
final _now = DateTime.utc(2026, 8, 30, 12);

JointPlanFriend _friend({
  required String id,
  required String name,
  Duration? age,
}) =>
    JointPlanFriend(
      id: id,
      name: name,
      latitude: 50,
      longitude: 8,
      locationUpdatedAt: age == null ? null : _now.subtract(age),
      themeColor: 0xFF3366FF,
    );

Future<JointPlanFriend?> _pumpChips(
  WidgetTester tester, {
  required List<JointPlanFriend> friends,
  String? selectedId,
  bool german = false,
}) async {
  JointPlanFriend? tapped;
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.lightTheme(_seed),
    home: Scaffold(
      body: JointFriendChips(
        friends: friends,
        selectedFriendId: selectedId,
        german: german,
        now: _now,
        onSelected: (friend) => tapped = friend,
      ),
    ),
  ));
  return tapped;
}

void main() {
  testWidgets('shows nothing when no friend shares a location', (tester) async {
    await _pumpChips(tester, friends: const []);

    expect(find.byKey(const ValueKey('joint-friend-chips')), findsNothing);
    expect(find.text('SHARING A LOCATION'), findsNothing);
  });

  testWidgets('lists every friend who shares a location', (tester) async {
    await _pumpChips(tester, friends: [
      _friend(id: 'a', name: 'Mara', age: const Duration(minutes: 3)),
      _friend(id: 'b', name: 'Jo', age: const Duration(minutes: 40)),
    ]);

    expect(find.text('Mara'), findsOneWidget);
    expect(find.text('Jo'), findsOneWidget);
    expect(find.text('3 min ago'), findsOneWidget);
    expect(find.text('40 min ago'), findsOneWidget);
  });

  testWidgets('reports the friend that was tapped', (tester) async {
    JointPlanFriend? tapped;
    final friends = [
      _friend(id: 'a', name: 'Mara', age: const Duration(minutes: 3)),
      _friend(id: 'b', name: 'Jo', age: const Duration(minutes: 4)),
    ];
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme(_seed),
      home: Scaffold(
        body: JointFriendChips(
          friends: friends,
          selectedFriendId: null,
          german: false,
          now: _now,
          onSelected: (friend) => tapped = friend,
        ),
      ),
    ));

    await tester.tap(find.byKey(const ValueKey('joint-friend-chip-b')));
    expect(tapped, same(friends[1]));
  });

  testWidgets('marks the selected friend', (tester) async {
    await _pumpChips(
      tester,
      friends: [
        _friend(id: 'a', name: 'Mara', age: const Duration(minutes: 3))
      ],
      selectedId: 'a',
    );

    final chip = tester.widget<Container>(
      find
          .descendant(
            of: find.byKey(const ValueKey('joint-friend-chip-a')),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = chip.decoration as BoxDecoration;
    expect(decoration.border!.top.color, _seed);
  });

  group('freshness label', () {
    test('describes recent, hourly, and day-old positions', () {
      expect(
        JointFriendChips.freshnessLabel(
          _friend(id: 'a', name: 'Mara', age: const Duration(seconds: 20)),
          german: false,
          now: _now,
        ),
        'just now',
      );
      expect(
        JointFriendChips.freshnessLabel(
          _friend(id: 'a', name: 'Mara', age: const Duration(hours: 3)),
          german: false,
          now: _now,
        ),
        '3 h ago',
      );
      expect(
        JointFriendChips.freshnessLabel(
          _friend(id: 'a', name: 'Mara', age: const Duration(days: 2)),
          german: true,
          now: _now,
        ),
        'vor 2 T.',
      );
    });

    test('falls back when nothing is known about the position', () {
      expect(
        JointFriendChips.freshnessLabel(
          _friend(id: 'a', name: 'Mara'),
          german: false,
          now: _now,
        ),
        'Location',
      );
    });
  });
}
