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

  /// Opens Android's picker for [mimeType] files (`image/*`,
  /// `application/pdf`); the content URIs picked, none if the user backed
  /// out.
  Future<List<String>> pickFiles(
    String mimeType, {
    bool multiple = false,
  }) async =>
      await _methods.invokeListMethod<String>('pickFiles', {
        'mimeType': mimeType,
        'multiple': multiple,
      }) ??
      const [];

  /// Pages, name and size of the PDF at [uri]; `pages` is null when it
  /// needs a password ([password] is tried).
  Future<({int? pages, String? name, int? size, bool protected})> pdfInfo(
    String uri, {
    String? password,
  }) async {
    final reply = jsonMap(
      await _methods.invokeMethod<Object?>('pdfInfo', {
        'uri': uri,
        'password': password,
      }),
    );
    return (
      pages: reply['pages'] as int?,
      name: reply['name'] as String?,
      size: reply['size'] as int?,
      protected: reply['protected'] as bool? ?? false,
    );
  }

  /// Runs a PDF tool (`op` and its arguments, see CLAUDE.md) and saves what
  /// it made in `targetDir`; the files' content URIs and sizes, in order.
  Future<({List<String> uris, List<int> sizes})> editPdf(
    Map<String, Object?> request,
  ) async {
    final reply = jsonMap(
      await _methods.invokeMethod<Object?>('editPdf', request),
    );
    return (
      uris: [for (final uri in reply['uris'] as List) uri as String],
      sizes: [for (final size in reply['sizes'] as List) size as int],
    );
  }

  /// Width and height in pixels of the image at [uri], as it is shown.
  Future<({int width, int height})> probeImage(String uri) async {
    final reply = jsonMap(
      await _methods.invokeMethod<Object?>('probeImage', {'uri': uri}),
    );
    return (width: reply['width'] as int, height: reply['height'] as int);
  }

  /// Saves a copy of the image at [uri] as `<targetDir>/<name>.<format>`
  /// (`jpg`, `png` or `webp`), [width] x [height] pixels at [quality]
  /// (1-100). With [targetBytes], quality and then pixels are lowered until
  /// it fits (`TOO_LARGE` if it can't). First the image is turned [rotate]
  /// degrees clockwise (0, 90, 180, 270) and cut to [crop], a rectangle in
  /// the turned image's pixels. The copy has no metadata.
  Future<({String uri, int size})> editImage({
    required String uri,
    required String targetDir,
    required String name,
    required String format,
    required int width,
    required int height,
    required int quality,
    int? targetBytes,
    int rotate = 0,
    ({int left, int top, int width, int height})? crop,
  }) async {
    final reply = jsonMap(
      await _methods.invokeMethod<Object?>('editImage', {
        'rotate': rotate,
        'crop': crop == null
            ? null
            : [crop.left, crop.top, crop.width, crop.height],
        'uri': uri,
        'targetDir': targetDir,
        'name': name,
        'format': format,
        'width': width,
        'height': height,
        'quality': quality,
        'targetBytes': targetBytes,
      }),
    );
    return (uri: reply['uri'] as String, size: reply['size'] as int);
  }

  /// Opens Android's folder picker at Download. The chosen folder's document
  /// id (`primary:Download/Videos`), or null if the user backed out.
  Future<String?> pickFolder() => _methods.invokeMethod<String>('pickFolder');
}

@Riverpod(keepAlive: true)
StorageChannel storageChannel(Ref ref) => StorageChannel();
