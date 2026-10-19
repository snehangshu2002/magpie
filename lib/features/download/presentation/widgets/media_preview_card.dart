import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/errors/failure_message.dart';
import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/core/platform/models/media_info.dart';
import 'package:media_downloader/core/theme/app_theme.dart';
import 'package:media_downloader/core/theme/motion.dart';
import 'package:media_downloader/core/utils/formatters.dart';
import 'package:media_downloader/core/widgets/platform_badge.dart';
import 'package:media_downloader/features/settings/presentation/engine_version_provider.dart';
import 'package:media_downloader/l10n/l10n.dart';

/// Thumbnail, title and source of the fetched media.
class MediaPreviewCard extends StatelessWidget {
  const new({required this.info, required this.platform, super.key});

  final MediaInfo info;
  final SourcePlatform platform;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final thumbnail = info.thumbnail;
    final duration = info.duration;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (thumbnail != null)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: scheme.surfaceContainerHighest),
                  Image.network(
                    thumbnail,
                    fit: BoxFit.cover,
                    frameBuilder: (context, child, frame, synchronous) =>
                        synchronous
                        ? child
                        : AnimatedOpacity(
                            opacity: frame == null ? 0 : 1,
                            duration: AppMotion.durationOf(context),
                            child: child,
                          ),
                    errorBuilder: (_, _, _) => Center(
                      child: PlatformBadge(platform: platform, size: 56),
                    ),
                  ),
                  if (duration != null)
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: _DurationPill(formatDuration(duration)),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    PlatformBadge(platform: platform, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        [
                          platform.label(l10n),
                          if (thumbnail == null && duration != null)
                            formatDuration(duration),
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DurationPill extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: ShapeDecoration(
      shape: AppTheme.shape(8),
      color: Colors.black.withValues(alpha: 0.72),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ),
  );
}

/// Stands in for [MediaPreviewCard] while yt-dlp looks the link up.
class LoadingPreview extends ConsumerWidget {
  const new({required this.platform, super.key});

  final SourcePlatform platform;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // The first lookup after install also unpacks the engine; say so, so a
    // slow first fetch doesn't look stuck.
    final preparing = ref.watch(engineVersionProvider).isLoading;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: const Center(
                child: SizedBox.square(
                  dimension: 28,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                PlatformBadge(platform: platform, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    preparing ? l10n.preparingEngine : l10n.fetchingFormats,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Why the lookup failed, with a way to try again.
class PreviewError extends StatelessWidget {
  const new({required this.error, required this.onRetry, super.key});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final error = this.error;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    error is Failure
                        ? error.message(l10n)
                        : l10n.failureUnknown,
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(l10n.retry),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
