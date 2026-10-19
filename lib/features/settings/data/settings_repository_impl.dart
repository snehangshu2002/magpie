import 'package:flutter/services.dart';
import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/platform/models/engine_update_result.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/settings/domain/app_settings.dart';
import 'package:media_downloader/features/settings/domain/settings_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'settings_repository_impl.g.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  new(this._prefs);

  final SharedPreferencesAsync _prefs;

  static const _maxQuality = 'maxQuality';
  static const _preferAudio = 'preferAudioForMusic';
  static const _engineChannel = 'engineChannel';

  @override
  Future<AppSettings> load() async {
    const defaults = AppSettings();
    try {
      final values = await _prefs.getAll(
        allowList: {_maxQuality, _preferAudio, _engineChannel},
      );
      return AppSettings(
        maxQuality: switch (values[_maxQuality]) {
          final int q when AppSettings.qualities.contains(q) => q,
          _ => defaults.maxQuality,
        },
        preferAudioForMusic:
            values[_preferAudio] as bool? ?? defaults.preferAudioForMusic,
        engineChannel:
            EngineReleaseChannel.values.asNameMap()[values[_engineChannel]] ??
            defaults.engineChannel,
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
      await _prefs.setString(_engineChannel, settings.engineChannel.name);
      return const Ok(null);
    } on PlatformException catch (e) {
      return Err(Failure.storage(detail: e.message));
    } on MissingPluginException catch (e) {
      return Err(Failure.unavailable(detail: e.message));
    }
  }
}

@Riverpod(keepAlive: true)
SettingsRepository settingsRepository(Ref ref) =>
    SettingsRepositoryImpl(SharedPreferencesAsync());
