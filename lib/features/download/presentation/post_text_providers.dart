import 'package:media_downloader/core/platform/models/media_info.dart';
import 'package:media_downloader/features/download/data/media_repository_impl.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'post_text_providers.g.dart';

/// Whether the description of [url] is shown in full.
@riverpod
class DescriptionExpanded extends _$DescriptionExpanded {
  @override
  bool build(Uri url) => false;

  void toggle() => state = !state;
}

/// The caption track picked in the transcript sheet for [url]; null means
/// the default one (`defaultCaption`).
@riverpod
class SelectedCaption extends _$SelectedCaption {
  @override
  CaptionTrack? build(Uri url) => null;

  // A method, not a setter, to read like the other notifier actions.
  // ignore: use_setters_to_change_properties
  void select(CaptionTrack track) => state = track;
}

/// The words of caption [track] of [url], as plain text.
@riverpod
Future<String> transcript(Ref ref, Uri url, CaptionTrack track) async =>
    (await ref.watch(mediaRepositoryProvider).fetchTranscript(url, track))
        .getOrThrow();
