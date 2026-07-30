class JourneySignalLevel {
  static const int minimum = 0;
  static const int maximum = 8;
  static const int defaultForNewUsers = 0;

  static int clamp(Object? value, {int fallback = defaultForNewUsers}) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    return (parsed ?? fallback).clamp(minimum, maximum);
  }

  static String title(int level, {String languageCode = 'en'}) {
    if (languageCode == 'de') {
      return switch (clamp(level)) {
        0 => 'Geist',
        1 => 'Unterwegs',
        2 => 'Reisezeit',
        3 => 'Reiseziel',
        4 => 'Reiseverlauf',
        5 => 'Live-Fortschritt',
        6 => 'Reisestandort',
        7 => 'Immer erreichbar',
        8 => 'Favoriten',
        _ => 'Geist',
      };
    }
    return switch (clamp(level)) {
      0 => 'Ghost',
      1 => 'On board',
      2 => 'Journey window',
      3 => 'Destination',
      4 => 'Itinerary',
      5 => 'Live progress',
      6 => 'Journey location',
      7 => 'Always available',
      8 => 'Favorites',
      _ => 'Ghost',
    };
  }

  static String description(int level, {String languageCode = 'en'}) {
    if (languageCode == 'de') {
      return switch (clamp(level)) {
        0 => 'Nichts teilen.',
        1 => 'Aktuelle oder kürzlich genutzte Linie teilen.',
        2 => 'Zusätzlich Start- und Endzeit der Reise teilen.',
        3 => 'Zusätzlich den Zielbahnhof teilen.',
        4 => 'Zusätzlich Halte, Linien und Umstiege teilen.',
        5 => 'Zusätzlich den Live-Fortschritt der Reise teilen.',
        6 =>
          'Zusätzlich den genauen Standort während einer erkannten Reise teilen.',
        7 =>
          'Den letzten genauen Standort für Routen zu Freunden bereithalten.',
        8 => 'Zusätzlich gespeicherte Favoriten mit Bezeichnungen teilen.',
        _ => 'Nichts teilen.',
      };
    }
    return switch (clamp(level)) {
      0 => 'Share nothing.',
      1 => 'Share the current or recently used transit line.',
      2 => 'Also share journey start and end times.',
      3 => 'Also share the destination station.',
      4 => 'Also share transit stations, lines, and transfers.',
      5 => 'Also share live progress along the journey.',
      6 => 'Also share exact location while on a detected journey.',
      7 => 'Keep the latest exact location available for friend routing.',
      8 => 'Also share saved favorite places with their labels.',
      _ => 'Share nothing.',
    };
  }
}

class JourneySharingSettings {
  final int globalLevel;
  final Map<String, int> friendOverrides;
  final bool hasFriends;

  const JourneySharingSettings({
    required this.globalLevel,
    this.friendOverrides = const {},
    this.hasFriends = true,
  });

  int effectiveLevelFor(String friendId) =>
      friendOverrides[friendId] ?? globalLevel;

  bool get needsAlwaysLocation =>
      hasFriends &&
      (globalLevel >= 7 || friendOverrides.values.any((level) => level >= 7));
}
