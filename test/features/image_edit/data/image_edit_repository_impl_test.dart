import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/core/db/app_database.dart';
import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/core/platform/storage_channel.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/image_edit/data/image_edit_repository_impl.dart';
import 'package:media_downloader/features/image_edit/domain/image_plan.dart';
import 'package:media_downloader/features/library/domain/library_item.dart';

// Made-up ids, titles and URIs only; no real media.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const storage = MethodChannel(StorageChannel.channelName);

  late AppDatabase db;
  late ImageEditRepositoryImpl repository;
  late Future<Object?> Function(MethodCall call) reply;
  MethodCall? sent;

  final item = LibraryItem(
    id: 'd1',
    title: 'Test photo',
    platform: SourcePlatform.other,
    type: OutputType.image,
    fileUri: 'content://media/external/downloads/1',
    sourceUrl: 'https://example.com/p/1',
    savedAt: DateTime(2026),
  );

  Future<Result<LibraryItem>> edit() => repository.edit(
    id: 'e1',
    item: item,
    targetDir: 'Download/Magpie/Other',
    name: 'Test photo (400×300)',
    format: ImageFormat.webp,
    width: 400,
    height: 300,
    quality: 80,
    targetBytes: 50000,
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = ImageEditRepositoryImpl(StorageChannel(), db);
    messenger.setMockMethodCallHandler(storage, (call) {
      sent = call;
      return reply(call);
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(storage, null);
    await db.close();
  });

  test('the copy is saved and joins the Library', () async {
    reply = (_) async => {
      'uri': 'content://media/external/downloads/2',
      'size': 41000,
    };

    final copy = (await edit()).getOrThrow();

    expect(sent!.method, 'editImage');
    expect(sent!.arguments, {
      'uri': item.fileUri,
      'targetDir': 'Download/Magpie/Other',
      'name': 'Test photo (400×300)',
      'format': 'webp',
      'width': 400,
      'height': 300,
      'quality': 80,
      'targetBytes': 50000,
      'rotate': 0,
      'crop': null,
    });
    expect(copy.fileUri, 'content://media/external/downloads/2');
    expect(copy.sizeBytes, 41000);

    final row = await db.select(db.downloadRecords).getSingle();
    expect(row.id, 'e1');
    expect(row.state, 'saved');
    expect(row.outputType, 'image');
    expect(row.fileUri, copy.fileUri);
    expect(row.mimeType, 'image/webp');
    expect(row.url, item.sourceUrl);
  });

  test('a failure records nothing', () async {
    reply = (_) async => throw PlatformException(code: 'TOO_LARGE');

    expect(await edit(), isA<Err<LibraryItem>>());
    expect((await edit() as Err).failure, isA<TooLargeFailure>());
    expect(await db.select(db.downloadRecords).get(), isEmpty);
  });
}
