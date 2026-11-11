import 'dart:math';

import 'package:drift/drift.dart';
import 'package:media_downloader/core/db/app_database.dart';
import 'package:media_downloader/core/errors/platform_failure.dart';
import 'package:media_downloader/core/platform/models/download_progress.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/core/platform/storage_channel.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/library/domain/library_item.dart';
import 'package:media_downloader/features/pdf/domain/pdf_repository.dart';
import 'package:media_downloader/features/pdf/domain/pdf_tool.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'pdf_repository_impl.g.dart';

/// `formatId` of the record of a file a PDF tool made.
const pdfFormatId = 'pdf';

class PdfRepositoryImpl implements PdfRepository {
  new(this._storage, this._db);

  final StorageChannel _storage;
  final AppDatabase _db;

  @override
  Future<Result<List<String>>> pick({
    required bool images,
    required bool multiple,
  }) => guardPlatformCall(
    () => _storage.pickFiles(
      images ? 'image/*' : 'application/pdf',
      multiple: multiple,
    ),
  );

  @override
  Future<Result<PdfInfo>> info(String uri, {String? password}) =>
      guardPlatformCall(() => _storage.pdfInfo(uri, password: password));

  @override
  Future<Result<List<LibraryItem>>> run({
    required PdfTool tool,
    required List<LibraryItem> items,
    required PdfOptions options,
    required String targetDir,
    required String name,
  }) async {
    final result = await guardPlatformCall(
      () => _storage.editPdf({
        'op': tool.op,
        'uris': [for (final item in items) item.fileUri],
        'targetDir': targetDir,
        'name': name,
        'pages': options.pages,
        'degrees': options.degrees,
        'text': options.text,
        'place': options.place.name,
        'fontSize': options.fontSize,
        'opacity': options.opacity,
        'diagonal': options.diagonal,
        'password': options.password,
        'quality': switch (tool) {
          PdfTool.compress => options.compression.quality,
          _ => 85,
        },
        'maxSide': switch (tool) {
          PdfTool.compress => options.compression.maxSide,
          _ => 2000,
        },
        'pageSize': options.a4 ? 'a4' : 'fit',
      }),
    );
    switch (result) {
      case Err(:final failure):
        return Err(failure);
      case Ok(value: (:final uris, :final sizes)):
        final images = tool == PdfTool.toImages;
        final type = images ? OutputType.image : OutputType.document;
        final ext = images ? 'jpg' : 'pdf';
        final mime = images ? 'image/jpeg' : 'application/pdf';
        final source = items.first;
        final now = DateTime.now();
        final made = [
          for (final (i, uri) in uris.indexed)
            LibraryItem(
              id: '${_newId()}-$i',
              title: uris.length > 1 ? '$name ${i + 1}' : name,
              platform: source.platform,
              type: type,
              fileUri: uri,
              sourceUrl: source.sourceUrl,
              savedAt: now,
              mimeType: mime,
              ext: ext,
              sizeBytes: sizes[i],
            ),
        ];
        await _db.batch((batch) {
          for (final item in made) {
            batch.insert(
              _db.downloadRecords,
              DownloadRecordsCompanion.insert(
                id: item.id,
                url: item.sourceUrl,
                title: Value(item.title),
                formatId: pdfFormatId,
                outputType: item.type.name,
                state: DownloadState.saved.name,
                platform: Value(item.platform.name),
                ext: Value(item.ext),
                sizeBytes: Value(item.sizeBytes),
                fileUri: Value(item.fileUri),
                mimeType: Value(item.mimeType),
                completedAt: Value(now),
              ),
              mode: InsertMode.insertOrReplace,
            );
          }
        });
        return Ok(made);
    }
  }

  static final _random = Random.secure();

  static String _newId() =>
      [for (var i = 0; i < 16; i++) _random.nextInt(16).toRadixString(16)]
          .join();
}

@Riverpod(keepAlive: true)
PdfRepository pdfRepository(Ref ref) => PdfRepositoryImpl(
  ref.watch(storageChannelProvider),
  ref.watch(appDatabaseProvider),
);
