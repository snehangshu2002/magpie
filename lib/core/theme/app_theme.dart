import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const _seed = Color(0xFF3D5AFE);

  static ThemeData light() =>
      ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: _seed));

  static ThemeData dark() => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    ),
  );
}
