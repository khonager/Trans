import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trans/config/app_theme.dart';
import 'package:trans/l10n/app_localizations.dart';
import 'package:trans/widgets/stop_departures_sheet.dart';

void main() {
  testWidgets('renders the initial service day without preloading other days',
      (tester) async {
    final pendingWeekendLoads =
        <DateTime, Completer<List<Map<String, dynamic>>>>{};

    Future<List<Map<String, dynamic>>> fakeLoader(
      String stationId, {
      DateTime? date,
      int maxResults = 250,
    }) async {
      final base = date ?? DateTime(2026, 4, 20);
      if (base.weekday == DateTime.saturday ||
          base.weekday == DateTime.sunday) {
        return pendingWeekendLoads
            .putIfAbsent(
              DateTime(base.year, base.month, base.day),
              () => Completer<List<Map<String, dynamic>>>(),
            )
            .future;
      }
      return List<Map<String, dynamic>>.generate(240, (index) {
        final time = DateTime(
          base.year,
          base.month,
          base.day,
        ).add(Duration(minutes: index * 6));
        final iso = time.toUtc().toIso8601String();
        return <String, dynamic>{
          'routeShortName': 'B$index',
          'headsign': 'Central Station',
          'place': <String, dynamic>{
            'stopId': stationId,
            'description': 'Main Stop',
            'track': '1',
            'scheduledDeparture': iso,
            'departure': iso,
          },
        };
      });
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: createTheme(const Color(0xFF4F46E5), Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StopDeparturesSheet(
            stopId: 'test-stop',
            stopName: 'Test Stop',
            date: DateTime(2026, 4, 20),
            departuresLoader: fakeLoader,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final listFinder = find.byType(ListView);
    expect(listFinder, findsOneWidget);
    expect(find.text('Mo-Fr'), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('So'), findsOneWidget);
    expect(find.text('Central Station'), findsWidgets);

    expect(pendingWeekendLoads, isEmpty);
  });

  testWidgets('uses the requested weekday date for the initial load',
      (tester) async {
    final requestedDates = <DateTime>[];
    final requestedMaxResults = <int>[];

    Future<List<Map<String, dynamic>>> fakeLoader(
      String stationId, {
      DateTime? date,
      int maxResults = 250,
    }) async {
      requestedDates.add(date!);
      requestedMaxResults.add(maxResults);
      return const <Map<String, dynamic>>[];
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: createTheme(const Color(0xFF4F46E5), Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StopDeparturesSheet(
            stopId: 'test-stop',
            stopName: 'Test Stop',
            date: DateTime(2026, 4, 24),
            departuresLoader: fakeLoader,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(requestedDates, [DateTime(2026, 4, 24)]);
    expect(requestedMaxResults, [6000]);
  });

  testWidgets('disambiguates duplicate stop area filter chips', (tester) async {
    Future<List<Map<String, dynamic>>> fakeLoader(
      String stationId, {
      DateTime? date,
      int maxResults = 250,
    }) async {
      final base = date ?? DateTime(2026, 4, 24);
      return <Map<String, dynamic>>[
        for (final entry in const [
          ('stop-a', 'Biebrich Rheinufer', '4'),
          ('stop-b', 'Suedfriedhof', '14'),
          ('stop-c', 'Dotzheim', '27'),
        ])
          <String, dynamic>{
            'routeShortName': entry.$3,
            'headsign': entry.$2,
            'place': <String, dynamic>{
              'stopId': entry.$1,
              'description': 'Wiesbaden Hauptbahnhof',
              'scheduledDeparture': base.toUtc().toIso8601String(),
              'departure': base.toUtc().toIso8601String(),
            },
          },
      ];
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: createTheme(const Color(0xFF4F46E5), Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StopDeparturesSheet(
            stopId: 'stop-a',
            stopName: 'Wiesbaden Hauptbahnhof',
            date: DateTime(2026, 4, 24),
            departuresLoader: fakeLoader,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(
      find.text('Biebrich Rheinufer · Wiesbaden Hauptbahnhof'),
      findsOneWidget,
    );
    expect(find.text('Suedfriedhof · Wiesbaden Hauptbahnhof'), findsOneWidget);
    expect(find.text('Dotzheim · Wiesbaden Hauptbahnhof'), findsOneWidget);
  });

  testWidgets('long-pressing a departure filters the list to that line',
      (tester) async {
    Future<List<Map<String, dynamic>>> fakeLoader(
      String stationId, {
      DateTime? date,
      int maxResults = 250,
    }) async {
      final day = date ?? DateTime(2026, 4, 24);
      Map<String, dynamic> departure(
        String line,
        String direction,
        int hour,
      ) {
        final time = DateTime(day.year, day.month, day.day, hour)
            .toUtc()
            .toIso8601String();
        return <String, dynamic>{
          'routeShortName': line,
          'headsign': direction,
          'place': <String, dynamic>{
            'stopId': stationId,
            'description': 'Test Stop',
            'scheduledDeparture': time,
            'departure': time,
          },
        };
      }

      return <Map<String, dynamic>>[
        departure('7', 'Town Hall', 9),
        departure('8', 'University', 10),
        departure('7', 'Central Station', 11),
      ];
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: createTheme(const Color(0xFF4F46E5), Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StopDeparturesSheet(
            stopId: 'test-stop',
            stopName: 'Test Stop',
            date: DateTime(2026, 4, 24, 10),
            departuresLoader: fakeLoader,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('University'), findsOneWidget);
    await tester.longPress(find.text('Town Hall'));
    await tester.pump();

    expect(find.text('Town Hall'), findsOneWidget);
    expect(find.text('Central Station'), findsOneWidget);
    expect(find.text('University'), findsNothing);
    expect(find.byIcon(Icons.close), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(find.text('University'), findsOneWidget);
  });

  testWidgets('greys departures before the sheet reference time',
      (tester) async {
    Future<List<Map<String, dynamic>>> fakeLoader(
      String stationId, {
      DateTime? date,
      int maxResults = 250,
    }) async {
      final day = date ?? DateTime(2026, 4, 24);
      Map<String, dynamic> departure(String direction, int hour) {
        final time = DateTime(day.year, day.month, day.day, hour)
            .toUtc()
            .toIso8601String();
        return <String, dynamic>{
          'routeShortName': direction == 'Past bus' ? '7' : '8',
          'headsign': direction,
          'place': <String, dynamic>{
            'stopId': stationId,
            'description': 'Test Stop',
            'scheduledDeparture': time,
            'departure': time,
          },
        };
      }

      return <Map<String, dynamic>>[
        departure('Past bus', 9),
        departure('Upcoming bus', 11),
      ];
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: createTheme(const Color(0xFF4F46E5), Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StopDeparturesSheet(
            stopId: 'test-stop',
            stopName: 'Test Stop',
            date: DateTime(2026, 4, 24, 10),
            departuresLoader: fakeLoader,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final pastOpacity = tester.widget<Opacity>(
      find.ancestor(
        of: find.text('Past bus'),
        matching: find.byType(Opacity),
      ),
    );
    final upcomingOpacity = tester.widget<Opacity>(
      find.ancestor(
        of: find.text('Upcoming bus'),
        matching: find.byType(Opacity),
      ),
    );

    expect(pastOpacity.opacity, 0.45);
    expect(upcomingOpacity.opacity, 1);
  });
}
