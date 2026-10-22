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
import 'package:media_downloader/features/download/domain/download_args.dart';
import 'package:media_downloader/features/download/domain/download_details.dart';
import 'package:media_downloader/features/download/domain/download_option.dart';
import 'package:media_downloader/features/download/domain/playlist_options.dart';
import 'package:media_downloader/features/download/domain/save_location.dart';
import 'package:media_downloader/features/download/domain/suggest_download_options.dart';
import 'package:media_downloader/features/download/domain/web_photo.dart';
import 'package:media_downloader/features/settings/domain/app_settings.dart';
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

const _engineUpdateWait = Duration(seconds: 20);

/// Fetches [url] with yt-dlp and works out what to offer. Full-size photos
/// yt-dlp leaves out (X, a link to an image) are looked up alongside.
@riverpod
Future<MediaPreview> mediaPreview(
  Ref ref,
  Uri url,
  SourcePlatform platform,
) async {
  final repository = ref.watch(mediaRepositoryProvider);
  final network = networkArgs(await ref.read(settingsProvider.future));
  final photosCall = repository.fetchPhotos(url, platform, options: network);
  // yt-dlp can't read a link to an image file; don't wait for it to say so.
  final info = isImageLink(url) ? null : await _fetchInfo(ref, url, network);
  // A failed photo lookup leaves yt-dlp's result as it is.
  var photos = switch (await photosCall) {
    Ok(:final value) => value,
    Err() => null,
  };
  if (photos == null &&
      info is Err<MediaInfo> &&
      info.failure is UnsupportedUrlFailure) {
    photos = switch (await repository.fetchImage(url, options: network)) {
      Ok(:final value) => value,
      Err() => null,
    };
  }
  final MediaInfo media;
  if (info is Ok<MediaInfo>) {
    media = info.value.thumbnail == null && photos != null
        ? info.value.copyWith(thumbnail: photos.photos.first.previewUrl)
        : info.value;
  } else if (photos != null) {
    media = MediaInfo(
      title: photos.title ?? url.host,
      extractor: '',
      thumbnail: photos.photos.first.previewUrl,
    );
  } else {
    throw (info as Err<MediaInfo>?)?.failure ?? const Failure.unsupportedUrl();
  }
  final resolved = platform == SourcePlatform.other
      ? SourcePlatform.fromExtractor(media.extractor)
      : platform;
  // Only these two shape the options; theme, font or folder changes must not
  // re-fetch the link.
  final (maxQuality, preferAudioForMusic) = await ref.watch(
    settingsProvider.selectAsync((s) => (s.maxQuality, s.preferAudioForMusic)),
  );
  final options = suggestDownloadOptions(
    media,
    platform: resolved,
    photos: photos?.photos ?? const [],
    maxQuality: maxQuality,
    preferAudioForMusic: preferAudioForMusic,
  );
  if (options == null) throw const Failure.unsupportedUrl();
  return MediaPreview(info: media, platform: resolved, options: options);
}

/// Fetches the playlist at [url] and offers its videos, as video or audio.
@riverpod
Future<MediaPreview> playlistPreview(
  Ref ref,
  Uri url,
  SourcePlatform platform,
) async {
  await _waitForEngineUpdate(ref);
  final settings = await ref.read(settingsProvider.future);
  final info =
      (await ref
              .read(mediaRepositoryProvider)
              .fetchPlaylist(url, options: networkArgs(settings)))
          .getOrThrow();
  final resolved = platform == SourcePlatform.other
      ? SourcePlatform.fromExtractor(info.extractor)
      : platform;
  final (maxQuality, preferAudioForMusic) = await ref.watch(
    settingsProvider.selectAsync((s) => (s.maxQuality, s.preferAudioForMusic)),
  );
  final options = playlistOptions(
    info,
    platform: resolved,
    maxQuality: maxQuality,
    preferAudioForMusic: preferAudioForMusic,
  );
  if (options == null) throw const Failure.unsupportedUrl();
  return MediaPreview(
    info: MediaInfo(
      title: info.title,
      extractor: info.extractor,
      thumbnail: info.thumbnail,
    ),
    platform: resolved,
    options: options,
  );
}

Future<Result<MediaInfo>> _fetchInfo(
  Ref ref,
  Uri url,
  List<String> options,
) async {
  await _waitForEngineUpdate(ref);
  return await ref
      .read(mediaRepositoryProvider)
      .fetchInfo(url, options: options);
}

