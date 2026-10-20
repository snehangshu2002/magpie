import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/errors/failure_message.dart';
import 'package:media_downloader/core/platform/models/download_progress.dart';
import 'package:media_downloader/core/platform/models/video_probe.dart';
import 'package:media_downloader/core/theme/app_theme.dart';
import 'package:media_downloader/core/theme/motion.dart';
import 'package:media_downloader/core/utils/formatters.dart';
import 'package:media_downloader/features/fit/domain/fit_plan.dart';
import 'package:media_downloader/features/fit/presentation/fit_providers.dart';
import 'package:media_downloader/features/library/domain/library_item.dart';
import 'package:media_downloader/features/library/presentation/library_actions.dart';
import 'package:media_downloader/l10n/l10n.dart';

/// Opens the sheet that makes a smaller copy of the video [item].
Future<void> showFitSheet(BuildContext context, LibraryItem item) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => FitSheet(item: item),
    );

/// Pick a size, then follow the copy until it can be shared.
class FitSheet extends ConsumerStatefulWidget {
  const new({required this.item, super.key});

  final LibraryItem item;

  @override
  ConsumerState<FitSheet> createState() => _FitSheetState();
}

class _FitSheetState extends ConsumerState<FitSheet> {
  ShareSize? _picked;

  /// File name of the copy being made, for the done note.
  String? _name;

  LibraryItem get item => widget.item;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final job = ref.watch(fitJobProvider(item.id));

    final body = switch (job) {
      AsyncError(:final error) => _Failed(
        message: error is Failure ? error.message(l10n) : l10n.failureUnknown,
        onRetry: () => ref.read(fitJobProvider(item.id).notifier).reset(),
      ),
      AsyncData(
        value: DownloadProgress(state: DownloadState.saved) && final saved,
      ) =>
        _Done(
          name: _name ?? item.title,
          onShare: () => _shareCopy(saved),
          onClose: () => Navigator.pop(context),
        ),
      AsyncData(value: final DownloadProgress p) => _Working(
        progress: p,
        onCancel: () => ref.read(fitJobProvider(item.id).notifier).cancel(),
      ),
      AsyncLoading() => _Working(
        progress: null,
        onCancel: () => ref.read(fitJobProvider(item.id).notifier).cancel(),
      ),
      AsyncData(value: null) => _options(),
    };

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.fitTitle,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.title,
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

  Widget _options() {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final probe = ref.watch(videoProbeProvider(item.fileUri));
    return switch (probe) {
      AsyncData(value: VideoProbe(durationMs: final durationMs?) && final p) =>
        _sizes(p, durationMs),
      AsyncData() => _Note(l10n.fitNoLength),
      AsyncError(:final error) => _Failed(
        message: error is Failure ? error.message(l10n) : l10n.failureUnknown,
        onRetry: () => ref.invalidate(videoProbeProvider(item.fileUri)),
      ),
      _ => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: CircularProgressIndicator(
            semanticsLabel: l10n.loading,
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    };
  }

  Widget _sizes(VideoProbe probe, int durationMs) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final plans = {
      for (final size in ShareSize.values)
        size: planFit(
          targetBytes: size.bytes,
          durationMs: durationMs,
          hasAudio: probe.hasAudio,
          sourceBytes: item.sizeBytes,
          width: probe.width,
          height: probe.height,
        ),
    };
    final picked = _picked ?? defaultShareSize(plans);
    final plan = plans[picked]!;
    final divider = Divider(
      height: 1,
      indent: 56,
      color: scheme.outlineVariant.withValues(alpha: 0.5),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.fitIntro,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          color: scheme.surfaceContainer,
          shape: AppTheme.shape(24),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final (i, size) in ShareSize.values.indexed) ...[
                if (i > 0) divider,
                _SizeRow(
                  size: size,
                  plan: plans[size]!,
                  selected: size == picked,
                  onTap: () {
                    unawaited(HapticFeedback.selectionClick());
                    setState(() => _picked = size);
                  },
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          style: _primaryButton(theme),
          onPressed: switch (plan) {
            FitEncode() => () => _start(picked, plan, durationMs),
            FitAlreadyFits() => _shareOriginal,
            FitTooLong() => null,
          },
          child: Text(
            plan is FitAlreadyFits ? l10n.fitShareAsIs : l10n.fitStart,
          ),
        ),
      ],
    );
  }

  void _start(ShareSize size, FitEncode plan, int durationMs) {
    final l10n = context.l10n;
    unawaited(HapticFeedback.lightImpact());
    // File names are cut at 120 characters natively; keep the size visible.
    final title = item.title.length > 90
        ? '${item.title.substring(0, 90).trimRight()}…'
        : item.title;
    final name = l10n.fitCopyTitle(title, formatByteSize(size.bytes, l10n));
    setState(() => _name = name);
    unawaited(
      ref
          .read(fitJobProvider(item.id).notifier)
          .start(
            item: item,
            size: size,
            plan: plan,
            durationMs: durationMs,
            name: name,
          ),
    );
  }

  Future<void> _shareOriginal() async {
    final navigator = Navigator.of(context);
    if (await shareLibraryItems(context, ref, [item])) navigator.pop();
  }

  Future<void> _shareCopy(DownloadProgress progress) async {
    final uri = progress.filePath;
    if (uri == null) return;
    final navigator = Navigator.of(context);
    final copy = LibraryItem(
      id: progress.id,
      title: _name ?? item.title,
      platform: item.platform,
      type: item.type,
      fileUri: uri,
      sourceUrl: item.sourceUrl,
      savedAt: DateTime.now(),
      mimeType: 'video/mp4',
    );
    if (await shareLibraryItems(context, ref, [copy])) navigator.pop();
  }
}

