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
}
