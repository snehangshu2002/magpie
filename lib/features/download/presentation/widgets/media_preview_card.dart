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
import 'package:media_downloader/features/settings/presentation/settings_providers.dart';
import 'package:media_downloader/l10n/l10n.dart';

/// Thumbnail, title and source of the fetched media.
class MediaPreviewCard extends StatelessWidget {
  const new({
    required this.info,
    required this.platform,
    required this.availability,
    super.key,
  });

  final MediaInfo info;
  final SourcePlatform platform;

  /// How many options the user can pick from.
  /// What can be saved, e.g. "3 formats available" or "19 photos".
  final String availability;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final thumbnail = info.thumbnail;
    final duration = info.duration;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return Card(
      color: scheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (thumbnail != null)
              ClipPath(
                clipper: ShapeBorderClipper(shape: AppTheme.shape(16)),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: scheme.surfaceContainerHighest),
                      Image.network(
                        thumbnail,
                        fit: BoxFit.cover,
                        // Decode at the card's size, not the source's.
                        cacheWidth:
                            (MediaQuery.sizeOf(context).width *
                                    MediaQuery.devicePixelRatioOf(context))
                                .round(),
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
                          child: _OverlayPill(text: formatDuration(duration)),
                        ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: platform.label(l10n)),
                        if (thumbnail == null && duration != null) ...[
                          const TextSpan(text: '  •  '),
                          TextSpan(
                            text: formatDuration(duration),
                            style: const TextStyle(
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                        TextSpan(text: '  •  $availability'),
                      ],
                    ),
                    style: muted,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dark, legible-on-any-image label over the thumbnail. Black and white on
/// purpose, not themed: it sits on a photo, not on the surface.
class _OverlayPill extends StatelessWidget {
  const new({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: ShapeDecoration(
      shape: const StadiumBorder(),
      color: Colors.black.withValues(alpha: 0.64),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
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
    // The lookup also waits (up to 20 s) for the downloader to update.
    final updating = ref.watch(engineAutoUpdateProvider).isLoading;

    return Card(
      color: scheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  shape: AppTheme.shape(16),
                  color: scheme.surfaceContainerHighest,
                ),
                child: const Center(
                  child: SizedBox.square(
                    dimension: 28,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
              child: Row(
                children: [
                  PlatformBadge(platform: platform, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      preparing
                          ? l10n.preparingEngine
                          : updating
                          ? l10n.updatingEngine
                          : l10n.fetchingFormats,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Rough shape of the options, so the card doesn't jump on load.
            for (var i = 0; i < 2; i++)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    shape: AppTheme.shape(12),
                    color: scheme.surfaceContainerHighest,
                  ),
                  child: const SizedBox(height: 40),
                ),
              ),
          ],
        ),
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
      color: theme.colorScheme.surfaceContainer,
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
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      error is Failure
                          ? error.message(l10n)
                          : l10n.failureUnknown,
                      style: theme.textTheme.bodyLarge,
                    ),
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
