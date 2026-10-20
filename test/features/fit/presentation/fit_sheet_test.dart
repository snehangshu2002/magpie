import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/core/platform/models/download_progress.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/core/platform/models/video_probe.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/fit/data/fit_repository_impl.dart';
import 'package:media_downloader/features/fit/domain/fit_plan.dart';
import 'package:media_downloader/features/fit/domain/fit_repository.dart';
import 'package:media_downloader/features/library/data/library_repository_impl.dart';
import 'package:media_downloader/features/library/domain/library_item.dart';
import 'package:media_downloader/features/library/presentation/library_screen.dart';
import 'package:media_downloader/features/settings/data/settings_repository_impl.dart';
import 'package:media_downloader/l10n/l10n.dart';

import '../../../helpers/fake_library_repository.dart';
import '../../../helpers/fake_settings_repository.dart';

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
  sizeBytes: 80000000,
);

class _FakeFitRepository implements FitRepository {
  new(this.probeResult);

  VideoProbe probeResult;
  final progress = StreamController<DownloadProgress>.broadcast();
  final started = <({ShareSize size, FitEncode plan, String name})>[];

  @override
  Future<Result<VideoProbe>> probe(String fileUri) async => Ok(probeResult);

  @override
  Future<Result<String>> start({
    required String id,
    required LibraryItem item,
    required ShareSize size,
    required FitEncode plan,
    required int durationMs,
    required String targetDir,
    required String name,
  }) async {
    started.add((size: size, plan: plan, name: name));
    return Ok(id);
  }

  @override
  Stream<DownloadProgress> progressOf(String id) => progress.stream;

  @override
  Future<Result<bool>> cancel(String id) async => const Ok(true);
}

/// Runs a few frames; an indeterminate progress bar never settles.
Future<void> pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  Future<void> openFitSheet(
    WidgetTester tester,
    _FakeFitRepository fit, [
    LibraryItem? item,
  ]) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          libraryRepositoryProvider.overrideWithValue(
            FakeLibraryRepository([item ?? _clip]),
          ),
          fitRepositoryProvider.overrideWithValue(fit),
          settingsRepositoryProvider.overrideWithValue(
            FakeSettingsRepository(),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LibraryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fit for sharing'));
    await tester.pumpAndSettle();
  }

  const minute = VideoProbe(
    durationMs: 60000,
    width: 1920,
    height: 1080,
    hasAudio: true,
  );

  testWidgets('photos have no Fit for sharing', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          libraryRepositoryProvider.overrideWithValue(
            FakeLibraryRepository([
              LibraryItem(
                id: 'd2',
                title: 'Test photo',
                platform: SourcePlatform.instagram,
                type: OutputType.image,
                fileUri: 'content://media/external/downloads/2',
                sourceUrl: 'https://example.com/p/test',
                savedAt: DateTime(2026, 10, 19),
              ),
            ]),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LibraryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();

    expect(find.text('Fit for sharing'), findsNothing);
  });

  testWidgets('shows what each size gives, then makes and follows a copy', (
    tester,
  ) async {
    final fit = _FakeFitRepository(minute);
    await openFitSheet(tester, fit);

    expect(find.text('Discord without Nitro · 480p, about 9.4 MB'), findsOne);
    expect(find.text('1080p, about 23 MB'), findsOne);

    await tester.tap(find.text('Make copy'));
    await pumpFrames(tester);
    expect(fit.started.single.size, ShareSize.mb10);
    expect(fit.started.single.name, 'Test clip (10 MB)');
    expect(find.text('Making a smaller copy…'), findsOne);

    fit.progress.add(
      const DownloadProgress(
        id: 'x',
        percent: 40,
        state: DownloadState.running,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('40%'), findsOne);

    fit.progress.add(
      const DownloadProgress(
        id: 'x',
        percent: 100,
        state: DownloadState.saved,
        filePath: 'content://media/external/downloads/3',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ready to share'), findsOne);
  });

  testWidgets('a failed copy says why and offers to try again', (tester) async {
    final fit = _FakeFitRepository(minute);
    await openFitSheet(tester, fit);
    await tester.tap(find.text('Make copy'));
    await pumpFrames(tester);

    fit.progress.add(
      const DownloadProgress(
        id: 'x',
        percent: 100,
        state: DownloadState.failed,
        error: 'TOO_LARGE',
      ),
    );
    await pumpFrames(tester);
    expect(
      find.text("Couldn't get this video under that size. Pick a bigger size."),
      findsOne,
    );

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Make copy'), findsOne);
  });

  testWidgets('a long video skips sizes it cannot fit', (tester) async {
    final fit = _FakeFitRepository(
      const VideoProbe(durationMs: 30 * 60000, hasAudio: true),
    );
    await openFitSheet(tester, fit);

    expect(
      find.text('Discord without Nitro · Too long for this size'),
      findsOne,
    );
    // Half an hour leaves too little bitrate below 50 MB.
    expect(find.text('Too long for this size'), findsNWidgets(2));
    expect(find.text('240p, about 47 MB'), findsOne);
    await tester.tap(find.text('Make copy'));
    await pumpFrames(tester);
    expect(fit.started.single.size, ShareSize.mb50);
  });

  testWidgets('a small video is shared as it is', (tester) async {
    final fit = _FakeFitRepository(minute);
    await openFitSheet(
      tester,
      fit,
      LibraryItem(
        id: 'd1',
        title: 'Test clip',
        platform: SourcePlatform.youtube,
        type: OutputType.video,
        fileUri: 'content://media/external/downloads/1',
        sourceUrl: 'https://example.com/watch/test',
        savedAt: DateTime(2026, 10, 19),
        sizeBytes: 4700000,
      ),
    );

    expect(find.text('Discord without Nitro · Already small enough'), findsOne);
    expect(find.text('Share as is'), findsOne);
  });
}
