import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'share_channel.g.dart';

/// Text shared to the app from other apps' Share sheets (usually a link).
///
/// Wraps `receive_sharing_intent`, which owns the native side.
class ShareChannel {
  new({ReceiveSharingIntent? plugin})
    : _plugin = plugin ?? ReceiveSharingIntent.instance;

  final ReceiveSharingIntent _plugin;

  /// Text the app was launched with, if any. Consumed once.
  Future<String?> initialText() async {
    final media = await _plugin.getInitialMedia();
    await _plugin.reset();
    return _text(media);
  }

  /// Text shared while the app is already running.
  Stream<String> get texts => _plugin
      .getMediaStream()
      .map(_text)
      .where((text) => text != null)
      .cast<String>();

  static String? _text(List<SharedMediaFile> media) => media
      .where(
        (m) => m.type == SharedMediaType.text || m.type == SharedMediaType.url,
      )
      .map((m) => m.path)
      .firstOrNull;
}

@Riverpod(keepAlive: true)
ShareChannel shareChannel(Ref ref) => ShareChannel();

/// Every shared text, starting with the one the app was launched with.
@Riverpod(keepAlive: true)
Stream<String> sharedText(Ref ref) async* {
  final channel = ref.watch(shareChannelProvider);
  final initial = await channel.initialText();
  if (initial != null) yield initial;
  yield* channel.texts;
}
