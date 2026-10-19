import 'package:drift/drift.dart';
import 'package:media_downloader/core/db/app_database.dart';
import 'package:media_downloader/core/errors/platform_failure.dart';
import 'package:media_downloader/core/platform/engine_channel.dart';
import 'package:media_downloader/core/platform/models/download_progress.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/core/platform/models/media_info.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/download/domain/download_details.dart';
import 'package:media_downloader/features/download/domain/media_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'media_repository_impl.g.dart';

class MediaRepositoryImpl implements MediaRepository {
  new(this._channel, this._db);

  final EngineChannel _channel;
  final AppDatabase _db;

  @override
  Future<Result<MediaInfo>> fetchInfo(Uri url) =>
      guardPlatformCall(() => _channel.fetchInfo(url.toString()));

  @override
  Future<Result<String>> startDownload(
    DownloadRequest request,
    DownloadDetails details,
  ) async {
    // Recorded first: the result may arrive while the app isn't listening.
    await _db
        .into(_db.downloadRecords)
        .insertOnConflictUpdate(
          DownloadRecordsCompanion.insert(
            id: request.id,
            url: request.url,
            title: Value(request.title),
            formatId: request.formatId,
            outputType: request.outputType.name,
            state: DownloadState.queued.name,
            platform: Value(details.platform.name),
            thumbnail: Value(details.thumbnail),
            ext: Value(details.ext),
            quality: Value(details.quality),
            sizeBytes: Value(details.sizeBytes),
          ),
        );
    final result = await guardPlatformCall(
      () => _channel.startDownload(request),
    );
    if (result is Err) {
      await (_db.delete(
        _db.downloadRecords,
      )..where((r) => r.id.equals(request.id))).go();
    }
    return result;
  }

  @override
  Stream<DownloadProgress> progressOf(String id) =>
      _channel.progress.where((event) => event.id == id);

  @override
  Future<Result<bool>> cancelDownload(String id) =>
      guardPlatformCall(() => _channel.cancelDownload(id));
}

@Riverpod(keepAlive: true)
MediaRepository mediaRepository(Ref ref) => MediaRepositoryImpl(
  ref.watch(engineChannelProvider),
  ref.watch(appDatabaseProvider),
);
