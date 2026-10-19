import 'package:flutter/material.dart';
import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/core/theme/app_theme.dart';
import 'package:media_downloader/core/widgets/platform_badge.dart';
import 'package:media_downloader/core/widgets/section_label.dart';
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
    SourcePlatform.facebook,
  ];

  static const _gap = 12.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(l10n.supportedTitle),
        const SizedBox(height: 4),
        LayoutBuilder(
          builder: (context, constraints) {
            // Fewer, wider tiles when large text needs the room.
            final columns = MediaQuery.textScalerOf(context).scale(1) > 1.3
                ? 3
                : 4;
            final width =
                (constraints.maxWidth - _gap * (columns - 1)) / columns;
            return Wrap(
              alignment: WrapAlignment.center,
              spacing: _gap,
              runSpacing: _gap,
              children: [
                for (final platform in _featured)
                  SizedBox(
                    width: width,
                    child: _PlatformTile(platform: platform),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        Text(
          l10n.supportedMore,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 28),
        const _ShareTip(),
      ],
    );
  }
}

class _PlatformTile extends StatelessWidget {
  const new({required this.platform});

  final SourcePlatform platform;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return MergeSemantics(
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: AppTheme.shape(16),
          color: scheme.surfaceContainerLow,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Column(
            children: [
              // The name is right below; the logo needs no label of its own.
              ExcludeSemantics(child: PlatformBadge(platform: platform)),
              const SizedBox(height: 6),
              Text(
                platform.label(context.l10n),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// How to send a link here without copying it.
class _ShareTip extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
      height: 1.5,
    );

    return DecoratedBox(
      decoration: ShapeDecoration(
        color: scheme.surfaceContainer,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.share_outlined,
                size: 20,
                color: scheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.shareTipTitle, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text.rich(
                    _emphasize(l10n.shareTip(l10n.shareAction, l10n.appTitle), {
                      l10n.shareAction: TextStyle(color: scheme.onSurface),
                      l10n.appTitle: TextStyle(color: scheme.primary),
                    }),
                    style: body,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Sets the first occurrence of each word in [text] in bold [styles].
  static TextSpan _emphasize(String text, Map<String, TextStyle> styles) {
    final marks = [
      for (final MapEntry(key: word, value: style) in styles.entries)
        if (text.indexOf(word) case final start when start >= 0)
          (start, word.length, style),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    final spans = <TextSpan>[];
    var at = 0;
    for (final (start, length, style) in marks) {
      if (start < at) continue;
      spans
        ..add(TextSpan(text: text.substring(at, start)))
        ..add(
          TextSpan(
            text: text.substring(start, start + length),
            style: style.copyWith(fontWeight: FontWeight.w600),
          ),
        );
      at = start + length;
    }
    spans.add(TextSpan(text: text.substring(at)));
    return TextSpan(children: spans);
  }
}
