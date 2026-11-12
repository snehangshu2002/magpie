import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/errors/failure_message.dart';
import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/core/theme/app_theme.dart';
import 'package:media_downloader/core/theme/motion.dart';
import 'package:media_downloader/core/utils/formatters.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/core/widgets/section_label.dart';
import 'package:media_downloader/core/widgets/sheet_buttons.dart';
import 'package:media_downloader/features/download/domain/save_location.dart';
import 'package:media_downloader/features/image_edit/data/image_edit_repository_impl.dart';
import 'package:media_downloader/features/image_edit/domain/image_plan.dart';
import 'package:media_downloader/features/image_edit/presentation/image_edit_providers.dart';
import 'package:media_downloader/features/library/domain/library_item.dart';
import 'package:media_downloader/features/library/presentation/library_actions.dart';
import 'package:media_downloader/features/library/presentation/library_providers.dart';
import 'package:media_downloader/features/settings/presentation/settings_providers.dart';
import 'package:media_downloader/l10n/l10n.dart';

/// Opens the sheet that makes rotated, cropped, resized, compressed or
/// converted copies of the images [items]: one with every option, or
/// several at once with the options that suit them all.
Future<void> showImageEditSheet(
  BuildContext context,
  List<LibraryItem> items,
) => showModalBottomSheet<void>(
  context: context,
  // Over the navigation bar, not under it.
  useRootNavigator: true,
  isScrollControlled: true,
  builder: (context) => ImageEditSheet(items: items),
);

/// The same sheet for images that aren't in the Library (picked on the
/// phone, or shared from another app), by content URI. Their copies have
/// no link.
Future<void> showImageEditSheetFor(BuildContext context, List<String> uris) =>
    showImageEditSheet(context, [
      for (final uri in uris)
        LibraryItem(
          id: uri,
          title: context.l10n.imageSharedTitle,
          platform: SourcePlatform.other,
          type: OutputType.image,
          fileUri: uri,
          sourceUrl: '',
          savedAt: DateTime.now(),
        ),
    ]);

typedef _Size = ({int width, int height});

/// Pick a shape, size, format and quality, then save the copies.
class ImageEditSheet extends ConsumerStatefulWidget {
  const new({required this.items, super.key});

  final List<LibraryItem> items;

  @override
  ConsumerState<ImageEditSheet> createState() => _ImageEditSheetState();
}

class _ImageEditSheetState extends ConsumerState<ImageEditSheet> {
  final _width = TextEditingController();
  final _height = TextEditingController();
  final _limit = TextEditingController();
  late ImageFormat _format = ImageFormat.fromExt(widget.items.first.ext);
  var _quality = 85;

  /// Degrees clockwise.
  var _rotate = 0;
  CropShape _shape = CropShape.original;

  /// Where the crop sits, 0–1 across and down; the user drags it.
  var _focus = const Offset(0.5, 0.5);

  /// Size of the copies of several images, as a share of each one's own.
  var _percent = 100;

  /// Null while picking; loading while saving; then the copies or, when
  /// none could be made, the failure.
  AsyncValue<List<LibraryItem>>? _job;
  var _made = 0;