ButtonStyle _primaryButton(ThemeData theme) => FilledButton.styleFrom(
  minimumSize: const Size.fromHeight(56),
  shape: const StadiumBorder(),
  textStyle: theme.textTheme.titleMedium,
);

ButtonStyle _secondaryButton(ThemeData theme) => FilledButton.styleFrom(
  minimumSize: const Size.fromHeight(56),
  shape: const StadiumBorder(),
  backgroundColor: theme.colorScheme.surfaceContainerLow,
  foregroundColor: theme.colorScheme.onSurface,
  textStyle: theme.textTheme.titleMedium,
);

/// One size: what the copy would be like, or why it can't be made.
class _SizeRow extends StatelessWidget {
  const new({
    required this.size,
    required this.plan,
    required this.selected,
    required this.onTap,
  });

  final ShareSize size;
  final FitPlan plan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = plan is! FitTooLong;
    final outcome = switch (plan) {
      FitEncode(:final shortSide, :final estimatedBytes) => l10n.fitOutcome(
        l10n.qualityLabel(shortSide),
        formatByteSize(estimatedBytes, l10n),
      ),
      FitAlreadyFits() => l10n.fitAlreadyFits,
      FitTooLong() => l10n.fitTooLong,
    };
    final subtitle = [
      if (size == ShareSize.mb10) l10n.fitSizeDiscord,
      outcome,
    ].join(' · ');

    return Semantics(
      selected: selected,
      enabled: enabled,
      inMutuallyExclusiveGroup: true,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatByteSize(size.bytes, l10n),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        subtitle,
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
        ),
      ),
    );
  }
}

/// The copy is being made; [progress] is null until the engine reports.
class _Working extends StatelessWidget {
  const new({required this.progress, required this.onCancel});

  final DownloadProgress? progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final percent = switch (progress) {
      DownloadProgress(state: DownloadState.running, :final percent) => percent,
      _ => null,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(l10n.fitWorking, style: theme.textTheme.titleMedium),
            ),
            if (percent != null)
              Text(
                '${percent.round()}%',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: scheme.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        ClipPath(
          clipper: const ShapeBorderClipper(shape: StadiumBorder()),
          child: LinearProgressIndicator(
            minHeight: 8,
            value: percent == null ? null : percent / 100,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.fitWorkingNote,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          style: _secondaryButton(theme),
          onPressed: progress == null ? null : onCancel,
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}

class _Done extends StatelessWidget {
  const new({required this.name, required this.onShare, required this.onClose});

  final String name;
  final VoidCallback onShare;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

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
          l10n.fitDoneNote(name),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          style: _primaryButton(theme),
          onPressed: onShare,
          icon: const Icon(Icons.share_outlined),
          label: Text(l10n.fitShare),
        ),
        const SizedBox(height: 8),
        FilledButton(
          style: _secondaryButton(theme),
          onPressed: onClose,
          child: Text(l10n.fitClose),
        ),
      ],
    );
  }
}

class _Failed extends StatelessWidget {
  const new({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
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
          style: _secondaryButton(theme),
          onPressed: onRetry,
          child: Text(context.l10n.fitTryAgain),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
