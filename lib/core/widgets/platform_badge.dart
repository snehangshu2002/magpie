import 'package:flutter/material.dart';
import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/core/theme/app_theme.dart';
import 'package:media_downloader/l10n/app_localizations.dart';
import 'package:simple_icons/simple_icons.dart';

extension SourcePlatformBrand on SourcePlatform {
  IconData get icon => switch (this) {
    SourcePlatform.youtube => SimpleIcons.youtube,
    SourcePlatform.youtubeMusic => SimpleIcons.youtubemusic,
    SourcePlatform.instagram => SimpleIcons.instagram,
    SourcePlatform.x => SimpleIcons.x,
    SourcePlatform.reddit => SimpleIcons.reddit,
    SourcePlatform.facebook => SimpleIcons.facebook,
    SourcePlatform.tiktok => SimpleIcons.tiktok,
    SourcePlatform.vimeo => SimpleIcons.vimeo,
    SourcePlatform.soundcloud => SimpleIcons.soundcloud,
    SourcePlatform.other => Icons.public,
  };

  Color? get brandColor => switch (this) {
    SourcePlatform.youtube => SimpleIconColors.youtube,
    SourcePlatform.youtubeMusic => SimpleIconColors.youtubemusic,
    SourcePlatform.instagram => SimpleIconColors.instagram,
    SourcePlatform.x => SimpleIconColors.x,
    SourcePlatform.reddit => SimpleIconColors.reddit,
    SourcePlatform.facebook => SimpleIconColors.facebook,
    SourcePlatform.tiktok => SimpleIconColors.tiktok,
    SourcePlatform.vimeo => SimpleIconColors.vimeo,
    SourcePlatform.soundcloud => SimpleIconColors.soundcloud,
    SourcePlatform.other => null,
  };

  String label(AppLocalizations l10n) => brandName ?? l10n.platformOther;
}

/// The site's logo on a soft tint of its brand colour. With no [platform],
/// shows a neutral link glyph (nothing recognized yet).
class PlatformBadge extends StatelessWidget {
  const new({this.platform, this.size = 40, super.key});

  final SourcePlatform? platform;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brand = platform?.brandColor;
    final glyph = brand == null
        ? scheme.onSurfaceVariant
        : _legible(brand, on: scheme.surface, fallback: scheme.onSurface);

    return Container(
      width: size,
      height: size,
      decoration: ShapeDecoration(
        shape: AppTheme.shape(size * 0.3),
        color: brand == null
            ? scheme.surfaceContainerHighest
            : glyph.withValues(alpha: 0.12),
      ),
      child: Icon(
        platform?.icon ?? Icons.link_rounded,
        size: size * 0.5,
        color: glyph,
        semanticLabel: platform?.brandName,
      ),
    );
  }

  /// Keeps the logo at the 3:1 contrast graphics need. Coloured brands are
  /// shifted darker or lighter so their hue survives (Vimeo's light blue on
  /// white); black logos (X, TikTok) on dark surfaces use [fallback].
  static Color _legible(
    Color color, {
    required Color on,
    required Color fallback,
  }) {
    double contrast(Color c) {
      final a = c.computeLuminance();
      final b = on.computeLuminance();
      return (a > b ? a + 0.05 : b + 0.05) / (a > b ? b + 0.05 : a + 0.05);
    }

    if (contrast(color) >= 3) return color;
    var hsl = HSLColor.fromColor(color);
    if (hsl.saturation < 0.1) return fallback;

    final darken = on.computeLuminance() > 0.5;
    for (var i = 0; i < 10 && contrast(hsl.toColor()) < 3; i++) {
      final l = hsl.lightness + (darken ? -0.05 : 0.05);
      hsl = hsl.withLightness(l.clamp(0, 1));
    }
    return contrast(hsl.toColor()) >= 3 ? hsl.toColor() : fallback;
  }
}
