import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/core/platform/engine_channel.dart';
import 'package:media_downloader/core/platform/storage_channel.dart';
import 'package:media_downloader/features/settings/data/settings_repository_impl.dart';
import 'package:media_downloader/features/settings/domain/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  SettingsRepositoryImpl repository() => SettingsRepositoryImpl(
    SharedPreferencesAsync(),
    StorageChannel(),
    EngineChannel(),
  );

  test('every setting survives a save and a reload', () async {
    // Every field away from its default, so one that isn't stored resets.
    const changed = AppSettings(
      maxQuality: 720,
      preferAudioForMusic: false,
      appearance: AppearanceMode.dark,
      font: AppFont.serif,
      themeColor: ThemeColor.clay,
      saveFolder: 'Download/Clips',
      audioFolder: 'Download/Music',
      wallpaperColors: true,
      pureBlack: true,
      downloadRightAway: true,
      askOnMobileData: true,
      skipDownloaded: true,
      keepHistory: false,
      audioFormat: AudioFormat.opus,
      embedThumbnail: true,
      squareCover: true,
      embedMetadata: true,
      subtitles: true,
      subtitleLanguage: 'de',
      autoCaptions: true,
      skipSponsors: true,
      saveAsMkv: true,
      speedLimitKiB: 512,
      parallelPieces: true,
      proxy: 'http://127.0.0.1:8080',
      forceIpv4: true,
      userAgent: 'Test Browser',
      fileNameTemplate: '%(id)s',
      simpleFileNames: true,
      extraOptions: '--no-mtime',
    );

    await repository().save(changed);
    final s = await repository().load();

    expect(
      [
        s.maxQuality, s.preferAudioForMusic, s.appearance, s.font, //
        s.themeColor, s.saveFolder, s.audioFolder, s.wallpaperColors,
        s.pureBlack, s.downloadRightAway, s.askOnMobileData,
        s.skipDownloaded, s.keepHistory, s.audioFormat, s.embedThumbnail,
        s.squareCover, s.embedMetadata, s.subtitles, s.subtitleLanguage,
        s.autoCaptions, s.skipSponsors, s.saveAsMkv, s.speedLimitKiB,
        s.parallelPieces, s.proxy, s.forceIpv4, s.userAgent,
        s.fileNameTemplate, s.simpleFileNames, s.extraOptions,
      ],
      [
        720, false, AppearanceMode.dark, AppFont.serif, //
        ThemeColor.clay, 'Download/Clips', 'Download/Music', true,
        true, true, true,
        true, false, AudioFormat.opus, true,
        true, true, true, 'de',
        true, true, true, 512,
        true, 'http://127.0.0.1:8080', true, 'Test Browser',
        '%(id)s', true, '--no-mtime',
      ],
    );
  });

  test('nothing saved yet loads the defaults', () async {
    final s = await repository().load();

    expect(s.themeColor, ThemeColor.sage);
    expect(s.keepHistory, isTrue);
    expect(s.saveFolder, const AppSettings().saveFolder);
  });
}
