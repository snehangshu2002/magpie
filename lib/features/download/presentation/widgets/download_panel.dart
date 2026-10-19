import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/core/theme/app_theme.dart';
import 'package:media_downloader/core/theme/motion.dart';
import 'package:media_downloader/core/utils/formatters.dart';
import 'package:media_downloader/features/download/domain/download_option.dart';
import 'package:media_downloader/features/download/domain/save_location.dart';
import 'package:media_downloader/features/download/presentation/media_providers.dart';
import 'package:media_downloader/features/download/presentation/widgets/media_preview_card.dart';
import 'package:media_downloader/l10n/l10n.dart';

extension OutputTypeLabel on OutputType {
  String label(AppLocalizations l10n) => switch (this) {
    OutputType.video => l10n.outputVideo,
    OutputType.audio => l10n.outputAudio,
    OutputType.image => l10n.outputImage,
  };

  IconData get icon => switch (this) {
    OutputType.video => Icons.movie_outlined,
    OutputType.audio => Icons.headphones_outlined,
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
  };
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final options = preview.options;
    final selected =
        ref.watch(selectedDownloadOptionProvider(url)) ?? options.recommended;
    final expanded = ref.watch(optionsExpandedProvider(url));

    void select(DownloadOption option) {
      if (option == selected) return;
      unawaited(HapticFeedback.selectionClick());
      ref.read(selectedDownloadOptionProvider(url).notifier).select(option);
      // A failure shown for the previous choice no longer applies.
      ref.invalidate(downloadStarterProvider(url));
    }

    final list = options.of(selected.type);
    final selectedIndex = list.indexOf(selected);
    final canCollapse =
        list.length > _collapsedCount && selectedIndex < _collapsedCount;
    final visible = canCollapse && !expanded
        ? list.take(_collapsedCount).toList()
        : list;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MediaPreviewCard(info: preview.info, platform: preview.platform),
        const SizedBox(height: 28),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            l10n.saveAs,
            style: theme.textTheme.titleSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (options.types.length > 1) ...[
          SegmentedButton<OutputType>(
            segments: [
              for (final type in options.types)
                ButtonSegment(
                  value: type,
                  icon: Icon(type.icon),
                  label: Text(type.label(l10n)),
                ),
            ],
            selected: {selected.type},
            showSelectedIcon: false,
            onSelectionChanged: (types) =>
                select(options.defaultFor(types.single)),
          ),
          const SizedBox(height: 12),
        ],
        Card(
          child: AnimatedSize(
            duration: AppMotion.durationOf(context),
            curve: AppMotion.standard,
            alignment: Alignment.topCenter,
            child: Column(
              children: [
                for (final (i, option) in visible.indexed) ...[
                  if (i > 0) const Divider(height: 1, indent: 54),
                  _OptionTile(
                    option: option,
                    selected: option == selected,
                    reason: option == options.recommended
                        ? options.reason.text(l10n, options.maxQuality)
                        : null,
                    onTap: () => select(option),
                  ),
                ],
                if (canCollapse) ...[
                  const Divider(height: 1),
                  ListTile(
                    title: Text(
                      expanded
                          ? l10n.showFewerOptions
                          : l10n.showAllOptions(list.length),
                      style: TextStyle(color: scheme.primary),
                    ),
                    trailing: AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: AppMotion.durationOf(context),
                      curve: AppMotion.standard,
                      child: Icon(
                        Icons.expand_more_rounded,
                        color: scheme.primary,
                      ),
                    ),
                    onTap: ref
                        .read(optionsExpandedProvider(url).notifier)
                        .toggle,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              Icon(
                Icons.folder_outlined,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.saveTo(saveDirFor(preview.platform)),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
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

    final title = switch (option.type) {
      OutputType.video when quality != null => l10n.qualityLabel(quality),
      _ => ext ?? option.type.label(l10n),
    };
    final details = [
      if (option.type == OutputType.video && ext != null) ext,
      // 24–30 fps is the norm; only call out smoother video.
      if (option.type == OutputType.video && fps != null && fps > 30)
        l10n.fpsLabel(fps),
      if (size != null) formatByteSize(size, l10n) else l10n.sizeUnknown,
    ].join(' · ');

    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              _SelectionMark(selected: selected),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        if (reason != null) _RecommendedTag(l10n.recommended),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      details,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (reason case final reason?) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            size: 14,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              reason,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
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

/// A radio mark that fills with a check when selected.
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
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? scheme.primary : Colors.transparent,
        border: Border.all(
          color: selected ? scheme.primary : scheme.outline,
          width: 2,
        ),
      ),
      child: AnimatedScale(
        scale: selected ? 1 : 0,
        duration: duration,
        curve: AppMotion.standard,
        child: Icon(Icons.check_rounded, size: 14, color: scheme.onPrimary),
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
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: AppTheme.shape(8),
        color: theme.colorScheme.primaryContainer,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          text,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
