import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:media_downloader/core/errors/failure_message.dart';
import 'package:media_downloader/core/theme/app_theme.dart';
import 'package:media_downloader/core/utils/formatters.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/core/widgets/section_label.dart';
import 'package:media_downloader/features/updater/data/update_repository_impl.dart';
import 'package:media_downloader/features/updater/domain/app_update.dart';
import 'package:media_downloader/features/updater/presentation/update_providers.dart';
import 'package:media_downloader/l10n/l10n.dart';

/// Says a new version is out, with what's new, and downloads and installs
/// its APK inside the app. The release notes, or the release page when no
/// APK fits this phone, open in the browser.
Future<void> showUpdateSheet(
  BuildContext context,
  WidgetRef ref,
  AppUpdate update,
) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final repository = ref.read(updateRepositoryProvider);
  final url = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _UpdateSheet(update),
  );
  if (url == null) return;
  if (await repository.open(url) case Err(:final failure)) {
    messenger.showSnackBar(SnackBar(content: Text(failure.message(l10n))));
  }
}

class _UpdateSheet extends ConsumerWidget {
  const new(this.update);

  final AppUpdate update;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final size = switch (update.size) {
      final bytes? => formatByteSize(bytes, l10n),
      null => null,
    };
    const tabular = [FontFeature.tabularFigures()];
    final hasNotes = update.notes.isNotEmpty;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ClipPath(
                  clipper: ShapeBorderClipper(shape: AppTheme.shape(16)),
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 56,
                    height: 56,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.updateAvailableTitle(
                          l10n.appTitle,
                          update.version,
                        ),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (hasNotes || size != null) ...[
                        const SizedBox(height: 6),
                        Material(
                          color: scheme.primaryContainer,
                          shape: const StadiumBorder(),
                          child: InkWell(
                            customBorder: const StadiumBorder(),
                            onTap: hasNotes
                                ? () => Navigator.pop(context, update.pageUrl)
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              child: Text(
                                [
                                  ?size,
                                  if (hasNotes) l10n.updateReleaseNotes,
                                ].join(' · '),
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: scheme.onPrimaryContainer,
                                  fontFeatures: tabular,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (hasNotes) ...[
              const SizedBox(height: 20),
              DecoratedBox(
                decoration: ShapeDecoration(
                  color: scheme.surfaceContainerLow,
                  shape: AppTheme.shape(16).copyWith(
                    side: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SectionLabel(
                        l10n.updateWhatsNew,
                        trailing: switch (update.published) {
                          final date? => DateFormat.yMMM(
                            l10n.localeName,
                          ).format(date.toLocal()),
                          null => null,
                        },
                      ),
                      Divider(
                        height: 1,
                        color: scheme.outlineVariant.withValues(alpha: 0.6),
                      ),
                      const SizedBox(height: 8),
                      for (final note in update.notes)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('•  ', style: theme.textTheme.bodyLarge),
                              Expanded(
                                child: Text(
                                  note,
                                  style: theme.textTheme.bodyLarge,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            _UpdateActions(update: update, size: size),
          ],
        ),
      ),
    );
  }
}

/// The update button, then progress while the APK downloads, then a way
/// back to Android's installer.
class _UpdateActions extends ConsumerWidget {
  const new({required this.update, required this.size});

  final AppUpdate update;
  final String? size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const tabular = [FontFeature.tabularFigures()];
    final progress = ref.watch(updateDownloadProvider);
    final controller = ref.read(updateDownloadProvider.notifier);
    final primaryStyle = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(56),
      shape: const StadiumBorder(),
      textStyle: theme.textTheme.titleMedium?.copyWith(fontFeatures: tabular),
    );
    final secondaryStyle = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(56),
      shape: const StadiumBorder(),
      backgroundColor: scheme.surfaceContainerLow,
      foregroundColor: scheme.onSurface,
      textStyle: theme.textTheme.titleMedium,
    );
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
      fontFeatures: tabular,
    );

    void start() {
      unawaited(HapticFeedback.lightImpact());
      if (update.installable) {
        unawaited(controller.start(update));
      } else {
        // No APK for this phone: the release page has the files.
        Navigator.pop(context, update.pageUrl);
      }
    }

    final updateButton = FilledButton.icon(
      style: primaryStyle,
      onPressed: start,
      icon: const Icon(Icons.install_mobile_rounded),
      label: Text(
        size == null ? l10n.updateInstall : l10n.updateInstallSize(size!),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        switch (progress) {
          UpdateDownloading(:final received, :final total, :final fraction) =>
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipPath(
                  clipper: const ShapeBorderClipper(shape: StadiumBorder()),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 12,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      fraction == null
                          ? l10n.updateDownloadingUnknown
                          : l10n.updateDownloading((fraction * 100).floor()),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontFeatures: tabular,
                      ),
                    ),
                    const Spacer(),
                    if (total != null)
                      Text(
                        l10n.updateDownloadingSize(
                          formatByteSize(received, l10n),
                          formatByteSize(total, l10n),
                        ),
                        style: muted,
                      ),
                  ],
                ),
              ],
            ),
          UpdateReady(:final path) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.updateReady, style: muted),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: primaryStyle,
                onPressed: () => controller.install(path, update),
                icon: const Icon(Icons.install_mobile_rounded),
                label: Text(l10n.updateInstallAgain),
              ),
            ],
          ),
          UpdateFailed(:final failure) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                failure.message(l10n),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.error,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: primaryStyle,
                onPressed: start,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(l10n.retry),
              ),
            ],
          ),
          UpdateIdle() => updateButton,
        },
        const SizedBox(height: 8),
        FilledButton(
          style: secondaryStyle,
          onPressed: () {
            if (progress is UpdateDownloading) {
              controller.cancel();
            } else {
              Navigator.pop(context);
            }
          },
          child: Text(
            progress is UpdateDownloading ? l10n.cancel : l10n.updateLater,
          ),
        ),
      ],
    );
  }
}
