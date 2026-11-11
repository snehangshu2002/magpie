import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/errors/failure_message.dart';
import 'package:media_downloader/core/platform/models/download_progress.dart';
import 'package:media_downloader/core/platform/models/video_probe.dart';
import 'package:media_downloader/core/theme/motion.dart';
import 'package:media_downloader/core/utils/formatters.dart';
import 'package:media_downloader/core/widgets/sheet_buttons.dart';
import 'package:media_downloader/features/fit/domain/video_tool.dart';
import 'package:media_downloader/features/fit/presentation/fit_providers.dart';
import 'package:media_downloader/features/fit/presentation/fit_sheet.dart';
import 'package:media_downloader/features/library/domain/library_item.dart';
import 'package:media_downloader/features/library/presentation/library_actions.dart';
import 'package:media_downloader/l10n/l10n.dart';

/// Opens the sheet that makes something else from the video [item]: its
/// sound, a part of it, a silent copy, an MP4 or a GIF.
Future<void> showVideoToolsSheet(BuildContext context, LibraryItem item) =>
    showModalBottomSheet<void>(
      context: context,
      // Over the navigation bar, not under it.
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (context) => VideoToolsSheet(item: item),
    );

/// Pick a tool (and a part of the video), then follow the job.
class VideoToolsSheet extends ConsumerStatefulWidget {
  const new({required this.item, super.key});

  final LibraryItem item;

  @override
  ConsumerState<VideoToolsSheet> createState() => _VideoToolsSheetState();
}

class _VideoToolsSheetState extends ConsumerState<VideoToolsSheet> {
  VideoTool _tool = VideoTool.audio;

  /// The part picked for a tool that takes one, in seconds; null is all.
  RangeValues? _range;

  /// The job being run, for the done note and sharing.
  String? _name;
  VideoJob? _job;

  LibraryItem get item => widget.item;

