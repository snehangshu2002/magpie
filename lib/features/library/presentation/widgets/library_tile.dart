import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_downloader/core/errors/failure_message.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/core/theme/app_theme.dart';
import 'package:media_downloader/core/theme/motion.dart';
import 'package:media_downloader/core/utils/formatters.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/core/widgets/platform_badge.dart';
import 'package:media_downloader/features/library/data/library_repository_impl.dart';
import 'package:media_downloader/features/library/domain/library_item.dart';
import 'package:media_downloader/features/library/domain/library_repository.dart';
import 'package:media_downloader/features/library/presentation/library_providers.dart';
import 'package:media_downloader/l10n/l10n.dart';

enum _Action { share, delete }

/// One saved file: tap to open it; the menu shares or deletes it.
class LibraryTile extends ConsumerWidget {
  const new({required this.item, super.key});

  final LibraryItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final details = [
      switch (item.type) {
        OutputType.video => switch (item.quality) {
          final quality? => l10n.qualityLabel(quality),
          null => l10n.outputVideo,
        },
        OutputType.audio => l10n.outputAudio,
        OutputType.image => l10n.outputImage,
      },
      if (item.ext case final ext?) ext.toUpperCase(),
      if (item.sizeBytes case final size?) formatByteSize(size, l10n),
      MaterialLocalizations.of(context).formatShortMonthDay(item.savedAt),
    ].join(' · ');

    return InkWell(
      onTap: () => _run(context, ref, (repository) => repository.open(item)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        child: Row(
          children: [
            _Thumbnail(item: item),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      PlatformBadge(platform: item.platform, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          details,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
            PopupMenuButton<_Action>(
              onSelected: (action) => switch (action) {
                _Action.share => _run(
                  context,
                  ref,
                  (repository) => repository.share(item),
                ),
                _Action.delete => _delete(context, ref),
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _Action.share,
                  child: ListTile(
                    leading: const Icon(Icons.share_outlined),
                    title: Text(l10n.libraryShare),
                  ),
                ),
                PopupMenuItem(
                  value: _Action.delete,
                  child: ListTile(
                    leading: Icon(Icons.delete_outline, color: scheme.error),
                    title: Text(
                      l10n.libraryDelete,
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Runs [call] and reports a failure in a snack bar.
  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<Result<void>> Function(LibraryRepository) call,
  ) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final result = await call(ref.read(libraryRepositoryProvider));
    if (result case Err(:final failure)) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message(l10n))));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    // The tile goes away once the file is deleted; keep what's needed after.
    final messenger = ScaffoldMessenger.of(context);
    final repository = ref.read(libraryRepositoryProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.libraryDeleteTitle),
        content: Text(l10n.libraryDeleteBody(item.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            child: Text(l10n.libraryDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    unawaited(HapticFeedback.mediumImpact());
    switch (await repository.delete(item)) {
      case Ok(value: true):
        messenger.showSnackBar(SnackBar(content: Text(l10n.libraryDeleted)));
      case Ok():
        break;
      case Err(:final failure):
        messenger.showSnackBar(SnackBar(content: Text(failure.message(l10n))));
    }
  }
}

/// A 16:9 preview from the file, else yt-dlp's thumbnail, else an icon for
/// the kind of file.
class _Thumbnail extends ConsumerWidget {
  const new({required this.item});

  final LibraryItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final local = ref.watch(libraryThumbnailProvider(item.fileUri));
    final placeholder = Center(
      child: Icon(switch (item.type) {
        OutputType.video => Icons.movie_outlined,
        OutputType.audio => Icons.music_note_rounded,
        OutputType.image => Icons.image_outlined,
      }, color: scheme.onSurfaceVariant),
    );
    final remote = item.thumbnailUrl;

    return SizedBox(
      width: 112,
      height: 63,
      child: Material(
        shape: AppTheme.shape(12),
        clipBehavior: Clip.antiAlias,
        color: scheme.surfaceContainerHighest,
        child: AnimatedSwitcher(
          duration: AppMotion.durationOf(context),
          child: switch (local) {
            AsyncData(value: final bytes?) => Image.memory(
              bytes,
              key: const ValueKey('local'),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              gaplessPlayback: true,
            ),
            AsyncLoading() => const SizedBox.expand(),
            _ when remote != null => Image.network(
              remote,
              key: const ValueKey('remote'),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, _, _) => placeholder,
            ),
            _ => placeholder,
          },
        ),
      ),
    );
  }
}
