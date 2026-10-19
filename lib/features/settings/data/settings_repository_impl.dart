import 'package:flutter/services.dart';
import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/errors/platform_failure.dart';
import 'package:media_downloader/core/platform/storage_channel.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/download/domain/save_location.dart';
import 'package:media_downloader/features/settings/domain/app_settings.dart';
import 'package:media_downloader/features/settings/domain/settings_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'settings_repository_impl.g.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  new(this._prefs, this._storage);

  final SharedPreferencesAsync _prefs;
  final StorageChannel _storage;

  static const _maxQuality = 'maxQuality';
  static const _preferAudio = 'preferAudioForMusic';
  static const _appearance = 'appearance';
  static const _font = 'font';
  static const _saveFolder = 'saveFolder';

  @override
  Future<AppSettings> load() async {
    const defaults = AppSettings();
    try {
      final values = await _prefs.getAll(
        allowList: {_maxQuality, _preferAudio, _appearance, _font, _saveFolder},
      );
      return AppSettings(
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
        saveFolder: switch (values[_saveFolder]) {
          final String folder when isSaveFolder(folder) => folder,
          _ => defaults.saveFolder,
        },
      );
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
      await _prefs.setString(_saveFolder, settings.saveFolder);
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
}

@Riverpod(keepAlive: true)
SettingsRepository settingsRepository(Ref ref) => SettingsRepositoryImpl(
  SharedPreferencesAsync(),
  ref.watch(storageChannelProvider),
);
