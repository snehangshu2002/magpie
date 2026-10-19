import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/core/theme/motion.dart';
import 'package:media_downloader/core/utils/formatters.dart';
import 'package:media_downloader/features/download/domain/download_option.dart';
import 'package:media_downloader/features/download/domain/save_location.dart';
import 'package:media_downloader/features/download/presentation/media_providers.dart';
import 'package:media_downloader/features/download/presentation/widgets/media_preview_card.dart';
import 'package:media_downloader/features/settings/presentation/settings_providers.dart';
import 'package:media_downloader/l10n/l10n.dart';

extension OutputTypeLabel on OutputType {
  String label(AppLocalizations l10n) => switch (this) {
    OutputType.video => l10n.outputVideo,
    OutputType.audio => l10n.outputAudio,
    OutputType.image => l10n.outputImage,
  };

  /// What the saved file contains.
  String detail(AppLocalizations l10n) => switch (this) {
    OutputType.video => l10n.outputVideoDetail,
    OutputType.audio => l10n.outputAudioDetail,
    OutputType.image => l10n.outputImageDetail,
  };

  IconData get icon => switch (this) {
    OutputType.video => Icons.movie_outlined,
    OutputType.audio => Icons.graphic_eq_rounded,
    OutputType.image => Icons.image_outlined,
  };
}

extension RecommendationReasonText on RecommendationReason {
  String text(AppLocalizations l10n, int maxQuality) => switch (this) {
    RecommendationReason.bestUpToCap => l10n.reasonBestUpToCap(maxQuality),
    RecommendationReason.closestToCap => l10n.reasonClosestToCap(maxQuality),
    RecommendationReason.musicSource => l10n.reasonMusicSource,
    RecommendationReason.audioOnly => l10n.reasonAudioOnly,
    RecommendationReason.imageOnly => l10n.reasonImageOnly,
    RecommendationReason.wholePost => l10n.reasonWholePost,
  };
}

extension DownloadOptionPostLabel on DownloadOption {
  /// "19 photos" for an option that saves a whole post; null otherwise.
  String? postLabel(AppLocalizations l10n) => count == 1
      ? null
      : type == OutputType.image
      ? l10n.postPhotos(count)
      : l10n.postFiles(count);
}

/// Preview of the fetched media and the choice of what to save. The common
/// path (the recommended option) is preselected; the rest is one tap away.
class DownloadPanel extends ConsumerWidget {
  const new({required this.url, required this.preview, super.key});

  final Uri url;
  final MediaPreview preview;

  /// Options listed before "Show all"; enough to cover the usual qualities.
  static const _collapsedCount = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final duration = AppMotion.durationOf(context);
    final options = preview.options;
    final selected =
        ref.watch(selectedDownloadOptionProvider(url)) ?? options.recommended;
    final expanded = ref.watch(optionsExpandedProvider(url));
    final saveFolder = ref.watch(
      settingsProvider.select((s) => s.value?.saveFolder ?? defaultSaveFolder),
    );

    void select(DownloadOption option) {
      if (option == selected) return;
      unawaited(HapticFeedback.selectionClick());
      ref.read(selectedDownloadOptionProvider(url).notifier).select(option);
      // A result shown for the previous choice no longer applies.
      ref.read(downloadStarterProvider(url).notifier).dismiss();
    }

