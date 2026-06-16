import 'package:flutter_test/flutter_test.dart';

import 'package:trans/main.dart';

void main() {
  testWidgets('app shell renders without startup services', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const TransApp());
    await tester.pump();

    expect(find.byType(TransApp), findsOneWidget);
  });
}
