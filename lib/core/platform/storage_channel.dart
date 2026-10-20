import 'package:flutter/services.dart';
import 'package:media_downloader/core/platform/channel_json.dart';
import 'package:media_downloader/core/platform/models/stored_file.dart';
import 'package:media_downloader/core/platform/models/video_probe.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'storage_channel.g.dart';

/// Dart side of the `app/storage` contract documented in CLAUDE.md: files
/// the app saved to shared storage, by content URI.
///
/// Methods throw [PlatformException] on native errors; repositories wrap
/// calls in `guardPlatformCall` to turn them into failures.
class StorageChannel {
  new({MethodChannel? methods, EventChannel? changes})
    : _methods = methods ?? const MethodChannel(channelName),
      _changes = changes ?? const EventChannel(changesChannelName);

  static const channelName = 'app/storage';
  static const changesChannelName = 'app/storage/changes';

  final MethodChannel _methods;
  final EventChannel _changes;

  /// Fires when shared storage changes: a file added, edited or deleted by
  /// any app. Comes in bursts; debounce before acting on it.
  late final Stream<void> changes = _changes.receiveBroadcastStream().map(
    (_) {},
  );

  /// The files among [uris] that still exist.
  Future<List<StoredFile>> queryFiles(List<String> uris) async {
    final reply = await _methods.invokeMethod<List<Object?>>('queryFiles', {
      'uris': uris,
    });
    return [
      for (final file in reply ?? const []) StoredFile.fromJson(jsonMap(file)),
    ];
  }

  /// A JPEG preview about [size] pixels across, or null if there is none.
  Future<Uint8List?> thumbnail(String uri, {int size = 256}) =>
      _methods.invokeMethod<Uint8List>('thumbnail', {'uri': uri, 'size': size});

  /// Length, size in pixels and whether there's sound, of the video at
  /// [uri]; `NOT_FOUND` if it is gone.
  Future<VideoProbe> probeVideo(String uri) async => VideoProbe.fromJson(
    jsonMap(await _methods.invokeMethod<Object?>('probeVideo', {'uri': uri})),
  );

  Future<void> openFile(String uri, {String? mimeType}) => _methods
      .invokeMethod<void>('openFile', {'uri': uri, 'mimeType': mimeType});

  /// Shares the files among [uris] that still exist; `NOT_FOUND` if none do.
  Future<void> shareFiles(
    List<String> uris, {
    String? mimeType,
    String? title,
  }) => _methods.invokeMethod<void>('shareFiles', {
    'uris': uris,
    'mimeType': mimeType,
    'title': title,
  });

  /// Deletes [uris]; returns those now gone. Ones the user declined to
  /// delete in the system prompt are left out.
  Future<List<String>> deleteFiles(List<String> uris) async =>
      await _methods.invokeListMethod<String>('deleteFiles', {'uris': uris}) ??
      const [];

  /// Saves [text] as `<targetDir>/<name>.txt` in shared storage; returns
  /// its content URI.
  Future<String> saveText({
    required String name,
    required String text,
    required String targetDir,
  }) async => (await _methods.invokeMethod<String>('saveText', {
    'name': name,
    'text': text,
    'targetDir': targetDir,
  }))!;

  /// Opens Android's folder picker at Download. The chosen folder's document
  /// id (`primary:Download/Videos`), or null if the user backed out.
  Future<String?> pickFolder() => _methods.invokeMethod<String>('pickFolder');
}

@Riverpod(keepAlive: true)
StorageChannel storageChannel(Ref ref) => StorageChannel();
