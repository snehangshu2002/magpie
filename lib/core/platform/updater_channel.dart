import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'updater_channel.g.dart';

/// The installed app's version and ABIs, and a way to open a download link.
class UpdaterChannel {
  new({MethodChannel? methods})
    : _methods = methods ?? const MethodChannel(channelName);

  static const channelName = 'app/updater';

  final MethodChannel _methods;

  /// `versionName` and `Build.SUPPORTED_ABIS`, most preferred first.
  Future<({String version, List<String> abis})> appInfo() async {
    final reply = (await _methods.invokeMapMethod<String, Object?>('appInfo'))!;
    return (
      version: reply['version']! as String,
      abis: (reply['abis']! as List).cast<String>(),
    );
  }

  /// Opens [url] in the browser (`NO_APP` if there is none).
  Future<void> openUrl(String url) =>
      _methods.invokeMethod<void>('openUrl', {'url': url});
}

@Riverpod(keepAlive: true)
UpdaterChannel updaterChannel(Ref ref) => UpdaterChannel();
