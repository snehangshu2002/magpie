import 'package:media_downloader/core/utils/result.dart';

/// The developer's GitHub account.
const projectOwner = 'snehangshu2002';

/// The app's GitHub repository (`owner/name`): its source and releases.
const projectRepo = '$projectOwner/magpie';

/// A release newer than the installed app.
class AppUpdate {
  const new({
    required this.version,
    required this.url,
    required this.pageUrl,
    this.size,
    this.apkName,
    this.sha256,
    this.notes = const [],
    this.published,
  });

  final String version;

  /// The APK for this phone, or [pageUrl] when none matches.
  final String url;

  /// The release on GitHub, with its full notes.
  final String pageUrl;

  /// Bytes of the APK at [url]; null when that is the release page.
  final int? size;

  /// File name of the APK at [url]; null when that is the release page.
  final String? apkName;

  /// The APK's SHA-256 as GitHub lists it (hex), to check the download.
  final String? sha256;

  /// Whether the APK can be downloaded and installed from inside the app.
  bool get installable => apkName != null;

  /// The bullet points of the release notes.
  final List<String> notes;
  final DateTime? published;
}

abstract interface class UpdateRepository {
  /// The latest GitHub release if it is newer than the installed app, else
  /// null.
  Future<Result<AppUpdate?>> check();

  /// The installed app's version name (e.g. `1.1.0`).
  Future<Result<String>> installedVersion();

  /// Opens [url] (a release page) in the browser.
  Future<Result<void>> open(String url);

  /// Downloads [update]'s APK into the app's cache; returns its path.
  /// [onProgress] gets bytes so far and the total, when known. Stops with
  /// `Failure.cancelled` once [isCancelled] is true.
  Future<Result<String>> download(
    AppUpdate update, {
    required void Function(int received, int? total) onProgress,
    required bool Function() isCancelled,
  });

  /// Checks the APK at [path] against [AppUpdate.sha256] and opens Android's
  /// installer for it.
  Future<Result<void>> install(String path, AppUpdate update);
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

/// The asset name in [names] built for the first of [abis] that has one;
/// CI names them `magpie-<version>-<abi>.apk`.
String? apkFor(Iterable<String> names, List<String> abis) {
  for (final abi in abis) {
    for (final name in names) {
      if (name.endsWith('-$abi.apk')) return name;
    }
  }
  return null;
}

/// The `-`/`*` bullets of a release's Markdown notes (the workflow's
/// `notes` input becomes one `- ` line per point).
List<String> releaseNoteLines(String body) => [
  for (final line in body.split('\n'))
    if (RegExp(r'^\s*[-*]\s+(.+)$').firstMatch(line) case final m?)
      m.group(1)!.trim(),
];
