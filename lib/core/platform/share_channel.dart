import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'share_channel.g.dart';

/// Text shared to the app from other apps' Share sheets (usually a link).
///
/// Native keeps a share that arrives before anyone listens (the one the app
/// was launched with, or one sent while it was still starting) and sends it
/// on listen, so no share is lost.
class ShareChannel {
  new({EventChannel? events})
    : _events = events ?? const EventChannel(channelName);

  static const channelName = 'app/share';

  final EventChannel _events;

  late final Stream<String> texts = _events
      .receiveBroadcastStream()
      .cast<String>();
}

@Riverpod(keepAlive: true)
ShareChannel shareChannel(Ref ref) => ShareChannel();

/// Every shared text, starting with the one the app was launched with.
@Riverpod(keepAlive: true)
Stream<String> sharedText(Ref ref) => ref.watch(shareChannelProvider).texts;
