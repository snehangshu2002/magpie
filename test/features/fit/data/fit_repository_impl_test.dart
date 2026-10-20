import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/core/db/app_database.dart';
import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/core/platform/engine_channel.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/core/platform/storage_channel.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/fit/data/fit_repository_impl.dart';
import 'package:media_downloader/features/fit/domain/fit_plan.dart';
import 'package:media_downloader/features/library/domain/library_item.dart';

// Made-up ids, titles and URIs only; no real media.
const _uri = 'content://media/external/downloads/1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const engine = MethodChannel(EngineChannel.methodChannelName);
  const storage = MethodChannel(StorageChannel.channelName);

  late AppDatabase db;
  late FitRepositoryImpl repository;
  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall call) reply;

  final item = LibraryItem(
    id: 'd1',
    title: 'Test clip',
    platform: SourcePlatform.other,
    type: OutputType.video,
    fileUri: _uri,
    sourceUrl: 'https://example.com/v/1',
    savedAt: DateTime(2026),
    sizeBytes: 80 * 1000 * 1000,
  );
  const plan = FitEncode(
    videoKbps: 1157,
    audioKbps: 96,
    shortSide: 480,
    estimatedBytes: 9397500,
  );

  Future<Result<String>> start() => repository.start(
    id: 'f1',
    item: item,
    size: ShareSize.mb10,
    plan: plan,
    durationMs: 60000,
    targetDir: 'Download/Magpie/Other',
    name: 'Test clip (10 MB)',
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    calls = [];
    reply = (call) async => {'id': (call.arguments as Map)['id']};
    for (final channel in [engine, storage]) {
      messenger.setMockMethodCallHandler(channel, (call) {
        calls.add(call);
        return reply(call);
      });
    }
    repository = FitRepositoryImpl(EngineChannel(), StorageChannel(), db);
  });

  tearDown(() async {
    for (final channel in [engine, storage]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    await db.close();
  });

  test('probe reads the video by its URI', () async {
    reply = (_) async => {
      'durationMs': 60000,
      'width': 1920,
      'height': 1080,
      'hasAudio': true,
    };

    final probe = (await repository.probe(_uri)).getOrThrow();

    expect(calls.single.method, 'probeVideo');
    expect(calls.single.arguments, {'uri': _uri});
    expect(probe.durationMs, 60000);
    expect(probe.hasAudio, isTrue);
  });

  test('start records the copy and hands the plan to the engine', () async {
    expect(await start(), isA<Ok<String>>());

    expect(calls.single.method, 'fitVideo');
    expect(calls.single.arguments, {
      'id': 'f1',
      'uri': _uri,
      'targetDir': 'Download/Magpie/Other',
      'name': 'Test clip (10 MB)',
      'targetBytes': 10000000,
      'durationMs': 60000,
      'videoKbps': 1157,
      'audioKbps': 96,
      'maxShortSide': 480,
      'title': 'Test clip (10 MB)',
    });
    final record = await db.select(db.downloadRecords).getSingle();
    expect(record.id, 'f1');
    expect(record.url, item.sourceUrl);
    expect(record.title, 'Test clip (10 MB)');
    expect(record.formatId, fitFormatId);
    expect(record.state, 'queued');
    expect(record.quality, 480);
  });

  test('start forgets the record when the engine refuses', () async {
    reply = (_) async => throw PlatformException(code: 'NOT_FOUND');

    final result = await start();

    expect(
      result,
      isA<Err<String>>().having((e) => e.failure, 'failure', isA<Failure>()),
    );
    expect(await db.select(db.downloadRecords).get(), isEmpty);
  });
}
