import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_downloader/core/theme/app_theme.dart';
import 'package:media_downloader/features/pdf/domain/pdf_repository.dart';
import 'package:media_downloader/features/pdf/domain/pdf_tool.dart';
import 'package:media_downloader/features/pdf/presentation/pdf_providers.dart';
import 'package:media_downloader/l10n/l10n.dart';

/// Text to draw on a page preview the way `addText` writes it.
typedef PageStamp = ({
  String text,
  TextPlace place,
  double fontSize,
  bool diagonal,
});

/// How one page looks in the preview with the tool's current choices.
typedef PageLook = ({
  bool picked,
  bool removed,
  bool faded,
  int quarterTurns,
  PageStamp? stamp,
});

/// Margin `addText` keeps from the page's edge, in points.
const _textMargin = 28.0;

/// The pages of the PDF at [uri], a few to a row in a box of its own height,
/// drawn as [lookOf] says. Tapping one calls [onTap] (or opens it larger
/// when null); touching and holding always opens it larger.
class PdfPageGrid extends StatelessWidget {
  const new({
    required this.uri,
    required this.pageCount,
    required this.lookOf,
    this.password,
    this.onTap,
    super.key,
  });

  final String uri;
  final String? password;
  final int pageCount;
  final PageLook Function(int page) lookOf;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    final rows = (pageCount / 3).ceil();
    // Short PDFs take only the room they need.
    final height = min<double>(340, rows * 150);
    return SizedBox(
      height: height,
      child: GridView.builder(
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 120,
          childAspectRatio: 0.78,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: pageCount,
        itemBuilder: (context, i) {
          final page = i + 1;
          return PdfPageTile(
            uri: uri,
            password: password,
            page: page,
            pageCount: pageCount,
            look: lookOf(page),
            onTap: onTap == null
                ? () => showPdfPage(context, uri, page, password: password)
                : () => onTap!(page),
            onLongPress: () =>
                showPdfPage(context, uri, page, password: password),
          );
        },
      ),
    );
  }
}

/// One page with its number under it.
class PdfPageTile extends ConsumerWidget {
  const new({
    required this.uri,
    required this.page,
    required this.pageCount,
    required this.look,
    this.password,
    this.onTap,
    this.onLongPress,
    super.key,
  });

  final String uri;
  final String? password;
  final int page;
  final int pageCount;
  final PageLook look;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final image = ref.watch(pdfPageProvider(uri, page, password: password));
    final accent = look.removed ? scheme.error : scheme.primary;
    final marked = look.picked || look.removed;

