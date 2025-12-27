import 'package:flutter/material.dart';

const List<Color> appThemeColors = [
  Color(0xFF4F46E5), // Indigo (Default)
  Colors.blue,
  Colors.teal,
  Colors.green,
  Colors.orange,
  Colors.red,
  Colors.purple,
  Colors.pink,
  Colors.amber,
  Color(0xFF000000), // Pure Black
];

@immutable
class TransColors extends ThemeExtension<TransColors> {
  final Color seed;
  final Brightness brightness;

  const TransColors({required this.seed, required this.brightness});

  bool get isDark => brightness == Brightness.dark;

  // ===========================================================================
  // 🟢 NEW COLORS (Ticket, Friends, Journey)
  // ===========================================================================
  
  // Ticket Panel
  Color get ticketBg => isDark ? const Color(0xFF1E1E1E) : Colors.white;
  Color get ticketBorder => isDark ? Colors.white24 : Colors.grey.shade300;

  // Add Friends Button
  Color get addFriendBtnBg => isDark ? Colors.green.withOpacity(0.2) : Colors.green.shade100;
  Color get addFriendBtnText => isDark ? Colors.greenAccent : Colors.green.shade800;

  // Plan Journey Inputs & Buttons
  Color get journeyInputFill => isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade200;
  Color get journeyInputIcon => isDark ? seed : Colors.grey;
  Color get journeyBtnBg => seed;
  Color get journeyBtnText => (seed.computeLuminance() > 0.5) ? Colors.black : Colors.white;

  // ===========================================================================
  // 🟡 EXISTING COLORS (Ported to simple getters)
  // ===========================================================================

  // Search
  Color get searchBarFill => isDark ? Colors.white.withOpacity(0.15) : Colors.grey.shade200;
  Color get searchIcon => seed;
  Color get searchHintText => isDark ? Colors.white54 : Colors.grey;
  Color get searchInputText => isDark ? Colors.white : Colors.black;

  // Favorites
  Color get favStationBg => isDark ? seed.withOpacity(0.3) : seed.withOpacity(0.15);
  Color get favStationIcon => isDark ? Colors.white : seed;
  Color get favFriendBg => isDark ? Colors.green.withOpacity(0.3) : Colors.green.withOpacity(0.15);
  Color get favFriendIcon => isDark ? Colors.white : Colors.green;
  Color get favAddBg => isDark ? Colors.white24 : Colors.grey.withOpacity(0.2);
  Color get favAddIcon => isDark ? Colors.white : Colors.black;
  Color get favText => isDark ? Colors.white70 : Colors.black87;

  // Timeline
  Color get timelineLine => isDark ? Colors.white24 : Colors.grey.shade300;
  Color get timelineDot => Colors.grey.shade500;
  Color get timelineTextMain => isDark ? Colors.white : Colors.black87;
  Color get timelineTextSub => isDark ? Colors.white54 : Colors.grey.shade700;
  Color get timelineTextTime => isDark ? Colors.white70 : Colors.black54;
  Color get timelineTextDelay => Colors.redAccent;
  Color get timelineTextOnTime => Colors.greenAccent;

  // Chips
  Color get chipBg => isDark ? Colors.white12 : Colors.grey.shade200;
  Color get chipFg => isDark ? Colors.white70 : Colors.grey.shade700;
  Color get chipActiveBg => seed;
  Color get chipActiveFg => (seed.computeLuminance() > 0.5) ? Colors.black : Colors.white;

  // ===========================================================================
  // 🛑 BOILERPLATE (Do not edit below)
  // ===========================================================================

  @override
  TransColors copyWith({Color? seed, Brightness? brightness}) {
    return TransColors(
      seed: seed ?? this.seed,
      brightness: brightness ?? this.brightness,
    );
  }

  @override
  TransColors lerp(ThemeExtension<TransColors>? other, double t) {
    if (other is! TransColors) return this;
    if (t < 0.5) return this;
    return other;
  }

  static TransColors fromSeed(Color seed, Brightness brightness) {
    return TransColors(seed: seed, brightness: brightness);
  }

  static TransColors of(BuildContext context) => Theme.of(context).extension<TransColors>()!;
}

ThemeData createTheme(Color seed, Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final baseScheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  
  final scheme = isDark 
      ? baseScheme.copyWith(
          primary: seed, 
          onPrimary: Colors.white,
          surface: Colors.black, 
          surfaceContainerLow: const Color(0xFF18181B),
        )
      : baseScheme.copyWith(
          scrim: const Color(0xFFF3F4F6),
        );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    cardColor: isDark ? const Color(0xFF18181B) : Colors.white,
    appBarTheme: AppBarTheme(
      backgroundColor: isDark ? Colors.black.withOpacity(0.8) : Colors.white.withOpacity(0.8),
      foregroundColor: isDark ? Colors.white : Colors.black,
    ),
    extensions: [
      TransColors.fromSeed(seed, brightness),
    ],
    sliderTheme: SliderThemeData(
      activeTrackColor: seed,
      thumbColor: Colors.white,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        return null;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return seed;
        return null;
      }),
    ),
  );
}