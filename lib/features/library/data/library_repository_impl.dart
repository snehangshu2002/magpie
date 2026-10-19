import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:media_downloader/core/db/app_database.dart';
import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/errors/platform_failure.dart';
import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/core/platform/engine_channel.dart';
import 'package:media_downloader/core/platform/models/download_progress.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/core/platform/models/stored_file.dart';
import 'package:media_downloader/core/platform/storage_channel.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/library/domain/active_download.dart';
import 'package:media_downloader/features/library/domain/library_item.dart';
import 'package:media_downloader/features/library/domain/library_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'library_repository_impl.g.dart';

class LibraryRepositoryImpl implements LibraryRepository {
  new(this._db, this._engine, this._storage);

  final AppDatabase _db;
  final EngineChannel _engine;
  final StorageChannel _storage;

  /// The running [sync], so overlapping calls share it.
  Future<Result<void>>? _syncing;

  /// Set when [sync] is called while it runs: files may have changed after
  /// the running one looked, so it goes once more.
  var _syncAgain = false;

  $DownloadRecordsTable get _records => _db.downloadRecords;

  @override
  Stream<List<LibraryItem>> watchItems() {
    final query = _db.select(_records)
      ..where(
        (r) => r.state.equals(DownloadState.saved.name) & r.fileUri.isNotNull(),
      )
      ..orderBy([
        (r) => OrderingTerm.desc(r.completedAt),
        (r) => OrderingTerm.desc(r.createdAt),
      ]);
    return query.watch().map((rows) => rows.map(_toItem).toList());
  }

