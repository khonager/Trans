import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trans/models/journey.dart';
import 'package:trans/widgets/route_share_ticket.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  testWidgets('RouteShareTicket builds correctly with journey info', (WidgetTester tester) async {
    final now = DateTime.now();
    final journey = Journey(
      steps: [
        JourneyStep(
          type: 'ride',
          line: 'IC 1234',
          instruction: 'Ride to Berlin',
          duration: '30 min',
          departureTime: '10:00',
          arrivalTime: '10:30',
          startStationName: 'Hamburg',
          destinationName: 'Berlin',
        )
      ],
      departure: now,
      arrival: now.add(const Duration(minutes: 30)),
      duration: const Duration(minutes: 30),
      transferCount: 0,
      totalWaitTime: Duration.zero,
      rawSource: {},
      source: 'db',
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: RouteShareTicket(
            journey: journey,
            username: 'TestUser',
          ),
        ),
      ),
    ));

    expect(find.text('IC 1234'), findsOneWidget);
    expect(find.text('Berlin'), findsOneWidget); // Destination
    expect(find.text('30 min'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
  });
}
