import 'package:flutter/material.dart';

/// The visual foundation for Manisa: calm, local-first and readable in Persian.
abstract final class ManisaColors {
  static const ink = Color(0xFF171D32);
  static const mutedInk = Color(0xFF70788C);
  static const teal = Color(0xFF4158EB);
  static const tealPressed = Color(0xFF3447CE);
  static const mint = Color(0xFFE9EDFF);
  static const canvas = Color(0xFFF4F5F8);
  static const surface = Color(0xFFFFFFFF);
  static const outline = Color(0xFFE2E5ED);
  static const warning = Color(0xFFA45C20);
  static const warningSurface = Color(0xFFFFF1E5);
  static const danger = Color(0xFFBA1A1A);
  static const dangerSurface = Color(0xFFFFDAD6);
}

abstract final class ManisaTheme {
  static ThemeData get light {
    const scheme = ColorScheme.light(
      primary: ManisaColors.teal,
      onPrimary: Colors.white,
      primaryContainer: ManisaColors.mint,
      onPrimaryContainer: ManisaColors.ink,
      secondary: ManisaColors.tealPressed,
      onSecondary: Colors.white,
      secondaryContainer: ManisaColors.mint,
      onSecondaryContainer: ManisaColors.ink,
      error: ManisaColors.danger,
      onError: Colors.white,
      errorContainer: ManisaColors.dangerSurface,
      onErrorContainer: Color(0xFF410002),
      surface: ManisaColors.surface,
      onSurface: ManisaColors.ink,
      onSurfaceVariant: ManisaColors.mutedInk,
      outline: ManisaColors.outline,
      outlineVariant: Color(0xFFECEEF4),
      shadow: Color(0x1F171D32),
      scrim: Color(0x66171D32),
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
          fontFamily: 'Vazirmatn',
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
          side: BorderSide.none,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ManisaColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          side: const BorderSide(color: ManisaColors.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
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
      chipTheme: ChipThemeData(
        backgroundColor: ManisaColors.surface,
        selectedColor: ManisaColors.mint,
        showCheckmark: false,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        labelStyle: const TextStyle(
          color: ManisaColors.ink,
          fontFamily: 'Vazirmatn',
          fontSize: 13,
        ),
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
