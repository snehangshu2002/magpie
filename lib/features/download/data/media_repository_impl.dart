import 'package:media_downloader/core/errors/platform_failure.dart';
import 'package:media_downloader/core/platform/engine_channel.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/core/platform/models/media_info.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/download/domain/media_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'media_repository_impl.g.dart';

class MediaRepositoryImpl implements MediaRepository {
  new(this._channel);

  final EngineChannel _channel;

  @override
  Future<Result<MediaInfo>> fetchInfo(Uri url) =>
      guardPlatformCall(() => _channel.fetchInfo(url.toString()));

  @override
  Future<Result<String>> startDownload(DownloadRequest request) =>
      guardPlatformCall(() => _channel.startDownload(request));
}

@Riverpod(keepAlive: true)
MediaRepository mediaRepository(Ref ref) =>
    MediaRepositoryImpl(ref.watch(engineChannelProvider));
