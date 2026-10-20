import 'package:flutter/material.dart';
import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/core/theme/app_theme.dart';
import 'package:media_downloader/core/widgets/platform_badge.dart';
import 'package:media_downloader/core/widgets/section_label.dart';
import 'package:media_downloader/l10n/l10n.dart';

/// Shown before a link is entered: which sites work. Logos, not buttons,
/// so they sit together in one quiet card.
class SupportedPlatforms extends StatelessWidget {
  const new({super.key});

  static const List<SourcePlatform> _featured = [
    SourcePlatform.youtube,
    SourcePlatform.instagram,
    SourcePlatform.x,
    SourcePlatform.facebook,
    SourcePlatform.telegram,
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = [
      for (final platform in _featured) _PlatformItem(platform: platform),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(context.l10n.supportedTitle),
        const SizedBox(height: 4),
        DecoratedBox(
          decoration: ShapeDecoration(
            shape: AppTheme.shape(24),
            color: scheme.surfaceContainer,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 20),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // One row while every name fits its fifth; narrow phones and
                // large text wrap instead of cutting names.
                final fits =
                    constraints.maxWidth / items.length >=
                    MediaQuery.textScalerOf(context).scale(68);
                return fits
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final item in items) Expanded(child: item),
                        ],
                      )
                    : Wrap(
                        alignment: WrapAlignment.center,
                        runSpacing: 16,
                        children: [
                          for (final item in items)
                            SizedBox(
                              width: MediaQuery.textScalerOf(context).scale(96),
                              child: item,
                            ),
                        ],
                      );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _PlatformItem extends StatelessWidget {
  const new({required this.platform});

  final SourcePlatform platform;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MergeSemantics(
      child: Column(
        children: [
          // The name is right below; the logo needs no label of its own.
          ExcludeSemantics(child: PlatformBadge(platform: platform, size: 48)),
          const SizedBox(height: 8),
          Text(
            platform.label(context.l10n),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

/// How to send a link here without copying it.
class ShareTip extends StatelessWidget {
  const new({super.key});

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
                mainAxisSize: MainAxisSize.min,
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
