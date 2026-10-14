import 'package:flutter/material.dart';

/// The visual foundation for Manisa: calm, local-first and readable in Persian.
abstract final class ManisaColors {
  static const ink = Color(0xFF172322);
  static const mutedInk = Color(0xFF586866);
  static const teal = Color(0xFF087A78);
  static const tealPressed = Color(0xFF005F5E);
  static const mint = Color(0xFFD9F3EF);
  static const canvas = Color(0xFFF5F8F6);
  static const surface = Color(0xFFFCFEFD);
  static const outline = Color(0xFFDCE5E2);
  static const warning = Color(0xFF9B5C00);
  static const warningSurface = Color(0xFFFFEFD2);
  static const danger = Color(0xFFBA1A1A);
  static const dangerSurface = Color(0xFFFFDAD6);
}

abstract final class ManisaTheme {
  static ThemeData get light {
    const scheme = ColorScheme.light(
      primary: ManisaColors.teal,
      onPrimary: Colors.white,
      primaryContainer: ManisaColors.mint,
      onPrimaryContainer: Color(0xFF00201F),
      secondary: Color(0xFF4A635F),
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFCCE8E3),
      onSecondaryContainer: Color(0xFF06201D),
      error: ManisaColors.danger,
      onError: Colors.white,
      errorContainer: ManisaColors.dangerSurface,
      onErrorContainer: Color(0xFF410002),
      surface: ManisaColors.surface,
      onSurface: ManisaColors.ink,
      onSurfaceVariant: ManisaColors.mutedInk,
      outline: ManisaColors.outline,
      outlineVariant: Color(0xFFE8EFED),
      shadow: Color(0x1F172322),
      scrim: Color(0x66172322),
      inverseSurface: Color(0xFF293331),
      onInverseSurface: Color(0xFFEEF2F0),
      inversePrimary: Color(0xFF81D5CF),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: ManisaColors.canvas,
      fontFamily: 'Vazirmatn',
      fontFamilyFallback: const <String>[
        'Noto Sans Arabic',
        'Roboto',
        'sans-serif',
      ],
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineLarge: base.textTheme.headlineLarge?.copyWith(
          fontSize: 30,
          height: 1.35,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          fontSize: 25,
          height: 1.4,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontSize: 20,
          height: 1.45,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontSize: 16,
          height: 1.5,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(
          fontSize: 16,
          height: 1.65,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          fontSize: 14,
          height: 1.6,
        ),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: ManisaColors.canvas,
        foregroundColor: ManisaColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: ManisaColors.ink,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          height: 1.4,
        ),
      ),
      cardTheme: CardThemeData(
        color: ManisaColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: ManisaColors.outline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ManisaColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: ManisaColors.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: ManisaColors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: ManisaColors.teal, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          side: const BorderSide(color: ManisaColors.outline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: ManisaColors.ink,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: StadiumBorder(),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: ManisaColors.surface,
        elevation: 0,
        indicatorColor: ManisaColors.mint,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            color: states.contains(WidgetState.selected)
                ? ManisaColors.tealPressed
                : ManisaColors.mutedInk,
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
          );
        }),
      ),
      dividerTheme: const DividerThemeData(
        color: ManisaColors.outline,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
