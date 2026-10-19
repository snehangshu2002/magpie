import 'dart:async';
import 'dart:math';

import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/errors/platform_failure.dart';
import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/core/platform/models/download_progress.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/core/platform/models/media_info.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/download/data/media_repository_impl.dart';
import 'package:media_downloader/features/download/domain/download_details.dart';
import 'package:media_downloader/features/download/domain/download_option.dart';
import 'package:media_downloader/features/download/domain/save_location.dart';
import 'package:media_downloader/features/download/domain/suggest_download_options.dart';
import 'package:media_downloader/features/settings/presentation/settings_providers.dart';
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
  final settings = await ref.watch(settingsProvider.future);
  final options = suggestDownloadOptions(
    info,
    platform: resolved,
    maxQuality: settings.maxQuality,
    preferAudioForMusic: settings.preferAudioForMusic,
  );
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

/// Hands the chosen option for [url] to the engine and follows it: null
/// before the first tap, then the latest progress; an error if it could not
/// be started or failed.
@riverpod
class DownloadStarter extends _$DownloadStarter {
  StreamSubscription<DownloadProgress>? _progress;

  @override
  FutureOr<DownloadProgress?> build(Uri url) {
    ref.onDispose(() => _progress?.cancel());
    return null;
  }

  Future<void> start(MediaPreview preview, DownloadOption option) async {
    if (state.value?.state.isActive ?? false) return;
    _stopFollowing();
    state = const AsyncLoading();
    final repository = ref.read(mediaRepositoryProvider);
    final id = _newId();
    // Listen first, so events sent while the call returns are not missed.
    _progress = repository.progressOf(id).listen(_onProgress);
    final result = await repository.startDownload(
      DownloadRequest(
        id: id,
        url: url.toString(),
        formatId: option.formatSelector,
        outputType: option.type,
        targetDir: saveDirFor(preview.platform),
        title: preview.info.title,
      ),
      DownloadDetails(
        platform: preview.platform,
        thumbnail: preview.info.thumbnail,
        ext: option.ext,
        quality: option.quality,
        sizeBytes: option.sizeBytes,
      ),
    );
    if (!ref.mounted) return;
    switch (result) {
      case Ok() when state is AsyncLoading:
        state = AsyncData(
          DownloadProgress(id: id, percent: 0, state: DownloadState.queued),
        );
      case Ok():
        break;
      case Err(:final failure):
        _stopFollowing();
        state = AsyncError(failure, StackTrace.current);
    }
  }

  Future<void> cancel() async {
    final download = state.value;
    if (download == null || !download.state.isActive) return;
    await ref.read(mediaRepositoryProvider).cancelDownload(download.id);
  }

  /// Clears a finished download or failure, e.g. when the user picks another
  /// option. A download in progress keeps showing.
  void dismiss() {
    if (!(state.value?.state.isActive ?? false)) state = const AsyncData(null);
  }

  void _onProgress(DownloadProgress progress) {
    state = progress.state == DownloadState.failed
        ? AsyncError(failureFromNativeCode(progress.error), StackTrace.current)
        : AsyncData(progress);
    if (!progress.state.isActive) _stopFollowing();
  }

  // Not awaited: an EventChannel cancel waits on a platform round trip.
  void _stopFollowing() {
    unawaited(_progress?.cancel());
    _progress = null;
  }

  static final _random = Random.secure();

  static String _newId() =>
      [for (var i = 0; i < 16; i++) _random.nextInt(16).toRadixString(16)]
          .join();
}