/// A link shared right after launch would otherwise be read by the old
/// yt-dlp while the new one downloads. Doesn't wait forever on a slow network.
Future<void> _waitForEngineUpdate(Ref ref) async {
  try {
    await ref.read(engineAutoUpdateProvider.future).timeout(_engineUpdateWait);
  } on Object {
    // Slow or failed: the installed yt-dlp still reads most sites.
  }
}

/// The part of [url]'s video to save; null saves all of it.
@riverpod
class ClipSelection extends _$ClipSelection {
  @override
  ClipRange? build(Uri url) => null;

  // A method, not a setter, to read like the other notifier actions.
  // ignore: use_setters_to_change_properties
  void set(ClipRange? range) => state = range;
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

/// Whether a cancel for [url] was asked for and the engine hasn't confirmed
/// it yet, so the bar can say "Cancelling…" at once.
@riverpod
class CancelRequested extends _$CancelRequested {
  @override
  bool build(Uri url) => false;

  // Named argument, so a call site reads as what it does.
  // ignore: use_setters_to_change_properties
  void set({required bool value}) => state = value;
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
    ref.read(cancelRequestedProvider(url).notifier).set(value: false);
    state = const AsyncLoading();
    final repository = ref.read(mediaRepositoryProvider);
    final settings = await ref.read(settingsProvider.future);
    final videoKey = option.playlist ? null : videoKeyOf(preview.info, option);
    // A video that is in the Library; deleting it there allows it again.
    if (settings.skipDownloaded &&
        videoKey != null &&
        await repository.isSaved(videoKey)) {
      if (ref.mounted) {
        state = AsyncError(const Failure.nothingNew(), StackTrace.current);
      }
      return;
    }
    final id = _newId();
    // Listen first, so events sent while the call returns are not missed.
    _progress = repository.progressOf(id).listen(_onProgress);
    final result = await repository.startDownload(
      DownloadRequest(
        id: id,
        url: url.toString(),
        formatId: option.formatSelector,
        outputType: option.type,
        targetDir: saveTargetFor(settings, preview, option),
        title: preview.info.title,
        items: option.items,
        imageUrls: option.imageUrls,
        options: downloadArgs(
          settings,
          option,
          clip: option.playlist ? null : ref.read(clipSelectionProvider(url)),
        ),
        playlist: option.playlist,
        // Single videos are checked against the Library above.
        archive: option.playlist && settings.skipDownloaded,
        fileName: switch (settings.fileNameTemplate.trim()) {
          '' => null,
          final template => template,
        },
      ),
      DownloadDetails(
        platform: preview.platform,
        thumbnail:
            preview.options.postItemsOf(option).firstOrNull?.thumbnail ??
            preview.info.thumbnail,
        ext: savedExtOf(settings, option),
        quality: option.quality == bestAvailableQuality ? null : option.quality,
        sizeBytes: option.sizeBytes,
        videoKey: videoKey,
      ),
      record: settings.keepHistory,
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
    final flag = ref.read(cancelRequestedProvider(url).notifier)
      ..set(value: true);
    final result = await ref
        .read(mediaRepositoryProvider)
        .cancelDownload(download.id);
    // Nothing to cancel (already finished): let the bar show the real state.
    if (!ref.mounted) return;
    if (result case Err() || Ok(value: false)) flag.set(value: false);
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
    if (!progress.state.isActive) {
      _stopFollowing();
      ref.read(cancelRequestedProvider(url).notifier).set(value: false);
    }
  }

  // Not awaited: an EventChannel cancel waits on a platform round trip.
  void _stopFollowing() {
    unawaited(_progress?.cancel());
    _progress = null;
  }

  /// Where [option] of [preview] is saved: audio in its own folder when one
  /// is set, a playlist in a folder named after it.
  static String saveTargetFor(
    AppSettings settings,
    MediaPreview preview,
    DownloadOption option,
  ) {
    final folder =
        option.type == OutputType.audio && settings.audioFolder.isNotEmpty
        ? settings.audioFolder
        : settings.saveFolder;
    final dir = saveDirFor(folder, preview.platform);
    return option.playlist
        ? '$dir/${playlistFolderName(preview.info.title)}'
        : dir;
  }

  static final _random = Random.secure();

  static String _newId() =>
      [for (var i = 0; i < 16; i++) _random.nextInt(16).toRadixString(16)]
          .join();
}
