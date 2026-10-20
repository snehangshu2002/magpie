import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/app.dart';
import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/core/platform/models/download_progress.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/core/platform/models/engine_update_result.dart';
import 'package:media_downloader/core/platform/models/media_info.dart';
import 'package:media_downloader/core/platform/share_channel.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/download/data/media_repository_impl.dart';
import 'package:media_downloader/features/download/domain/download_details.dart';
import 'package:media_downloader/features/download/domain/download_option.dart';
import 'package:media_downloader/features/download/domain/media_repository.dart';
import 'package:media_downloader/features/download/domain/web_photo.dart';
import 'package:media_downloader/features/intake/presentation/widgets/supported_platforms.dart';
import 'package:media_downloader/features/library/data/library_repository_impl.dart';
import 'package:media_downloader/features/settings/data/engine_repository_impl.dart';
import 'package:media_downloader/features/settings/data/settings_repository_impl.dart';
import 'package:media_downloader/features/settings/domain/app_settings.dart';
import 'package:media_downloader/features/settings/domain/engine_repository.dart';
import 'package:media_downloader/features/settings/presentation/settings_providers.dart';

import '../../../helpers/fake_library_repository.dart';
import '../../../helpers/fake_settings_repository.dart';

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

/// A made-up carousel: a photo, then two clips.
const _carousel = MediaInfo(
  title: 'Test post',
  extractor: 'instagram',
  entries: [
    MediaEntry(thumbnail: 'https://example.com/photo.jpg'),
    MediaEntry(
      duration: 12,
      formats: [MediaFormat(formatId: 'v1', ext: 'mp4', height: 720)],
    ),
    MediaEntry(
      duration: 30,
      formats: [MediaFormat(formatId: 'v2', ext: 'mp4', height: 720)],
    ),
  ],
);

class _FakeMediaRepository implements MediaRepository {
  /// What [fetchInfo] returns.
  MediaInfo info = _clip;
  final fetched = <Uri>[];
  final requests = <DownloadRequest>[];
  final cancelled = <String>[];
  final progress = StreamController<DownloadProgress>.broadcast();

  /// Returned by [startDownload] instead of the id, when set.
  Failure? startFailure;

  @override
  Future<Result<MediaInfo>> fetchInfo(Uri url) async {
    fetched.add(url);
    return Ok(info);
  }

  /// What [fetchPhotos] returns.
  WebPhotos? photos;

  @override
  Future<Result<WebPhotos?>> fetchPhotos(
    Uri url,
    SourcePlatform platform,
  ) async => Ok(photos);

  @override
  Future<Result<WebPhotos?>> fetchImage(Uri url) async => const Ok(null);

  @override
  Future<Result<String>> startDownload(
    DownloadRequest request,
    DownloadDetails details,
  ) async {
    requests.add(request);
    return switch (startFailure) {
      final failure? => Err(failure),
      null => Ok(request.id),
    };
  }

  @override
  Stream<DownloadProgress> progressOf(String id) =>
      progress.stream.where((event) => event.id == id);

  @override
  Future<Result<bool>> cancelDownload(String id) async {
    cancelled.add(id);
    return const Ok(true);
  }

  /// Sends a progress event for the last started download.
  void emit(
    DownloadState state, {
    double percent = 0,
    String? error,
    String? filePath,
  }) => progress.add(
    DownloadProgress(
      id: requests.last.id,
      percent: percent,
      state: state,
      error: error,
      filePath: filePath,
    ),
  );
}

class _FakeEngineRepository implements EngineRepository {
  @override
  Future<Result<String>> initialize() async => const Ok('2026.01.01');

  @override
  Future<Result<EngineUpdateResult>> update(
    EngineReleaseChannel channel,
  ) async => const Ok(
    EngineUpdateResult(status: EngineUpdateStatus.done, version: '2026.02.02'),
  );
}

