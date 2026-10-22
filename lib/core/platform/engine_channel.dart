import 'package:flutter/services.dart';
import 'package:media_downloader/core/platform/channel_json.dart';
import 'package:media_downloader/core/platform/models/download_progress.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/core/platform/models/engine_info.dart';
import 'package:media_downloader/core/platform/models/engine_update_result.dart';
import 'package:media_downloader/core/platform/models/fit_request.dart';
import 'package:media_downloader/core/platform/models/media_info.dart';
import 'package:media_downloader/core/platform/models/playlist_info.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'engine_channel.g.dart';

/// Dart side of the `app/engine` contract documented in CLAUDE.md.
///
/// Methods throw [PlatformException] on native errors; repositories wrap
/// calls in `guardPlatformCall` to turn them into failures.
class EngineChannel {
  new({MethodChannel? methods, EventChannel? progress})
    : _methods = methods ?? const MethodChannel(methodChannelName),
      _progress = progress ?? const EventChannel(progressChannelName);

  static const methodChannelName = 'app/engine';
  static const progressChannelName = 'app/engine/progress';

  final MethodChannel _methods;
  final EventChannel _progress;

  /// Prepares yt-dlp and FFmpeg. Safe to call more than once; the first call
  /// after install unpacks the bundled Python and can take a few seconds.
  Future<EngineInfo> init() async =>
      EngineInfo.fromJson(await _invokeMap('init'));

  /// [options]: yt-dlp arguments from Settings (`networkArgs`).
  Future<MediaInfo> fetchInfo(
    String url, {
    List<String> options = const [],
  }) async => MediaInfo.fromJson(
    await _invokeMap('fetchInfo', {'url': url, 'options': options}),
  );

  /// The videos of the playlist at [url], without looking each one up.
  Future<PlaylistInfo> fetchPlaylist(
    String url, {
    List<String> options = const [],
  }) async => PlaylistInfo.fromJson(
    await _invokeMap('fetchPlaylist', {'url': url, 'options': options}),
  );

  /// The caption [track] of [url] as WebVTT text; the video isn't
  /// downloaded. `NOT_FOUND` when the track has no file.
  Future<String> fetchTranscript(
    String url,
    CaptionTrack track, {
    List<String> options = const [],
  }) async {
    final reply = await _invokeMap('fetchTranscript', {
      'url': url,
      'lang': track.lang,
      'auto': track.auto,
      'options': options,
    });
    return reply['text'] as String;
  }

  /// Returns the download id.
  Future<String> startDownload(DownloadRequest request) async {
    final reply = await _invokeMap('startDownload', request.toJson());
    return reply['id'] as String;
  }

  /// Starts re-encoding a saved video to fit a size; returns its id. It
  /// reports progress and finishes like a download, and `cancelDownload`
  /// stops it.
  Future<String> fitVideo(FitRequest request) async {
    final reply = await _invokeMap('fitVideo', request.toJson());
    return reply['id'] as String;
  }

  Future<bool> cancelDownload(String id) async =>
      await _methods.invokeMethod<bool>('cancelDownload', {'id': id}) ?? false;

  /// Final events of downloads that finished since the last call, including
  /// those whose live event nobody received. Each is returned once.
  Future<List<DownloadProgress>> takeFinishedDownloads() async {
    final reply = await _methods.invokeMethod<List<Object?>>(
      'takeFinishedDownloads',
    );
    return [
      for (final event in reply ?? const [])
        DownloadProgress.fromJson(jsonMap(event)),
    ];
  }

  Future<EngineUpdateResult> updateEngine(EngineReleaseChannel channel) async =>
      EngineUpdateResult.fromJson(
        await _invokeMap('updateEngine', {'channel': channel.name}),
      );

  /// Whether the phone is on a metered network (usually mobile data).
  Future<bool> isNetworkMetered() async =>
      (await _invokeMap('networkStatus'))['metered'] as bool? ?? false;

  /// Opens a page where the user signs in at [url]; returns the sites
  /// signed in to afterwards, e.g. `instagram.com`.
  Future<List<String>> signIn(String url) async => _strings(
    await _methods.invokeMethod<List<Object?>>('signIn', {'url': url}),
  );

  Future<List<String>> signedInSites() async =>
      _strings(await _methods.invokeMethod<List<Object?>>('signedInSites'));

  /// Forgets the sign-in to [site]; returns the sites still signed in to.
  Future<List<String>> signOut(String site) async => _strings(
    await _methods.invokeMethod<List<Object?>>('signOut', {'site': site}),
  );

  static List<String> _strings(List<Object?>? list) => [
    for (final item in list ?? const []) item! as String,
  ];

  /// Progress for all downloads; filter by [DownloadProgress.id].
  late final Stream<DownloadProgress> progress = _progress
      .receiveBroadcastStream()
      .map((event) => DownloadProgress.fromJson(jsonMap(event)));

  Future<Map<String, dynamic>> _invokeMap(
    String method, [
    Map<String, Object?>? arguments,
  ]) async => jsonMap(await _methods.invokeMethod<Object?>(method, arguments));
}

@Riverpod(keepAlive: true)
EngineChannel engineChannel(Ref ref) => EngineChannel();
