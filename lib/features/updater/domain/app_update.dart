import 'package:media_downloader/core/utils/result.dart';

/// A release newer than the installed app.
class AppUpdate {
  const new({required this.version, required this.url});

  final String version;

  /// The APK for this phone, or the release page when none matches.
  final String url;
}

abstract interface class UpdateRepository {
  /// The latest GitHub release if it is newer than the installed app, else
  /// null.
  Future<Result<AppUpdate?>> check();

  /// Opens the update's download in the browser.
  Future<Result<void>> download(AppUpdate update);
}

/// Whether release tag [latest] (`v1.2.0`) is newer than [current]
/// (`1.1.9`). Compares the dotted numbers; anything after `-` or `+` is
/// ignored.
bool isNewerVersion(String latest, String current) {
  List<int> parts(String v) => v
      .replaceFirst(RegExp('^v'), '')
      .split(RegExp('[-+]'))
      .first
      .split('.')
      .map((p) => int.tryParse(p) ?? 0)
      .toList();
  final a = parts(latest);
  final b = parts(current);
  for (var i = 0; i < a.length || i < b.length; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

/// The asset in [apks] (name -> download URL) built for the first of
/// [abis] that has one; CI names them `magpie-<version>-<abi>.apk`.
String? apkFor(Map<String, String> apks, List<String> abis) {
  for (final abi in abis) {
    for (final MapEntry(:key, :value) in apks.entries) {
      if (key.endsWith('-$abi.apk')) return value;
    }
  }
  return null;
}
