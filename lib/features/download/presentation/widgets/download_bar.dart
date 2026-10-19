import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/errors/failure_message.dart';
import 'package:media_downloader/core/theme/app_theme.dart';
import 'package:media_downloader/core/theme/motion.dart';
import 'package:media_downloader/core/utils/formatters.dart';
import 'package:media_downloader/core/widgets/pressable_scale.dart';
import 'package:media_downloader/features/download/domain/download_option.dart';
import 'package:media_downloader/features/download/presentation/media_providers.dart';
import 'package:media_downloader/l10n/l10n.dart';

/// The Download button, floating on a translucent bar that content
/// scrolls under. Shows a failure from the last attempt right above it.
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

    ref.listen(downloadStarterProvider(url), (_, next) {
      if (next case AsyncData(value: _?)) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.downloadStarted)));
      }
    });

    final busy = starter.isLoading;
    final error = switch (starter) {
      AsyncError(error: final Failure failure) => failure.message(l10n),
      AsyncError() => l10n.failureUnknown,
      _ => null,
    };
    final size = option.sizeBytes;
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
              child: error == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Semantics(
                        liveRegion: true,
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              size: 18,
                              color: scheme.error,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                error,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: scheme.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
            PressableScale(
              enabled: !busy,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  shape: AppTheme.shape(18),
                  textStyle: theme.textTheme.titleMedium,
                ),
                // Stays enabled while starting so it keeps its colour; the
                // spinner says a tap is in progress.
                onPressed: busy
                    ? () {}
                    : () {
                        unawaited(HapticFeedback.mediumImpact());
                        unawaited(
                          ref
                              .read(downloadStarterProvider(url).notifier)
                              .start(preview.platform, option),
                        );
                      },
                icon: busy
                    ? SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: scheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.download_rounded),
                label: Text(
                  size == null
                      ? l10n.download
                      : l10n.downloadWithSize(formatByteSize(size, l10n)),
                ),
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
