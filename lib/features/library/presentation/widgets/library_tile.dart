import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_downloader/core/errors/failure_message.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/core/theme/motion.dart';
import 'package:media_downloader/core/utils/formatters.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/core/widgets/platform_badge.dart';
import 'package:media_downloader/core/widgets/pressable_scale.dart';
import 'package:media_downloader/features/fit/presentation/fit_sheet.dart';
import 'package:media_downloader/features/fit/presentation/video_tools_sheet.dart';
import 'package:media_downloader/features/image_edit/presentation/image_edit_sheet.dart';
import 'package:media_downloader/features/library/data/library_repository_impl.dart';
import 'package:media_downloader/features/library/domain/library_item.dart';
import 'package:media_downloader/features/library/presentation/library_actions.dart';
import 'package:media_downloader/features/library/presentation/library_providers.dart';
import 'package:media_downloader/features/library/presentation/widgets/library_thumbnail.dart';
import 'package:media_downloader/features/tools/presentation/tool_entry.dart';
import 'package:media_downloader/l10n/l10n.dart';

extension on LibraryItem {
  /// "1080p", or the kind of file when there's no quality.
  String kind(AppLocalizations l10n) => switch (type) {
    OutputType.video => switch (quality) {
      final quality? => l10n.qualityLabel(quality),
      null => l10n.outputVideo,
    },
    OutputType.audio => l10n.outputAudio,
    OutputType.image => l10n.outputImage,
    OutputType.document => l10n.outputDocument,
  };
}

/// One saved file: tap to open it; More opens a sheet to share, copy the
/// link or delete it. A long press starts selecting several files; while
/// [selecting], a tap picks or unpicks the file instead.
class LibraryTile extends ConsumerWidget {
  const new({
    required this.item,
    this.selecting = false,
    this.grid = false,
    super.key,
  });

  final LibraryItem item;
  final bool selecting;

  /// A card with a big preview, for the Library's grid; else a row.
  final bool grid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = ref.watch(
      librarySelectionProvider.select((ids) => ids.contains(item.id)),
    );
    final details = [
      // Made by a tool from a file on the phone: there's no site to name.
      if (item.sourceUrl.isEmpty)
        l10n.libraryOnPhone
      else
        item.platform.label(l10n),
      item.kind(l10n),
      if (item.sizeBytes case final size?) formatByteSize(size, l10n),
    ].join(' · ');

    void toggle() {
      unawaited(HapticFeedback.selectionClick());
      ref.read(librarySelectionProvider.notifier).toggle(item.id);
    }

