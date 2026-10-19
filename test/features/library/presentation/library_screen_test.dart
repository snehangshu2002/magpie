import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/features/library/data/library_repository_impl.dart';
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
    expect(find.text('1080p · MP4 · 4.7 MB · Oct 19'), findsOneWidget);
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

  testWidgets('share is in the menu', (tester) async {
    final repository = FakeLibraryRepository([_clip]);
    await pumpLibrary(tester, repository);

    await tester.tap(find.byTooltip('Show menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();

    expect(repository.shared, ['d1']);
  });

  testWidgets('delete asks first, then removes the file', (tester) async {
    await pumpLibrary(tester, FakeLibraryRepository([_clip]));

    await tester.tap(find.byTooltip('Show menu'));
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
}
