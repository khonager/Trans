import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trans/models/journey.dart';
import 'package:trans/screens/map_screen.dart';

void main() {
  JourneyStep step(String type) => JourneyStep(
        type: type,
        line: type,
        instruction: type,
        duration: '5 min',
        departureTime: '10:00',
        arrivalTime: '10:05',
      );

  group('Google Maps directions mode', () {
    test('uses bicycling for a focused bike step', () {
      expect(
        googleMapsTravelModeForRoute(
          steps: [step('walk'), step('bike')],
          focusStep: step('bike'),
        ),
        'bicycling',
      );
    });

    test('uses bicycling for pure bike routes', () {
      expect(
        googleMapsTravelModeForRoute(steps: [step('bike')]),
        'bicycling',
      );
    });

    test('keeps walking mode for mixed or walking routes', () {
      expect(
        googleMapsTravelModeForRoute(steps: [step('bike'), step('ride')]),
        'walking',
      );
      expect(
        googleMapsTravelModeForRoute(
          steps: [step('bike')],
          focusStep: step('walk'),
        ),
        'walking',
      );
    });

    test('serializes the selected travel mode into the URL', () {
      final uri = buildGoogleMapsDirectionsUri(
        start: const LatLng(40.0, 4.0),
        end: const LatLng(40.1, 4.1),
        travelMode: 'bicycling',
      );

      expect(uri.queryParameters['travelmode'], 'bicycling');
      expect(uri.queryParameters['origin'], '40.0,4.0');
      expect(uri.queryParameters['destination'], '40.1,4.1');
    });
  });
}
