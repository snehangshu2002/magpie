import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/errors/failure_message.dart';
import 'package:media_downloader/core/platform/models/download_progress.dart';
import 'package:media_downloader/core/theme/motion.dart';
import 'package:media_downloader/core/utils/formatters.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/core/widgets/pressable_scale.dart';
import 'package:media_downloader/features/download/domain/download_option.dart';
import 'package:media_downloader/features/download/presentation/media_providers.dart';
import 'package:media_downloader/features/download/presentation/start_download.dart';
import 'package:media_downloader/features/download/presentation/widgets/download_panel.dart';
import 'package:media_downloader/features/library/data/library_repository_impl.dart';
import 'package:media_downloader/features/library/domain/library_item.dart';
import 'package:media_downloader/features/settings/domain/app_settings.dart';
import 'package:media_downloader/features/settings/presentation/settings_providers.dart';
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
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();

    ref.listen(downloadStarterProvider(url), (previous, next) {
      final saved = next.value?.state == DownloadState.saved;
      if (saved && previous?.value?.state != DownloadState.saved) {
        unawaited(HapticFeedback.mediumImpact());
      }
      if (next is AsyncError && previous is! AsyncError) {
        unawaited(HapticFeedback.heavyImpact());
      }
    });
    final cancelling = ref.watch(cancelRequestedProvider(url));

    Future<void> open(DownloadProgress saved) async {
      final uri = saved.filePath;
      if (uri == null) return;
      final result = await ref
          .read(libraryRepositoryProvider)
          .open(
            LibraryItem(
              id: saved.id,
              title: preview.info.title,
              platform: preview.platform,
              type: option.type,
              fileUri: uri,
              sourceUrl: url.toString(),
              savedAt: DateTime.now(),
            ),
          );
      if (result case Err(:final failure) when context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.message(l10n))));
      }
    }

    final download = switch (starter) {
      AsyncData(value: final progress?) when progress.state.isActive =>
        progress,
      _ => null,
    };
    final notice = switch (starter) {
      AsyncError(error: final Failure failure) => _Notice(
        _NoticeKind.failed,
        failure.message(l10n),
        Icons.error_outline_rounded,
        scheme.error,
      ),
      AsyncError() => _Notice(
        _NoticeKind.failed,
        l10n.failureUnknown,
        Icons.error_outline_rounded,
        scheme.error,
      ),
      AsyncData(value: final DownloadProgress saved)
          when saved.state == DownloadState.saved =>
        _Notice(
          _NoticeKind.saved,
          l10n.downloadSaved(
            DownloadStarter.saveTargetFor(settings, preview, option),
          ),
          Icons.check_circle_outline_rounded,
          scheme.primary,
          onOpen: saved.filePath == null ? null : () => unawaited(open(saved)),
        ),
      AsyncData(value: DownloadProgress(state: DownloadState.cancelled)) =>
        _Notice(
          _NoticeKind.cancelled,
          l10n.downloadCancelled,
          Icons.info_outline_rounded,
          scheme.onSurfaceVariant,
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
              child: AnimatedSwitcher(
                duration: AppMotion.durationOf(context),
                switchInCurve: AppMotion.standard,
                switchOutCurve: AppMotion.standard,
                child: switch (notice) {
                  null => const SizedBox(
                    key: ValueKey('none'),
                    width: double.infinity,
                  ),
                  final notice => Padding(
                    key: ValueKey(notice.kind),
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Semantics(
                      liveRegion: true,
                      child: Row(
                        children: [
                          Icon(notice.icon, size: 18, color: notice.color),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              notice.text,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: notice.color,
                              ),
                            ),
                          ),
                          if (notice.onOpen case final onOpen?)
                            TextButton(
                              onPressed: onOpen,
                              child: Text(l10n.libraryOpen),
                            ),
                        ],
                      ),
                    ),
                  ),
                },
              ),
            ),
            // Both are the same height, so the bar doesn't jump.
            AnimatedSwitcher(
              duration: AppMotion.durationOf(context),
              switchInCurve: AppMotion.standard,
              switchOutCurve: AppMotion.standard,
              // The outgoing child fades out; it mustn't take taps meanwhile.
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.center,
                children: [
                  for (final child in previous) IgnorePointer(child: child),
                  ?current,
                ],
              ),
              child: download != null
                  ? _ProgressButton(
                      key: const ValueKey('progress'),
                      progress: download,
                      cancelling: cancelling,
                      // Past the point where yt-dlp can be stopped, or
                      // already asked to stop.
                      onCancel:
                          cancelling || download.state == DownloadState.merging
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
                      sizeText: option.sizeText(l10n),
                      again: notice?.kind == _NoticeKind.saved,
                      busy: starter.isLoading,
                      onPressed: () {
                        unawaited(HapticFeedback.lightImpact());
                        unawaited(
                          startDownload(
                            context,
                            ref,
                            url: url,
                            preview: preview,
                            option: option,
                          ),
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

enum _NoticeKind { failed, saved, cancelled }

class _Notice {
  const new(this.kind, this.text, this.icon, this.color, {this.onOpen});

  final _NoticeKind kind;
  final String text;
  final IconData icon;
  final Color color;
  final VoidCallback? onOpen;
}

class _DownloadButton extends StatelessWidget {
  const new({
    required this.sizeText,
    required this.again,
    required this.busy,
    required this.onPressed,
    super.key,
  });

  final String? sizeText;

  /// A copy was just saved; tapping saves another.
  final bool again;

  /// The request is on its way, e.g. while a permission prompt is open.
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final size = sizeText;
    return PressableScale(
      enabled: !busy,
      child: Semantics(
        liveRegion: busy,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            shape: const StadiumBorder(),
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
                    semanticsLabel: l10n.downloadStarting,
                  ),
                )
              : const Icon(Icons.download_rounded),
          label: Text(
            again
                ? l10n.downloadAgain
                : size == null
                ? l10n.download
                : l10n.downloadWithSize(size),
          ),
        ),
      ),
    );
  }
}

