import 'package:flutter/services.dart';
import 'package:media_downloader/core/platform/models/download_progress.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/core/platform/models/engine_info.dart';
import 'package:media_downloader/core/platform/models/engine_update_result.dart';
import 'package:media_downloader/core/platform/models/media_info.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'engine_channel.g.dart';

/// Dart side of the `app/engine` contract documented in CLAUDE.md.
///
/// Methods throw [PlatformException] on native errors; repositories wrap
/// calls in `guardPlatformCall` to turn them into failures.
class EngineChannel {
  EngineChannel({MethodChannel? methods, EventChannel? progress})
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

  Future<MediaInfo> fetchInfo(String url) async =>
      MediaInfo.fromJson(await _invokeMap('fetchInfo', {'url': url}));

  /// Returns the download id.
  Future<String> startDownload(DownloadRequest request) async {
    final reply = await _invokeMap('startDownload', request.toJson());
    return reply['id'] as String;
  }

  Future<bool> cancelDownload(String id) async =>
      await _methods.invokeMethod<bool>('cancelDownload', {'id': id}) ?? false;

  Future<EngineUpdateResult> updateEngine(EngineReleaseChannel channel) async =>
      EngineUpdateResult.fromJson(
        await _invokeMap('updateEngine', {'channel': channel.name}),
      );

  /// Progress for all downloads; filter by [DownloadProgress.id].
  late final Stream<DownloadProgress> progress = _progress
      .receiveBroadcastStream()
      .map((event) => DownloadProgress.fromJson(_jsonMap(event)));

  Future<Map<String, dynamic>> _invokeMap(
    String method, [
    Map<String, Object?>? arguments,
  ]) async => _jsonMap(await _methods.invokeMethod<Object?>(method, arguments));
}

/// Platform channels deliver `Map<Object?, Object?>` at every nesting level,
/// while generated `fromJson` code expects `Map<String, dynamic>`.
Map<String, dynamic> _jsonMap(Object? value) => (value! as Map).map(
  (key, value) => MapEntry(key as String, _jsonValue(value)),
);

Object? _jsonValue(Object? value) => switch (value) {
  Map() => _jsonMap(value),
  List() => value.map(_jsonValue).toList(),
  _ => value,
};

@Riverpod(keepAlive: true)
EngineChannel engineChannel(Ref ref) => EngineChannel();
