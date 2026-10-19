import 'package:flutter/material.dart';
import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/core/theme/app_theme.dart';
import 'package:media_downloader/core/widgets/platform_badge.dart';
import 'package:media_downloader/l10n/l10n.dart';

/// Shown before a link is entered: which sites work, and how to send a
/// link here from another app.
class SupportedPlatforms extends StatelessWidget {
  const new({super.key});

  static const List<SourcePlatform> _featured = [
    SourcePlatform.youtube,
    SourcePlatform.instagram,
    SourcePlatform.x,
    SourcePlatform.reddit,
    SourcePlatform.tiktok,
    SourcePlatform.facebook,
    SourcePlatform.vimeo,
    SourcePlatform.soundcloud,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = TextStyle(color: scheme.onSurfaceVariant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.supportedTitle,
          style: theme.textTheme.titleSmall?.merge(muted),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final platform in _featured)
              Container(
                padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
                decoration: ShapeDecoration(
                  shape: AppTheme.shape(14),
                  color: scheme.surfaceContainerLow,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PlatformBadge(platform: platform, size: 28),
                    const SizedBox(width: 8),
                    Text(
                      platform.label(l10n),
                      style: theme.textTheme.labelLarge,
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          l10n.supportedMore,
          style: theme.textTheme.bodySmall?.merge(muted),
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.share_outlined, color: scheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    l10n.shareTip(l10n.appTitle),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
