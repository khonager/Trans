import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trans/config/app_theme.dart';
import 'package:trans/models/journey.dart';
import 'package:trans/services/transport_api.dart';
import 'package:trans/widgets/route_shape_sketch.dart';

JourneyStep _step({
  required String type,
  List<dynamic>? path,
  double? startLat,
  double? startLng,
  double? endLat,
  double? endLng,
  bool isWalking = false,
}) =>
    JourneyStep(
      type: type,
      line: 'RB21',
      instruction: '',
      duration: '10 min',
      departureTime: '10:00',
      arrivalTime: '10:10',
      isWalking: isWalking,
      path: path,
      startLat: startLat,
      startLng: startLng,
      endLat: endLat,
      endLng: endLng,
    );

Journey _journey(List<JourneyStep> steps) => Journey(
      steps: steps,
      departure: DateTime(2026, 8, 1, 10),
      arrival: DateTime(2026, 8, 1, 10, 30),
      duration: const Duration(minutes: 30),
      transferCount: 0,
      totalWaitTime: Duration.zero,
      rawSource: const {},
      source: 'motis',
    );

void main() {
  group('routeShapeSegments', () {
    test('uses leg geometry when present', () {
      final segments = routeShapeSegments(_journey([
        _step(type: 'ride', path: const [
          [50.0, 8.0],
          [50.1, 8.1],
          [50.2, 8.05],
        ]),
      ]));

      expect(segments, hasLength(1));
      expect(segments.single.isWalk, isFalse);
      expect(segments.single.points, hasLength(3));
      expect(routeShapeIsRenderable(segments), isTrue);
    });

    test('falls back to endpoints when a leg has no geometry', () {
      final segments = routeShapeSegments(_journey([
        _step(
          type: 'walk',
          isWalking: true,
          startLat: 50.0,
          startLng: 8.0,
          endLat: 50.01,
          endLng: 8.01,
        ),
      ]));

      expect(segments, hasLength(1));
      expect(segments.single.isWalk, isTrue);
      expect(segments.single.points, [
        [50.0, 8.0],
        [50.01, 8.01],
      ]);
    });

    test('drops wait steps, junk coordinates and legs without any position',
        () {
      final segments = routeShapeSegments(_journey([
        _step(type: 'wait', startLat: 50.0, startLng: 8.0),
        _step(type: 'ride'),
        _step(type: 'ride', path: const [
          [50.0, 8.0],
          ['x', 'y'],
          [999.0, 8.1],
          [50.0, 8.0],
          [50.3, 8.4],
        ]),
      ]));

      expect(segments, hasLength(1));
      expect(segments.single.points, [
        [50.0, 8.0],
        [50.3, 8.4],
      ]);
    });

    test('is not renderable when the route collapses to a point', () {
      final segments = routeShapeSegments(_journey([
        _step(type: 'ride', path: const [
          [50.0, 8.0],
          [50.00001, 8.00001],
        ]),
      ]));

      expect(segments, hasLength(1));
      expect(routeShapeIsRenderable(segments), isFalse);
    });
  });

  group('v6 leg geometry', () {
    test('decodes GeoJSON point features into [lat, lng] pairs', () {
      final path = TransportApi.decodeV6LegPath({
        'polyline': {
          'features': [
            {
              'geometry': {
                'coordinates': [8.0, 50.0]
              }
            },
            {
              'geometry': {
                'coordinates': [8.1, 50.1]
              }
            },
          ],
        },
      });

      expect(path, [
        [50.0, 8.0],
        [50.1, 8.1],
      ]);
    });

    test('returns null when a leg carries no usable polyline', () {
      expect(TransportApi.decodeV6LegPath(const {}), isNull);
      expect(
        TransportApi.decodeV6LegPath(const {
          'polyline': {
            'features': [
              {
                'geometry': {
                  'coordinates': [8.0, 50.0]
                }
              }
            ]
          }
        }),
        isNull,
      );
    });

    test('attaches decoded paths to every leg of a journey', () {
      final journey = <String, dynamic>{
        'legs': [
          <String, dynamic>{
            'polyline': {
              'features': [
                {
                  'geometry': {
                    'coordinates': [8.0, 50.0]
                  }
                },
                {
                  'geometry': {
                    'coordinates': [8.1, 50.1]
                  }
                },
              ]
            }
          },
          <String, dynamic>{'decodedPath': 'untouched'},
        ],
      };

      TransportApi.attachV6LegPaths(journey);

      final legs = journey['legs'] as List;
      expect((legs[0] as Map)['decodedPath'], [
        [50.0, 8.0],
        [50.1, 8.1],
      ]);
      expect((legs[1] as Map)['decodedPath'], 'untouched');
    });
  });

  group('RouteShapeSketch widget', () {
    Widget host(Journey journey, double width) => MaterialApp(
          theme: createTheme(const Color(0xFF4F46E5), Brightness.light),
          home: Scaffold(
            body: SizedBox(
              width: width,
              child: RouteShapeSketch(journey: journey),
            ),
          ),
        );

    testWidgets('paints a route that spans real ground', (tester) async {
      await tester.pumpWidget(host(
        _journey([
          _step(type: 'ride', path: const [
            [50.0, 8.0],
            [50.1, 8.2],
            [50.05, 8.4],
          ]),
        ]),
        320,
      ));

      expect(find.byType(CustomPaint), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders nothing when the journey has no usable geometry',
        (tester) async {
      await tester.pumpWidget(host(_journey([_step(type: 'ride')]), 320));

      expect(
        find.descendant(
          of: find.byType(RouteShapeSketch),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
    });
  });
}
