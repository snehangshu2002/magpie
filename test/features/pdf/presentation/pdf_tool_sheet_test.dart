import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/library/domain/library_item.dart';
import 'package:media_downloader/features/pdf/data/pdf_repository_impl.dart';
import 'package:media_downloader/features/pdf/domain/pdf_repository.dart';
import 'package:media_downloader/features/pdf/domain/pdf_tool.dart';
import 'package:media_downloader/features/pdf/presentation/pdf_tool_sheet.dart';
import 'package:media_downloader/features/settings/data/settings_repository_impl.dart';
import 'package:media_downloader/l10n/app_localizations.dart';

import '../../../helpers/fake_settings_repository.dart';

class _FakePdfRepository implements PdfRepository {
  new(this.pages);

  /// Null: the PDF is locked until opened with 'secret'.
  final int? pages;
  final runs = <(PdfTool, PdfOptions)>[];

  @override
  Future<Result<List<String>>> pick({
    required bool images,
    required bool multiple,
  }) async => const Ok([]);

  @override
  Future<Result<PdfInfo>> info(String uri, {String? password}) async => Ok((
    pages: pages ?? (password == 'secret' ? 4 : null),
    name: 'Notes.pdf',
    size: 1000,
    protected: pages == null && password != 'secret',
  ));

  @override
  Future<Result<List<LibraryItem>>> run({
    required PdfTool tool,
    required List<LibraryItem> items,
    required PdfOptions options,
    required String targetDir,
    required String name,
  }) async {
    runs.add((tool, options));
    return Ok([items.first.copy(title: name)]);
  }
}

extension on LibraryItem {
  LibraryItem copy({required String title}) => LibraryItem(
    id: '$id-copy',
    title: title,
    platform: platform,
    type: type,
    fileUri: '$fileUri-copy',
    sourceUrl: sourceUrl,
    savedAt: savedAt,
    sizeBytes: 900,
  );
}

final _pdf = LibraryItem(
  id: 'p1',
  title: 'Notes',
  platform: SourcePlatform.other,
  type: OutputType.document,
  fileUri: 'content://media/external/downloads/1',
  sourceUrl: '',
  savedAt: DateTime(2026),
);

Future<void> _pump(
  WidgetTester tester,
  _FakePdfRepository repository,
  PdfTool tool,
) async {
  tester.view.physicalSize = const Size(360, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        pdfRepositoryProvider.overrideWithValue(repository),
        settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PdfToolSheet(tool: tool, items: [_pdf]),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('pages are checked as they are typed, then sent', (tester) async {
    final repository = _FakePdfRepository(5);
    await _pump(tester, repository, PdfTool.extract);
    expect(find.text('5 pages · 1 KB'), findsOneWidget);
    final make = find.widgetWithText(FilledButton, 'Make it');
    expect(tester.widget<FilledButton>(make).onPressed, isNull);

    await tester.enterText(find.byType(TextField), '9');
    await tester.pump();
    expect(find.textContaining('from 1 to 5'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '3, 2');
    await tester.pump();
    await tester.tap(make);
    await tester.pumpAndSettle();

    expect(repository.runs.single.$2.pages, [2, 3]);
    expect(find.text('Ready to share'), findsOneWidget);
  });

  testWidgets('deleting every page is refused', (tester) async {
    await _pump(tester, _FakePdfRepository(2), PdfTool.delete);
    await tester.enterText(find.byType(TextField), '1-2');
    await tester.pump();
    expect(find.text('That would leave no pages.'), findsOneWidget);
  });

  testWidgets('a locked PDF asks for its password first', (tester) async {
    final repository = _FakePdfRepository(null);
    await _pump(tester, repository, PdfTool.unlock);
    expect(find.textContaining('This PDF is locked'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'secret');
    await tester.tap(find.widgetWithText(FilledButton, 'Open'));
    await tester.pumpAndSettle();
    expect(find.text('4 pages · 1 KB'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Make it'));
    await tester.pumpAndSettle();
    expect(repository.runs.single.$2.password, 'secret');
    expect(repository.runs.single.$1, PdfTool.unlock);
  });

  testWidgets('page numbers need no text and go on every page', (tester) async {
    final repository = _FakePdfRepository(3);
    await _pump(tester, repository, PdfTool.addText);
    await tester.tap(find.text('Numbers'));
    await tester.pump();
    await tester.tap(find.text('1 / 9'));
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Make it'));
    await tester.tap(find.widgetWithText(FilledButton, 'Make it'));
    await tester.pumpAndSettle();
    final options = repository.runs.single.$2;
    expect(options.text, '{n} / {total}');
    expect(options.pages, isNull);
    expect(options.diagonal, isFalse);
  });
}
