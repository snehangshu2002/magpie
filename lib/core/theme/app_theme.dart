import 'package:flutter/material.dart';

abstract final class AppTheme {
  /// Deep sage: calm, earthy, never neon.
  static const _seed = Color(0xFF56664F);

  /// [fontFamily] is a family from pubspec.yaml; null keeps the phone's font.
  /// [wallpaper] replaces the sage palette with the phone's own colours;
  /// otherwise [seed], when set, grows another palette in its place.
  static ThemeData light({
    String? fontFamily,
    ColorScheme? wallpaper,
    Color? seed,
  }) => _build(wallpaper ?? scheme(Brightness.light, seed: seed), fontFamily);

  /// The palette for [brightness]: sage, or one grown from [seed].
  static ColorScheme scheme(Brightness brightness, {Color? seed}) =>
      seed == null
      ? (brightness == Brightness.light ? _lightScheme : _darkScheme)
      : ColorScheme.fromSeed(seedColor: seed, brightness: brightness);

  static final ColorScheme _lightScheme =
      ColorScheme.fromSeed(
        seedColor: _seed,
        dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
      ).copyWith(
        primary: const Color(0xFF3F4E38),
        onPrimary: const Color(0xFFFFFFFF),
        primaryContainer: const Color(0xFF56664F),
        onPrimaryContainer: const Color(0xFFD1E3C6),
        secondary: const Color(0xFF53634F),
        onSecondary: const Color(0xFFFFFFFF),
        secondaryContainer: const Color(0xFFD7E8CE),
        onSecondaryContainer: const Color(0xFF596955),
        tertiary: const Color(0xFF454C42),
        onTertiary: const Color(0xFFFFFFFF),
        tertiaryContainer: const Color(0xFF5D6459),
        onTertiaryContainer: const Color(0xFFDAE0D3),
        error: const Color(0xFFBA1A1A),
        onError: const Color(0xFFFFFFFF),
        errorContainer: const Color(0xFFFFDAD6),
        onErrorContainer: const Color(0xFF93000A),
        surface: const Color(0xFFF6FBEF),
        onSurface: const Color(0xFF181D16),
        onSurfaceVariant: const Color(0xFF444841),
        surfaceDim: const Color(0xFFD7DCD1),
        surfaceBright: const Color(0xFFF6FBEF),
        surfaceContainerLowest: const Color(0xFFFFFFFF),
        surfaceContainerLow: const Color(0xFFF1F5EA),
        surfaceContainer: const Color(0xFFEBF0E4),
        surfaceContainerHigh: const Color(0xFFE5EADF),
        surfaceContainerHighest: const Color(0xFFDFE4D9),
        outline: const Color(0xFF747870),
        outlineVariant: const Color(0xFFC4C8BE),
        inverseSurface: const Color(0xFF2D322A),
        onInverseSurface: const Color(0xFFEEF2E7),
        inversePrimary: const Color(0xFFBACCB0),
        surfaceTint: const Color(0xFF53634C),
      );

  /// Deep peat surfaces with light sage accents; [pureBlack] turns the page
  /// black, for OLED screens.
  static ThemeData dark({
    String? fontFamily,
    ColorScheme? wallpaper,
    Color? seed,
    bool pureBlack = false,
  }) {
    final scheme = wallpaper ?? AppTheme.scheme(Brightness.dark, seed: seed);
    return _build(
      pureBlack
          ? scheme.copyWith(
              surface: Colors.black,
              surfaceDim: Colors.black,
              surfaceContainerLowest: Colors.black,
            )
          : scheme,
      fontFamily,
    );
  }

  static final ColorScheme _darkScheme =
      ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: Brightness.dark,
        dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
      ).copyWith(
        primary: const Color(0xFFA9B8A2),
        onPrimary: const Color(0xFF1F241D),
        error: const Color(0xFFF2B8B5),
        errorContainer: const Color(0xFF410E0B),
        // The next five extend the Stitch peat ladder evenly (same hue family).
        surfaceDim: const Color(0xFF121511),
        surfaceBright: const Color(0xFF353B33),
        surfaceContainerLowest: const Color(0xFF0D100C),
        surfaceContainerHighest: const Color(0xFF2E352C),
        outline: const Color(0xFF6E756A),
        surface: const Color(0xFF121511),
        onSurface: const Color(0xFFEFEBE2),
        onSurfaceVariant: const Color(0xFFA3AA9F),
        surfaceContainerLow: const Color(0xFF181C17),
        surfaceContainer: const Color(0xFF1C211B),
        surfaceContainerHigh: const Color(0xFF252C24),
        outlineVariant: const Color(0xFF2E352C),
      );

  /// Continuous corners: the curvature eases into the straight edge instead
  /// of meeting it abruptly, so surfaces read as one smooth shape.
  static RoundedSuperellipseBorder shape(double radius) =>
      RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(radius));

  static ThemeData _build(ColorScheme scheme, String? fontFamily) {
    final base = ThemeData(colorScheme: scheme, fontFamily: fontFamily);
    final text = _tightenLargeText(base.textTheme);
    return base.copyWith(
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        shape: shape(24),
        clipBehavior: Clip.antiAlias,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: scheme.surfaceContainerHigh,
        dragHandleColor: scheme.onSurfaceVariant.withValues(alpha: 0.4),
        shape: const RoundedSuperellipseBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(shape: shape(28)),
      snackBarTheme: SnackBarThemeData(shape: shape(16)),
      popupMenuTheme: PopupMenuThemeData(shape: shape(16)),
      // Hierarchy comes from tone, not shadow.
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? text.labelMedium?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w700,
                )
              : text.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
        ),
      ),
    );
  }

  /// Letters look further apart as text grows, so large styles get negative
  /// tracking proportional to their size; body and label styles keep the
  /// Material defaults, which favour legibility at small sizes.
  static TextTheme _tightenLargeText(TextTheme t) {
    TextStyle? track(TextStyle? style, double em) =>
        style?.copyWith(letterSpacing: (style.fontSize ?? 14) * em);
    return t.copyWith(
      displayLarge: track(t.displayLarge, -0.02),
      displayMedium: track(t.displayMedium, -0.02),
      displaySmall: track(t.displaySmall, -0.02),
      headlineLarge: track(t.headlineLarge, -0.02),
      headlineMedium: track(t.headlineMedium, -0.015),
      headlineSmall: track(t.headlineSmall, -0.01),
      titleLarge: track(t.titleLarge, -0.01),
    );
  }
}
