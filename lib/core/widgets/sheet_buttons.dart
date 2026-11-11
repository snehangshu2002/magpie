import 'package:flutter/material.dart';

/// The main action of a bottom sheet: a full-width pill.
ButtonStyle primarySheetButton(ThemeData theme) => FilledButton.styleFrom(
  minimumSize: const Size.fromHeight(56),
  shape: const StadiumBorder(),
  textStyle: theme.textTheme.titleMedium,
);

/// A quieter action under it (Cancel, Done, Try again).
ButtonStyle secondarySheetButton(ThemeData theme) => FilledButton.styleFrom(
  minimumSize: const Size.fromHeight(56),
  shape: const StadiumBorder(),
  backgroundColor: theme.colorScheme.surfaceContainerLow,
  foregroundColor: theme.colorScheme.onSurface,
  textStyle: theme.textTheme.titleMedium,
);
