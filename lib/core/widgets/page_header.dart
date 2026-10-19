import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:media_downloader/core/theme/app_theme.dart';
import 'package:media_downloader/l10n/l10n.dart';

/// Shared page geometry, so every tab lines up the same way.
abstract final class PageLayout {
  /// Widest a page's content grows; tablets get a readable column.
  static const maxWidth = 600.0;

  /// Side padding that keeps content within [maxWidth], centred.
  static double gutter(BuildContext context) =>
      math.max(16, (MediaQuery.sizeOf(context).width - maxWidth) / 2);
}

/// The app's mark and name, shown in every tab's top bar.
class BrandTitle extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        ClipPath(
          clipper: ShapeBorderClipper(shape: AppTheme.shape(10)),
          child: Image.asset(
            'assets/images/logo.png',
            width: 32,
            height: 32,
            excludeFromSemantics: true,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          context.l10n.appTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// A tab's headline and one line on what it's for.
class PageHeader extends StatelessWidget {
  const new({required this.title, required this.subtitle, super.key});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
