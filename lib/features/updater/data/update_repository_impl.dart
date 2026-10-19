import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/errors/platform_failure.dart';
import 'package:media_downloader/core/platform/updater_channel.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/updater/domain/app_update.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'update_repository_impl.g.dart';

class UpdateRepositoryImpl implements UpdateRepository {
  new(this._channel);

  static final Uri latestRelease = Uri.parse(
    'https://api.github.com/repos/snehangshu2002/magpie/releases/latest',
  );

  final UpdaterChannel _channel;

  @override
  Future<Result<AppUpdate?>> check() async {
    final info = await guardPlatformCall(_channel.appInfo);
    if (info case Err(:final failure)) return Err(failure);
    final app = info.getOrThrow();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
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
      final apks = {
        for (final asset in release['assets'] as List)
          (asset as Map)['name'] as String:
              asset['browser_download_url'] as String,
      };
      return Ok(
        AppUpdate(
          version: tag.replaceFirst(RegExp('^v'), ''),
          url: apkFor(apks, app.abis) ?? release['html_url'] as String,
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
  Future<Result<void>> download(AppUpdate update) =>
      guardPlatformCall(() => _channel.openUrl(update.url));
}

@Riverpod(keepAlive: true)
UpdateRepository updateRepository(Ref ref) =>
    UpdateRepositoryImpl(ref.watch(updaterChannelProvider));