    Widget sheet = switch (image.value) {
      final PdfPage p => AspectRatio(
        aspectRatio: p.width / p.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(p.bytes, fit: BoxFit.fill, gaplessPlayback: true),
            if (look.stamp case final stamp?)
              _Stamp(
                stamp: stamp,
                page: page,
                pageCount: pageCount,
                pageWidth: p.width.toDouble(),
                pageHeight: p.height.toDouble(),
              ),
          ],
        ),
      ),
      // Loading, or it can't be drawn: a blank page.
      _ => AspectRatio(
        aspectRatio: 1 / sqrt2,
        child: ColoredBox(
          color: Colors.white,
          child: image.isLoading
              ? null
              : Icon(Icons.description_outlined, color: scheme.outline),
        ),
      ),
    };
    sheet = RotatedBox(quarterTurns: look.quarterTurns, child: sheet);

    return Semantics(
      button: true,
      selected: marked,
      label: marked ? l10n.pdfPagePicked(page) : l10n.pdfPageLabel(page),
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          children: [
            Expanded(
              child: AnimatedOpacity(
                opacity: look.faded ? 0.35 : 1,
                duration: const Duration(milliseconds: 150),
                child: Center(
                  child: Stack(
                    children: [
                      DecoratedBox(
                        position: DecorationPosition.foreground,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: marked
                                ? accent
                                : scheme.outlineVariant.withValues(alpha: 0.6),
                            width: marked ? 3 : 1,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: sheet,
                        ),
                      ),
                      if (marked)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: CircleAvatar(
                            radius: 11,
                            backgroundColor: accent,
                            child: Icon(
                              look.removed
                                  ? Icons.close_rounded
                                  : Icons.check_rounded,
                              size: 15,
                              color: look.removed
                                  ? scheme.onError
                                  : scheme.onPrimary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$page',
              style: theme.textTheme.labelSmall?.copyWith(
                color: marked ? accent : scheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The first page of the PDF at [uri], small, for a list of files.
class PdfFirstPage extends ConsumerWidget {
  const new({required this.uri, super.key});

  final String uri;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(pdfPageProvider(uri, 1, size: 120)).value?.bytes;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 36,
        height: 48,
        color: Colors.white,
        child: bytes == null
            ? Icon(
                Icons.picture_as_pdf_outlined,
                size: 20,
                color: Theme.of(context).colorScheme.outline,
              )
            : Image.memory(bytes, fit: BoxFit.contain),
      ),
    );
  }
}

/// Text drawn where `addText` puts it, scaled from points to the preview.
class _Stamp extends StatelessWidget {
  const new({
    required this.stamp,
    required this.page,
    required this.pageCount,
    required this.pageWidth,
    required this.pageHeight,
  });

  final PageStamp stamp;
  final int page;
  final int pageCount;
  final double pageWidth;
  final double pageHeight;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final scale = box.maxWidth / pageWidth;
      final text = stamp.text
          .replaceAll('{n}', '$page')
          .replaceAll('{total}', '$pageCount');
      final style = TextStyle(
        fontSize: max(0.5, stamp.fontSize * scale),
        height: 1,
        color: stamp.diagonal
            ? const Color(0xFF808080).withValues(alpha: 0.3)
            : Colors.black,
      );
      final line = Text(text, maxLines: 1, softWrap: false, style: style);
      if (stamp.diagonal) {
        return Center(
          child: OverflowBox(
            maxWidth: double.infinity,
            child: Transform.rotate(
              angle: -atan2(pageHeight, pageWidth),
              child: line,
            ),
          ),
        );
      }
      final place = stamp.place;
      return Padding(
        padding: EdgeInsets.all(_textMargin * scale),
        child: OverflowBox(
          maxWidth: double.infinity,
          alignment: switch (place) {
            TextPlace.topLeft => Alignment.topLeft,
            TextPlace.topCenter => Alignment.topCenter,
            TextPlace.topRight => Alignment.topRight,
            TextPlace.center => Alignment.center,
            TextPlace.bottomLeft => Alignment.bottomLeft,
            TextPlace.bottomCenter => Alignment.bottomCenter,
            TextPlace.bottomRight => Alignment.bottomRight,
          },
          child: line,
        ),
      );
    },
  );
}

/// Page [page] of the PDF at [uri] full screen: pinch to zoom.
Future<void> showPdfPage(
  BuildContext context,
  String uri,
  int page, {
  String? password,
}) => showDialog<void>(
  context: context,
  builder: (context) => Dialog.fullscreen(
    backgroundColor: Colors.black,
    child: Stack(
      children: [
        Consumer(
          builder: (context, ref, _) {
            final big = ref.watch(
              pdfPageProvider(uri, page, size: 1600, password: password),
            );
            return InteractiveViewer(
              maxScale: 5,
              child: Center(
                child: switch (big.value) {
                  final PdfPage p => Image.memory(p.bytes),
                  _ => const CircularProgressIndicator(),
                },
              ),
            );
          },
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                IconButton.filledTonal(
                  tooltip: context.l10n.fitClose,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 12),
                DecoratedBox(
                  decoration: ShapeDecoration(
                    color: Colors.black54,
                    shape: AppTheme.shape(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Text(
                      context.l10n.pdfPageLabel(page),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  ),
);