/// The Download button's place while a download runs: fills from the
/// leading edge as it progresses, with a cancel button at the end.
class _ProgressButton extends StatefulWidget {
  const new({
    required this.progress,
    required this.cancelling,
    required this.onCancel,
    super.key,
  });

  final DownloadProgress progress;

  /// A cancel was asked for; the engine hasn't confirmed it yet.
  final bool cancelling;
  final VoidCallback? onCancel;

  @override
  State<_ProgressButton> createState() => _ProgressButtonState();
}

class _ProgressButtonState extends State<_ProgressButton> {
  // Merging holds the fill where the download left it.
  late double _fraction = widget.progress.percent / 100;

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress;
    final onCancel = widget.onCancel;
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    switch (progress.state) {
      case DownloadState.queued:
        _fraction = 0;
      case DownloadState.running:
        _fraction = progress.percent / 100;
      case DownloadState.merging ||
          DownloadState.saved ||
          DownloadState.failed ||
          DownloadState.cancelled:
        break;
    }
    final running = progress.state == DownloadState.running;
    final label = widget.cancelling
        ? l10n.downloadCancelling
        : switch (progress.state) {
            DownloadState.queued => l10n.downloadWaiting,
            DownloadState.running => l10n.downloadRunning,
            _ => l10n.downloadFinishing,
          };
    final eta = progress.etaSeconds;
    final speed = progress.speed;
    final rate = running && !widget.cancelling
        ? [
            ?speed,
            if (eta != null) l10n.downloadEta(formatDuration(eta)),
          ].join(' · ')
        : '';
    const tabular = [FontFeature.tabularFigures()];
    final foreground = scheme.onSecondaryContainer;

    return Material(
      color: scheme.secondaryContainer,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: _fraction.clamp(0, 1)),
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
          ),
          // A minimum, so large text grows the button instead of clipping.
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Row(
              children: [
                const SizedBox(width: 20),
                if (running)
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
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: foreground,
                          ),
                        ),
                        if (rate.isNotEmpty)
                          Text(
                            rate,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: foreground,
                              fontFeatures: tabular,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (running && !widget.cancelling) ...[
                  const SizedBox(width: 8),
                  // Never shrinks, so the percentage is always whole.
                  Text(
                    l10n.downloadPercent(progress.percent.floor()),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: foreground,
                      fontFeatures: tabular,
                    ),
                  ),
                ],
                IconButton(
                  tooltip: progress.state == DownloadState.merging
                      ? l10n.downloadCancelUnavailable
                      : l10n.downloadCancel,
                  onPressed: onCancel,
                  color: foreground,
                  icon: const Icon(Icons.close_rounded),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
