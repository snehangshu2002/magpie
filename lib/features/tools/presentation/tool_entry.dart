import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_downloader/core/errors/failure_message.dart';
import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/core/theme/app_theme.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/core/widgets/pressable_scale.dart';
import 'package:media_downloader/features/image_edit/presentation/image_edit_sheet.dart';
import 'package:media_downloader/features/library/domain/library_item.dart';
import 'package:media_downloader/features/pdf/data/pdf_repository_impl.dart';
import 'package:media_downloader/features/pdf/domain/pdf_tool.dart';
import 'package:media_downloader/features/pdf/presentation/pdf_tool_sheet.dart';
import 'package:media_downloader/l10n/l10n.dart';

/// A tool as offered on the Tools tab and the home screen.
enum ToolEntry {
  editPhotos(null),
  imagesToPdf(PdfTool.fromImages),
  merge(PdfTool.merge),
  compress(PdfTool.compress),
  extract(PdfTool.extract),
  delete(PdfTool.delete),
  rotate(PdfTool.rotate),
  addText(PdfTool.addText),
  pageNumbers(PdfTool.addText),
  watermark(PdfTool.addText),
  protect(PdfTool.protect),
  unlock(PdfTool.unlock),
  toImages(PdfTool.toImages);

  new(this.tool);

  /// The PDF tool it runs; null for the photo editor.
  final PdfTool? tool;

  /// What [PdfTool.addText] starts on.
  TextMode get textMode => switch (this) {
    pageNumbers => TextMode.pageNumbers,
    watermark => TextMode.watermark,
    _ => TextMode.text,
  };

  /// Starts from photos rather than PDFs.
  bool get takesImages => tool == null || tool!.takesImages;

  IconData get icon => switch (this) {
    editPhotos => Icons.photo_size_select_large_rounded,
    imagesToPdf => Icons.picture_as_pdf_outlined,
    merge => Icons.merge_type_rounded,
    compress => Icons.compress_rounded,
    extract => Icons.call_split_rounded,
    delete => Icons.delete_sweep_outlined,
    rotate => Icons.rotate_right_rounded,
    addText => Icons.text_fields_rounded,
    pageNumbers => Icons.format_list_numbered_rounded,
    watermark => Icons.branding_watermark_outlined,
    protect => Icons.lock_outline_rounded,
    unlock => Icons.lock_open_rounded,
    toImages => Icons.collections_outlined,
  };

  String title(AppLocalizations l10n) => switch (this) {
    editPhotos => l10n.toolEditPhotos,
    imagesToPdf => l10n.toolImagesToPdf,
    merge => l10n.toolMerge,
    compress => l10n.toolCompress,
    extract => l10n.toolExtract,
    delete => l10n.toolDelete,
    rotate => l10n.toolRotate,
    addText => l10n.toolAddText,
    pageNumbers => l10n.toolPageNumbers,
    watermark => l10n.toolWatermark,
    protect => l10n.toolProtect,
    unlock => l10n.toolUnlock,
    toImages => l10n.toolToImages,
  };

  String hint(AppLocalizations l10n) => switch (this) {
    editPhotos => l10n.toolEditPhotosHint,
    imagesToPdf => l10n.toolImagesToPdfHint,
    merge => l10n.toolMergeHint,
    compress => l10n.toolCompressHint,
    extract => l10n.toolExtractHint,
    delete => l10n.toolDeleteHint,
    rotate => l10n.toolRotateHint,
    addText => l10n.toolAddTextHint,
    pageNumbers => l10n.toolPageNumbersHint,
    watermark => l10n.toolWatermarkHint,
    protect => l10n.toolProtectHint,
    unlock => l10n.toolUnlockHint,
    toImages => l10n.toolToImagesHint,
  };

  /// The tools a saved PDF's menu offers.
  static const List<ToolEntry> forPdf = [
    compress,
    extract,
    delete,
    rotate,
    addText,
    pageNumbers,
    watermark,
    protect,
    unlock,
    toImages,
  ];
}

/// Lets the user pick the files [entry] works on, then opens its sheet.
Future<void> launchTool(
  BuildContext context,
  WidgetRef ref,
  ToolEntry entry,
) async {
  unawaited(HapticFeedback.lightImpact());
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final picked = await ref
      .read(pdfRepositoryProvider)
      .pick(images: entry.takesImages, multiple: entry.tool?.takesMany ?? true);
  if (!context.mounted) return;
  switch (picked) {
    case Ok(value: []):
      break; // Backed out of the picker.
    case Ok(value: final uris) when entry == ToolEntry.editPhotos:
      await showImageEditSheetFor(context, uris);
    case Ok(value: final uris):
      await showPdfToolSheet(
        context,
        tool: entry.tool!,
        mode: entry.textMode,
        items: [
          for (final uri in uris)
            LibraryItem(
              id: uri,
              title: entry.takesImages ? l10n.imageSharedTitle : 'PDF',
              platform: SourcePlatform.other,
              type: entry.takesImages ? OutputType.image : OutputType.document,
              fileUri: uri,
              sourceUrl: '',
              savedAt: DateTime.now(),
            ),
        ],
      );
    case Err(:final failure):
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.message(l10n))));
  }
}

/// The PDF tools for the saved PDF [item], as a list; a tap opens one.
Future<void> showPdfToolPicker(BuildContext context, LibraryItem item) async {
  final l10n = context.l10n;
  final entry = await showModalBottomSheet<ToolEntry>(
    context: context,
    // Over the navigation bar, not under it.
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                l10n.pdfTools,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            for (final entry in ToolEntry.forPdf)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                leading: Icon(entry.icon),
                title: Text(entry.title(l10n)),
                subtitle: Text(entry.hint(l10n)),
                onTap: () => Navigator.pop(context, entry),
              ),
          ],
        ),
      ),
    ),
  );
  if (entry == null || !context.mounted) return;
  await showPdfToolSheet(
    context,
    tool: entry.tool!,
    mode: entry.textMode,
    items: [item],
  );
}

/// A tool as a card: its icon on a soft tint, name and one line on it.
class ToolCard extends StatelessWidget {
  const new({required this.entry, required this.onTap, super.key});

  final ToolEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pdf = !entry.takesImages || entry == ToolEntry.imagesToPdf;
    return PressableScale(
      child: Card(
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainer,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: ShapeDecoration(
                    shape: AppTheme.shape(12),
                    color: pdf
                        ? scheme.tertiaryContainer
                        : scheme.primaryContainer,
                  ),
                  child: Icon(
                    entry.icon,
                    size: 22,
                    color: pdf
                        ? scheme.onTertiaryContainer
                        : scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  entry.title(l10n),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.hint(l10n),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// [entries] as a grid of [ToolCard]s inside a scrolling list.
class ToolGrid extends ConsumerWidget {
  const new({required this.entries, this.onTap, super.key});

  final List<ToolEntry> entries;

  /// What a tap does; picks the files and opens the tool when left out.
  final void Function(ToolEntry entry)? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Room for the title and two lines of hint at any text size.
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return GridView.builder(
      shrinkWrap: true,
      // Scrolls with the page around it.
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 92 + 48 * scale,
      ),
      itemCount: entries.length,
      itemBuilder: (context, i) => ToolCard(
        entry: entries[i],
        onTap: () => onTap == null
            ? launchTool(context, ref, entries[i])
            : onTap!(entries[i]),
      ),
    );
  }
}
