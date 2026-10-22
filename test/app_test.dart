import 'dart:async';

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
import 'package:media_downloader/features/settings/presentation/settings_screen.dart';
import 'package:media_downloader/features/updater/data/update_repository_impl.dart';
import 'package:media_downloader/features/updater/domain/app_update.dart';

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

class _FakeUpdateRepository implements UpdateRepository {
  new([this.update]);

  final AppUpdate? update;
  final opened = <String>[];

  int checks = 0;

  @override
  Future<Result<AppUpdate?>> check() async {
    checks++;
    return Ok(update);
  }

  @override
  Future<Result<String>> installedVersion() async => const Ok('1.1.0');

  @override
  Future<Result<void>> open(String url) async {
    opened.add(url);
    return const Ok(null);
  }

  final installed = <String>[];

  /// Completes the download started by the update sheet.
  final Completer<void> downloadDone = Completer();

  @override
  Future<Result<String>> download(
    AppUpdate update, {
    required void Function(int received, int? total) onProgress,
    required bool Function() isCancelled,
  }) async {
    onProgress(8000000, update.size);
    await downloadDone.future;
    if (isCancelled()) return const Err(Failure.cancelled());
    return const Ok('/cache/updates/magpie.apk');
  }

  @override
  Future<Result<void>> install(String path, AppUpdate update) async {
    installed.add(path);
    return const Ok(null);
  }
}

