import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_downloader/core/errors/failure_message.dart';
import 'package:media_downloader/core/platform/models/download_progress.dart';
import 'package:media_downloader/core/theme/motion.dart';
import 'package:media_downloader/core/utils/formatters.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/library/data/library_repository_impl.dart';
import 'package:media_downloader/features/library/domain/active_download.dart';
import 'package:media_downloader/features/library/presentation/widgets/library_thumbnail.dart';
import 'package:media_downloader/l10n/l10n.dart';

/// A download in progress: how far along, how fast, and a way to stop it.
class ActiveDownloadTile extends ConsumerWidget {
  const new({required this.download, super.key});

  final ActiveDownload download;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final progress = download.progress;
    final total = download.sizeBytes;

    final status = switch (progress.state) {
      DownloadState.queued => l10n.downloadWaiting,
      DownloadState.running => [
        l10n.percentLabel(progress.percent.floor()),
        ?progress.speed,
        if (total != null)
          l10n.libraryProgress(
            formatByteSize((total * progress.percent / 100).round(), l10n),
            formatByteSize(total, l10n),
          ),
      ].join(' · '),
      _ => l10n.downloadFinishing,
    };
    final fraction = switch (progress.state) {
      DownloadState.queued => 0.0,
      DownloadState.running => progress.percent / 100,
      _ => 1.0,
    };

    return Card(
      color: scheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 16),
        child: Column(
          children: [
            Row(
              children: [
                LibraryThumbnail(
                  type: download.type,
                  thumbnailUrl: download.thumbnailUrl,
                  width: 96,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        download.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        status,
                        maxLines: 2,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          // Digits that don't shift as the numbers change.
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                // Past the point where yt-dlp can be stopped.
                if (progress.state != DownloadState.merging)
                  IconButton(
                    tooltip: l10n.downloadCancel,
                    icon: const Icon(Icons.close_rounded),
                    color: scheme.onSurfaceVariant,
                    onPressed: () => _cancel(context, ref),
                  )
                else
                  const SizedBox(width: 48),
              ],
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: fraction.clamp(0, 1)),
                duration: AppMotion.durationOf(context),
                curve: AppMotion.standard,
                builder: (context, value, _) => LinearProgressIndicator(
                  value: progress.state == DownloadState.queued ? null : value,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                  color: scheme.primary,
                  backgroundColor: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    unawaited(HapticFeedback.lightImpact());
    final result = await ref
        .read(libraryRepositoryProvider)
        .cancel(download.id);
    if (result case Err(:final failure)) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message(l10n))));
    }
  }
}
