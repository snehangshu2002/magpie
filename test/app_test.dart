import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/app.dart';
import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/platform/models/engine_update_result.dart';
import 'package:media_downloader/core/platform/share_channel.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/library/data/library_repository_impl.dart';
import 'package:media_downloader/features/settings/data/engine_repository_impl.dart';
import 'package:media_downloader/features/settings/data/settings_repository_impl.dart';
import 'package:media_downloader/features/settings/domain/engine_repository.dart';

import 'helpers/fake_library_repository.dart';
import 'helpers/fake_settings_repository.dart';

class _FakeEngineRepository implements EngineRepository {
  new(this.result);

  Result<String?> result;

  @override
  Future<Result<String?>> initialize() async => result;

  @override
  Future<Result<EngineUpdateResult>> update(
    EngineReleaseChannel channel,
  ) async => const Ok(
    EngineUpdateResult(status: EngineUpdateStatus.done, version: '2026.02.02'),
  );
}

void main() {
  Future<void> pumpApp(
    WidgetTester tester,
    EngineRepository repository, {
    FakeSettingsRepository? settings,
  }) => tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        engineRepositoryProvider.overrideWithValue(repository),
        sharedTextProvider.overrideWith((ref) => const Stream.empty()),
        settingsRepositoryProvider.overrideWithValue(
          settings ?? FakeSettingsRepository(),
        ),
        libraryRepositoryProvider.overrideWithValue(FakeLibraryRepository()),
      ],
      child: const App(),
    ),
  );

  Future<void> openSettings(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
  }

  testWidgets('settings shows the yt-dlp version', (tester) async {
    await pumpApp(tester, _FakeEngineRepository(const Ok('2026.01.01')));
    await openSettings(tester);

    expect(find.text('yt-dlp version'), findsOneWidget);
    expect(find.text('2026.01.01'), findsOneWidget);
  });

  testWidgets('settings names the bundled build and offers an update', (
    tester,
  ) async {
    await pumpApp(tester, _FakeEngineRepository(const Ok(null)));
    await openSettings(tester);

    expect(find.text('Bundled version'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);
  });

  testWidgets('settings shows a failure and retries on tap', (tester) async {
    final repository = _FakeEngineRepository(const Err(Failure.network()));
    await pumpApp(tester, repository);
    await openSettings(tester);

    expect(
      find.text('Network error. Check your connection and try again.'),
      findsOneWidget,
    );

    repository.result = const Ok('2026.01.01');
    await tester.ensureVisible(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();

    expect(find.text('2026.01.01'), findsOneWidget);
  });

  testWidgets('updating yt-dlp reports the new version', (tester) async {
    await pumpApp(tester, _FakeEngineRepository(const Ok('2026.01.01')));
    await openSettings(tester);

    await tester.ensureVisible(find.text('Update'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();

    expect(find.text('yt-dlp updated to 2026.02.02'), findsOneWidget);
  });

  testWidgets('default quality is picked from a sheet and kept', (
    tester,
  ) async {
    final settings = FakeSettingsRepository();
    await pumpApp(
      tester,
      _FakeEngineRepository(const Ok('2026.01.01')),
      settings: settings,
    );
    await openSettings(tester);

    await tester.tap(find.text('Default video quality'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('720p'));
    await tester.pumpAndSettle();

    expect(find.text('720p'), findsOneWidget);
    expect(settings.settings.maxQuality, 720);
  });
}
