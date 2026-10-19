import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/settings/domain/app_settings.dart';

/// Stored user choices.
abstract interface class SettingsRepository {
  /// The saved settings; defaults for anything never set or unreadable.
  Future<AppSettings> load();

  Future<Result<void>> save(AppSettings settings);
}
