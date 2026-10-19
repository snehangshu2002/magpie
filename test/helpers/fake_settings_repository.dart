import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/settings/domain/app_settings.dart';
import 'package:media_downloader/features/settings/domain/settings_repository.dart';

/// In-memory settings for widget tests.
class FakeSettingsRepository implements SettingsRepository {
  new([this.settings = const AppSettings()]);

  AppSettings settings;

  @override
  Future<AppSettings> load() async => settings;

  @override
  Future<Result<void>> save(AppSettings settings) async {
    this.settings = settings;
    return const Ok(null);
  }
}
