import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/errors/failure_message.dart';
import 'package:media_downloader/core/theme/motion.dart';
import 'package:media_downloader/core/utils/formatters.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/core/widgets/section_label.dart';
import 'package:media_downloader/core/widgets/sheet_buttons.dart';
import 'package:media_downloader/features/download/domain/save_location.dart';
import 'package:media_downloader/features/library/data/library_repository_impl.dart';
import 'package:media_downloader/features/library/domain/library_item.dart';
import 'package:media_downloader/features/library/presentation/library_actions.dart';
import 'package:media_downloader/features/pdf/data/pdf_repository_impl.dart';
import 'package:media_downloader/features/pdf/domain/pdf_repository.dart';
import 'package:media_downloader/features/pdf/domain/pdf_tool.dart';
import 'package:media_downloader/features/pdf/presentation/pdf_providers.dart';
import 'package:media_downloader/features/settings/presentation/settings_providers.dart';
import 'package:media_downloader/l10n/l10n.dart';

/// What [PdfTool.addText] writes.
enum TextMode { text, watermark, pageNumbers }

/// Opens the sheet that runs [tool] over [items] (PDFs, or photos for
/// [PdfTool.fromImages]); [mode] is where [PdfTool.addText] starts.
Future<void> showPdfToolSheet(
  BuildContext context, {
  required PdfTool tool,
  required List<LibraryItem> items,
  TextMode mode = TextMode.text,
}) => showModalBottomSheet<void>(
  context: context,
  // Over the navigation bar, not under it.
  useRootNavigator: true,
  isScrollControlled: true,
  builder: (context) => PdfToolSheet(tool: tool, items: items, mode: mode),
);

/// Pick the tool's options, run it, then share or open what it made.
class PdfToolSheet extends ConsumerStatefulWidget {
  const new({
    required this.tool,
    required this.items,
    this.mode = TextMode.text,
    super.key,
  });

  final PdfTool tool;
  final List<LibraryItem> items;
  final TextMode mode;

  @override
  ConsumerState<PdfToolSheet> createState() => _PdfToolSheetState();
}

class _PdfToolSheetState extends ConsumerState<PdfToolSheet> {
  late PdfTool _tool = widget.tool;
  late final List<LibraryItem> _items = [...widget.items];
  late TextMode _mode = widget.mode;

  final _pages = TextEditingController();
  final _text = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  /// The password the PDF opened with, once the user gave one.
  String? _openedWith;
  var _degrees = 90;
  TextPlace _place = TextPlace.bottomCenter;
  PdfCompression _compression = PdfCompression.medium;
  var _a4 = false;
  var _numberStyle = 0;
  double? _fontSize;

  /// Null while picking; loading while it runs; then the files or a failure.
  AsyncValue<List<LibraryItem>>? _job;

