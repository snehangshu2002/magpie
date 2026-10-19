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
import 'package:media_downloader/l10n/l10n.dart';

/// Says a new version is out, with what's new, and offers to download its
/// APK (or read the release notes) in the browser.
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

class _UpdateSheet extends StatelessWidget {
  const new(this.update);

  final AppUpdate update;

  @override
  Widget build(BuildContext context) {
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
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                shape: const StadiumBorder(),
                textStyle: theme.textTheme.titleMedium?.copyWith(
                  fontFeatures: tabular,
                ),
              ),
              onPressed: () {
                unawaited(HapticFeedback.lightImpact());
                Navigator.pop(context, update.url);
              },
              icon: const Icon(Icons.install_mobile_rounded),
              label: Text(
                size == null
                    ? l10n.updateInstall
                    : l10n.updateInstallSize(size),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                shape: const StadiumBorder(),
                backgroundColor: scheme.surfaceContainerLow,
                foregroundColor: scheme.onSurface,
                textStyle: theme.textTheme.titleMedium,
              ),
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.updateLater),
            ),
          ],
        ),
      ),
    );
  }
}
