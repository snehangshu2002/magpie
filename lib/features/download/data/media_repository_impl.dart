import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:media_downloader/core/db/app_database.dart';
import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/errors/platform_failure.dart';
import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/core/platform/engine_channel.dart';
import 'package:media_downloader/core/platform/models/download_progress.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/core/platform/models/media_info.dart';
import 'package:media_downloader/core/platform/models/playlist_info.dart';
import 'package:media_downloader/core/platform/storage_channel.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/download/data/web_photo_source.dart';
import 'package:media_downloader/features/download/domain/download_details.dart';
import 'package:media_downloader/features/download/domain/media_repository.dart';
import 'package:media_downloader/features/download/domain/transcript.dart';
import 'package:media_downloader/features/download/domain/web_photo.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'media_repository_impl.g.dart';

class MediaRepositoryImpl implements MediaRepository {
  new(
    this._channel,
    this._db, [
    WebPhotoSource? photos,
    StorageChannel? storage,
  ]) : _photos = photos ?? WebPhotoSource(),
       _storage = storage ?? StorageChannel();

  final EngineChannel _channel;
  final AppDatabase _db;
  final WebPhotoSource _photos;
  final StorageChannel _storage;

  @override
  Future<Result<String>> fetchTranscript(
    Uri url,
    CaptionTrack track, {
    List<String> options = const [],
  }) => guardPlatformCall(
    () async => transcriptFromVtt(
      await _channel.fetchTranscript(url.toString(), track, options: options),
    ),
  );

  @override
  Future<Result<String>> saveText({
    required String name,
    required String text,
    required String targetDir,
  }) => guardPlatformCall(
    () => _storage.saveText(name: name, text: text, targetDir: targetDir),
  );

  @override
  Future<Result<MediaInfo>> fetchInfo(
    Uri url, {
    List<String> options = const [],
  }) => guardPlatformCall(
    () => _channel.fetchInfo(url.toString(), options: options),
  );

  @override
  Future<Result<PlaylistInfo>> fetchPlaylist(
    Uri url, {
    List<String> options = const [],
  }) => guardPlatformCall(
    () => _channel.fetchPlaylist(url.toString(), options: options),
  );

  @override
  Future<bool> isSaved(String videoKey) async {
    final records = _db.downloadRecords;
    final saved =
        await (_db.select(records)
              ..where(
                (r) =>
                    r.videoKey.equals(videoKey) &
                    r.state.equals(DownloadState.saved.name) &
                    r.fileUri.isNotNull(),
              )
              ..limit(1))
            .getSingleOrNull();
    return saved != null;
  }

  @override
  Future<bool> isNetworkMetered() async =>
      switch (await guardPlatformCall(_channel.isNetworkMetered)) {
        Ok(:final value) => value,
        Err() => false,
      };

  @override
  Future<Result<WebPhotos?>> fetchPhotos(
    Uri url,
    SourcePlatform platform, {
    List<String> options = const [],
  }) => _guardHttp(() => _photos.photosOf(url, platform, options: options));

  @override
  Future<Result<WebPhotos?>> fetchImage(
    Uri url, {
    List<String> options = const [],
  }) => _guardHttp(() => _photos.imageAt(url, options: options));

  static Future<Result<T>> _guardHttp<T>(Future<T> Function() call) async {
    try {
      return Ok(await call());
    } on IOException catch (e) {
      return Err(Failure.network(detail: '$e'));
    } on TimeoutException catch (e) {
      return Err(Failure.network(detail: '$e'));
    } on FormatException catch (e) {
      return Err(Failure.unknown(detail: '$e'));
    }
  }

  @override
  Future<Result<String>> startDownload(
    DownloadRequest request,
    DownloadDetails details, {
    bool record = true,
  }) async {
    if (!record) {
      return await guardPlatformCall(() => _channel.startDownload(request));
    }
    // Recorded first: the result may arrive while the app isn't listening.
    try {
      await _recordStart(request, details);
    } on Exception catch (e) {
      // An unreadable database mustn't leave the Download button spinning.
      return Err(Failure.storage(detail: '$e'));
    }
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

  Future<void> _recordStart(
    DownloadRequest request,
    DownloadDetails details,
  ) async {
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
            videoKey: Value(details.videoKey),
          ),
        );
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
  null,
  ref.watch(storageChannelProvider),
);
