import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trans/widgets/friend_map_markers.dart';

void main() {
  test('buildFriendMapMarkers includes only shared locations', () {
    final markers = buildFriendMapMarkers([
      {
        'username': 'Alice',
        'latitude': 52.5,
        'longitude': 13.4,
        'avatar_emoji': '🚲',
        'theme_color': 0xFF008080,
      },
      {'username': 'Hidden'},
    ]);

    expect(markers, hasLength(1));
    expect(markers.single.point.latitude, 52.5);
    expect(markers.single.point.longitude, 13.4);
  });

  testWidgets('friend marker uses emoji or username initial', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Row(
          children: [
            FriendProfileMarker(username: 'Alice', emoji: '🚲'),
            FriendProfileMarker(username: 'Bob'),
          ],
        ),
      ),
    );

    expect(find.text('🚲'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
  });

  test('friendThemeColor supports stored integer and hex colors', () {
    expect(friendThemeColor(0xFF123456), const Color(0xFF123456));
    expect(friendThemeColor('#123456'), const Color(0xFF123456));
  });
}
