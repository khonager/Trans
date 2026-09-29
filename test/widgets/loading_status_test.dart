import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trans/l10n/app_localizations.dart';
import 'package:trans/widgets/loading_status.dart';

void main() {
  testWidgets('shows the active stage and explains a long wait', (tester) async {
    Widget app(String message) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: LoadingStatus(message: message)),
        );

    await tester.pumpWidget(app('Finding your starting place…'));
    expect(find.text('Finding your starting place…'), findsOneWidget);
    expect(find.text('This is taking longer than expected…'), findsNothing);

    await tester.pumpWidget(app('Checking available routes…'));
    expect(find.text('Checking available routes…'), findsOneWidget);
    expect(find.text('Finding your starting place…'), findsNothing);

    await tester.pump(const Duration(seconds: 8));
    expect(find.text('This is taking longer than expected…'), findsOneWidget);
  });
}
