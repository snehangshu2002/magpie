import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/core/db/app_database.dart';
import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/core/platform/storage_channel.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/library/domain/library_item.dart';
import 'package:media_downloader/features/pdf/data/pdf_repository_impl.dart';
import 'package:media_downloader/features/pdf/domain/pdf_repository.dart';
import 'package:media_downloader/features/pdf/domain/pdf_tool.dart';

// Made-up titles and URIs only; no real documents.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const storage = MethodChannel(StorageChannel.channelName);

  late AppDatabase db;
  late PdfRepositoryImpl repository;
  late Future<Object?> Function(MethodCall call) reply;
  MethodCall? sent;

  LibraryItem pdf(int n) => LibraryItem(
    id: 'p$n',
    title: 'Notes $n',
    platform: SourcePlatform.other,
    type: OutputType.document,
    fileUri: 'content://media/external/downloads/$n',
    sourceUrl: '',
    savedAt: DateTime(2026),
  );

  Future<Result<List<LibraryItem>>> run(PdfTool tool, PdfOptions options) =>
      repository.run(
        tool: tool,
        items: [pdf(1), pdf(2)],
        options: options,
        targetDir: 'Download/Magpie/Other',
        name: 'Notes (merged)',
      );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = PdfRepositoryImpl(StorageChannel(), db);
    messenger.setMockMethodCallHandler(storage, (call) {
      sent = call;
      return reply(call);
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(storage, null);
    await db.close();
  });

  test('a merge sends every file in order and joins the Library', () async {
    reply = (_) async => {
      'uris': ['content://media/external/downloads/9'],
      'sizes': [5000],
    };

    final made = (await run(PdfTool.merge, const PdfOptions())).getOrThrow();

    final args = sent!.arguments as Map;
    expect(sent!.method, 'editPdf');
    expect(args['op'], 'merge');
    expect(args['uris'], [pdf(1).fileUri, pdf(2).fileUri]);
    expect(args['name'], 'Notes (merged)');
    expect(made.single.type, OutputType.document);
    expect(made.single.sizeBytes, 5000);

    final row = await db.select(db.downloadRecords).getSingle();
    expect(row.outputType, 'document');
    expect(row.mimeType, 'application/pdf');
    expect(row.state, 'saved');
  });

  test('deleting pages asks native to keep the others', () async {
    reply = (_) async => {
      'uris': ['content://media/external/downloads/9'],
      'sizes': [100],
    };
    await run(PdfTool.delete, const PdfOptions(pages: [1, 3]));
    final args = sent!.arguments as Map;
    expect(args['op'], 'extract');
    expect(args['pages'], [1, 3]);
  });

  test('pages as photos are each a Library image', () async {
    reply = (_) async => {
      'uris': ['content://a/1', 'content://a/2'],
      'sizes': [10, 20],
    };
    final made = (await run(PdfTool.toImages, const PdfOptions())).getOrThrow();
    expect(
      [for (final m in made) m.type],
      [OutputType.image, OutputType.image],
    );
    expect(
      [for (final m in made) m.title],
      ['Notes (merged) 1', 'Notes (merged) 2'],
    );
  });

  test('a compress that saves nothing records nothing', () async {
    reply = (_) async => {'uris': <String>[], 'sizes': <int>[]};
    final made = (await run(
      PdfTool.compress,
      const PdfOptions(compression: PdfCompression.strong),
    )).getOrThrow();
    expect(made, isEmpty);
    expect((sent!.arguments as Map)['quality'], 35);
    expect(await db.select(db.downloadRecords).get(), isEmpty);
  });

  test('a locked PDF is a readable failure', () async {
    reply = (_) async => throw PlatformException(code: 'PROTECTED');
    final result = await run(PdfTool.merge, const PdfOptions());
    expect((result as Err).failure, isA<ProtectedPdfFailure>());
    expect(await db.select(db.downloadRecords).get(), isEmpty);
  });
}
