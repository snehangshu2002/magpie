import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/core/platform/models/download_progress.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/features/library/data/library_repository_impl.dart';
import 'package:media_downloader/features/library/domain/active_download.dart';
import 'package:media_downloader/features/library/domain/library_item.dart';
import 'package:media_downloader/features/library/presentation/library_screen.dart';
import 'package:media_downloader/l10n/l10n.dart';

import '../../../helpers/fake_library_repository.dart';

// Made-up titles and URIs only; no real media.
final _clip = LibraryItem(
  id: 'd1',
  title: 'Test clip',
  platform: SourcePlatform.youtube,
  type: OutputType.video,
  fileUri: 'content://media/external/downloads/1',
  sourceUrl: 'https://example.com/watch/test',
  savedAt: DateTime(2026, 10, 19),
  ext: 'mp4',
  quality: 1080,
  sizeBytes: 4700000,
);

void main() {
  Future<void> pumpLibrary(
    WidgetTester tester,
    FakeLibraryRepository repository,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [libraryRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LibraryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('says so when nothing is downloaded', (tester) async {
    await pumpLibrary(tester, FakeLibraryRepository());

    expect(find.text('Nothing downloaded yet'), findsOneWidget);
  });

  testWidgets('lists saved files with their details', (tester) async {
    await pumpLibrary(tester, FakeLibraryRepository([_clip]));

    expect(find.text('Test clip'), findsOneWidget);
    expect(find.text('YouTube · 1080p · 4.7 MB'), findsOneWidget);
  });

  testWidgets('tapping a file opens it, and explains a failure', (
    tester,
  ) async {
    final repository = FakeLibraryRepository([_clip])
      ..openFailure = const Failure.notFound();
    await pumpLibrary(tester, repository);

    await tester.tap(find.text('Test clip'));
    await tester.pumpAndSettle();

    expect(repository.opened, ['d1']);
    expect(find.text('This file was moved or deleted.'), findsOneWidget);
  });

  testWidgets('share is in the sheet', (tester) async {
    final repository = FakeLibraryRepository([_clip]);
    await pumpLibrary(tester, repository);

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();

    expect(repository.shared, ['d1']);
  });

  testWidgets('delete asks first, then removes the file', (tester) async {
    await pumpLibrary(tester, FakeLibraryRepository([_clip]));

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this file?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Test clip'), findsNothing);
    expect(find.text('Deleted'), findsOneWidget);
    expect(find.text('Nothing downloaded yet'), findsOneWidget);
  });

  group('selecting', () {
    final photo = LibraryItem(
      id: 'd2',
      title: 'Test photo',
      platform: SourcePlatform.instagram,
      type: OutputType.image,
      fileUri: 'content://media/external/downloads/2',
      sourceUrl: 'https://example.com/p/test',
      savedAt: DateTime(2026, 10, 19),
    );

    testWidgets('a long press starts it; taps pick more; select all', (
      tester,
    ) async {
      await pumpLibrary(tester, FakeLibraryRepository([_clip, photo]));

      await tester.longPress(find.text('Test clip'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byTooltip('More options'), findsNothing);

      await tester.tap(find.text('Test photo'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      // Everything is picked; nothing left to select.
      expect(find.byTooltip('Select all'), findsNothing);

      await tester.tap(find.text('Test photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Select all'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
    });

    testWidgets('shares the picked files together', (tester) async {
      final repository = FakeLibraryRepository([_clip, photo]);
      await pumpLibrary(tester, repository);

      await tester.longPress(find.text('Test clip'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Share'));
      await tester.pumpAndSettle();

      expect(repository.shared, ['d1', 'd2']);
      expect(find.text('2 selected'), findsNothing);
    });

    testWidgets('deletes the picked files after asking once', (tester) async {
      await pumpLibrary(tester, FakeLibraryRepository([_clip, photo]));

      await tester.longPress(find.text('Test clip'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete 2 files?'), findsOneWidget);
      expect(find.text("They'll be removed from this device."), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Deleted 2 files'), findsOneWidget);
      expect(find.text('Nothing downloaded yet'), findsOneWidget);
    });

    testWidgets('close and back end it without leaving', (tester) async {
      final repository = FakeLibraryRepository([_clip]);
      await pumpLibrary(tester, repository);

      await tester.longPress(find.text('Test clip'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Done selecting'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsNothing);

      await tester.longPress(find.text('Test clip'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsNothing);
      expect(find.text('Test clip'), findsOneWidget);

      // Not selecting: a tap opens the file again.
      await tester.tap(find.text('Test clip'));
      await tester.pumpAndSettle();
      expect(repository.opened, ['d1']);
    });
  });

  testWidgets('copy link puts the source link on the clipboard', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpLibrary(tester, FakeLibraryRepository([_clip]));

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy link'));
    await tester.pumpAndSettle();

    expect(copied, 'https://example.com/watch/test');
    expect(find.text('Link copied'), findsOneWidget);
  });

  testWidgets('filters by kind of file and by search', (tester) async {
    final song = LibraryItem(
      id: 'd2',
      title: 'Test song',
      platform: SourcePlatform.youtubeMusic,
      type: OutputType.audio,
      fileUri: 'content://media/external/downloads/2',
      sourceUrl: 'https://example.com/listen/test',
      savedAt: DateTime(2026, 10, 18),
      ext: 'm4a',
    );
    await pumpLibrary(tester, FakeLibraryRepository([_clip, song]));

    await tester.tap(find.widgetWithText(ChoiceChip, 'Audio'));
    await tester.pumpAndSettle();
    expect(find.text('Test clip'), findsNothing);
    expect(find.text('Test song'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'clip');
    await tester.pumpAndSettle();
    expect(find.text('Test clip'), findsOneWidget);
    expect(find.text('Test song'), findsNothing);

    await tester.enterText(find.byType(TextField), 'nothing like it');
    await tester.pumpAndSettle();
    expect(find.text('Nothing matches'), findsOneWidget);
  });

  testWidgets('shows downloads in progress and cancels them', (tester) async {
    final repository = FakeLibraryRepository();
    await pumpLibrary(tester, repository);

    repository.active.add([
      const ActiveDownload(
        id: 'd3',
        title: 'Test stream',
        platform: SourcePlatform.youtube,
        type: OutputType.video,
        sizeBytes: 100000000,
        progress: DownloadProgress(
          id: 'd3',
          percent: 40,
          state: DownloadState.running,
          speed: '2.00MiB/s',
        ),
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('IN PROGRESS'), findsOneWidget);
    expect(find.text('1 active'), findsOneWidget);
    expect(find.text('40% · 2.00MiB/s · 40 MB / 100 MB'), findsOneWidget);
    expect(find.text('Nothing downloaded yet'), findsNothing);

    await tester.tap(find.byTooltip('Cancel download'));
    await tester.pumpAndSettle();
    expect(repository.cancelled, ['d3']);
  });
}
