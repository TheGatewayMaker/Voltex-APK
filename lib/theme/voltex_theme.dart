// Voltex design system.
//
// Dark theme only - the web app ships no light theme
// (ANDROID_INTEGRATION.md §15.2). Colours are taken verbatim from
// client/global.css; do not introduce a light variant or "improve" these
// values without checking with the web app's design tokens first.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class VoltexColors {
  VoltexColors._();

  static const background = Color(0xFF071212);
  static const foreground = Color(0xFFE8F7F3); // primary text
  static const card = Color(0xFF14292A); // surface
  static const popover = Color(0xFF112627);
  static const primary = Color(0xFF2CC3A5); // brand accent
  static const primaryForeground = Color(0xFF081516);
  static const secondary = Color(0xFF213A3B);
  static const muted = Color(0xFF1B2B2C);
  static const mutedForeground = Color(0xFFABC4BE); // secondary text
  static const accent = Color(0xFF254B4A);
  static const destructive = Color(0xFFE33131);
  static const border = Color(0xFF385C5C);
  static const input = Color(0xFF152828);
  static const focusRing = Color(0xFF89ECD8);

  // Message bubble / status colours derived from the accent scale, kept
  // separate so chat-specific tweaks don't leak into the base palette.
  static const sentBubble = primary;
  static const receivedBubble = card;
  static const delivered = mutedForeground;
  static const seen = primary;
}

class VoltexRadii {
  VoltexRadii._();

  static const double base = 16; // 1rem
  static const double card = 24; // 22-28px range, midpoint
  static const double cardLarge = 28;
  static const double pill = 999; // fully rounded
}

class VoltexTextStyles {
  VoltexTextStyles._();

  // Manrope for body copy.
  static TextStyle body = GoogleFonts.manrope(
    color: VoltexColors.foreground,
    fontSize: 15,
    height: 1.4,
  );

  static TextStyle bodyMuted = GoogleFonts.manrope(
    color: VoltexColors.mutedForeground,
    fontSize: 13,
    height: 1.4,
  );

  // Montserrat, heavy weights, tight negative letter spacing for headings.
  static TextStyle heading1 = GoogleFonts.montserrat(
    color: VoltexColors.foreground,
    fontSize: 28,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.06 * 28,
    height: 1.15,
  );

  static TextStyle heading2 = GoogleFonts.montserrat(
    color: VoltexColors.foreground,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.05 * 20,
    height: 1.2,
  );

  static TextStyle heading3 = GoogleFonts.montserrat(
    color: VoltexColors.foreground,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.04 * 16,
    height: 1.25,
  );

  // IBM Plex Mono for identifiers, ids and key fingerprints.
  static TextStyle mono = GoogleFonts.ibmPlexMono(
    color: VoltexColors.foreground,
    fontSize: 13,
    height: 1.4,
  );

  static TextStyle monoMuted = GoogleFonts.ibmPlexMono(
    color: VoltexColors.mutedForeground,
    fontSize: 12,
    height: 1.4,
  );
}

class VoltexTheme {
  VoltexTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);

    final colorScheme = ColorScheme.dark(
      surface: VoltexColors.background,
      primary: VoltexColors.primary,
      onPrimary: VoltexColors.primaryForeground,
      secondary: VoltexColors.secondary,
      onSecondary: VoltexColors.foreground,
      error: VoltexColors.destructive,
      onError: Colors.white,
      onSurface: VoltexColors.foreground,
      surfaceContainerHighest: VoltexColors.card,
      outline: VoltexColors.border,
    );

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: VoltexColors.background,
      primaryColor: VoltexColors.primary,
      dividerColor: VoltexColors.border,
      appBarTheme: AppBarTheme(
        backgroundColor: VoltexColors.background,
        foregroundColor: VoltexColors.foreground,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: null, // set per-screen via SystemChrome if needed
        titleTextStyle: VoltexTextStyles.heading3,
      ),
      textTheme: base.textTheme.copyWith(
        bodyLarge: VoltexTextStyles.body,
        bodyMedium: VoltexTextStyles.body,
        bodySmall: VoltexTextStyles.bodyMuted,
        titleLarge: VoltexTextStyles.heading1,
        titleMedium: VoltexTextStyles.heading2,
        titleSmall: VoltexTextStyles.heading3,
      ),
      cardTheme: CardThemeData(
        color: VoltexColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VoltexRadii.card),
          side: const BorderSide(color: VoltexColors.border, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: VoltexColors.popover,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VoltexRadii.cardLarge),
        ),
        titleTextStyle: VoltexTextStyles.heading2,
        contentTextStyle: VoltexTextStyles.body,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: VoltexColors.input,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(VoltexRadii.base),
          borderSide: const BorderSide(color: VoltexColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(VoltexRadii.base),
          borderSide: const BorderSide(color: VoltexColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(VoltexRadii.base),
          borderSide: const BorderSide(color: VoltexColors.focusRing, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(VoltexRadii.base),
          borderSide: const BorderSide(color: VoltexColors.destructive),
        ),
        hintStyle: VoltexTextStyles.bodyMuted,
        labelStyle: VoltexTextStyles.bodyMuted,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: VoltexColors.primary,
          foregroundColor: VoltexColors.primaryForeground,
          textStyle: VoltexTextStyles.heading3,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(VoltexRadii.pill),
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: VoltexColors.foreground,
          side: const BorderSide(color: VoltexColors.border),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(VoltexRadii.pill),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: VoltexColors.primary,
          textStyle: VoltexTextStyles.body,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: VoltexColors.background,
        selectedItemColor: VoltexColors.primary,
        unselectedItemColor: VoltexColors.mutedForeground,
        type: BottomNavigationBarType.fixed,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: VoltexColors.popover,
        contentTextStyle: VoltexTextStyles.body,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VoltexRadii.base),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: VoltexColors.primary,
        unselectedLabelColor: VoltexColors.mutedForeground,
        indicatorColor: VoltexColors.primary,
        labelStyle: VoltexTextStyles.heading3,
      ),
    );
  }
}
