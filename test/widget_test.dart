import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:trans/main.dart';

void main() {
  testWidgets('app shell renders without startup services', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(const {
      'current_tab_index': 0,
      'current_tab_id': 'routes',
    });
    await tester.pumpWidget(const TransApp());
    await tester.pump();

    expect(find.byType(TransApp), findsOneWidget);
  });

  testWidgets(
      'the swipe handle reveals Together and adds friend start above From',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(const {
      'current_tab_index': 0,
      'current_tab_id': 'routes',
    });
    await tester.pumpWidget(const TransApp());
    await tester.pump(const Duration(seconds: 3));

    final handle = find.byKey(const ValueKey('joint-plan-swipe-handle'));
    expect(handle, findsOneWidget);

    final initialHandleLeft = tester.getTopLeft(handle).dx;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    // The first small movement lets Flutter's horizontal drag recognizer win
    // the gesture arena; subsequent updates should track one-for-one.
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(tester.getTopLeft(handle).dx, initialHandleLeft);
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    final trackingStartLeft = tester.getTopLeft(handle).dx;

    await gesture.moveBy(const Offset(110, 0));
    await tester.pump();
    final firstHandleLeft = tester.getTopLeft(handle).dx;
    expect(firstHandleLeft, greaterThan(trackingStartLeft + 50));

    await gesture.moveBy(const Offset(110, 0));
    await tester.pump();
    final secondHandleLeft = tester.getTopLeft(handle).dx;
    expect(secondHandleLeft, greaterThan(firstHandleLeft + 50));

    final reveal = find.byKey(const ValueKey('joint-together-reveal'));
    expect(reveal, findsOneWidget);
    expect(
      tester.getTopRight(reveal).dx,
      moreOrLessEquals(tester.getTopLeft(handle).dx, epsilon: 0.75),
    );
    expect(
      tester
          .getCenter(find.byKey(const ValueKey('joint-plan-title-reveal')))
          .dy,
      moreOrLessEquals(
        tester
            .getCenter(find.byKey(const ValueKey('joint-plan-title-base')))
            .dy,
        epsilon: 0.1,
      ),
    );

    await gesture.moveBy(const Offset(110, 0));
    await tester.pump();
    final thirdHandleLeft = tester.getTopLeft(handle).dx;
    expect(thirdHandleLeft, greaterThan(secondHandleLeft + 50));

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    final friendField = find.byKey(const ValueKey('route-search-field-friend'));
    final fromField = find.byKey(const ValueKey('route-search-field-from'));
    expect(friendField, findsOneWidget);
    expect(fromField, findsOneWidget);
    expect(
      tester.getTopLeft(friendField).dy,
      lessThan(tester.getTopLeft(fromField).dy),
    );
    expect(find.byKey(const ValueKey('joint-plan-options')), findsNothing);
  });

  testWidgets('the completed reveal shows all of Together', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(const {
      'current_tab_index': 0,
      'current_tab_id': 'routes',
    });
    await tester.pumpWidget(const TransApp());
    await tester.pump(const Duration(seconds: 3));

    await tester.tap(find.byKey(const ValueKey('joint-plan-swipe-handle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final title = find.byKey(const ValueKey('joint-plan-title-reveal'));
    // The paragraph is laid out inside a forced-width box, so ask it what it
    // would take unconstrained: that is the width the glyphs really need, and
    // it is measured independently of the header's own measurement.
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: title, matching: find.byType(RichText)),
    );
    final scale = tester
        .widget<Transform>(
          find.ancestor(of: title, matching: find.byType(Transform)).first,
        )
        .transform
        .storage[0];
    expect(
      tester.getSize(find.byKey(const ValueKey('joint-together-reveal'))).width,
      greaterThanOrEqualTo(
        paragraph.getMaxIntrinsicWidth(double.infinity) * scale,
      ),
    );
  });
}
