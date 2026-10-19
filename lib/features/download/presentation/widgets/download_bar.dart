import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/errors/failure_message.dart';
import 'package:media_downloader/core/platform/models/download_progress.dart';
import 'package:media_downloader/core/theme/app_theme.dart';
import 'package:media_downloader/core/theme/motion.dart';
import 'package:media_downloader/core/utils/formatters.dart';
import 'package:media_downloader/core/widgets/pressable_scale.dart';
import 'package:media_downloader/features/download/domain/download_option.dart';
import 'package:media_downloader/features/download/domain/save_location.dart';
import 'package:media_downloader/features/download/presentation/media_providers.dart';
import 'package:media_downloader/l10n/l10n.dart';

/// The Download button, floating on a translucent bar that content
/// scrolls under. Turns into a progress bar while downloading, and shows
/// where the file was saved, or why it wasn't, right above it.
class DownloadBar extends ConsumerWidget {
  const new({required this.url, required this.preview, super.key});

  final Uri url;
  final MediaPreview preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final option =
        ref.watch(selectedDownloadOptionProvider(url)) ??
        preview.options.recommended;
    final starter = ref.watch(downloadStarterProvider(url));

    ref.listen(downloadStarterProvider(url), (previous, next) {
      final saved = next.value?.state == DownloadState.saved;
      if (saved && previous?.value?.state != DownloadState.saved) {
        unawaited(HapticFeedback.mediumImpact());
      }
    });

    final download = switch (starter) {
      AsyncData(value: final progress?) when progress.state.isActive =>
        progress,
      _ => null,
    };
    final notice = switch (starter) {
      AsyncError(error: final Failure failure) => (
        failure.message(l10n),
        Icons.error_outline_rounded,
        scheme.error,
      ),
      AsyncError() => (
        l10n.failureUnknown,
        Icons.error_outline_rounded,
        scheme.error,
      ),
      AsyncData(value: DownloadProgress(state: DownloadState.saved)) => (
        l10n.downloadSaved(saveDirFor(preview.platform)),
        Icons.check_circle_outline_rounded,
        scheme.primary,
      ),
      _ => null,
    };
    // Translucency costs legibility; drop it when the user asks for contrast.
    final solid = MediaQuery.highContrastOf(context);

    Widget bar = ColoredBox(
      color: scheme.surface.withValues(alpha: solid ? 1 : 0.8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedSize(
              duration: AppMotion.durationOf(context),
              curve: AppMotion.standard,
              child: switch (notice) {
                null => const SizedBox(width: double.infinity),
                (final text, final icon, final color) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Semantics(
                    liveRegion: true,
                    child: Row(
                      children: [
                        Icon(icon, size: 18, color: color),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            text,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: color,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              },
            ),
            // Both are the same height, so the bar doesn't jump.
            AnimatedSwitcher(
              duration: AppMotion.durationOf(context),
              switchInCurve: AppMotion.standard,
              switchOutCurve: AppMotion.standard,
              child: download != null
                  ? _ProgressButton(
                      key: const ValueKey('progress'),
                      progress: download,
                      // Past the point where yt-dlp can be stopped.
                      onCancel: download.state == DownloadState.merging
                          ? null
                          : () {
                              unawaited(HapticFeedback.lightImpact());
                              unawaited(
                                ref
                                    .read(downloadStarterProvider(url).notifier)
                                    .cancel(),
                              );
                            },
                    )
                  : _DownloadButton(
                      key: const ValueKey('download'),
                      sizeBytes: option.sizeBytes,
                      busy: starter.isLoading,
                      onPressed: () {
                        unawaited(HapticFeedback.mediumImpact());
                        unawaited(
                          ref
                              .read(downloadStarterProvider(url).notifier)
                              .start(preview, option),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
    if (!solid) {
      bar = ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: bar,
        ),
      );
    }
    return bar;
  }
}

class _DownloadButton extends StatelessWidget {
  const new({
    required this.sizeBytes,
    required this.busy,
    required this.onPressed,
    super.key,
  });

  final int? sizeBytes;

  /// The request is on its way, e.g. while a permission prompt is open.
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final size = sizeBytes;
    return PressableScale(
      enabled: !busy,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: AppTheme.shape(18),
          textStyle: theme.textTheme.titleMedium,
        ),
        // Stays enabled while starting so it keeps its colour; the
        // spinner says a tap is in progress.
        onPressed: busy ? () {} : onPressed,
        icon: busy
            ? SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: theme.colorScheme.onPrimary,
                ),
              )
            : const Icon(Icons.download_rounded),
        label: Text(
          size == null
              ? l10n.download
              : l10n.downloadWithSize(formatByteSize(size, l10n)),
        ),
      ),
    );
  }
}

/// The Download button's place while a download runs: fills from the
/// leading edge as it progresses, with a cancel button at the end.
class _ProgressButton extends StatelessWidget {
  const new({required this.progress, required this.onCancel, super.key});

  final DownloadProgress progress;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (label, fraction) = switch (progress.state) {
      DownloadState.queued => (l10n.downloadWaiting, 0.0),
      DownloadState.running => (
        l10n.downloadRunning(progress.percent.floor()),
        progress.percent / 100,
      ),
      _ => (l10n.downloadFinishing, 1.0),
    };
    final foreground = scheme.onSecondaryContainer;

    return Material(
      color: scheme.secondaryContainer,
      shape: AppTheme.shape(18),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 56,
        child: Stack(
          fit: StackFit.expand,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(end: fraction.clamp(0, 1)),
              duration: AppMotion.durationOf(context),
              curve: AppMotion.standard,
              builder: (context, value, _) => FractionallySizedBox(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: value,
                child: ColoredBox(
                  color: scheme.primary.withValues(alpha: 0.28),
                ),
              ),
            ),
            Row(
              children: [
                const SizedBox(width: 20),
                if (progress.state == DownloadState.running)
                  Icon(Icons.download_rounded, color: foreground)
                else
                  SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: foreground,
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: foreground,
                      // Digits that don't shift as the percentage changes.
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                if (onCancel case final onCancel?)
                  IconButton(
                    tooltip: l10n.downloadCancel,
                    onPressed: onCancel,
                    color: foreground,
                    icon: const Icon(Icons.close_rounded),
                  ),
                const SizedBox(width: 6),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