void main() {
  late _FakeMediaRepository media;
  late FakeLibraryRepository library;
  late StreamController<String> shared;
  String? clipboard;

  setUp(() {
    media = _FakeMediaRepository();
    library = FakeLibraryRepository();
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
    await media.progress.close();
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
          settingsRepositoryProvider.overrideWithValue(
            FakeSettingsRepository(),
          ),
          libraryRepositoryProvider.overrideWithValue(library),
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

  testWidgets('the share tip rests at the bottom at its own height', (
    tester,
  ) async {
    await pumpApp(tester);
    final tip = tester.getRect(find.byType(ShareTip));
    final nav = tester.getRect(find.byType(NavigationBar));
    expect(tip.height, lessThan(200));
    expect(nav.top - tip.bottom, lessThan(40));
  });

  testWidgets('recognizes the site while typing, without fetching', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.text('WORKS WITH'), findsOneWidget);

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
    expect(find.textContaining('Best quality up to 1080p'), findsOneWidget);
    expect(find.text('Download · 48 MB'), findsOneWidget);
    expect(find.text('Download/Magpie/YouTube'), findsOneWidget);
  });

  testWidgets('switching to audio updates the download', (tester) async {
    await pumpApp(tester);
    await submit(tester, _link);

    await tester.tap(find.text('Audio'));
    await tester.pumpAndSettle();

    expect(find.text('M4A'), findsOneWidget);
    expect(find.text('Download · 3 MB'), findsOneWidget);
  });

  testWidgets('one item of a post can be picked and saved alone', (
    tester,
  ) async {
    media.info = _carousel;
    await pumpApp(tester);
    await submit(tester, 'https://www.instagram.com/p/test123/');

    expect(find.text('Choose what to save'), findsOneWidget);
    expect(find.text('3 files'), findsWidgets);

    await tester.tap(find.bySemanticsLabel('Item 2, Video'));
    await tester.pumpAndSettle();
    expect(find.text('Item 2 of 3'), findsOneWidget);

    await tester.tap(find.text('Download').first);
    await tester.pump(const Duration(seconds: 1));

    final request = media.requests.single;
    expect(request.formatId, postSelector);
    expect(request.items, [2]);
    expect(request.outputType, OutputType.video);
  });

  testWidgets('a whole post is saved by default', (tester) async {
    media.info = _carousel;
    await pumpApp(tester);
    await submit(tester, 'https://www.instagram.com/p/test123/');

    await tester.tap(find.text('Download').first);
    await tester.pump(const Duration(seconds: 1));

    expect(media.requests.single.items, isNull);
  });

  testWidgets('several items of a post can be picked together', (tester) async {
    media.info = _carousel;
    await pumpApp(tester);
    await submit(tester, 'https://www.instagram.com/p/test123/');

    await tester.tap(find.bySemanticsLabel('Item 3, Video'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Item 1, Image'));
    await tester.pumpAndSettle();
    expect(find.text('2 of 3 selected'), findsOneWidget);

    // Tapping a picked item again leaves it out.
    await tester.tap(find.bySemanticsLabel('Item 3, Video'));
    await tester.pumpAndSettle();
    expect(find.text('Item 1 of 3'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Item 2, Video'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Download').first);
    await tester.pump(const Duration(seconds: 1));

    final request = media.requests.single;
    expect(request.formatId, postSelector);
    expect(request.items, [1, 2]);
    expect(request.outputType, OutputType.video);
  });

  testWidgets('picking every item saves the whole post', (tester) async {
    media.info = _carousel;
    await pumpApp(tester);
    await submit(tester, 'https://www.instagram.com/p/test123/');

    for (final label in ['Item 1, Image', 'Item 2, Video', 'Item 3, Video']) {
      await tester.tap(find.bySemanticsLabel(label));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Download').first);
    await tester.pump(const Duration(seconds: 1));

    expect(media.requests.single.items, isNull);
  });

  // The queued state shows a spinner, so these pump a fixed time instead of
  // settling.
  Future<void> pumpFor(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 1));

  testWidgets('download sends the choice and shows its progress', (
    tester,
  ) async {
    await pumpApp(tester);
    await submit(tester, _link);

    await tester.tap(find.text('Download · 48 MB'));
    await pumpFor(tester);

    final request = media.requests.single;
    expect(request.url, _link);
    expect(request.formatId, '137+140');
    expect(request.outputType, OutputType.video);
    expect(request.targetDir, 'Download/Magpie/YouTube');
    expect(request.title, 'Test clip');
    expect(find.text('Waiting to start…'), findsOneWidget);

    media.emit(DownloadState.running, percent: 45.6);
    await pumpFor(tester);
    expect(find.text('Downloading'), findsOneWidget);
    expect(find.text('45%'), findsOneWidget);

    media.emit(DownloadState.saved, percent: 100, filePath: 'content://f/1');
    await tester.pumpAndSettle();
    expect(find.text('Saved to Download/Magpie/YouTube'), findsOneWidget);
    await tester.tap(find.text('Open'));
    await tester.pump();
    expect(library.opened, [media.requests.single.id]);
    expect(find.text('Download again'), findsOneWidget);
  });

  testWidgets('changing the theme does not fetch the link again', (
    tester,
  ) async {
    await pumpApp(tester);
    await submit(tester, _link);
    expect(media.fetched, hasLength(1));

    await ProviderScope.containerOf(tester.element(find.byType(App)))
        .read(settingsProvider.notifier)
        .change((s) => s.copyWith(appearance: AppearanceMode.dark));
    await tester.pumpAndSettle();

    expect(media.fetched, hasLength(1));
    expect(find.text('Test clip'), findsOneWidget);
  });

  testWidgets('cancel stops the download', (tester) async {
    await pumpApp(tester);
    await submit(tester, _link);
    await tester.tap(find.text('Download · 48 MB'));
    media.emit(DownloadState.running, percent: 10);
    await pumpFor(tester);

    await tester.tap(find.byTooltip('Cancel download'));
    await pumpFor(tester);
    expect(media.cancelled, [media.requests.single.id]);
    expect(find.text('Cancelling…'), findsOneWidget);

    media.emit(DownloadState.cancelled, percent: 10);
    await tester.pumpAndSettle();
    expect(find.text('Download cancelled'), findsOneWidget);
    expect(find.text('Download · 48 MB'), findsOneWidget);
    expect(find.textContaining('Saved to'), findsNothing);
  });

  testWidgets('a failed download explains why', (tester) async {
    await pumpApp(tester);
    await submit(tester, _link);
    await tester.tap(find.text('Download · 48 MB'));
    await pumpFor(tester);

    media.emit(DownloadState.failed, error: 'NETWORK');
    await tester.pumpAndSettle();
    expect(
      find.text('Network error. Check your connection and try again.'),
      findsOneWidget,
    );
    expect(find.text('Download · 48 MB'), findsOneWidget);
  });

  testWidgets('a download that cannot start shows the failure inline', (
    tester,
  ) async {
    media.startFailure = const Failure.unavailable();
    await pumpApp(tester);
    await submit(tester, _link);

    await tester.tap(find.text('Download · 48 MB'));
    await tester.pumpAndSettle();

    expect(
      find.text("This isn't available right now. Try again later."),
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

  testWidgets('text that is not a link gets a quiet hint', (tester) async {
    await pumpApp(tester);
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pumpAndSettle();

    expect(find.text("Paste a full link, like a video's share link"), findsOne);
    expect(find.text("That doesn't look like a link."), findsNothing);
  });
}