void main() {
  Future<void> pumpApp(
    WidgetTester tester, {
    EngineRepository? engine,
    FakeSettingsRepository? settings,
    UpdateRepository? updates,
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
        updateRepositoryProvider.overrideWithValue(
          updates ?? _FakeUpdateRepository(),
        ),
      ],
      child: const App(),
    ),
  );

  Future<void> openSettings(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
  }

  // The sections sit in a PageView, so name the list to scroll.
  final settingsList = find
      .descendant(
        of: find.byType(SettingsScreen),
        matching: find.byType(Scrollable),
      )
      .first;

  Future<void> tapSetting(WidgetTester tester, String title) async {
    // Rows below the screen aren't built until scrolled to.
    await tester.scrollUntilVisible(
      find.text(title),
      200,
      scrollable: settingsList,
    );
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

  testWidgets('a newer release is offered for download', (tester) async {
    final update = AppUpdate(
      version: '1.2.0',
      url: 'https://example.com/a.apk',
      pageUrl: 'https://example.com/release',
      size: 32000000,
      apkName: 'magpie-1.2.0-arm64-v8a.apk',
      notes: const ['Faster downloads'],
      published: DateTime(2026, 10, 15),
    );
    final updates = _FakeUpdateRepository(update);
    await pumpApp(tester, updates: updates);
    await tester.pumpAndSettle();

    expect(find.text('Magpie 1.2.0 is available'), findsOneWidget);
    expect(find.text('32 MB · Release notes'), findsOneWidget);
    expect(find.text('Oct 2026'), findsOneWidget);
    expect(find.text('Faster downloads'), findsOneWidget);
    await tester.tap(find.text('Update (32 MB)'));
    await tester.pump();

    // Downloads inside the app, with progress; no browser.
    expect(find.text('Downloading… 25%'), findsOneWidget);
    expect(find.text('8 MB of 32 MB'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(updates.opened, isEmpty);

    updates.downloadDone.complete();
    await tester.pumpAndSettle();

    expect(updates.installed, ['/cache/updates/magpie.apk']);
    expect(
      find.text("Finish the update in Android's installer."),
      findsOneWidget,
    );
    await tester.tap(find.text('Install'));
    await tester.pumpAndSettle();
    expect(updates.installed, hasLength(2));
  });

  testWidgets('without an APK for this phone, the release page opens', (
    tester,
  ) async {
    const update = AppUpdate(
      version: '1.2.0',
      url: 'https://example.com/release',
      pageUrl: 'https://example.com/release',
    );
    final updates = _FakeUpdateRepository(update);
    await pumpApp(tester, updates: updates);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();

    expect(updates.opened, ['https://example.com/release']);
    expect(find.text('Magpie 1.2.0 is available'), findsNothing);
  });

  testWidgets('swiping left and right moves between sections', (tester) async {
    await pumpApp(tester);
    await tester.pumpAndSettle();
    NavigationBar nav() => tester.widget(find.byType(NavigationBar));
    expect(nav().selectedIndex, 0);

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();
    expect(nav().selectedIndex, 1);

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();
    expect(nav().selectedIndex, 2);
    expect(find.byTooltip('Source code on GitHub'), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(400, 0), 1000);
    await tester.pumpAndSettle();
    expect(nav().selectedIndex, 1);
  });

  testWidgets('settings has a GitHub button at the top', (tester) async {
    final updates = _FakeUpdateRepository();
    await pumpApp(tester, updates: updates);
    await openSettings(tester);

    await tester.tap(find.byTooltip('Source code on GitHub'));
    await tester.pumpAndSettle();

    expect(updates.opened, ['https://github.com/snehangshu2002/magpie']);
  });

  testWidgets('settings says Magpie is up to date and can check again', (
    tester,
  ) async {
    final updates = _FakeUpdateRepository();
    await pumpApp(tester, updates: updates);
    await openSettings(tester);
    // Past the row, so it isn't under the navigation bar.
    await tester.scrollUntilVisible(
      find.text('Your privacy'),
      200,
      scrollable: settingsList,
    );

    expect(find.text('You have the latest version (1.1.0)'), findsOneWidget);
    expect(updates.checks, 1);
    await tester.tap(find.text('Check'));
    await tester.pumpAndSettle();
    expect(updates.checks, 2);
  });

  testWidgets('after Later, settings offers the update again', (tester) async {
    const update = AppUpdate(
      version: '1.2.0',
      url: 'https://example.com/a.apk',
      pageUrl: 'https://example.com/release',
      size: 32000000,
      apkName: 'magpie-1.2.0-arm64-v8a.apk',
    );
    await pumpApp(tester, updates: _FakeUpdateRepository(update));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.text('Magpie 1.2.0 is available'), findsNothing);

    await openSettings(tester);
    // Past the row, so it isn't under the navigation bar.
    await tester.scrollUntilVisible(
      find.text('Your privacy'),
      200,
      scrollable: settingsList,
    );
    expect(find.text('Magpie 1.2.0 is ready to install'), findsOneWidget);
    await tester.tap(find.text('Update now'));
    await tester.pumpAndSettle();

    expect(find.text('Magpie 1.2.0 is available'), findsOneWidget);
    expect(find.text('Update (32 MB)'), findsOneWidget);
  });

  testWidgets('settings says what stays on the phone', (tester) async {
    await pumpApp(tester);
    await openSettings(tester);
    await tester.scrollUntilVisible(
      find.text('Your privacy'),
      200,
      scrollable: settingsList,
    );

    expect(
      find.textContaining('stay on this phone. No account, no ads'),
      findsOneWidget,
    );
  });

  testWidgets('settings shows the version and links to the developer', (
    tester,
  ) async {
    final updates = _FakeUpdateRepository();
    await pumpApp(tester, updates: updates);
    await openSettings(tester);
    await tester.scrollUntilVisible(
      find.text('Developer'),
      200,
      scrollable: settingsList,
    );

    expect(find.text('1.1.0'), findsOneWidget);
    await tapSetting(tester, 'Developer');

    expect(updates.opened, ['https://github.com/snehangshu2002']);
  });

  testWidgets('a release without notes only offers the update', (tester) async {
    const update = AppUpdate(
      version: '1.2.0',
      url: 'https://example.com/a.apk',
      pageUrl: 'https://example.com/release',
      size: 32000000,
    );
    await pumpApp(tester, updates: _FakeUpdateRepository(update));
    await tester.pumpAndSettle();

    expect(find.text('Magpie 1.2.0 is available'), findsOneWidget);
    expect(find.text('32 MB'), findsOneWidget);
    expect(find.textContaining('Release notes'), findsNothing);
    expect(find.text("What's new".toUpperCase()), findsNothing);
    expect(find.text('Update (32 MB)'), findsOneWidget);
  });

  testWidgets('settings says updates are automatic, in plain words', (
    tester,
  ) async {
    await pumpApp(tester);
    await openSettings(tester);
    await tester.scrollUntilVisible(
      find.text('Automatic updates'),
      200,
      scrollable: settingsList,
    );

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
    await tester.scrollUntilVisible(
      find.text('Automatic updates'),
      200,
      scrollable: settingsList,
    );

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

    expect(find.text('Same as phone'), findsNWidgets(2));
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
    expect(find.text('Best available'), findsOneWidget);
    // The sheet scrolls on small screens.
    await tester.ensureVisible(find.text('720p'));
    await tester.tap(find.text('720p'));
    await tester.pumpAndSettle();

    expect(find.text('720p'), findsOneWidget);
    expect(settings.settings.maxQuality, 720);
  });
}
