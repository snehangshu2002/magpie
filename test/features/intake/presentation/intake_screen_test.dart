import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/app.dart';
import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/core/platform/models/media_info.dart';
import 'package:media_downloader/core/platform/share_channel.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/download/data/media_repository_impl.dart';
import 'package:media_downloader/features/download/domain/media_repository.dart';
import 'package:media_downloader/features/settings/data/engine_repository_impl.dart';
import 'package:media_downloader/features/settings/domain/engine_repository.dart';

// Made-up ids and titles only; no real media.
const _link = 'https://youtu.be/test123';

const _clip = MediaInfo(
  title: 'Test clip',
  extractor: 'youtube',
  duration: 125,
  formats: [
    MediaFormat(
      formatId: '140',
      ext: 'm4a',
      vcodec: 'none',
      acodec: 'mp4a.40.2',
      fileSize: 3000000,
    ),
    MediaFormat(
      formatId: '136',
      ext: 'mp4',
      width: 1280,
      height: 720,
      vcodec: 'avc1.4d401f',
      acodec: 'none',
      fileSize: 20000000,
    ),
    MediaFormat(
      formatId: '137',
      ext: 'mp4',
      width: 1920,
      height: 1080,
      vcodec: 'avc1.640028',
      acodec: 'none',
      fileSize: 45000000,
    ),
  ],
);

class _FakeMediaRepository implements MediaRepository {
  final fetched = <Uri>[];
  final requests = <DownloadRequest>[];

  @override
  Future<Result<MediaInfo>> fetchInfo(Uri url) async {
    fetched.add(url);
    return const Ok(_clip);
  }

  @override
  Future<Result<String>> startDownload(DownloadRequest request) async {
    requests.add(request);
    return const Err(Failure.unavailable());
  }
}

class _FakeEngineRepository implements EngineRepository {
  @override
  Future<Result<String>> initialize() async => const Ok('2026.01.01');
}

void main() {
  late _FakeMediaRepository media;
  late StreamController<String> shared;
  String? clipboard;

  setUp(() {
    media = _FakeMediaRepository();
    shared = StreamController<String>();
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') {
            return clipboard == null ? null : {'text': clipboard};
          }
          return null; // Haptics and other platform calls.
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    await shared.close();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    // A phone-sized screen, so the options aren't below the fold.
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          mediaRepositoryProvider.overrideWithValue(media),
          engineRepositoryProvider.overrideWithValue(_FakeEngineRepository()),
          sharedTextProvider.overrideWith((ref) => shared.stream),
        ],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
  }

  testWidgets('recognizes the site while typing, without fetching', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.text('Works with'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'youtu.be/test123');
    await tester.pumpAndSettle();

    expect(find.text('YouTube · Video'), findsOneWidget);
    expect(media.fetched, isEmpty);
  });

  testWidgets('submitting shows the media and the recommended option', (
    tester,
  ) async {
    await pumpApp(tester);
    await submit(tester, _link);

    expect(media.fetched, [Uri.parse(_link)]);
    expect(find.text('Test clip'), findsOneWidget);
    expect(find.text('1080p'), findsOneWidget);
    expect(find.text('Recommended'), findsOneWidget);
    expect(find.text('Best quality up to 1080p'), findsOneWidget);
    expect(find.text('Download · 48 MB'), findsOneWidget);
    expect(find.text('Saves to Download/Magpie/YouTube'), findsOneWidget);
  });

  testWidgets('switching to audio updates the download', (tester) async {
    await pumpApp(tester);
    await submit(tester, _link);

    await tester.tap(find.text('Audio'));
    await tester.pumpAndSettle();

    expect(find.text('M4A'), findsOneWidget);
    expect(find.text('Download · 3 MB'), findsOneWidget);
  });

  testWidgets('download sends the choice and shows the failure inline', (
    tester,
  ) async {
    await pumpApp(tester);
    await submit(tester, _link);

    await tester.tap(find.text('Download · 48 MB'));
    await tester.pumpAndSettle();

    final request = media.requests.single;
    expect(request.url, _link);
    expect(request.formatId, '137+140');
    expect(request.outputType, OutputType.video);
    expect(request.targetDir, 'Download/Magpie/YouTube');
    expect(
      find.text("This isn't available in this version yet."),
      findsOneWidget,
    );
  });

  testWidgets('a shared link fills the box and fetches at once', (
    tester,
  ) async {
    await pumpApp(tester);

    shared.add('Watch this $_link !');
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      _link,
    );
    expect(media.fetched, [Uri.parse(_link)]);
    expect(find.text('Test clip'), findsOneWidget);
  });

  testWidgets('Paste fetches the link on the clipboard', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();
    expect(find.text("There's no link on the clipboard."), findsOneWidget);

    clipboard = _link;
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();
    expect(find.text('Test clip'), findsOneWidget);
  });

  testWidgets('a playlist link explains why it is not fetched', (tester) async {
    await pumpApp(tester);
    await submit(tester, 'https://www.youtube.com/playlist?list=PLtest');

    expect(find.textContaining("Playlists aren't supported"), findsOneWidget);
    expect(media.fetched, isEmpty);
  });
}
