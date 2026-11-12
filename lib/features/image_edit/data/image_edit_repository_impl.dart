import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:media_downloader/core/db/app_database.dart';
import 'package:media_downloader/core/errors/platform_failure.dart';
import 'package:media_downloader/core/platform/models/download_progress.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/core/platform/storage_channel.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/image_edit/domain/image_edit_repository.dart';
import 'package:media_downloader/features/image_edit/domain/image_plan.dart';
import 'package:media_downloader/features/library/domain/library_item.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'image_edit_repository_impl.g.dart';

/// `formatId` of an edited copy's record; nothing was downloaded for it.
const imageEditFormatId = 'edit';

class ImageEditRepositoryImpl implements ImageEditRepository {
  new(this._storage, this._db);

  final StorageChannel _storage;
  final AppDatabase _db;

  @override
  Future<Result<List<String>>> pick() =>
      guardPlatformCall(() => _storage.pickFiles('image/*', multiple: true));

  @override
  Future<Result<({int width, int height})>> probe(String fileUri) =>
      guardPlatformCall(() => _storage.probeImage(fileUri));

  @override
  Future<Uint8List?> preview(String fileUri, {int size = 720}) async {
    try {
      return await _storage.thumbnail(fileUri, size: size);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<Result<LibraryItem>> edit({
    required String id,
    required LibraryItem item,
    required String targetDir,
    required String name,
    required ImageFormat format,
    required int width,
    required int height,
    required int quality,
    int? targetBytes,
    int rotate = 0,
    ImageCrop? crop,
  }) async {
    final result = await guardPlatformCall(
      () => _storage.editImage(
        uri: item.fileUri,
        targetDir: targetDir,
        name: name,
        format: format.name,
        width: width,
        height: height,
        quality: quality,
        targetBytes: targetBytes,
        rotate: rotate,
        crop: crop,
      ),
    );
    switch (result) {
      case Err(:final failure):
        return Err(failure);
      case Ok(value: final saved):
        final now = DateTime.now();
        await _db
            .into(_db.downloadRecords)
            .insertOnConflictUpdate(
              DownloadRecordsCompanion.insert(
                id: id,
                url: item.sourceUrl,
                title: Value(name),
                formatId: imageEditFormatId,
                outputType: OutputType.image.name,
                state: DownloadState.saved.name,
                platform: Value(item.platform.name),
                ext: Value(format.name),
                sizeBytes: Value(saved.size),
                fileUri: Value(saved.uri),
                mimeType: Value(format.mimeType),
                completedAt: Value(now),
              ),
            );
        return Ok(
          LibraryItem(
            id: id,
            title: name,
            platform: item.platform,
            type: OutputType.image,
            fileUri: saved.uri,
            sourceUrl: item.sourceUrl,
            savedAt: now,
            mimeType: format.mimeType,
            ext: format.name,
            sizeBytes: saved.size,
          ),
        );
    }
  }
}

@Riverpod(keepAlive: true)
ImageEditRepository imageEditRepository(Ref ref) => ImageEditRepositoryImpl(
  ref.watch(storageChannelProvider),
  ref.watch(appDatabaseProvider),
);
