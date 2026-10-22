import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/core/db/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('stores and reads a download record', () async {
    await db
        .into(db.downloadRecords)
        .insert(
          DownloadRecordsCompanion.insert(
            id: 'abc',
            url: 'https://example.com/video',
            formatId: '18',
            outputType: 'video',
            state: 'queued',
          ),
        );

    final record = await db.select(db.downloadRecords).getSingle();

    expect(record.id, 'abc');
    expect(record.state, 'queued');
    expect(record.fileUri, isNull);
  });

  group('upgrade to schema 3', () {
    // The v2 table, as a phone has it before this version.
    const v2Columns =
        'id TEXT NOT NULL PRIMARY KEY, url TEXT NOT NULL, title TEXT, '
        'extractor TEXT, format_id TEXT NOT NULL, output_type TEXT NOT NULL, '
        'state TEXT NOT NULL, platform TEXT, thumbnail TEXT, ext TEXT, '
        'quality INTEGER, size_bytes INTEGER, file_uri TEXT, mime_type TEXT, '
        'error TEXT, created_at INTEGER NOT NULL DEFAULT '
        "(CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), "
        'completed_at INTEGER';

    Future<void> expectOpensWithVideoKey(String columns) async {
      final old = AppDatabase(
        NativeDatabase.memory(
          setup: (raw) => raw
            ..execute('CREATE TABLE download_records ($columns)')
            ..userVersion = 2,
        ),
      );
      addTearDown(old.close);
      await old
          .into(old.downloadRecords)
          .insert(
            DownloadRecordsCompanion.insert(
              id: 'a',
              url: 'https://example.com/video',
              formatId: '18',
              outputType: 'video',
              state: 'saved',
              videoKey: const Value('youtube a'),
            ),
          );
      final record = await old.select(old.downloadRecords).getSingle();
      expect(record.videoKey, 'youtube a');
    }

    test('adds the video key column', () async {
      await expectOpensWithVideoKey(v2Columns);
    });

    test('keeps a video key column a test build already added', () async {
      await expectOpensWithVideoKey('$v2Columns, video_key TEXT');
    });
  });
}