  @override
  Stream<List<ActiveDownload>> watchActive() {
    final query = _db.select(_records)
      ..where(
        (r) => r.state.isIn([
          for (final state in DownloadState.values)
            if (state.isActive) state.name,
        ]),
      )
      ..orderBy([(r) => OrderingTerm.asc(r.createdAt)]);

    final latest = <String, DownloadProgress>{};
    var rows = <DownloadRecord>[];
    StreamSubscription<List<DownloadRecord>>? recordChanges;
    StreamSubscription<DownloadProgress>? events;
    late final StreamController<List<ActiveDownload>> controller;

    void emit() => controller.add([
      for (final r in rows)
        if (latest[r.id] case final progress? when progress.state.isActive)
          ActiveDownload(
            id: r.id,
            title: r.title ?? r.url,
            platform:
                SourcePlatform.values.asNameMap()[r.platform] ??
                SourcePlatform.other,
            type:
                OutputType.values.asNameMap()[r.outputType] ?? OutputType.video,
            progress: progress,
            thumbnailUrl: r.thumbnail,
            sizeBytes: r.sizeBytes,
          ),
    ]);

    controller = StreamController(
      onListen: () {
        emit();
        recordChanges = query.watch().listen((value) {
          rows = value;
          emit();
        }, onError: controller.addError);
        // Progress is best effort: without it nothing shows as running.
        events = _engine.progress.listen((event) {
          latest[event.id] = event;
          emit();
        }, onError: (_) {});
      },
      onCancel: () async {
        await recordChanges?.cancel();
        await events?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<Result<bool>> cancel(String id) =>
      guardPlatformCall(() => _engine.cancelDownload(id));

  @override
  Stream<void> get downloadsFinished =>
      _engine.progress.where((event) => !event.state.isActive);

  @override
  Stream<void> get filesChanged => _storage.changes;

  @override
  Future<Result<void>> sync() {
    if (_syncing case final running?) {
      _syncAgain = true;
      return running;
    }
    return _syncing = _syncUntilSettled();
  }

  Future<Result<void>> _syncUntilSettled() async {
    try {
      Result<void> result;
      do {
        _syncAgain = false;
        result = await _sync();
      } while (_syncAgain);
      return result;
    } finally {
      _syncing = null;
    }
  }

  Future<Result<void>> _sync() async {
    final finished = await guardPlatformCall(_engine.takeFinishedDownloads);
    if (finished case Ok(value: final events)) {
      for (final event in events) {
        await _apply(event);
      }
    }

    final saved = await (_db.select(
      _records,
    )..where((r) => r.state.equals(DownloadState.saved.name))).get();
    if (saved.isEmpty) return const Ok(null);
    final uris = [for (final r in saved) ?r.fileUri];
    final Map<String, StoredFile> files;
    switch (await guardPlatformCall(() => _storage.queryFiles(uris))) {
      case Ok(:final value):
        files = {for (final file in value) file.uri: file};
      // Never forget files just because the lookup failed.
      case Err(:final failure):
        return Err(failure);
    }

    await _db.batch((batch) {
      for (final record in saved) {
        final file = files[record.fileUri];
        if (file == null) {
          batch.deleteWhere(_records, (r) => r.id.equals(record.id));
        } else {
          batch.update(
            _records,
            DownloadRecordsCompanion(
              sizeBytes: Value(file.size ?? record.sizeBytes),
              mimeType: Value(file.mimeType ?? record.mimeType),
            ),
            where: (r) => r.id.equals(record.id),
          );
        }
      }
    });
    return switch (finished) {
      Err(:final failure) => Err(failure),
      Ok() => const Ok(null),
    };
  }

  /// Records the final state of a download; failed and cancelled ones are
  /// dropped, since the Library only lists saved files.
  Future<void> _apply(DownloadProgress event) async {
    final row = _records.id.equals(event.id);
    if (event.state == DownloadState.saved && event.filePath != null) {
      final saved = DownloadRecordsCompanion(
        state: Value(DownloadState.saved.name),
        fileUri: Value(event.filePath),
        completedAt: Value(DateTime.now()),
      );
      await (_db.update(_records)..where((_) => row)).write(saved);
      // A post saved several files: one Library entry each, like the
      // first. Size and type are filled in by the next sync.
      final more = event.filePaths?.skip(1) ?? const <String>[];
      if (more.isEmpty) return;
      final first = await (_db.select(
        _records,
      )..where((_) => row)).getSingleOrNull();
      if (first == null) return;
      await _db.batch((batch) {
        for (final (i, uri) in more.indexed) {
          batch.insert(
            _records,
            first
                .toCompanion(false)
                .copyWith(
                  id: Value('${event.id}-${i + 2}'),
                  fileUri: Value(uri),
                  sizeBytes: const Value(null),
                  mimeType: const Value(null),
                ),
            mode: InsertMode.insertOrReplace,
          );
        }
      });
    } else if (!event.state.isActive) {
      await (_db.delete(_records)..where((_) => row)).go();
    }
  }

  @override
  Future<Uint8List?> thumbnail(String fileUri) async {
    try {
      return await _storage.thumbnail(fileUri);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<Result<void>> open(LibraryItem item) => _forgetIfMissing(
    [item],
    guardPlatformCall(
      () => _storage.openFile(item.fileUri, mimeType: item.mimeType),
    ),
  );

  @override
  Future<Result<void>> share(List<LibraryItem> items) => _forgetIfMissing(
    items,
    guardPlatformCall(
      () => _storage.shareFiles(
        [for (final item in items) item.fileUri],
        mimeType: sharedMimeType([for (final item in items) item.mimeType]),
        title: items.length == 1 ? items.single.title : null,
      ),
    ),
  );

  @override
  Future<Result<int>> delete(List<LibraryItem> items) async {
    final result = await guardPlatformCall(
      () => _storage.deleteFiles([for (final item in items) item.fileUri]),
    );
    switch (result) {
      case Ok(value: final gone):
        final deleted = [
          for (final item in items)
            if (gone.contains(item.fileUri)) item,
        ];
        await _forget(deleted);
        return Ok(deleted.length);
      case Err(:final failure):
        return Err(failure);
    }
  }

  /// A file deleted outside the app can't come back; drop it from the list.
  /// Sharing fails this way only when none of [items] exist.
  Future<Result<T>> _forgetIfMissing<T>(
    List<LibraryItem> items,
    Future<Result<T>> call,
  ) async {
    final result = await call;
    if (result case Err(failure: NotFoundFailure())) await _forget(items);
    return result;
  }

  Future<void> _forget(List<LibraryItem> items) => (_db.delete(
    _records,
  )..where((r) => r.id.isIn([for (final item in items) item.id]))).go();

  static LibraryItem _toItem(DownloadRecord r) => LibraryItem(
    id: r.id,
    title: r.title ?? r.url,
    platform:
        SourcePlatform.values.asNameMap()[r.platform] ?? SourcePlatform.other,
    type: OutputType.values.asNameMap()[r.outputType] ?? OutputType.video,
    fileUri: r.fileUri!,
    sourceUrl: r.url,
    savedAt: r.completedAt ?? r.createdAt,
    mimeType: r.mimeType,
    ext: r.ext,
    quality: r.quality,
    sizeBytes: r.sizeBytes,
    thumbnailUrl: r.thumbnail,
  );
}

/// One MIME type covering all of [types], for sharing them together: the
/// type itself when they all match, `video/*` when they are one kind, else
/// `*/*`. Unknown types count as anything.
String sharedMimeType(List<String?> types) {
  final distinct = types.toSet();
  if (distinct.length == 1 && distinct.single != null) return distinct.single!;
  final kinds = {for (final type in types) type?.split('/').first};
  if (kinds.length == 1 && kinds.single != null) return '${kinds.single}/*';
  return '*/*';
}

@Riverpod(keepAlive: true)
LibraryRepository libraryRepository(Ref ref) => LibraryRepositoryImpl(
  ref.watch(appDatabaseProvider),
  ref.watch(engineChannelProvider),
  ref.watch(storageChannelProvider),
);
