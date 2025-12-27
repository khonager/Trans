import 'package:flutter/material.dart';

/// --------------------------------------------------------------------------
/// 1. AVAILABLE THEME COLORS
/// Add or remove colors here to update the picker in Settings.
/// --------------------------------------------------------------------------
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
  Color(0xFF000000), // Pure Black/White
];

/// --------------------------------------------------------------------------
/// 2. CUSTOM COMPONENT COLORS (Like CSS Classes)
/// This defines the unique colors for specific parts of your app.
/// --------------------------------------------------------------------------
@immutable
class TransColors extends ThemeExtension<TransColors> {
  // Search Bar
  final Color searchBarFill;
  final Color searchIcon;
  final Color searchHintText;

  // Favorites
  final Color favStationBg;
  final Color favStationIcon;
  final Color favFriendBg;
  final Color favFriendIcon;
  final Color favAddBg;
  final Color favAddIcon;

  // Timeline / Route Steps
  final Color timelineLine;
  final Color timelineDot;
  final Color timelineTextMain;
  final Color timelineTextSub;
  final Color timelineTextTime;
  final Color timelineTextDelay; // The bold red text
  final Color timelineTextOnTime;

  // Action Chips (e.g., "Chat", "Guide" buttons)
  final Color chipBg;
  final Color chipFg;
  final Color chipActiveBg;
  final Color chipActiveFg;

  const TransColors({
    required this.searchBarFill,
    required this.searchIcon,
    required this.searchHintText,
    required this.favStationBg,
    required this.favStationIcon,
    required this.favFriendBg,
    required this.favFriendIcon,
    required this.favAddBg,
    required this.favAddIcon,
    required this.timelineLine,
    required this.timelineDot,
    required this.timelineTextMain,
    required this.timelineTextSub,
    required this.timelineTextTime,
    required this.timelineTextDelay,
    required this.timelineTextOnTime,
    required this.chipBg,
    required this.chipFg,
    required this.chipActiveBg,
    required this.chipActiveFg,
  });

  /// Helper to access colors easily: TransColors.of(context).searchBarFill
  static TransColors of(BuildContext context) => Theme.of(context).extension<TransColors>()!;

  /// --------------------------------------------------------------------------
  /// LOGIC: How colors are derived from the Main Seed Color
  /// Edit this method to tune Light vs Dark mode contrasts.
  /// --------------------------------------------------------------------------
  static TransColors fromSeed(Color seed, Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    // Fix for "Pure Black" theme seed being invisible
    final effectiveSeed = (isDark && seed.value == 0xFF000000) ? Colors.white : seed;

    return TransColors(
      // Search Bar: Darker in light mode, translucent white in dark mode
      searchBarFill: isDark ? Colors.white.withOpacity(0.12) : Colors.grey.shade200,
      searchIcon: isDark ? effectiveSeed.withOpacity(0.9) : effectiveSeed,
      searchHintText: isDark ? Colors.white38 : Colors.grey,

      // Favorites
      favStationBg: isDark ? effectiveSeed.withOpacity(0.25) : effectiveSeed.withOpacity(0.1),
      favStationIcon: effectiveSeed,
      favFriendBg: isDark ? Colors.green.withOpacity(0.25) : Colors.green.withOpacity(0.1),
      favFriendIcon: Colors.green,
      
      // The "Add (+)" button
      favAddBg: isDark ? effectiveSeed.withOpacity(0.2) : effectiveSeed.withOpacity(0.1),
      favAddIcon: effectiveSeed,

      // Timeline
      timelineLine: isDark ? Colors.white24 : Colors.grey.shade300,
      timelineDot: isDark ? Colors.grey.shade600 : Colors.grey.shade500,
      timelineTextMain: isDark ? Colors.white : Colors.black87,
      timelineTextSub: isDark ? Colors.white54 : Colors.grey.shade700,
      timelineTextTime: isDark ? Colors.white70 : Colors.black54,
      timelineTextDelay: Colors.redAccent,
      timelineTextOnTime: Colors.greenAccent,

      // Chips
      chipBg: isDark ? Colors.white10 : Colors.grey.shade200,
      chipFg: isDark ? Colors.white70 : Colors.grey.shade700,
      chipActiveBg: effectiveSeed,
      chipActiveFg: Colors.white,
    );
  }

