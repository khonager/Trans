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
];

@immutable
class TransColors extends ThemeExtension<TransColors> {
  final Color seed;
  final Brightness brightness;

  const TransColors({required this.seed, required this.brightness});

  bool get isDark => brightness == Brightness.dark;
  
  // Helper for consistent "effective seed" (White in dark mode if seed is Black)
  Color get effectiveSeed => (isDark && seed.value == 0xFF000000) ? Colors.white : seed;
  
  // Helper for consistent base cards
  Color get baseCard => isDark ? const Color(0xFF18181B) : Colors.white;
  Color get baseText => isDark ? Colors.white : Colors.black87;
  Color get subText => isDark ? Colors.white54 : Colors.grey.shade700;

  // ===========================================================================
  // 1. BASE COLORS
  // ===========================================================================
  Color get scaffoldBg => isDark ? Colors.black : const Color(0xFFF3F4F6);
  Color get cardBg => baseCard;
  Color get textPrimary => baseText;
  Color get textSecondary => subText;
  Color get divider => isDark ? Colors.white10 : Colors.grey.shade300;
  Color get modalHandle => Colors.grey.shade600;

  // ===========================================================================
  // 2. APP BAR & NAVIGATION
  // ===========================================================================
  Color get appBarBg => (isDark ? Colors.black : Colors.white).withOpacity(0.8);
  Color get appBarTitle => baseText;
  Color get appBarIconBg => effectiveSeed;
  Color get navBarBg => baseCard;
  Color get navBarSelected => effectiveSeed;
  Color get navBarUnselected => Colors.grey;

  // ===========================================================================
  // 3. SEARCH & HOME
  // ===========================================================================
  Color get searchHeaderIconBg => Colors.indigo.withOpacity(0.2);
  Color get searchHeaderIcon => Colors.indigoAccent;
  Color get searchInputFill => isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade200;
  Color get searchInputIcon => isDark ? effectiveSeed : Colors.grey;
  Color get searchInputText => baseText;
  Color get searchHintText => isDark ? Colors.white38 : Colors.grey;
  Color get searchBtnBg => effectiveSeed;
  Color get searchBtnText => (effectiveSeed.computeLuminance() > 0.5) ? Colors.black : Colors.white;
  Color get timeContainerBg => isDark ? const Color(0xFF1F2937) : Colors.grey.shade200;
  Color get timeToggleBg => Colors.indigoAccent;
  Color get timeToggleText => Colors.white;
  Color get sectionHeader => isDark ? Colors.white60 : Colors.grey.shade600;

  // ===========================================================================
  // 4. FAVORITES
  // ===========================================================================
  Color get favStationBg => isDark ? effectiveSeed.withOpacity(0.3) : effectiveSeed.withOpacity(0.15);
  Color get favStationIcon => isDark ? Colors.white : effectiveSeed;
  Color get favFriendBg => isDark ? Colors.green.withOpacity(0.3) : Colors.green.withOpacity(0.15);
  Color get favFriendIcon => isDark ? Colors.white : Colors.green;
  Color get favAddBg => isDark ? Colors.white24 : Colors.grey.withOpacity(0.2);
  Color get favAddIcon => isDark ? Colors.white : Colors.black;
  Color get favText => isDark ? Colors.white70 : Colors.black87;

  // ===========================================================================
  // 5. ROUTES & STEPS
  // ===========================================================================
  Color get stepCardBg => baseCard;
  Color get stepTransferBg => Colors.orange.withOpacity(0.1);
  Color get stepTransferBorder => Colors.orange.withOpacity(0.3);
  Color get stepTransferText => Colors.orange;
  Color get stepTimeText => Colors.indigoAccent;
  Color get stepPlatformText => Colors.greenAccent;
  Color get stepStopoversBg => (isDark ? Colors.black : const Color(0xFFF3F4F6)).withOpacity(0.5);
  Color get delayLate => Colors.red;
  Color get delayOnTime => Colors.green;
  
  // Chips
  Color get chipBg => isDark ? Colors.white12 : Colors.grey.shade200;
  Color get chipFg => isDark ? Colors.white70 : Colors.grey.shade700;
  Color get chipActiveBg => effectiveSeed;
  Color get chipActiveFg => (effectiveSeed.computeLuminance() > 0.5) ? Colors.black : Colors.white;

  // ===========================================================================
  // 6. FRIENDS TAB
  // ===========================================================================
  Color get friendCardActiveBg => baseCard.withOpacity(0.9);
  Color get friendCardInactiveBg => baseCard.withOpacity(0.4);
  Color get friendCardActiveBorder => Colors.green.withOpacity(0.3);
  Color get friendCardInactiveBorder => Colors.white10;
  Color get requestCardBg => Colors.indigo.withOpacity(0.1);
  Color get requestCardBorder => Colors.indigo.withOpacity(0.3);
  Color get statusOnline => Colors.blue;
  Color get statusActive => Colors.green;
  Color get statusOffline => Colors.grey;
  Color get actionIconSuccess => Colors.green;
  Color get actionIconError => Colors.red;

  // ===========================================================================
  // 7. CHAT
  // ===========================================================================
  Color get chatHeaderIconBg => Colors.indigo;
  Color get chatBubbleMeBg => effectiveSeed;
  Color get chatBubbleMeText => Colors.white;
  Color get chatBubbleFriendBg => baseCard;
  Color get chatBubbleFriendText => baseText;
  Color get chatBubbleFriendBorder => Colors.white10;
  Color get chatInputFill => baseCard;
  Color get chatSendBtnBg => effectiveSeed;
  Color get chatSendBtnIcon => Colors.white;

  // ===========================================================================
  // 8. TICKET PANEL
  // ===========================================================================
  Color get ticketSheetBg => isDark ? const Color(0xFF1F2937) : Colors.white;
  Color get ticketHeader => baseText;
  Color get ticketBorder => Colors.grey.withOpacity(0.2);
  Color get ticketEmptyIcon => Colors.grey.withOpacity(0.5);
  Color get ticketAddBtnBg => const Color(0xFF4F46E5);
  Color get ticketAddBtnText => Colors.white;

  // ===========================================================================
  // 9. SETTINGS
  // ===========================================================================
  Color get settingsSectionBg => baseCard;
  Color get settingsHeader => subText;
  Color get iconBlock => Colors.orange;
  Color get iconDelete => Colors.red;
  Color get authFormBg => baseCard;

  // ===========================================================================
  // 🛑 BOILERPLATE (Simplified for Getter Method)
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
    // Snap change (no fade) for simplicity
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