import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_database.g.dart';

/// Download queue and history; one row per download.
class DownloadRecords extends Table {
  TextColumn get id => text()();
  TextColumn get url => text()();
  TextColumn get title => text().nullable()();
  TextColumn get extractor => text().nullable()();
  TextColumn get formatId => text()();
  TextColumn get outputType => text()();
  TextColumn get state => text()();

  /// `SourcePlatform.name`.
  TextColumn get platform => text().nullable()();

  /// Remote thumbnail from yt-dlp; may expire, so the Library prefers one
  /// made from the saved file.
  TextColumn get thumbnail => text().nullable()();
  TextColumn get ext => text().nullable()();

  /// Short side in pixels, for video.
  IntColumn get quality => integer().nullable()();

  /// Estimated at start, then the real size once saved.
  IntColumn get sizeBytes => integer().nullable()();

  /// MediaStore content URI once saved.
  TextColumn get fileUri => text().nullable()();
  TextColumn get mimeType => text().nullable()();
  TextColumn get error => text().nullable()();

  /// `<extractor> <id>` of a single video, so "Skip videos already
  /// downloaded" can tell it is in the Library.
  TextColumn get videoKey => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get completedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [DownloadRecords])
class AppDatabase extends _$AppDatabase {
  new([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'media_downloader'));

  @override
  int get schemaVersion => 3;

  Future<bool> _hasColumn(String table, String column) async {
    final columns = await customSelect('PRAGMA table_info($table)').get();
    return columns.any((c) => c.read<String>('name') == column);
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        final t = downloadRecords;
        for (final column in [
          t.platform,
          t.thumbnail,
          t.ext,
          t.quality,
          t.sizeBytes,
          t.mimeType,
        ]) {
          await m.addColumn(t, column);
        }
      }
      // A test build added this column without moving the version to 3,
      // so it may already be there.
      if (from < 3 && !await _hasColumn('download_records', 'video_key')) {
        await m.addColumn(downloadRecords, downloadRecords.videoKey);
      }
    },
  );
}

@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
}
