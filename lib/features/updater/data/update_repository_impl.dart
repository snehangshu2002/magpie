import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/errors/platform_failure.dart';
import 'package:media_downloader/core/platform/updater_channel.dart';
import 'package:media_downloader/core/utils/network_options.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/updater/domain/app_update.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'update_repository_impl.g.dart';

class UpdateRepositoryImpl implements UpdateRepository {
  new(this._channel);

  static final Uri latestRelease = Uri.parse(
    'https://api.github.com/repos/$projectRepo/releases/latest',
  );

  final UpdaterChannel _channel;

  @override
  Future<Result<AppUpdate?>> check({List<String> options = const []}) async {
    final info = await guardPlatformCall(_channel.appInfo);
    if (info case Err(:final failure)) return Err(failure);
    final app = info.getOrThrow();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    applyNetworkOptions(client, options);
    try {
      final request = await client.getUrl(latestRelease);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final body = await response.transform(utf8.decoder).join();
      // 404: nothing released yet.
      if (response.statusCode == HttpStatus.notFound) return const Ok(null);
      if (response.statusCode != HttpStatus.ok) {
        return Err(Failure.network(detail: 'HTTP ${response.statusCode}'));
      }
      final release = jsonDecode(body) as Map<String, dynamic>;
      final tag = release['tag_name'] as String;
      if (!isNewerVersion(tag, app.version)) return const Ok(null);
      final assets = {
        for (final asset in release['assets'] as List)
          (asset as Map)['name'] as String: asset,
      };
      final apkName = apkFor(assets.keys, app.abis);
      final apk = assets[apkName];
      final page = release['html_url'] as String;
      return Ok(
        AppUpdate(
          version: tag.replaceFirst(RegExp('^v'), ''),
          url: apk?['browser_download_url'] as String? ?? page,
          pageUrl: page,
          size: apk?['size'] as int?,
          apkName: apkName,
          // "sha256:<hex>", listed for assets uploaded since mid-2025.
          sha256: switch (apk?['digest']) {
            final String digest when digest.startsWith('sha256:') =>
              digest.substring('sha256:'.length),
            _ => null,
          },
          notes: releaseNoteLines(release['body'] as String? ?? ''),
          published: DateTime.tryParse(
            release['published_at'] as String? ?? '',
          ),
        ),
      );
    } on IOException catch (e) {
      return Err(Failure.network(detail: '$e'));
    } on TimeoutException catch (e) {
      return Err(Failure.network(detail: '$e'));
    } on FormatException catch (e) {
      return Err(Failure.unknown(detail: '$e'));
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<Result<String>> installedVersion() async =>
      switch (await guardPlatformCall(_channel.appInfo)) {
        Ok(:final value) => Ok(value.version),
        Err(:final failure) => Err(failure),
      };

  @override
  Future<Result<void>> open(String url) =>
      guardPlatformCall(() => _channel.openUrl(url));

  @override
  Future<Result<String>> download(
    AppUpdate update, {
    required void Function(int received, int? total) onProgress,
    required bool Function() isCancelled,
    List<String> options = const [],
  }) async {
    final name = update.apkName;
    if (name == null) return const Err(Failure.notFound());
    final path = await guardPlatformCall(() => _channel.prepareApk(name));
    if (path case Err(:final failure)) return Err(failure);
    final file = File(path.getOrThrow());
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    applyNetworkOptions(client, options);
    IOSink? sink;
    try {
      // GitHub redirects the asset to its storage host; HttpClient follows.
      final request = await client.getUrl(Uri.parse(update.url));
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != HttpStatus.ok) {
        return Err(Failure.network(detail: 'HTTP ${response.statusCode}'));
      }
      final total = response.contentLength > 0
          ? response.contentLength
          : update.size;
      sink = file.openWrite();
      var received = 0;
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        if (isCancelled()) return const Err(Failure.cancelled());
        sink.add(chunk);
        received += chunk.length;
        onProgress(received, total);
      }
      await sink.close();
      sink = null;
      return Ok(file.path);
    } on IOException catch (e) {
      return Err(Failure.network(detail: '$e'));
    } on TimeoutException catch (e) {
      return Err(Failure.network(detail: '$e'));
    } finally {
      await sink?.close();
      client.close(force: true);
    }
  }

  @override
  Future<Result<void>> install(String path, AppUpdate update) =>
      guardPlatformCall(() => _channel.installApk(path, sha256: update.sha256));
}

@Riverpod(keepAlive: true)
UpdateRepository updateRepository(Ref ref) =>
    UpdateRepositoryImpl(ref.watch(updaterChannelProvider));
