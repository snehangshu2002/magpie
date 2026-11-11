import 'package:flutter/material.dart';

abstract final class AppTheme {
  /// Indigo: a clear, modern accent on near-neutral surfaces.
  static const _seed = Color(0xFF4F5BD5);

  /// [fontFamily] is a family from pubspec.yaml; null keeps the phone's font.
  /// [wallpaper] replaces the indigo palette with the phone's own colours;
  /// otherwise [seed], when set, grows another palette in its place.
  static ThemeData light({
    String? fontFamily,
    ColorScheme? wallpaper,
    Color? seed,
  }) => _build(wallpaper ?? scheme(Brightness.light, seed: seed), fontFamily);

  /// The palette for [brightness]: indigo, or one grown from [seed].
  static ColorScheme scheme(Brightness brightness, {Color? seed}) =>
      seed == null
      ? (brightness == Brightness.light ? _lightScheme : _darkScheme)
      : ColorScheme.fromSeed(seedColor: seed, brightness: brightness);

  // `content` keeps the seed itself as primaryContainer and picks a violet
  // tertiary (PDF tools' badges).
  static final ColorScheme _lightScheme = ColorScheme.fromSeed(
    seedColor: _seed,
    dynamicSchemeVariant: DynamicSchemeVariant.content,
  );

  /// Dark near-neutral surfaces with light indigo accents; [pureBlack]
  /// turns the page black, for OLED screens.
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

  static final ColorScheme _darkScheme = ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: Brightness.dark,
    dynamicSchemeVariant: DynamicSchemeVariant.content,
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
