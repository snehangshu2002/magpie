import 'dart:async';

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
import 'package:media_downloader/features/download/data/media_repository_impl.dart';
import 'package:media_downloader/features/download/domain/download_details.dart';
import 'package:media_downloader/features/library/data/library_repository_impl.dart';

// Made-up ids, titles and URIs only; no real media.
const _uri = 'content://media/external/downloads/1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late List<Object?> finished;
  late Object? Function(MethodCall call) storage;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    finished = [];
    storage = (_) => null;
    messenger
      ..setMockMethodCallHandler(
        const MethodChannel(EngineChannel.methodChannelName),
        (call) async => switch (call.method) {
          'startDownload' => {'id': (call.arguments as Map)['id']},
          'takeFinishedDownloads' => finished,
          _ => null,
        },
      )
      ..setMockMethodCallHandler(
        const MethodChannel(StorageChannel.channelName),
        (call) async => storage(call),
      );
    library = LibraryRepositoryImpl(db, EngineChannel(), StorageChannel());
  });

  tearDown(() async {
    messenger
      ..setMockMethodCallHandler(
        const MethodChannel(EngineChannel.methodChannelName),
        null,
      )
      ..setMockMethodCallHandler(
        const MethodChannel(StorageChannel.channelName),
        null,
      );
    await db.close();
  });

  /// Starts a download the way the Download screen does, then has the
  /// engine report it [state] (with [_uri] when saved).
  Future<void> download(String state) async {
    await MediaRepositoryImpl(EngineChannel(), db).startDownload(
      const DownloadRequest(
        id: 'd1',
        url: 'https://example.com/v/1',
        formatId: '137+140',
        outputType: OutputType.video,
        targetDir: 'Download/Magpie/YouTube',
        title: 'Test clip',
      ),
      const DownloadDetails(
        platform: SourcePlatform.youtube,
        ext: 'mp4',
        quality: 1080,
        sizeBytes: 4000000,
      ),
    );
    finished = [
      {
        'id': 'd1',
        'percent': 100.0,
        'state': state,
        if (state == 'saved') 'filePath': _uri,
      },
    ];
  }

  Object? fileExists(MethodCall call) => call.method == 'queryFiles'
      ? [
          {
            'uri': _uri,
            'name': 'Test clip.mp4',
            'size': 4700000,
            'mimeType': 'video/mp4',
          },
        ]
      : null;

  test('a download that saved while the app was away shows up', () async {
    await download('saved');
    storage = fileExists;

    expect(await library.watchItems().first, isEmpty);
    await library.sync();

    final item = (await library.watchItems().first).single;
    expect(item.title, 'Test clip');
    expect(item.platform, SourcePlatform.youtube);
    expect(item.type, OutputType.video);
    expect(item.quality, 1080);
    expect(item.fileUri, _uri);
    expect(item.sizeBytes, 4700000);
    expect(item.mimeType, 'video/mp4');
  });

  test('failed and cancelled downloads are dropped', () async {
    for (final state in ['failed', 'cancelled']) {
      await download(state);
      await library.sync();
      expect(await db.select(db.downloadRecords).get(), isEmpty);
    }
  });

  test('files deleted outside the app are forgotten', () async {
    await download('saved');
    storage = fileExists;
    await library.sync();

    storage = (call) => call.method == 'queryFiles' ? <Object?>[] : null;
    await library.sync();

    expect(await library.watchItems().first, isEmpty);
  });

  test(
    'a file deleted while a sync runs is forgotten by a second run',
    () async {
      await download('saved');
      storage = fileExists;
      await library.sync();

      // The first run looks before the file is deleted.
      final lookup = Completer<Object?>();
      storage = (call) => call.method == 'queryFiles' ? lookup.future : null;
      final first = library.sync();
      await pumpEventQueue();
      final second = library.sync();
      storage = (call) => call.method == 'queryFiles' ? <Object?>[] : null;
      lookup.complete(fileExists(const MethodCall('queryFiles')));
      await Future.wait([first, second]);

      expect(await library.watchItems().first, isEmpty);
    },
  );

  test('a failed lookup keeps the files', () async {
    await download('saved');
    storage = (_) => throw PlatformException(code: 'UNKNOWN');

    expect(await library.sync(), isA<Err<void>>());
    expect(await library.watchItems().first, hasLength(1));
  });

  test('opening a file that is gone forgets it', () async {
    await download('saved');
    storage = fileExists;
    await library.sync();
    final item = (await library.watchItems().first).single;

    storage = (_) => throw PlatformException(code: 'NOT_FOUND');
    final result = await library.open(item);

    expect(result, isA<Err<void>>());
    expect((result as Err<void>).failure, isA<NotFoundFailure>());
    expect(await library.watchItems().first, isEmpty);
  });

  test('deleting forgets only the files that are gone', () async {
    await download('saved');
    storage = fileExists;
    await library.sync();
    final item = (await library.watchItems().first).single;

    // The user declined the system prompt: nothing deleted, nothing forgotten.
    storage = (call) => call.method == 'deleteFiles' ? <Object?>[] : null;
    expect(
      await library.delete([item]),
      isA<Ok<int>>().having((r) => r.value, 'value', 0),
    );
    expect(await library.watchItems().first, hasLength(1));

    Object? asked;
    storage = (call) {
      asked = call.arguments;
      return call.method == 'deleteFiles' ? [_uri] : null;
    };
    expect(
      await library.delete([item]),
      isA<Ok<int>>().having((r) => r.value, 'value', 1),
    );
    expect(asked, {
      'uris': [_uri],
    });
    expect(await library.watchItems().first, isEmpty);
  });

  test('files shared together get one type that covers them all', () {
    expect(sharedMimeType(['video/mp4']), 'video/mp4');
    expect(sharedMimeType(['video/mp4', 'video/mp4']), 'video/mp4');
    expect(sharedMimeType(['video/mp4', 'video/webm']), 'video/*');
    expect(sharedMimeType(['video/mp4', 'image/jpeg']), '*/*');
    expect(sharedMimeType(['video/mp4', null]), '*/*');
    expect(sharedMimeType([null]), '*/*');
  });
}