    final list = options.of(selected.type);
    final selectedIndex = list.indexOf(selected);
    final canCollapse =
        list.length > _collapsedCount && selectedIndex < _collapsedCount;
    final visible = canCollapse && !expanded
        ? list.take(_collapsedCount).toList()
        : list;
    final ext = selected.ext?.toUpperCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MediaPreviewCard(
          info: preview.info,
          platform: preview.platform,
          availability:
              options.recommended.postLabel(l10n) ??
              l10n.formatsAvailable(
                [for (final type in options.types) ...options.of(type)].length,
              ),
        ),
        const SizedBox(height: 28),
        _SectionHeader(
          title: l10n.saveAs,
          trailing: selected.type.detail(l10n),
        ),
        const SizedBox(height: 10),
        if (options.types.length > 1) ...[
          _TypePicker(
            types: options.types,
            selected: selected.type,
            onSelected: (type) => select(options.defaultFor(type)),
          ),
          const SizedBox(height: 24),
        ],
        _SectionHeader(
          title: selected.type == OutputType.video
              ? l10n.qualityTitle
              : l10n.formatTitle,
          trailing: ext == null ? null : l10n.containerLabel(ext),
        ),
        const SizedBox(height: 10),
        Card(
          color: scheme.surfaceContainer,
          child: AnimatedSize(
            duration: duration,
            curve: AppMotion.standard,
            alignment: Alignment.topCenter,
            child: Column(
              children: [
                for (final (i, option) in visible.indexed) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  _OptionTile(
                    option: option,
                    selected: option == selected,
                    reason: option == options.recommended
                        ? options.reason.text(l10n, options.maxQuality)
                        : null,
                    onTap: () => select(option),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (canCollapse) ...[
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: ref.read(optionsExpandedProvider(url).notifier).toggle,
              style: TextButton.styleFrom(
                foregroundColor: scheme.onSurfaceVariant,
              ),
              iconAlignment: IconAlignment.end,
              icon: AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: duration,
                curve: AppMotion.standard,
                child: const Icon(Icons.expand_more_rounded),
              ),
              label: Text(
                expanded
                    ? l10n.showFewerOptions
                    : l10n.showAllOptions(list.length),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _SaveDestination(path: saveDirFor(saveFolder, preview.platform)),
      ],
    );
  }
}

/// A muted section title with an optional sage note at the end.
class _SectionHeader extends StatelessWidget {
  const new({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (trailing case final trailing?)
            Text(
              trailing,
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

/// Video / Audio / Image as one pill; the selection slides between them.
class _TypePicker extends StatelessWidget {
  const new({
    required this.types,
    required this.selected,
    required this.onSelected,
  });

  final List<OutputType> types;
  final OutputType selected;
  final ValueChanged<OutputType> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final duration = AppMotion.durationOf(context);
    final index = types.indexOf(selected);

    return DecoratedBox(
      decoration: ShapeDecoration(
        color: scheme.surfaceContainer,
        shape: StadiumBorder(
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: SizedBox(
          height: 48,
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedAlign(
                duration: duration,
                curve: AppMotion.standard,
                alignment: AlignmentDirectional(
                  -1 + 2 * index / (types.length - 1),
                  0,
                ).resolve(Directionality.of(context)),
                child: FractionallySizedBox(
                  widthFactor: 1 / types.length,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: scheme.primary,
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final type in types)
                      Expanded(
                        child: _TypeSegment(
                          icon: type.icon,
                          label: type.label(l10n),
                          selected: type == selected,
                          onTap: () => onSelected(type),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeSegment extends StatelessWidget {
  const new({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = selected ? scheme.onPrimary : scheme.onSurfaceVariant;
    final duration = AppMotion.durationOf(context);

    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: color),
          duration: duration,
          curve: AppMotion.standard,
          builder: (context, color, _) => Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const new({
    required this.option,
    required this.selected,
    required this.reason,
    required this.onTap,
  });

  final DownloadOption option;
  final bool selected;

  /// Set on the recommended option: why it was picked.
  final String? reason;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ext = option.ext?.toUpperCase();
    final quality = option.quality;
    final fps = option.fps;
    final size = option.sizeBytes;
    const tabular = [FontFeature.tabularFigures()];

    final title = switch (option.type) {
      _ when option.count > 1 => option.postLabel(l10n)!,
      OutputType.video when quality != null => l10n.qualityLabel(quality),
      _ => ext ?? option.type.label(l10n),
    };
    final details = [
      if (option.type == OutputType.video && fps != null) l10n.fpsLabel(fps),
      if (option.type == OutputType.video && ext != null) ext,
      ?reason,
    ].join(' · ');

    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: Material(
        color: selected ? scheme.surfaceContainerHigh : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Row(
              children: [
                _SelectionMark(selected: selected),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontFeatures: tabular,
                            ),
                          ),
                          if (reason != null) _RecommendedTag(l10n.recommended),
                        ],
                      ),
                      if (details.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          details,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  size == null ? l10n.sizeUnknown : formatByteSize(size, l10n),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: selected
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    fontFeatures: tabular,
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

/// A radio mark: an outline ring, filled with a centre dot when selected.
class _SelectionMark extends StatelessWidget {
  const new({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final duration = AppMotion.durationOf(context);
    return AnimatedContainer(
      duration: duration,
      curve: AppMotion.standard,
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? scheme.primary : Colors.transparent,
        border: Border.all(
          color: selected ? scheme.primary : scheme.outline,
          width: 2,
        ),
      ),
      child: Center(
        child: AnimatedScale(
          scale: selected ? 1 : 0,
          duration: duration,
          curve: AppMotion.standard,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.onPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _RecommendedTag extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: StadiumBorder(side: BorderSide(color: scheme.outlineVariant)),
        color: scheme.surfaceContainerHighest,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: Text(
          text,
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Where the file will be saved.
class _SaveDestination extends StatelessWidget {
  const new({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      color: scheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.surfaceContainerHighest,
              ),
              child: Icon(
                Icons.folder_open_outlined,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.saveDestination.toUpperCase(),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(path, style: theme.textTheme.bodyLarge),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