  @override
  void dispose() {
    _pages.dispose();
    _text.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _fromImages => _tool == PdfTool.fromImages;

  double get _size => _fontSize ?? (_mode == TextMode.watermark ? 60 : 12);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final body = switch (_job) {
      AsyncData(value: final made) => _done(made),
      AsyncError(:final error) => _failed(
        error is Failure ? error.message(l10n) : l10n.failureUnknown,
        () => setState(() => _job = null),
      ),
      AsyncLoading() => _spinner(l10n.videoToolWorking),
      null when _fromImages => _options(null),
      null => switch (ref.watch(
        pdfInfoProvider(_items.first.fileUri, password: _openedWith),
      )) {
        AsyncData(value: final info) => _options(info),
        AsyncError(:final error) => _failed(
          error is Failure ? error.message(l10n) : l10n.failureUnknown,
          () => ref.invalidate(pdfInfoProvider(_items.first.fileUri)),
        ),
        _ => _spinner(l10n.loading),
      },
    };

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          0,
          24,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _title(l10n),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _items.length > 1
                  ? (_fromImages
                        ? l10n.imageBatchTitle(_items.length)
                        : l10n.pdfFiles(_items.length))
                  : _items.first.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            AnimatedSize(
              duration: AppMotion.durationOf(context),
              curve: AppMotion.standard,
              alignment: Alignment.topCenter,
              child: body,
            ),
          ],
        ),
      ),
    );
  }

  String _title(AppLocalizations l10n) => switch (_tool) {
    PdfTool.fromImages => l10n.toolImagesToPdf,
    PdfTool.merge => l10n.toolMerge,
    PdfTool.compress => l10n.toolCompress,
    PdfTool.extract => l10n.toolExtract,
    PdfTool.delete => l10n.toolDelete,
    PdfTool.rotate => l10n.toolRotate,
    PdfTool.addText => switch (_mode) {
      TextMode.text => l10n.toolAddText,
      TextMode.watermark => l10n.toolWatermark,
      TextMode.pageNumbers => l10n.toolPageNumbers,
    },
    PdfTool.protect => l10n.toolProtect,
    PdfTool.unlock => l10n.toolUnlock,
    PdfTool.toImages => l10n.toolToImages,
  };

  /// [info] is the first PDF's; null for photos.
  Widget _options(PdfInfo? info) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final pageCount = info?.pages;

    // Locked: it opens with its password first, whatever the tool.
    if (info != null && pageCount == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Note(
            icon: Icons.lock_outline_rounded,
            text: _openedWith == null
                ? l10n.pdfLocked
                : l10n.failureProtectedPdf,
          ),
          const SizedBox(height: 16),
          _passwordField(_password, l10n.pdfPassword),
          const SizedBox(height: 20),
          FilledButton(
            style: primarySheetButton(theme),
            onPressed: () => setState(() => _openedWith = _password.text),
            child: Text(l10n.pdfOpen),
          ),
        ],
      );
    }

    final picked = pageCount == null || _pages.text.trim().isEmpty
        ? null
        : parsePageRange(_pages.text, pageCount);
    final pagesBad = _pages.text.trim().isNotEmpty && picked == null;
    final needsPages = _tool == PdfTool.extract || _tool == PdfTool.delete;
    final pages = picked == null || pageCount == null
        ? null
        : pagesFor(_tool, picked, pageCount);
    final nothingLeft = picked != null && pages == null;
    final textNeeded =
        _tool == PdfTool.addText && _mode != TextMode.pageNumbers;
    final passwordShort = _tool == PdfTool.protect && _password.text.length < 4;
    final passwordsDiffer =
        _tool == PdfTool.protect && _confirm.text != _password.text;

    final ready =
        !pagesBad &&
        !nothingLeft &&
        (!needsPages || pages != null) &&
        (!textNeeded || _text.text.trim().isNotEmpty) &&
        !passwordShort &&
        !passwordsDiffer &&
        (_tool != PdfTool.merge || _items.length > 1);

    final pageField = TextField(
      controller: _pages,
      keyboardType: TextInputType.text,
      decoration: _field(
        needsPages ? l10n.pdfPagesPick : l10n.pdfPagesOptional,
        helper: l10n.pdfPagesHint(pageCount ?? 0),
        error: pagesBad
            ? l10n.pdfPagesBad(pageCount ?? 0)
            : (nothingLeft ? l10n.pdfPagesAll : null),
      ),
      onChanged: (_) => setState(() {}),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pageCount != null && _items.length == 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              [
                l10n.pdfPageCount(pageCount),
                if (info?.size case final size? when size > 0)
                  formatByteSize(size, l10n),
              ].join(' · '),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ...switch (_tool) {
          PdfTool.merge || PdfTool.fromImages => [
            SectionLabel(l10n.pdfOrder),
            const SizedBox(height: 8),
            _orderList(),
            if (_fromImages) ...[
              const SizedBox(height: 20),
              SectionLabel(l10n.pdfPageSize),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: false, label: Text(l10n.pdfPagePhoto)),
                  ButtonSegment(value: true, label: Text(l10n.pdfPageA4)),
                ],
                selected: {_a4},
                onSelectionChanged: (v) => setState(() => _a4 = v.single),
              ),
            ],
            if (_tool == PdfTool.merge && _items.length < 2) ...[
              const SizedBox(height: 12),
              _Note(icon: Icons.info_outline_rounded, text: l10n.pdfMergeTwo),
            ],
          ],
          PdfTool.compress => [
            RadioGroup<PdfCompression>(
              groupValue: _compression,
              onChanged: (v) => setState(() => _compression = v!),
              child: Column(
                children: [
                  for (final level in PdfCompression.values)
                    RadioListTile<PdfCompression>(
                      value: level,
                      contentPadding: EdgeInsets.zero,
                      title: Text(switch (level) {
                        PdfCompression.light => l10n.pdfCompressLight,
                        PdfCompression.medium => l10n.pdfCompressMedium,
                        PdfCompression.strong => l10n.pdfCompressStrong,
                      }),
                      subtitle: Text(switch (level) {
                        PdfCompression.light => l10n.pdfCompressLightHint,
                        PdfCompression.medium => l10n.pdfCompressMediumHint,
                        PdfCompression.strong => l10n.pdfCompressStrongHint,
                      }),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _Note(icon: Icons.info_outline_rounded, text: l10n.pdfCompressNote),
          ],
          PdfTool.extract || PdfTool.delete => [pageField],
          PdfTool.rotate => [
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 90, label: Text(l10n.pdfRotateRight)),
                ButtonSegment(value: 180, label: Text(l10n.pdfRotateHalf)),
                ButtonSegment(value: 270, label: Text(l10n.pdfRotateLeft)),
              ],
              selected: {_degrees},
              onSelectionChanged: (v) => setState(() => _degrees = v.single),
            ),
            const SizedBox(height: 16),
            pageField,
          ],
          PdfTool.addText => _textOptions(pageField),
          PdfTool.protect => [
            _passwordField(
              _password,
              l10n.pdfNewPassword,
              error: _password.text.isNotEmpty && passwordShort
                  ? l10n.pdfPasswordShort
                  : null,
            ),
            const SizedBox(height: 12),
            _passwordField(
              _confirm,
              l10n.pdfConfirmPassword,
              error: _confirm.text.isNotEmpty && passwordsDiffer
                  ? l10n.pdfPasswordsDiffer
                  : null,
            ),
            const SizedBox(height: 12),
            _Note(icon: Icons.warning_amber_rounded, text: l10n.pdfProtectNote),
          ],
          PdfTool.unlock => [
            _Note(
              icon: Icons.lock_open_rounded,
              text: _openedWith == null
                  ? l10n.pdfNotLocked
                  : l10n.pdfUnlockNote,
            ),
          ],
          PdfTool.toImages => [
            _Note(icon: Icons.collections_outlined, text: l10n.pdfToImagesNote),
          ],
        },
        const SizedBox(height: 24),
        FilledButton(
          style: primarySheetButton(theme),
          onPressed: ready && !(_tool == PdfTool.unlock && _openedWith == null)
              ? () => _run(info, pages)
              : null,
          child: Text(l10n.pdfStart),
        ),
      ],
    );
  }

  List<Widget> _textOptions(Widget pageField) {
    final l10n = context.l10n;
    final numbers = [
      ('{n}', '1'),
      ('${l10n.pdfPageWord} {n}', '${l10n.pdfPageWord} 1'),
      ('{n} / {total}', '1 / 9'),
    ];
    return [
      SegmentedButton<TextMode>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(value: TextMode.text, label: Text(l10n.pdfModeText)),
          ButtonSegment(
            value: TextMode.watermark,
            label: Text(l10n.pdfModeWatermark),
          ),
          ButtonSegment(
            value: TextMode.pageNumbers,
            label: Text(l10n.pdfModeNumbers),
          ),
        ],
        selected: {_mode},
        onSelectionChanged: (v) => setState(() {
          _mode = v.single;
          _fontSize = null;
        }),
      ),
      const SizedBox(height: 16),
      if (_mode == TextMode.pageNumbers)
        Wrap(
          spacing: 8,
          children: [
            for (final (i, (_, sample)) in numbers.indexed)
              ChoiceChip(
                label: Text(sample),
                selected: _numberStyle == i,
                showCheckmark: false,
                shape: const StadiumBorder(),
                onSelected: (_) => setState(() => _numberStyle = i),
              ),
          ],
        )
      else
        TextField(
          controller: _text,
          maxLength: 200,
          decoration: _field(
            _mode == TextMode.watermark ? l10n.pdfWatermarkText : l10n.pdfText,
          ),
          onChanged: (_) => setState(() {}),
        ),
      if (_mode != TextMode.watermark) ...[
        const SizedBox(height: 16),
        SectionLabel(l10n.pdfPlace),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final place in TextPlace.values)
              ChoiceChip(
                label: Text(switch (place) {
                  TextPlace.topLeft => l10n.pdfPlaceTopLeft,
                  TextPlace.topCenter => l10n.pdfPlaceTop,
                  TextPlace.topRight => l10n.pdfPlaceTopRight,
                  TextPlace.center => l10n.pdfPlaceCenter,
                  TextPlace.bottomLeft => l10n.pdfPlaceBottomLeft,
                  TextPlace.bottomCenter => l10n.pdfPlaceBottom,
                  TextPlace.bottomRight => l10n.pdfPlaceBottomRight,
                }),
                selected: _place == place,
                showCheckmark: false,
                shape: const StadiumBorder(),
                onSelected: (_) => setState(() => _place = place),
              ),
          ],
        ),
      ],
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(child: SectionLabel(l10n.pdfTextSize)),
          Text(
            '${_size.round()} pt',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
      Slider(
        value: _size,
        min: 8,
        max: _mode == TextMode.watermark ? 120 : 48,
        onChanged: (v) => setState(() => _fontSize = v.roundToDouble()),
      ),
      pageField,
    ];
  }

  Widget _orderList() {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainer,
      child: Column(
        children: [
          for (final (i, item) in _items.indexed)
            ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 14,
                backgroundColor: scheme.primaryContainer,
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              title: _fromImages
                  ? Text(item.title, maxLines: 1)
                  : _PdfName(uri: item.fileUri),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: l10n.pdfMoveUp,
                    icon: const Icon(Icons.arrow_upward_rounded),
                    onPressed: i == 0 ? null : () => _move(i, i - 1),
                  ),
                  IconButton(
                    tooltip: l10n.pdfMoveDown,
                    icon: const Icon(Icons.arrow_downward_rounded),
                    onPressed: i == _items.length - 1
                        ? null
                        : () => _move(i, i + 1),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _move(int from, int to) {
    unawaited(HapticFeedback.selectionClick());
    setState(() => _items.insert(to, _items.removeAt(from)));
  }

  Future<void> _run(PdfInfo? info, List<int>? pages) async {
    final l10n = context.l10n;
    unawaited(HapticFeedback.lightImpact());
    FocusScope.of(context).unfocus();
    setState(() => _job = const AsyncLoading());

    // The PDF's own name, without .pdf, else the Library title.
    var base = info?.name ?? _items.first.title;
    if (base.toLowerCase().endsWith('.pdf')) {
      base = base.substring(0, base.length - 4);
    }
    if (base.length > 90) base = '${base.substring(0, 90).trimRight()}…';
    final suffix = switch (_tool) {
      PdfTool.fromImages => null,
      PdfTool.merge => l10n.pdfSuffixMerged,
      PdfTool.compress => l10n.pdfSuffixCompressed,
      PdfTool.extract || PdfTool.delete => l10n.pdfSuffixPages,
      PdfTool.rotate => l10n.pdfSuffixRotated,
      PdfTool.addText => l10n.pdfSuffixEdited,
      PdfTool.protect => l10n.pdfSuffixLocked,
      PdfTool.unlock => l10n.pdfSuffixUnlocked,
      PdfTool.toImages => null,
    };
    final name = _fromImages
        ? l10n.pdfFromImagesName
        : (suffix == null ? base : l10n.fitCopyTitle(base, suffix));
    final text = switch (_mode) {
      TextMode.pageNumbers => [
        '{n}',
        '${l10n.pdfPageWord} {n}',
        '{n} / {total}',
      ][_numberStyle],
      _ => _text.text.trim(),
    };

    final folder = (await ref.read(settingsProvider.future)).saveFolder;
    final result = await ref
        .read(pdfRepositoryProvider)
        .run(
          tool: _tool,
          items: _items,
          targetDir: saveDirFor(folder, _items.first.platform),
          name: name,
          options: PdfOptions(
            pages: pages,
            degrees: _degrees,
            text: text,
            place: _mode == TextMode.watermark ? TextPlace.center : _place,
            fontSize: _size,
            opacity: _mode == TextMode.watermark ? 0.3 : 1,
            diagonal: _mode == TextMode.watermark,
            password: _tool == PdfTool.protect ? _password.text : _openedWith,
            compression: _compression,
            a4: _a4,
          ),
        );
    if (!mounted) return;
    setState(
      () => _job = switch (result) {
        Ok(:final value) => AsyncData(value),
        Err(:final failure) => AsyncError(failure, StackTrace.current),
      },
    );
  }

  Widget _done(List<LibraryItem> made) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (made.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Note(icon: Icons.check_circle_outline, text: l10n.pdfAlreadySmall),
          const SizedBox(height: 24),
          FilledButton(
            style: secondarySheetButton(theme),
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.fitClose),
          ),
        ],
      );
    }
    final size = made.fold(0, (sum, item) => sum + (item.sizeBytes ?? 0));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle_rounded, color: scheme.primary),
            const SizedBox(width: 12),
            Text(l10n.fitDone, style: theme.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          made.length == 1
              ? l10n.imageDoneNote(
                  made.single.title,
                  formatByteSize(size, l10n),
                )
              : l10n.imageBatchDone(made.length),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          style: primarySheetButton(theme),
          onPressed: () async {
            final navigator = Navigator.of(context);
            if (await shareLibraryItems(context, ref, made)) navigator.pop();
          },
          icon: const Icon(Icons.share_outlined),
          label: Text(l10n.fitShare),
        ),
        const SizedBox(height: 8),
        if (made.length == 1) ...[
          FilledButton.icon(
            style: secondarySheetButton(theme),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final opened = await ref
                  .read(libraryRepositoryProvider)
                  .open(made.single);
              if (opened case Err(:final failure)) {
                messenger.showSnackBar(
                  SnackBar(content: Text(failure.message(l10n))),
                );
              }
            },
            icon: const Icon(Icons.open_in_new_rounded),
            label: Text(l10n.libraryOpen),
          ),
          const SizedBox(height: 8),
        ],
        FilledButton(
          style: secondarySheetButton(theme),
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.fitClose),
        ),
      ],
    );
  }

  Widget _failed(String message, VoidCallback onRetry) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final locked =
        _tool != PdfTool.unlock &&
        switch (_job) {
          AsyncError(error: ProtectedPdfFailure()) => true,
          _ => false,
        };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          message,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          style: secondarySheetButton(theme),
          onPressed: onRetry,
          child: Text(l10n.fitTryAgain),
        ),
        // A locked PDF in a merge: it can be unlocked on its own first.
        if (locked && _items.length == 1) ...[
          const SizedBox(height: 8),
          FilledButton(
            style: secondarySheetButton(theme),
            onPressed: () => setState(() {
              _tool = PdfTool.unlock;
              _job = null;
            }),
            child: Text(l10n.toolUnlock),
          ),
        ],
      ],
    );
  }

  Widget _spinner(String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Center(child: CircularProgressIndicator(semanticsLabel: label)),
  );

  InputDecoration _field(String label, {String? helper, String? error}) =>
      InputDecoration(
        labelText: label,
        helperText: helper,
        errorText: error,
        helperMaxLines: 2,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      );

  Widget _passwordField(
    TextEditingController controller,
    String label, {
    String? error,
  }) => TextField(
    controller: controller,
    obscureText: true,
    autocorrect: false,
    enableSuggestions: false,
    decoration: _field(label, error: error),
    onChanged: (_) => setState(() {}),
  );
}

/// A PDF's file name, or "PDF" until it's known.
class _PdfName extends ConsumerWidget {
  const new({required this.uri});

  final String uri;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Text(
    ref.watch(pdfInfoProvider(uri)).value?.name ?? 'PDF',
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
}

class _Note extends StatelessWidget {
  const new({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