  @override
  TransColors copyWith({
    Color? searchBarFill, Color? searchIcon, Color? searchHintText,
    Color? favStationBg, Color? favStationIcon,
    Color? favFriendBg, Color? favFriendIcon,
    Color? favAddBg, Color? favAddIcon,
    Color? timelineLine, Color? timelineDot,
    Color? timelineTextMain, Color? timelineTextSub,
    Color? timelineTextTime, Color? timelineTextDelay, Color? timelineTextOnTime,
    Color? chipBg, Color? chipFg, Color? chipActiveBg, Color? chipActiveFg,
  }) {
    return TransColors(
      searchBarFill: searchBarFill ?? this.searchBarFill,
      searchIcon: searchIcon ?? this.searchIcon,
      searchHintText: searchHintText ?? this.searchHintText,
      favStationBg: favStationBg ?? this.favStationBg,
      favStationIcon: favStationIcon ?? this.favStationIcon,
      favFriendBg: favFriendBg ?? this.favFriendBg,
      favFriendIcon: favFriendIcon ?? this.favFriendIcon,
      favAddBg: favAddBg ?? this.favAddBg,
      favAddIcon: favAddIcon ?? this.favAddIcon,
      timelineLine: timelineLine ?? this.timelineLine,
      timelineDot: timelineDot ?? this.timelineDot,
      timelineTextMain: timelineTextMain ?? this.timelineTextMain,
      timelineTextSub: timelineTextSub ?? this.timelineTextSub,
      timelineTextTime: timelineTextTime ?? this.timelineTextTime,
      timelineTextDelay: timelineTextDelay ?? this.timelineTextDelay,
      timelineTextOnTime: timelineTextOnTime ?? this.timelineTextOnTime,
      chipBg: chipBg ?? this.chipBg,
      chipFg: chipFg ?? this.chipFg,
      chipActiveBg: chipActiveBg ?? this.chipActiveBg,
      chipActiveFg: chipActiveFg ?? this.chipActiveFg,
    );
  }

  @override
  TransColors lerp(ThemeExtension<TransColors>? other, double t) {
    if (other is! TransColors) return this;
    return TransColors(
      searchBarFill: Color.lerp(searchBarFill, other.searchBarFill, t)!,
      searchIcon: Color.lerp(searchIcon, other.searchIcon, t)!,
      searchHintText: Color.lerp(searchHintText, other.searchHintText, t)!,
      favStationBg: Color.lerp(favStationBg, other.favStationBg, t)!,
      favStationIcon: Color.lerp(favStationIcon, other.favStationIcon, t)!,
      favFriendBg: Color.lerp(favFriendBg, other.favFriendBg, t)!,
      favFriendIcon: Color.lerp(favFriendIcon, other.favFriendIcon, t)!,
      favAddBg: Color.lerp(favAddBg, other.favAddBg, t)!,
      favAddIcon: Color.lerp(favAddIcon, other.favAddIcon, t)!,
      timelineLine: Color.lerp(timelineLine, other.timelineLine, t)!,
      timelineDot: Color.lerp(timelineDot, other.timelineDot, t)!,
      timelineTextMain: Color.lerp(timelineTextMain, other.timelineTextMain, t)!,
      timelineTextSub: Color.lerp(timelineTextSub, other.timelineTextSub, t)!,
      timelineTextTime: Color.lerp(timelineTextTime, other.timelineTextTime, t)!,
      timelineTextDelay: Color.lerp(timelineTextDelay, other.timelineTextDelay, t)!,
      timelineTextOnTime: Color.lerp(timelineTextOnTime, other.timelineTextOnTime, t)!,
      chipBg: Color.lerp(chipBg, other.chipBg, t)!,
      chipFg: Color.lerp(chipFg, other.chipFg, t)!,
      chipActiveBg: Color.lerp(chipActiveBg, other.chipActiveBg, t)!,
      chipActiveFg: Color.lerp(chipActiveFg, other.chipActiveFg, t)!,
    );
  }
}

/// --------------------------------------------------------------------------
/// 3. THEME GENERATOR
/// This combines standard Material Theme with your Custom Colors
/// --------------------------------------------------------------------------
ThemeData createTheme(Color seed, Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  
  // Base ColorScheme
  final baseScheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  
  // Custom ColorScheme Overrides for High Contrast Dark Mode
  final scheme = isDark 
      ? baseScheme.copyWith(
          primary: seed, 
          onPrimary: Colors.white,
          surface: Colors.black, // Pure black background
          surfaceContainerLow: const Color(0xFF121212), // Cards
        )
      : baseScheme.copyWith(
          scrim: const Color(0xFFF3F4F6), // Light grey background
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
    // Inject your custom color class here
    extensions: [
      TransColors.fromSeed(seed, brightness),
    ],
    sliderTheme: SliderThemeData(
      activeTrackColor: seed,
      thumbColor: Colors.white,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.selected)) return Colors.white;
        return null;
      }),
      trackColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.selected)) return seed;
        return null;
      }),
    ),
  );
}