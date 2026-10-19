import 'package:flutter/services.dart';
import 'package:media_downloader/core/platform/channel_json.dart';
import 'package:media_downloader/core/platform/models/stored_file.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'storage_channel.g.dart';

/// Dart side of the `app/storage` contract documented in CLAUDE.md: files
/// the app saved to shared storage, by content URI.
///
/// Methods throw [PlatformException] on native errors; repositories wrap
/// calls in `guardPlatformCall` to turn them into failures.
class StorageChannel {
  new({MethodChannel? methods})
    : _methods = methods ?? const MethodChannel(channelName);

  static const channelName = 'app/storage';

  final MethodChannel _methods;

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

  Future<void> openFile(String uri, {String? mimeType}) => _methods
      .invokeMethod<void>('openFile', {'uri': uri, 'mimeType': mimeType});

  Future<void> shareFile(String uri, {String? mimeType, String? title}) =>
      _methods.invokeMethod<void>('shareFile', {
        'uri': uri,
        'mimeType': mimeType,
        'title': title,
      });

  /// False if the system asked the user to confirm and they declined.
  Future<bool> deleteFile(String uri) async =>
      await _methods.invokeMethod<bool>('deleteFile', {'uri': uri}) ?? false;
}

@Riverpod(keepAlive: true)
StorageChannel storageChannel(Ref ref) => StorageChannel();