  List<LibraryItem> get items => widget.items;
  bool get _many => items.length > 1;

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    _limit.dispose();
    super.dispose();
  }

  /// The size of the picture once turned and cut, before any resizing.
  _Size _shaped(_Size source) {
    final turned = _rotate % 180 == 0
        ? source
        : (width: source.height, height: source.width);
    final crop = centeredCrop(turned.width, turned.height, _shape);
    return crop == null ? turned : (width: crop.width, height: crop.height);
  }

  int? get _limitKb => _limit.text.isEmpty ? null : int.tryParse(_limit.text);

  bool get _limitBad => _limit.text.isNotEmpty && (_limitKb ?? 0) < 1;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final uri = items.first.fileUri;

    final body = switch (_job) {
      AsyncData(value: final copies) => _done(copies),
      AsyncError(:final error) => _failed(switch (error) {
        TooLargeFailure() => l10n.imageTooLarge,
        Failure() => error.message(l10n),
        _ => l10n.failureUnknown,
      }, () => setState(() => _job = null)),
      AsyncLoading() => _spinner(
        _many ? l10n.imageBatchProgress(_made, items.length) : null,
      ),
      null when _many => _options(null),
      null => switch (ref.watch(imageProbeProvider(uri))) {
        AsyncData(value: final source) => _options(source),
        AsyncError(:final error) => _failed(
          error is Failure ? error.message(l10n) : l10n.failureUnknown,
          () => ref.invalidate(imageProbeProvider(uri)),
        ),
        _ => _spinner(null),
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
              l10n.imageEditTitle,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _many ? l10n.imageBatchTitle(items.length) : items.first.title,
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

  /// The picture as its copy will be shaped: turned and cut. Dragging it
  /// moves the crop when part of it is cut off.
  Widget _preview(_Size source, _Size shaped) {
    final uri = items.first.fileUri;
    final image =
        ref.watch(imagePreviewProvider(uri)).value ??
        ref.watch(libraryThumbnailProvider(uri)).value;
    if (image == null) return const SizedBox.shrink();
    final turned = _rotate % 180 == 0
        ? source
        : (width: source.height, height: source.width);
    final cut = _shape != CropShape.original;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        children: [
          SizedBox(
            height: 240,
            child: Center(
              child: AspectRatio(
                aspectRatio: shaped.width / shaped.height,
                child: LayoutBuilder(
                  builder: (context, box) {
                    // How far the picture reaches past the frame, in pixels
                    // on screen.
                    final scale = max(
                      box.maxWidth / turned.width,
                      box.maxHeight / turned.height,
                    );
                    final spareX = turned.width * scale - box.maxWidth;
                    final spareY = turned.height * scale - box.maxHeight;
                    return GestureDetector(
                      onPanUpdate: cut
                          ? (d) => setState(
                              () => _focus = Offset(
                                spareX < 1
                                    ? 0.5
                                    : (_focus.dx - d.delta.dx / spareX).clamp(
                                        0,
                                        1,
                                      ),
                                spareY < 1
                                    ? 0.5
                                    : (_focus.dy - d.delta.dy / spareY).clamp(
                                        0,
                                        1,
                                      ),
                              ),
                            )
                          : null,
                      child: _Shaped(
                        image: image,
                        rotate: _rotate,
                        alignment: Alignment(
                          _focus.dx * 2 - 1,
                          _focus.dy * 2 - 1,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          if (cut) ...[
            const SizedBox(height: 8),
            Text(
              context.l10n.imageCropDragHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Several pictures, each as its copy will be shaped.
  Widget _strip() => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final image = ref
              .watch(libraryThumbnailProvider(items[i].fileUri))
              .value;
          if (image == null) {
            return AspectRatio(
              aspectRatio: _shape.ratio ?? 1,
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            );
          }
          final picture = _Shaped(image: image, rotate: _rotate);
          return switch (_shape.ratio) {
            final ratio? => AspectRatio(aspectRatio: ratio, child: picture),
            null => picture,
          };
        },
      ),
    ),
  );

  /// [source] is the one picture's size; null when there are several.
  Widget _options(_Size? source) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shaped = source == null ? null : _shaped(source);
    if (shaped != null && _width.text.isEmpty && _height.text.isEmpty) {
      _width.text = '${shaped.width}';
      _height.text = '${shaped.height}';
    }
    final width = int.tryParse(_width.text);
    final height = int.tryParse(_height.text);
    final sizeError =
        shaped != null &&
            (width == null ||
                height == null ||
                width < 1 ||
                height < 1 ||
                width > shaped.width ||
                height > shaped.height)
        ? l10n.imageSizeError('${shaped.width}', '${shaped.height}')
        : null;

    int part(int side, int p) => max(1, (side * p / 100).round());

    // The fields follow the picture's new shape.
    void reshape(VoidCallback change) {
      unawaited(HapticFeedback.selectionClick());
      setState(() {
        change();
        _focus = const Offset(0.5, 0.5);
        _width.clear();
        _height.clear();
      });
    }

    // Typing one side sets the other, so the picture keeps its proportions.
    void link(String text, TextEditingController other, {required bool w}) {
      final value = int.tryParse(text);
      if (value != null && value > 0 && shaped != null) {
        final size = scaledSize(
          shaped.width,
          shaped.height,
          maxWidth: w ? value : null,
          maxHeight: w ? null : value,
        );
        other.text = '${w ? size.height : size.width}';
      }
      setState(() {});
    }

    void percent(int p) {
      unawaited(HapticFeedback.selectionClick());
      setState(() {
        _percent = p;
        if (shaped != null) {
          _width.text = '${part(shaped.width, p)}';
          _height.text = '${part(shaped.height, p)}';
        }
      });
    }

    InputDecoration field(String label, {String? suffix, String? helper}) =>
        InputDecoration(
          labelText: label,
          suffixText: suffix,
          helperText: helper,
          helperMaxLines: 2,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        );
    final digits = [FilteringTextInputFormatter.digitsOnly];
    final numbers = theme.textTheme.bodyLarge?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    ChoiceChip chip(String label, {required bool on, VoidCallback? tap}) =>
        ChoiceChip(
          label: Text(label),
          selected: on,
          showCheckmark: false,
          shape: const StadiumBorder(),
          onSelected: (_) => tap?.call(),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (source != null && shaped != null)
          _preview(source, shaped)
        else
          _strip(),
        SectionLabel(l10n.imageShapeLabel),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ActionChip(
              avatar: const Icon(Icons.rotate_right_rounded, size: 18),
              label: Text(_rotate == 0 ? l10n.imageRotate : '$_rotate°'),
              shape: const StadiumBorder(),
              onPressed: () => reshape(() => _rotate = (_rotate + 90) % 360),
            ),
            for (final shape in CropShape.values)
              chip(
                switch (shape) {
                  CropShape.original => l10n.imageCropNone,
                  CropShape.square => '1:1',
                  CropShape.portrait => '4:5',
                  CropShape.wide => '16:9',
                  CropShape.tall => '9:16',
                },
                on: _shape == shape,
                tap: () => reshape(() => _shape = shape),
              ),
          ],
        ),
        const SizedBox(height: 20),
        SectionLabel(l10n.imageSizeLabel),
        const SizedBox(height: 12),
        if (shaped != null) ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _width,
                  keyboardType: TextInputType.number,
                  inputFormatters: digits,
                  style: numbers,
                  decoration: field(l10n.imageWidth, suffix: 'px'),
                  onChanged: (t) => link(t, _height, w: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _height,
                  keyboardType: TextInputType.number,
                  inputFormatters: digits,
                  style: numbers,
                  decoration: field(l10n.imageHeight, suffix: 'px'),
                  onChanged: (t) => link(t, _width, w: false),
                ),
              ),
            ],
          ),
          if (sizeError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                sizeError,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          children: [
            for (final p in const [100, 75, 50, 25])
              chip(
                p == 100 ? l10n.imageOriginalSize : '$p%',
                on: shaped == null
                    ? _percent == p
                    : width == part(shaped.width, p) &&
                          height == part(shaped.height, p),
                tap: () => percent(p),
              ),
          ],
        ),
        const SizedBox(height: 20),
        SectionLabel(l10n.imageFormatLabel),
        const SizedBox(height: 12),
        SegmentedButton<ImageFormat>(
          showSelectedIcon: false,
          segments: [
            for (final f in ImageFormat.values)
              ButtonSegment(value: f, label: Text(f.name.toUpperCase())),
          ],
          selected: {_format},
          onSelectionChanged: (picked) {
            unawaited(HapticFeedback.selectionClick());
            setState(() => _format = picked.single);
          },
        ),
        if (_format.hasQuality) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: SectionLabel(l10n.imageQualityLabel)),
              Text(
                '$_quality%',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: scheme.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          Slider(
            value: _quality.toDouble(),
            min: 10,
            max: 100,
            divisions: 18,
            label: '$_quality%',
            onChanged: (v) => setState(() => _quality = v.round()),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _limit,
          keyboardType: TextInputType.number,
          inputFormatters: digits,
          style: numbers,
          decoration: field(
            l10n.imageLimitLabel,
            suffix: 'KB',
            helper: l10n.imageLimitHint,
          ).copyWith(errorText: _limitBad ? l10n.imageLimitError : null),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        Text(
          l10n.imagePrivacyNote,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          style: primarySheetButton(theme),
          onPressed: sizeError != null || _limitBad
              ? null
              : () => _start(
                  shaped == null ? null : (width: width!, height: height!),
                ),
          child: Text(
            _many ? l10n.imageBatchStart(items.length) : l10n.fitStart,
          ),
        ),
      ],
    );
  }

  /// Makes the copies one after another. [size] is the one picture's new
  /// size; several pictures each get [_percent] of their own.
  Future<void> _start(_Size? size) async {
    final l10n = context.l10n;
    unawaited(HapticFeedback.lightImpact());
    FocusScope.of(context).unfocus();
    final limitKb = _limitKb;
    setState(() {
      _job = const AsyncLoading();
      _made = 0;
    });
    final repository = ref.read(imageEditRepositoryProvider);
    final folder = (await ref.read(settingsProvider.future)).saveFolder;
    final copies = <LibraryItem>[];
    Failure? failure;
    for (final item in items) {
      final probe = await repository.probe(item.fileUri);
      if (probe case Err(failure: final f)) {
        failure ??= f;
      } else if (probe case Ok(value: final source)) {
        final turned = _rotate % 180 == 0
            ? source
            : (width: source.height, height: source.width);
        final crop = centeredCrop(
          turned.width,
          turned.height,
          _shape,
          x: _focus.dx,
          y: _focus.dy,
        );
        final shaped = _shaped(source);
        final out =
            size ??
            scaledSize(
              shaped.width,
              shaped.height,
              maxWidth: max(1, (shaped.width * _percent / 100).round()),
            );
        // File names are cut at 120 characters natively; keep the size
        // visible.
        final title = item.title.length > 90
            ? '${item.title.substring(0, 90).trimRight()}…'
            : item.title;
        final result = await repository.edit(
          id: _newId(),
          item: item,
          targetDir: saveDirFor(folder, item.platform),
          // Under a limit the pixels may shrink too: name it by the limit.
          name: limitKb == null
              ? l10n.imageCopyTitle(title, '${out.width}', '${out.height}')
              : l10n.fitCopyTitle(title, formatByteSize(limitKb * 1000, l10n)),
          format: _format,
          width: out.width,
          height: out.height,
          quality: _format.hasQuality ? _quality : 100,
          targetBytes: limitKb == null ? null : limitKb * 1000,
          rotate: _rotate,
          crop: crop,
        );
        switch (result) {
          case Ok(:final value):
            copies.add(value);
          case Err(failure: final f):
            failure ??= f;
        }
      }
      if (!mounted) return;
      setState(() => _made++);
    }
    setState(
      () => _job = copies.isEmpty
          ? AsyncError(failure ?? const Failure.unknown(), StackTrace.current)
          : AsyncData(copies),
    );
  }

  Widget _done(List<LibraryItem> copies) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final missed = items.length - copies.length;
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
          [
            if (_many)
              l10n.imageBatchDone(copies.length)
            else
              l10n.imageDoneNote(
                copies.single.title,
                formatByteSize(copies.single.sizeBytes ?? 0, l10n),
              ),
            if (missed > 0) l10n.imageBatchMissed(missed),
          ].join(' '),
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
            if (await shareLibraryItems(context, ref, copies)) navigator.pop();
          },
          icon: const Icon(Icons.share_outlined),
          label: Text(l10n.fitShare),
        ),
        const SizedBox(height: 8),
        FilledButton(
          style: secondarySheetButton(theme),
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.fitClose),
        ),
      ],
    );
  }

  Widget _failed(String message, VoidCallback onRetry) {
    final theme = Theme.of(context);
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
          child: Text(context.l10n.fitTryAgain),
        ),
      ],
    );
  }

  /// [progress] says how far along several copies are.
  Widget _spinner(String? progress) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            semanticsLabel: context.l10n.loading,
            color: theme.colorScheme.primary,
          ),
          if (progress != null) ...[
            const SizedBox(height: 16),
            Text(
              progress,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static final _random = Random.secure();

  static String _newId() =>
      [for (var i = 0; i < 16; i++) _random.nextInt(16).toRadixString(16)]
          .join();
}

/// [image] turned [rotate] degrees and cut to fill its box at [alignment].
class _Shaped extends StatelessWidget {
  const new({
    required this.image,
    required this.rotate,
    this.alignment = Alignment.center,
  });

  final Uint8List image;
  final int rotate;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => ClipPath(
    clipper: ShapeBorderClipper(shape: AppTheme.shape(16)),
    child: FittedBox(
      fit: BoxFit.cover,
      alignment: alignment,
      clipBehavior: Clip.hardEdge,
      child: RotatedBox(
        quarterTurns: rotate ~/ 90,
        child: Image.memory(image, gaplessPlayback: true),
      ),
    ),
  );
}
