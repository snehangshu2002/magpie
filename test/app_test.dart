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
import 'package:media_downloader/features/settings/domain/app_settings.dart';
import 'package:media_downloader/features/settings/domain/engine_repository.dart';

import 'helpers/fake_library_repository.dart';
import 'helpers/fake_settings_repository.dart';

class _FakeEngineRepository implements EngineRepository {
  new([this.updateResult = _updated]);

  static const Result<EngineUpdateResult> _updated = Ok(
    EngineUpdateResult(status: EngineUpdateStatus.done, version: '2026.02.02'),
  );

  Result<EngineUpdateResult> updateResult;
  final updates = <EngineReleaseChannel>[];

  @override
  Future<Result<String?>> initialize() async => const Ok('2026.01.01');

  @override
  Future<Result<EngineUpdateResult>> update(
    EngineReleaseChannel channel,
  ) async {
    updates.add(channel);
    return updateResult;
  }
}

void main() {
  Future<void> pumpApp(
    WidgetTester tester, {
    EngineRepository? engine,
    FakeSettingsRepository? settings,
  }) => tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        engineRepositoryProvider.overrideWithValue(
          engine ?? _FakeEngineRepository(),
        ),
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

  Future<void> tapSetting(WidgetTester tester, String title) async {
    await tester.ensureVisible(find.text(title));
    await tester.pumpAndSettle();
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  testWidgets('updates yt-dlp at launch', (tester) async {
    final engine = _FakeEngineRepository();
    await pumpApp(tester, engine: engine);
    await tester.pumpAndSettle();

    expect(engine.updates, [EngineReleaseChannel.stable]);
  });

  testWidgets('settings says updates are automatic, in plain words', (
    tester,
  ) async {
    await pumpApp(tester);
    await openSettings(tester);
    await tester.scrollUntilVisible(find.text('Automatic updates'), 200);

    expect(find.text('Automatic updates'), findsOneWidget);
    expect(
      find.text('Up to date. Keeps downloads working as sites change'),
      findsOneWidget,
    );
    expect(find.textContaining('yt-dlp'), findsNothing);
    expect(find.textContaining('Nightly'), findsNothing);
  });

  testWidgets('a failed update offers to try again', (tester) async {
    final engine = _FakeEngineRepository(const Err(Failure.network()));
    await pumpApp(tester, engine: engine);
    await openSettings(tester);
    await tester.scrollUntilVisible(find.text('Automatic updates'), 200);

    expect(find.text("Couldn't update. Check your connection"), findsOneWidget);

    engine.updateResult = _FakeEngineRepository._updated;
    await tapSetting(tester, 'Retry');

    expect(
      find.text('Up to date. Keeps downloads working as sites change'),
      findsOneWidget,
    );
    expect(engine.updates, hasLength(2));
  });

  testWidgets('theme is picked from a sheet and applied', (tester) async {
    final settings = FakeSettingsRepository();
    await pumpApp(tester, settings: settings);
    await openSettings(tester);

    expect(find.text('Same as phone'), findsOneWidget);
    await tapSetting(tester, 'Theme');
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(settings.settings.appearance, AppearanceMode.dark);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
  });

  testWidgets('font is picked from a sheet and applied', (tester) async {
    final settings = FakeSettingsRepository();
    await pumpApp(tester, settings: settings);
    await openSettings(tester);

    await tapSetting(tester, 'Font');
    await tester.tap(find.text('Classic'));
    await tester.pumpAndSettle();

    expect(settings.settings.font, AppFont.serif);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme?.textTheme.bodyMedium?.fontFamily, 'SourceSerif4');
  });

  testWidgets('a folder inside Download becomes the save location', (
    tester,
  ) async {
    final settings = FakeSettingsRepository()
      ..pickedFolder = const Ok('primary:Download/Clips');
    await pumpApp(tester, settings: settings);
    await openSettings(tester);

    await tapSetting(tester, 'Save location');

    expect(settings.settings.saveFolder, 'Download/Clips');
    expect(
      find.text('Download/Clips · each site gets its own folder'),
      findsOneWidget,
    );
  });

  testWidgets('a folder outside Download is refused', (tester) async {
    final settings = FakeSettingsRepository()
      ..pickedFolder = const Ok('primary:DCIM/Camera');
    await pumpApp(tester, settings: settings);
    await openSettings(tester);

    await tapSetting(tester, 'Save location');

    expect(settings.settings.saveFolder, 'Download/Magpie');
    expect(
      find.text('Choose a folder inside Download on this phone'),
      findsOneWidget,
    );
  });

  testWidgets('default quality is picked from a sheet and kept', (
    tester,
  ) async {
    final settings = FakeSettingsRepository();
    await pumpApp(tester, settings: settings);
    await openSettings(tester);

    await tapSetting(tester, 'Default video quality');
    await tester.tap(find.text('720p'));
    await tester.pumpAndSettle();

    expect(find.text('720p'), findsOneWidget);
    expect(settings.settings.maxQuality, 720);
  });
}
