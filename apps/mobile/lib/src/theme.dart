import 'package:flutter/material.dart';

/// mindOS visual identity — a cinematic, dark, "living intelligence" theme.
///
/// Design intent (2035 keynote): the interface should feel lit from within.
/// Deep space blacks and midnight blues, a violet presence, glass surfaces,
/// almost-imperceptible shadows. Not pure black; never saturated. Dark is the
/// primary experience; a light variant exists as a graceful fallback.
class AppTheme {
  AppTheme._();

  // Brand presence.
  static const Color violet = Color(0xFF8B7BFF); // luminous accent
  static const Color violetDeep = Color(0xFF6D4AFF); // seed
  static const Color electric = Color(0xFF6EE7FF); // rare cool highlight

  // Deep-space surfaces (dark).
  static const Color space = Color(0xFF06060E); // scaffold base
  static const Color midnight = Color(0xFF0C0C1A); // gradient toward
  static const Color glass = Color(0xFF14142A); // opaque glass base
  static const Color onDark = Color(0xFFECEAF6);
  static const Color onDarkMuted = Color(0xFF9E9BC0);

  static ThemeData dark() {
    final base = ColorScheme.fromSeed(
      seedColor: violetDeep,
      brightness: Brightness.dark,
    );
    final scheme = base.copyWith(
      primary: violet,
      onPrimary: const Color(0xFF120C2E),
      secondary: electric,
      surface: space,
      onSurface: onDark,
      onSurfaceVariant: onDarkMuted,
      surfaceContainerHighest: glass,
      outlineVariant: const Color(0xFF2A2A44),
    );
    return _build(scheme, glassAlpha: 0.55, borderAlpha: 0.10);
  }

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: violetDeep,
      brightness: Brightness.light,
    );
    return _build(scheme, glassAlpha: 0.6, borderAlpha: 0.6);
  }

  static ThemeData _build(
    ColorScheme scheme, {
    required double glassAlpha,
    required double borderAlpha,
  }) {
    final radius = BorderRadius.circular(22);
    final isDark = scheme.brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerHighest.withValues(alpha: glassAlpha),
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: (isDark ? Colors.white : scheme.outlineVariant)
                .withValues(alpha: borderAlpha),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(
          color: (isDark ? Colors.white : scheme.outlineVariant)
              .withValues(alpha: borderAlpha),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 70,
        backgroundColor: isDark
            ? AppTheme.midnight.withValues(alpha: 0.85)
            : scheme.surface,
        indicatorColor: scheme.primary.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11.5,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? AppTheme.glass : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? AppTheme.glass : null,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.4),
        thickness: 1,
      ),
    );
  }
}
