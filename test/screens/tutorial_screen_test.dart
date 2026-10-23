import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trans/config/app_theme.dart';
import 'package:trans/data/tutorial_content.dart';
import 'package:trans/screens/tutorial_screen.dart';

Widget app({Locale locale = const Locale('en')}) => MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('de')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: AppTheme.lightTheme(Colors.blue),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppTutorial(context),
            child: const Text('Open guide'),
          ),
        ),
      ),
    );

Future<void> openGuide(WidgetTester tester) async {
  await tester.tap(find.text('Open guide'));
  await tester.pumpAndSettle();
}

Future<void> searchFor(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pumpAndSettle();
}

Future<void> toggleFirstLesson(WidgetTester tester) async {
  await tester.ensureVisible(
      find.widgetWithText(ExpansionTile, 'Find your first route'));
  await tester.tap(find.widgetWithText(ExpansionTile, 'Find your first route'));
  await tester.pumpAndSettle();
  final button = find.byKey(const ValueKey('complete-search'));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('every lesson has a stable unique ID, category, and bilingual content',
      () {
    expect(tutorialLessons.map((l) => l.id).toSet().length,
        tutorialLessons.length);
    for (final lesson in tutorialLessons) {
      expect(tutorialGroups.any((g) => g.id == lesson.group), isTrue);
      for (final copy in [lesson.english, lesson.german]) {
        expect(copy.length, 4);
        expect(copy.every((s) => s.trim().isNotEmpty), isTrue);
      }
    }
  });

  testWidgets('fullscreen guide can be dismissed without completing anything',
      (tester) async {
    await tester.pumpWidget(app());
    await openGuide(tester);
    expect(find.text('Explore Trans'), findsOneWidget);
    final context = tester.element(find.byType(TutorialScreen));
    expect((ModalRoute.of(context)! as MaterialPageRoute).fullscreenDialog,
        isTrue);
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    expect(find.text('Open guide'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(TutorialScreen.progressKey), isNull);
  });

  testWidgets('completion persists after reopening and can be undone',
      (tester) async {
    await tester.pumpWidget(app());
    await openGuide(tester);
    await searchFor(tester, 'Find your first route');
    await toggleFirstLesson(tester);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(TutorialScreen.progressKey), ['search']);
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    await openGuide(tester);
    expect(find.text('1 of ${tutorialLessons.length} learned'), findsOneWidget);
    await searchFor(tester, 'Find your first route');
    await toggleFirstLesson(tester);
    expect(prefs.getStringList(TutorialScreen.progressKey), isEmpty);
  });

  testWidgets('search and unfinished filter combine without changing progress',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      TutorialScreen.progressKey: ['search', 'removed-lesson'],
    });
    await tester.pumpWidget(app());
    await openGuide(tester);
    expect(find.text('1 of ${tutorialLessons.length} learned'), findsOneWidget);
    await searchFor(tester, 'Find your first route');
    await tester.ensureVisible(find.byType(FilterChip));
    await tester.tap(find.byType(FilterChip));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ExpansionTile, 'Find your first route'),
        findsNothing);
    expect(find.text('No matching lessons. Try another search or filter.'),
        findsOneWidget);
    await tester.tap(find.byType(FilterChip));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ExpansionTile, 'Find your first route'),
        findsOneWidget);
  });

  testWidgets('German guide supports narrow screens and large text',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(app(locale: const Locale('de')));
    await openGuide(tester);
    expect(find.text('Trans entdecken'), findsOneWidget);
    await tester.scrollUntilVisible(find.byType(TextField), 200);
    await searchFor(tester, 'Die erste Route finden');
    await tester.ensureVisible(
        find.widgetWithText(ExpansionTile, 'Die erste Route finden'));
    await tester
        .tap(find.widgetWithText(ExpansionTile, 'Die erste Route finden'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('complete-search')));
    expect(find.text('So funktioniert es'), findsOneWidget);
    expect(find.text('Zum Beispiel…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
