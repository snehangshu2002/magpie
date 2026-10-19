import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const _seed = Color(0xFF3D5AFE);

  static ThemeData light() => _build(ColorScheme.fromSeed(seedColor: _seed));

  static ThemeData dark() => _build(
    ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark),
  );

  /// Continuous corners: the curvature eases into the straight edge instead
  /// of meeting it abruptly, so surfaces read as one smooth shape.
  static RoundedSuperellipseBorder shape(double radius) =>
      RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(radius));

  static ThemeData _build(ColorScheme scheme) {
    final base = ThemeData(colorScheme: scheme);
    return base.copyWith(
      textTheme: _tightenLargeText(base.textTheme),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        shape: shape(24),
        clipBehavior: Clip.antiAlias,
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