    if (grid) {
      return Semantics(
        selected: selecting ? selected : null,
        child: PressableScale(
          child: Card(
            clipBehavior: Clip.antiAlias,
            color: selected
                ? scheme.secondaryContainer
                : scheme.surfaceContainer,
            child: InkWell(
              onTap: selecting ? toggle : () => _open(context, ref),
              onLongPress: toggle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                          child: LibraryThumbnail(
                            type: item.type,
                            fileUri: item.fileUri,
                            thumbnailUrl: item.thumbnailUrl,
                            width: double.infinity,
                            height: double.infinity,
                          ),
                        ),
                        Positioned(
                          left: 14,
                          bottom: 6,
                          child: PlatformBadge(
                            platform: item.platform,
                            size: 26,
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: selecting
                              ? Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Icon(
                                    selected
                                        ? Icons.check_circle_rounded
                                        : Icons.radio_button_unchecked_rounded,
                                    color: selected
                                        ? scheme.primary
                                        : scheme.onSurface,
                                  ),
                                )
                              : IconButton.filledTonal(
                                  tooltip: l10n.libraryMore,
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.more_vert_rounded),
                                  onPressed: () => _showActions(context, ref),
                                ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          [
                            item.kind(l10n),
                            if (item.sizeBytes case final size?)
                              formatByteSize(size, l10n),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      selected: selecting ? selected : null,
      child: PressableScale(
        scale: 0.985,
        child: Card(
          color: selected ? scheme.secondaryContainer : scheme.surfaceContainer,
          child: InkWell(
            onTap: selecting ? toggle : () => _open(context, ref),
            onLongPress: toggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
              child: Row(
                children: [
                  LibraryThumbnail(
                    type: item.type,
                    fileUri: item.fileUri,
                    thumbnailUrl: item.thumbnailUrl,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          details,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: AppMotion.durationOf(context),
                    switchInCurve: AppMotion.standard,
                    child: selecting
                        ? Padding(
                            key: const ValueKey('check'),
                            padding: const EdgeInsets.all(12),
                            child: Icon(
                              selected
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              color: selected
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                            ),
                          )
                        : IconButton(
                            key: const ValueKey('more'),
                            tooltip: l10n.libraryMore,
                            icon: const Icon(Icons.more_vert_rounded),
                            color: scheme.onSurfaceVariant,
                            onPressed: () => _showActions(context, ref),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showActions(BuildContext context, WidgetRef ref) async {
    final action = await showModalBottomSheet<_Action>(
      context: context,
      // As tall as its rows, not capped at the default 9/16 of the screen.
      isScrollControlled: true,
      builder: (context) => _ActionSheet(item: item),
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case _Action.open:
        await _open(context, ref);
      case _Action.share:
        await shareLibraryItems(context, ref, [item]);
      case _Action.fit:
        await showFitSheet(context, item);
      case _Action.videoTools:
        await showVideoToolsSheet(context, item);
      case _Action.editImage:
        await showImageEditSheet(context, [item]);
      case _Action.pdfTools:
        await showPdfToolPicker(context, item);
      case _Action.copyLink:
        final messenger = ScaffoldMessenger.of(context);
        final copied = context.l10n.libraryLinkCopied;
        await Clipboard.setData(ClipboardData(text: item.sourceUrl));
        unawaited(HapticFeedback.lightImpact());
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(copied)));
      case _Action.delete:
        await deleteLibraryItems(context, ref, [item]);
    }
  }

  /// Opens the file; reports a failure in a snack bar.
  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(libraryRepositoryProvider).open(item);
    if (result case Err(:final failure)) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.message(l10n))));
    }
  }
}

enum _Action {
  open,
  share,
  fit,
  videoTools,
  editImage,
  pdfTools,
  copyLink,
  delete,
}

/// The file at the top, then what can be done with it.
class _ActionSheet extends StatelessWidget {
  const new({required this.item});

  final LibraryItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final details = [
      // "PDF" already names the type.
      if (item.type == OutputType.document)
        item.kind(l10n)
      else
        [item.kind(l10n), ?item.ext?.toUpperCase()].join(' '),
      if (item.sizeBytes case final size?) formatByteSize(size, l10n),
      if (item.sourceUrl.isEmpty)
        l10n.libraryOnPhone
      else
        item.platform.label(l10n),
    ].join(' · ');
    final divider = Divider(
      height: 1,
      indent: 20,
      endIndent: 20,
      color: scheme.outlineVariant.withValues(alpha: 0.6),
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                children: [
                  LibraryThumbnail(
                    type: item.type,
                    fileUri: item.fileUri,
                    thumbnailUrl: item.thumbnailUrl,
                    width: 72,
                    height: 54,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          details,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            divider,
            const SizedBox(height: 8),
            _ActionTile(
              icon: Icons.play_arrow_rounded,
              title: l10n.libraryOpen,
              subtitle: l10n.libraryOpenHint,
              chevron: true,
              onTap: () => Navigator.pop(context, _Action.open),
            ),
            _ActionTile(
              icon: Icons.share_outlined,
              title: l10n.libraryShare,
              subtitle: l10n.libraryShareHint,
              onTap: () => Navigator.pop(context, _Action.share),
            ),
            if (item.type == OutputType.video)
              _ActionTile(
                icon: Icons.compress_rounded,
                title: l10n.fitTitle,
                subtitle: l10n.fitHint,
                onTap: () => Navigator.pop(context, _Action.fit),
              ),
            if (item.type == OutputType.video)
              _ActionTile(
                icon: Icons.auto_fix_high_rounded,
                title: l10n.videoToolsTitle,
                subtitle: l10n.videoToolsHint,
                onTap: () => Navigator.pop(context, _Action.videoTools),
              ),
            if (item.type == OutputType.image)
              _ActionTile(
                icon: Icons.photo_size_select_large_rounded,
                title: l10n.imageEditTitle,
                subtitle: l10n.imageEditHint,
                onTap: () => Navigator.pop(context, _Action.editImage),
              ),
            if (item.type == OutputType.document)
              _ActionTile(
                icon: Icons.picture_as_pdf_outlined,
                title: l10n.pdfTools,
                subtitle: l10n.pdfToolsHint,
                onTap: () => Navigator.pop(context, _Action.pdfTools),
              ),
            // A copy of an image shared from another app has no link.
            if (item.sourceUrl.isNotEmpty)
              _ActionTile(
                icon: Icons.link_rounded,
                title: l10n.libraryCopyLink,
                subtitle: l10n.libraryCopyLinkHint(item.platform.label(l10n)),
                onTap: () => Navigator.pop(context, _Action.copyLink),
              ),
            const SizedBox(height: 8),
            divider,
            const SizedBox(height: 8),
            _ActionTile(
              icon: Icons.delete_outline_rounded,
              title: l10n.libraryDelete,
              subtitle: l10n.libraryDeleteHint,
              destructive: true,
              onTap: () => Navigator.pop(context, _Action.delete),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.chevron = false,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool chevron;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = destructive ? scheme.error : scheme.onSurface;

    return MergeSemantics(
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: destructive
                        ? scheme.errorContainer
                        : scheme.secondaryContainer,
                  ),
                  child: Icon(
                    icon,
                    size: 22,
                    color: destructive
                        ? scheme.onErrorContainer
                        : scheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: color,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: destructive
                              ? scheme.error
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (chevron)
                  Icon(
                    Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
