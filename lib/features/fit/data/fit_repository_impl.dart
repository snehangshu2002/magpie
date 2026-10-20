import 'package:drift/drift.dart';
import 'package:media_downloader/core/db/app_database.dart';
import 'package:media_downloader/core/errors/platform_failure.dart';
import 'package:media_downloader/core/platform/engine_channel.dart';
import 'package:media_downloader/core/platform/models/download_progress.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/core/platform/models/fit_request.dart';
import 'package:media_downloader/core/platform/models/video_probe.dart';
import 'package:media_downloader/core/platform/storage_channel.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/fit/domain/fit_plan.dart';
import 'package:media_downloader/features/fit/domain/fit_repository.dart';
import 'package:media_downloader/features/library/domain/library_item.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'fit_repository_impl.g.dart';

/// `formatId` of a copy's record; nothing was downloaded for it.
const fitFormatId = 'fit';

class FitRepositoryImpl implements FitRepository {
  new(this._engine, this._storage, this._db);

  final EngineChannel _engine;
  final StorageChannel _storage;
  final AppDatabase _db;

  @override
  Future<Result<VideoProbe>> probe(String fileUri) =>
      guardPlatformCall(() => _storage.probeVideo(fileUri));

  @override
  Future<Result<String>> start({
    required String id,
    required LibraryItem item,
    required ShareSize size,
    required FitEncode plan,
    required int durationMs,
    required String targetDir,
    required String name,
  }) async {
    // Recorded first, like a download: the copy may finish while the app
    // isn't listening, and the Library picks it up from here.
    await _db
        .into(_db.downloadRecords)
        .insertOnConflictUpdate(
          DownloadRecordsCompanion.insert(
            id: id,
            url: item.sourceUrl,
            title: Value(name),
            formatId: fitFormatId,
            outputType: OutputType.video.name,
            state: DownloadState.queued.name,
            platform: Value(item.platform.name),
            thumbnail: Value(item.thumbnailUrl),
            ext: const Value('mp4'),
            quality: Value(plan.shortSide),
            sizeBytes: Value(plan.estimatedBytes),
          ),
        );
    final result = await guardPlatformCall(
      () => _engine.fitVideo(
        FitRequest(
          id: id,
          uri: item.fileUri,
          targetDir: targetDir,
          name: name,
          targetBytes: size.bytes,
          durationMs: durationMs,
          videoKbps: plan.videoKbps,
          audioKbps: plan.audioKbps,
          maxShortSide: plan.shortSide,
          title: name,
        ),
      ),
    );
    if (result is Err) {
      await (_db.delete(
        _db.downloadRecords,
      )..where((r) => r.id.equals(id))).go();
    }
    return result;
  }

  @override
  Stream<DownloadProgress> progressOf(String id) =>
      _engine.progress.where((event) => event.id == id);

  @override
  Future<Result<bool>> cancel(String id) =>
      guardPlatformCall(() => _engine.cancelDownload(id));
}

@Riverpod(keepAlive: true)
FitRepository fitRepository(Ref ref) => FitRepositoryImpl(
  ref.watch(engineChannelProvider),
  ref.watch(storageChannelProvider),
  ref.watch(appDatabaseProvider),
);
