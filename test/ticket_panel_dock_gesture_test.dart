import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trans/config/app_theme.dart';
import 'package:trans/l10n/app_localizations.dart';
import 'package:trans/widgets/ticket_panel.dart';

void main() {
  Future<(TestGesture, List<bool>, List<double>)> startDockGesture(
    WidgetTester tester, {
    required VoidCallback onDockRequested,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final armedStates = <bool>[];
    final progressValues = <double>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const [
            TransColors(seed: Color(0xFF4F46E5), brightness: Brightness.light),
          ],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TicketPanel(
            onDockGestureArmedChanged: armedStates.add,
            onDockGestureProgressChanged: progressValues.add,
            onDockRequested: onDockRequested,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('My Ticket')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    return (gesture, armedStates, progressValues);
  }

  testWidgets('dock drag can scrub between visible and docked repeatedly',
      (WidgetTester tester) async {
    var dockRequests = 0;
    final (gesture, armedStates, progressValues) = await startDockGesture(
      tester,
      onDockRequested: () => dockRequests += 1,
    );

    await gesture.moveBy(const Offset(0, 80));
    await tester.pump();
    expect(armedStates.last, isTrue);
    expect(progressValues.last, greaterThan(0.5));

    await gesture.moveBy(const Offset(0, -100));
    await tester.pump();
    expect(armedStates.last, isTrue);
    expect(progressValues.last, 0);

    await gesture.moveBy(const Offset(0, 110));
    await tester.pump();
    expect(progressValues.last, greaterThan(0.5));

    await gesture.moveBy(const Offset(0, -70));
    await tester.pump();
    expect(progressValues.last, lessThan(0.5));

    await gesture.moveBy(const Offset(0, 70));
    await tester.pump();
    expect(progressValues.last, greaterThan(0.5));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(dockRequests, 1);
  });

  testWidgets('releasing on the visible side never requests docking',
      (WidgetTester tester) async {
    var dockRequests = 0;
    final (gesture, armedStates, progressValues) = await startDockGesture(
      tester,
      onDockRequested: () => dockRequests += 1,
    );

    await gesture.moveBy(const Offset(0, 80));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -100));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(progressValues.last, 0);
    expect(armedStates.last, isFalse);
    expect(dockRequests, 0);
  });

  testWidgets('restore progress scrubs the same panel in both directions',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    double? restoreProgress;
    var settleToNavigation = false;
    var cancelCompletions = 0;
    late StateSetter rebuild;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const [
            TransColors(seed: Color(0xFF4F46E5), brightness: Brightness.light),
          ],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return TicketPanel(
                interactiveRestoreProgress: restoreProgress,
                settleRestoreBackToNavigation: settleToNavigation,
                onInteractiveRestoreCancelled: () => cancelCompletions += 1,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    double slideOffset() => tester
        .widget<SlideTransition>(
          find
              .descendant(
                of: find.byType(TicketPanel),
                matching: find.byType(SlideTransition),
              )
              .first,
        )
        .position
        .value
        .dy;

    rebuild(() => restoreProgress = 0);
    await tester.pump();
    final dockedOffset = slideOffset();
    expect(dockedOffset, greaterThan(0));

    rebuild(() => restoreProgress = 0.8);
    await tester.pump();
    final mostlyVisibleOffset = slideOffset();
    expect(mostlyVisibleOffset, lessThan(dockedOffset));

    rebuild(() => restoreProgress = 0.2);
    await tester.pump();
    expect(slideOffset(), greaterThan(mostlyVisibleOffset));

    rebuild(() => restoreProgress = 1);
    await tester.pump();
    expect(slideOffset(), 0);

    rebuild(() {
      restoreProgress = 0;
      settleToNavigation = true;
    });
    await tester.pump();
    rebuild(() => restoreProgress = null);
    await tester.pumpAndSettle();

    expect(slideOffset(), dockedOffset);
    expect(cancelCompletions, 1);
  });
}
