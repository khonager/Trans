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
}
