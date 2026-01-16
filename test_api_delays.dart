
import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  // Test V6 API for delays
  final baseUrl = 'https://v6.db.transport.rest/journeys';
  // Example: Frankfurt Main Hbf to Berlin Hbf (long distance usually has delays)
  final fromId = '8000105';
  final toId = '8011160'; 
  
  final uri = Uri.parse('$baseUrl?from=$fromId&to=$toId&results=3&stopovers=true');
  
  print("Fetching $uri");
  try {
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final journeys = data['journeys'] as List;
      for (var j in journeys) {
        final legs = j['legs'] as List;
        for (var leg in legs) {
          if (leg['line'] != null) {
            print("Leg: ${leg['line']['name']}");
            print("  Planned Dep: ${leg['plannedDeparture']}");
            print("  Actual Dep : ${leg['departure']}");
            print("  Delay      : ${leg['departureDelay']}");
            print("  Cancelled  : ${leg['cancelled']}");
          }
        }
      }
    } else {
      print("Error: ${response.statusCode} - ${response.body}");
    }
  } catch (e) {
    print("Exception: $e");
  }
}
