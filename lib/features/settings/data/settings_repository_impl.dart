import 'package:flutter/services.dart';
import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/errors/platform_failure.dart';
import 'package:media_downloader/core/platform/engine_channel.dart';
import 'package:media_downloader/core/platform/storage_channel.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/download/domain/save_location.dart';
import 'package:media_downloader/features/settings/domain/app_settings.dart';
import 'package:media_downloader/features/settings/domain/settings_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'settings_repository_impl.g.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  new(this._prefs, this._storage, this._engine);

  final SharedPreferencesAsync _prefs;
  final StorageChannel _storage;
  final EngineChannel _engine;

  static const _maxQuality = 'maxQuality';
  static const _preferAudio = 'preferAudioForMusic';
  static const _appearance = 'appearance';
  static const _font = 'font';
  static const _themeColor = 'themeColor';
  static const _saveFolder = 'saveFolder';
  static const _audioFolder = 'audioFolder';
  static const _audioFormat = 'audioFormat';
  static const _subtitleLanguage = 'subtitleLanguage';
  static const _speedLimit = 'speedLimitKiB';

  /// Free text settings, by key.
  static final _texts =
      <
        String,
        (
          String Function(AppSettings),
          AppSettings Function(AppSettings, String),
        )
      >{
        'proxy': ((s) => s.proxy, (s, v) => s.copyWith(proxy: v)),
        'userAgent': ((s) => s.userAgent, (s, v) => s.copyWith(userAgent: v)),
        'fileNameTemplate': (
          (s) => s.fileNameTemplate,
          (s, v) => s.copyWith(fileNameTemplate: v),
        ),
        'extraOptions': (
          (s) => s.extraOptions,
          (s, v) => s.copyWith(extraOptions: v),
        ),
      };

  /// On/off settings, by key: how to read one, and to set it.
  static final _switches =
      <
        String,
        (
          bool Function(AppSettings),
          // The setters take the stored value as it comes.
          // ignore: avoid_positional_boolean_parameters
          AppSettings Function(AppSettings, bool),
        )
      >{
        'wallpaperColors': (
          (s) => s.wallpaperColors,
          (s, v) => s.copyWith(wallpaperColors: v),
        ),
        'pureBlack': ((s) => s.pureBlack, (s, v) => s.copyWith(pureBlack: v)),
        'downloadRightAway': (
          (s) => s.downloadRightAway,
          (s, v) => s.copyWith(downloadRightAway: v),
        ),
        'askOnMobileData': (
          (s) => s.askOnMobileData,
          (s, v) => s.copyWith(askOnMobileData: v),
        ),
        'skipDownloaded': (
          (s) => s.skipDownloaded,
          (s, v) => s.copyWith(skipDownloaded: v),
        ),
        'keepHistory': (
          (s) => s.keepHistory,
          (s, v) => s.copyWith(keepHistory: v),
        ),
        'embedThumbnail': (
          (s) => s.embedThumbnail,
          (s, v) => s.copyWith(embedThumbnail: v),
        ),
        'squareCover': (
          (s) => s.squareCover,
          (s, v) => s.copyWith(squareCover: v),
        ),
        'embedMetadata': (
          (s) => s.embedMetadata,
          (s, v) => s.copyWith(embedMetadata: v),
        ),
        'subtitles': ((s) => s.subtitles, (s, v) => s.copyWith(subtitles: v)),
        'autoCaptions': (
          (s) => s.autoCaptions,
          (s, v) => s.copyWith(autoCaptions: v),
        ),
        'skipSponsors': (
          (s) => s.skipSponsors,
          (s, v) => s.copyWith(skipSponsors: v),
        ),
        'saveAsMkv': ((s) => s.saveAsMkv, (s, v) => s.copyWith(saveAsMkv: v)),
        'parallelPieces': (
          (s) => s.parallelPieces,
          (s, v) => s.copyWith(parallelPieces: v),
        ),
        'forceIpv4': ((s) => s.forceIpv4, (s, v) => s.copyWith(forceIpv4: v)),
        'simpleFileNames': (
          (s) => s.simpleFileNames,
          (s, v) => s.copyWith(simpleFileNames: v),
        ),
      };

  @override
  Future<AppSettings> load() async {
    const defaults = AppSettings();
    try {
      final values = await _prefs.getAll(
        allowList: {
          _maxQuality,
          _preferAudio,
          _appearance,
          _font,
          _themeColor,
          _saveFolder,
          _audioFolder,
          _audioFormat,
          _subtitleLanguage,
          _speedLimit,
          ..._texts.keys,
          ..._switches.keys,
        },
      );
      var settings = AppSettings(
        maxQuality: switch (values[_maxQuality]) {
          final int q when AppSettings.qualities.contains(q) => q,
          _ => defaults.maxQuality,
        },
        preferAudioForMusic:
            values[_preferAudio] as bool? ?? defaults.preferAudioForMusic,
        appearance:
            AppearanceMode.values.asNameMap()[values[_appearance]] ??
            defaults.appearance,
        font: AppFont.values.asNameMap()[values[_font]] ?? defaults.font,
        themeColor:
            ThemeColor.values.asNameMap()[values[_themeColor]] ??
            defaults.themeColor,
        saveFolder: switch (values[_saveFolder]) {
          final String folder when isSaveFolder(folder) => folder,
          _ => defaults.saveFolder,
        },
        audioFolder: switch (values[_audioFolder]) {
          final String folder when isSaveFolder(folder) => folder,
          _ => defaults.audioFolder,
        },
        audioFormat:
            AudioFormat.values.asNameMap()[values[_audioFormat]] ??
            defaults.audioFormat,
        subtitleLanguage: switch (values[_subtitleLanguage]) {
          final String lang when AppSettings.subtitleLanguages.contains(lang) =>
            lang,
          _ => defaults.subtitleLanguage,
        },
        speedLimitKiB: switch (values[_speedLimit]) {
          final int kib when AppSettings.speedLimits.contains(kib) => kib,
          _ => defaults.speedLimitKiB,
        },
      );
      for (final MapEntry(:key, value: (_, set)) in _texts.entries) {
        if (values[key] case final String text) settings = set(settings, text);
      }
      for (final MapEntry(:key, value: (_, set)) in _switches.entries) {
        if (values[key] case final bool on) settings = set(settings, on);
      }
      return settings;
      // Unreadable storage shouldn't stop downloads; fall back to defaults.
    } on PlatformException {
      return defaults;
    } on MissingPluginException {
      return defaults;
    }
  }

  @override
  Future<Result<void>> save(AppSettings settings) async {
    try {
      await _prefs.setInt(_maxQuality, settings.maxQuality);
      await _prefs.setBool(_preferAudio, settings.preferAudioForMusic);
      await _prefs.setString(_appearance, settings.appearance.name);
      await _prefs.setString(_font, settings.font.name);
      await _prefs.setString(_themeColor, settings.themeColor.name);
      await _prefs.setString(_saveFolder, settings.saveFolder);
      await _prefs.setString(_audioFolder, settings.audioFolder);
      await _prefs.setString(_audioFormat, settings.audioFormat.name);
      await _prefs.setString(_subtitleLanguage, settings.subtitleLanguage);
      await _prefs.setInt(_speedLimit, settings.speedLimitKiB);
      for (final MapEntry(:key, value: (get, _)) in _texts.entries) {
        await _prefs.setString(key, get(settings));
      }
      for (final MapEntry(:key, value: (get, _)) in _switches.entries) {
        await _prefs.setBool(key, get(settings));
      }
      return const Ok(null);
    } on PlatformException catch (e) {
      return Err(Failure.storage(detail: e.message));
    } on MissingPluginException catch (e) {
      return Err(Failure.unavailable(detail: e.message));
    }
  }

  @override
  Future<Result<String?>> pickFolder() =>
      guardPlatformCall(_storage.pickFolder);

  @override
  Future<Result<List<String>>> signedInSites() =>
      guardPlatformCall(_engine.signedInSites);

  @override
  Future<Result<List<String>>> signIn(String url) =>
      guardPlatformCall(() => _engine.signIn(url));

  @override
  Future<Result<List<String>>> signOut(String site) =>
      guardPlatformCall(() => _engine.signOut(site));
}

@Riverpod(keepAlive: true)
SettingsRepository settingsRepository(Ref ref) => SettingsRepositoryImpl(
  SharedPreferencesAsync(),
  ref.watch(storageChannelProvider),
  ref.watch(engineChannelProvider),
);
