import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/errors/failure_message.dart';
import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/core/platform/models/media_info.dart';
import 'package:media_downloader/core/theme/app_theme.dart';
import 'package:media_downloader/core/theme/motion.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/core/widgets/section_label.dart';
import 'package:media_downloader/features/download/data/media_repository_impl.dart';
import 'package:media_downloader/features/download/domain/save_location.dart';
import 'package:media_downloader/features/download/domain/transcript.dart';
import 'package:media_downloader/features/download/presentation/media_providers.dart';
import 'package:media_downloader/features/download/presentation/post_text_providers.dart';
import 'package:media_downloader/features/settings/presentation/settings_providers.dart';
import 'package:media_downloader/l10n/l10n.dart';

/// What a post says: a video's description or a post's caption, to read and
/// copy, and the transcript of a video that has captions.
class PostTextCard extends ConsumerWidget {
  const new({required this.url, required this.preview, super.key});

  final Uri url;
  final MediaPreview preview;

  /// Longer than this, the text starts collapsed.
  static const _collapsedLines = 4;
  static const _longText = 220;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = preview.info.description;
    final captions = preview.info.captions;
    final expanded = ref.watch(descriptionExpandedProvider(url));
    final long =
        text != null &&
        (text.length > _longText ||
            '\n'.allMatches(text).length >= _collapsedLines);
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
      height: 1.45,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(_title(l10n, preview.platform)),
        Card(
          color: scheme.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (text != null)
                  AnimatedSize(
                    duration: AppMotion.durationOf(context),
                    curve: AppMotion.standard,
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: expanded || !long
                          ? SelectableText(text, style: style)
                          : Text(
                              text,
                              style: style,
                              maxLines: _collapsedLines,
                              overflow: TextOverflow.ellipsis,
                            ),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (long)
                      TextButton(
                        onPressed: ref
                            .read(descriptionExpandedProvider(url).notifier)
                            .toggle,
                        child: Text(
                          expanded ? l10n.postTextLess : l10n.postTextMore,
                        ),
                      ),
                    const Spacer(),
                    if (captions.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: FilledButton.tonalIcon(
                          onPressed: () => _openTranscript(context),
                          icon: const Icon(Icons.subtitles_outlined),
                          label: Text(l10n.transcriptOpen),
                        ),
                      ),
                    if (text != null)
                      IconButton(
                        tooltip: l10n.postTextCopy,
                        onPressed: () => copyText(context, text),
                        icon: const Icon(Icons.copy_rounded),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openTranscript(BuildContext context) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => TranscriptSheet(url: url, preview: preview),
  );

  static String _title(AppLocalizations l10n, SourcePlatform platform) =>
      switch (platform) {
        SourcePlatform.instagram ||
        SourcePlatform.facebook => l10n.postTextCaption,
        SourcePlatform.x => l10n.postTextPost,
        _ => l10n.postTextDescription,
      };
}

/// Puts [text] on the clipboard and says so.
Future<void> copyText(BuildContext context, String text) async {
  final messenger = ScaffoldMessenger.of(context);
  final copied = context.l10n.postTextCopied;
  await Clipboard.setData(ClipboardData(text: text));
  unawaited(HapticFeedback.lightImpact());
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(copied)));
}

/// The transcript of a video, in one of its caption languages, to read,
/// copy or save as a text file.
class TranscriptSheet extends ConsumerWidget {
  const new({required this.url, required this.preview, super.key});

  final Uri url;
  final MediaPreview preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tracks = preview.info.captions;
    final track =
        ref.watch(selectedCaptionProvider(url)) ??
        defaultCaption(
          tracks,
          languageCode: Localizations.localeOf(context).languageCode,
        )!;
    final transcript = ref.watch(transcriptProvider(url, track));
    final text = transcript.value;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.transcriptTitle, style: theme.textTheme.titleLarge),
            if (tracks.length > 1) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: tracks.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => ChoiceChip(
                    label: Text(_trackLabel(l10n, tracks[i])),
                    selected: tracks[i] == track,
                    onSelected: (_) {
                      unawaited(HapticFeedback.selectionClick());
                      ref
                          .read(selectedCaptionProvider(url).notifier)
                          .select(tracks[i]);
                    },
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: scheme.surfaceContainer,
                  shape: AppTheme.shape(20),
                ),
                child: switch (transcript) {
                  AsyncData(:final value) when value.trim().isEmpty => Center(
                    child: Text(
                      l10n.transcriptEmpty,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  AsyncData(:final value) => SingleChildScrollView(
                    controller: scroll,
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      value,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                    ),
                  ),
                  AsyncError(:final error) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            error is Failure
                                ? error.message(l10n)
                                : const Failure.unknown().message(l10n),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          FilledButton.tonal(
                            onPressed: () =>
                                ref.invalidate(transcriptProvider(url, track)),
                            child: Text(l10n.retry),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _ => const Center(child: CircularProgressIndicator()),
                },
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: text == null || text.trim().isEmpty
                        ? null
                        : () => copyText(context, text),
                    icon: const Icon(Icons.copy_rounded),
                    label: Text(l10n.postTextCopy),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: text == null || text.trim().isEmpty
                        ? null
                        : () => _save(context, ref, text, track),
                    icon: const Icon(Icons.download_rounded),
                    label: Text(l10n.transcriptSave),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    String text,
    CaptionTrack track,
  ) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final folder = saveDirFor(
      (await ref.read(settingsProvider.future)).saveFolder,
      preview.platform,
    );
    final result = await ref
        .read(mediaRepositoryProvider)
        .saveText(
          name: l10n.transcriptFileName(
            preview.info.captions.length > 1
                ? '${preview.info.title} ${track.lang}'
                : preview.info.title,
          ),
          text: text,
          targetDir: folder,
        );
    unawaited(HapticFeedback.mediumImpact());
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(switch (result) {
            Ok() => l10n.transcriptSaved(folder),
            Err(:final failure) => failure.message(l10n),
          }),
        ),
      );
  }

  static String _trackLabel(AppLocalizations l10n, CaptionTrack track) {
    final name = track.name ?? track.lang;
    return track.auto && !name.contains('(') ? l10n.transcriptAuto(name) : name;
  }
}
