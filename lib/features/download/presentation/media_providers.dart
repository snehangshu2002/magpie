import 'dart:math';

import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/core/platform/models/media_info.dart';
import 'package:media_downloader/features/download/data/media_repository_impl.dart';
import 'package:media_downloader/features/download/domain/download_option.dart';
import 'package:media_downloader/features/download/domain/save_location.dart';
import 'package:media_downloader/features/download/domain/suggest_download_options.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'media_providers.g.dart';

/// What the Download screen shows for one link.
final class MediaPreview {
  const new({
    required this.info,
    required this.platform,
    required this.options,
  });

  final MediaInfo info;

  /// The link's site, or the one yt-dlp reported for unrecognized hosts.
  final SourcePlatform platform;
  final DownloadOptions options;
}

/// Fetches [url] with yt-dlp and works out what to offer.
@riverpod
Future<MediaPreview> mediaPreview(
  Ref ref,
  Uri url,
  SourcePlatform platform,
) async {
  final info = (await ref.watch(mediaRepositoryProvider).fetchInfo(url))
      .getOrThrow();
  final resolved = platform == SourcePlatform.other
      ? SourcePlatform.fromExtractor(info.extractor)
      : platform;
  final options = suggestDownloadOptions(info, platform: resolved);
  if (options == null) throw const Failure.unsupportedUrl();
  return MediaPreview(info: info, platform: resolved, options: options);
}

/// The option the user picked for [url]; null means the recommended one.
@riverpod
class SelectedDownloadOption extends _$SelectedDownloadOption {
  @override
  DownloadOption? build(Uri url) => null;

  // A method, not a setter, to read like the other notifier actions.
  // ignore: use_setters_to_change_properties
  void select(DownloadOption option) => state = option;
}

/// Whether the full option list for [url] is shown, not just the top few.
@riverpod
class OptionsExpanded extends _$OptionsExpanded {
  @override
  bool build(Uri url) => false;

  void toggle() => state = !state;
}

/// Hands the chosen option for [url] to the engine. Holds the download id
/// once queued, or the failure.
@riverpod
class DownloadStarter extends _$DownloadStarter {
  @override
  FutureOr<String?> build(Uri url) => null;

  Future<void> start(SourcePlatform platform, DownloadOption option) async {
    state = const AsyncLoading();
    final request = DownloadRequest(
      id: _newId(),
      url: url.toString(),
      formatId: option.formatSelector,
      outputType: option.type,
      targetDir: saveDirFor(platform),
    );
    final result = await AsyncValue.guard(
      () async =>
          (await ref.read(mediaRepositoryProvider).startDownload(request))
              .getOrThrow(),
    );
    if (ref.mounted) state = result;
  }

  static final _random = Random.secure();

  static String _newId() =>
      [for (var i = 0; i < 16; i++) _random.nextInt(16).toRadixString(16)]
          .join();
}
