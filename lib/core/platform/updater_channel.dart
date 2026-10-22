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

  /// Where to download update APK [name] (in the app's cache); earlier
  /// downloads there are deleted.
  Future<String> prepareApk(String name) async =>
      (await _methods.invokeMethod<String>('prepareApk', {'name': name}))!;

  /// Opens Android's installer for the APK at [path], after checking it
  /// against [sha256] when given (`NETWORK` if it doesn't match).
  Future<void> installApk(String path, {String? sha256}) => _methods
      .invokeMethod<void>('installApk', {'path': path, 'sha256': sha256});

  /// Opens [url] in the browser (`NO_APP` if there is none).
  Future<void> openUrl(String url) =>
      _methods.invokeMethod<void>('openUrl', {'url': url});
}

@Riverpod(keepAlive: true)
UpdaterChannel updaterChannel(Ref ref) => UpdaterChannel();