  // Already an MP4: nothing to convert.
  List<VideoTool> get _tools => [
    for (final tool in VideoTool.values)
      if (tool != VideoTool.mp4 || item.ext?.toLowerCase() != 'mp4') tool,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final job = ref.watch(fitJobProvider(item.id));
    final notifier = ref.read(fitJobProvider(item.id).notifier);

    final body = switch (job) {
      AsyncError(:final error) => FitFailed(
        message: switch (error) {
          EncodeFailure() => l10n.videoToolFailed,
          Failure() => error.message(l10n),
          _ => l10n.failureUnknown,
        },
        onRetry: notifier.reset,
      ),
      AsyncData(
        value: DownloadProgress(state: DownloadState.saved) && final saved,
      ) =>
        FitDone(
          name: _name ?? item.title,
          onShare: () => _share(saved),
          onClose: () => Navigator.pop(context),
        ),
      AsyncData(value: final DownloadProgress p) => FitWorking(
        progress: p,
        label: l10n.videoToolWorking,
        onCancel: notifier.cancel,
      ),
      AsyncLoading() => FitWorking(
        progress: null,
        label: l10n.videoToolWorking,
        onCancel: notifier.cancel,
      ),
      AsyncData(value: null) => _options(),
    };

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.videoToolsTitle,
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
    final scheme = theme.colorScheme;
    final probe = ref.watch(videoProbeProvider(item.fileUri));
    final durationMs = switch (probe) {
      AsyncData(value: VideoProbe(:final durationMs?)) => durationMs,
      _ => null,
    };
    if (probe is AsyncError) {
      return FitFailed(
        message: switch (probe.error) {
          final Failure failure => failure.message(l10n),
          _ => l10n.failureUnknown,
        },
        onRetry: () => ref.invalidate(videoProbeProvider(item.fileUri)),
      );
    }
    if (probe.isLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: CircularProgressIndicator(semanticsLabel: l10n.loading),
        ),
      );
    }
    if (durationMs == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(l10n.fitNoLength, style: theme.textTheme.bodyLarge),
      );
    }

    final seconds = durationMs / 1000;
    // A GIF starts as the first few seconds; a trim as the whole video.
    final range =
        _range ??
        RangeValues(
          0,
          _tool == VideoTool.gif ? seconds.clamp(0, 6).toDouble() : seconds,
        );
    final gifTooLong =
        _tool == VideoTool.gif && (range.end - range.start) * 1000 > maxGifMs;
    final divider = Divider(
      height: 1,
      indent: 56,
      color: scheme.outlineVariant.withValues(alpha: 0.5),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: EdgeInsets.zero,
          color: scheme.surfaceContainer,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final (i, tool) in _tools.indexed) ...[
                if (i > 0) divider,
                _ToolRow(
                  tool: tool,
                  selected: tool == _tool,
                  onTap: () {
                    unawaited(HapticFeedback.selectionClick());
                    setState(() {
                      _tool = tool;
                      _range = null;
                    });
                  },
                ),
              ],
            ],
          ),
        ),
        if (_tool.hasRange) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.videoToolRange(
                    formatDuration(range.start.round()),
                    formatDuration(range.end.round()),
                  ),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Text(
                formatDuration((range.end - range.start).round()),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: gifTooLong ? scheme.error : scheme.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          RangeSlider(
            values: range,
            max: seconds,
            labels: RangeLabels(
              formatDuration(range.start.round()),
              formatDuration(range.end.round()),
            ),
            onChanged: (values) => setState(() => _range = values),
          ),
          Text(
            gifTooLong ? l10n.videoToolGifTooLong : l10n.videoToolTrimNote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: gifTooLong ? scheme.error : scheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          style: primarySheetButton(theme),
          onPressed: gifTooLong || range.end - range.start < 0.2
              ? null
              : () => _start(durationMs, range),
          child: Text(l10n.videoToolStart),
        ),
      ],
    );
  }

  void _start(int durationMs, RangeValues range) {
    final l10n = context.l10n;
    unawaited(HapticFeedback.lightImpact());
    final job = planVideoJob(
      _tool,
      durationMs: durationMs,
      sourceExt: item.ext,
      startMs: (range.start * 1000).round(),
      endMs: (range.end * 1000).round(),
    );
    // File names are cut at 120 characters natively; keep the label visible.
    final title = item.title.length > 90
        ? '${item.title.substring(0, 90).trimRight()}…'
        : item.title;
    final name = l10n.fitCopyTitle(title, _tool.label(l10n).toLowerCase());
    setState(() {
      _name = name;
      _job = job;
    });
    unawaited(
      ref
          .read(fitJobProvider(item.id).notifier)
          .startTool(item: item, job: job, name: name),
    );
  }

  Future<void> _share(DownloadProgress progress) async {
    final uri = progress.filePath;
    if (uri == null) return;
    final navigator = Navigator.of(context);
    final copy = LibraryItem(
      id: progress.id,
      title: _name ?? item.title,
      platform: item.platform,
      type: _job?.type ?? item.type,
      fileUri: uri,
      sourceUrl: item.sourceUrl,
      savedAt: DateTime.now(),
      mimeType: _job?.mimeType,
    );
    if (await shareLibraryItems(context, ref, [copy])) navigator.pop();
  }
}

extension on VideoTool {
  String label(AppLocalizations l10n) => switch (this) {
    VideoTool.audio => l10n.videoToolAudio,
    VideoTool.trim => l10n.videoToolTrim,
    VideoTool.mute => l10n.videoToolMute,
    VideoTool.mp4 => l10n.videoToolMp4,
    VideoTool.gif => l10n.videoToolGif,
  };

  String hint(AppLocalizations l10n) => switch (this) {
    VideoTool.audio => l10n.videoToolAudioHint,
    VideoTool.trim => l10n.videoToolTrimHint,
    VideoTool.mute => l10n.videoToolMuteHint,
    VideoTool.mp4 => l10n.videoToolMp4Hint,
    VideoTool.gif => l10n.videoToolGifHint,
  };

  IconData get icon => switch (this) {
    VideoTool.audio => Icons.music_note_rounded,
    VideoTool.trim => Icons.content_cut_rounded,
    VideoTool.mute => Icons.volume_off_rounded,
    VideoTool.mp4 => Icons.movie_outlined,
    VideoTool.gif => Icons.gif_box_outlined,
  };
}

class _ToolRow extends StatelessWidget {
  const new({required this.tool, required this.selected, required this.onTap});

  final VideoTool tool;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Icon(
                tool.icon,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tool.label(l10n),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      tool.hint(l10n),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
