import 'package:media_downloader/core/platform/models/engine_update_result.dart';
import 'package:media_downloader/core/utils/result.dart';

/// The yt-dlp download engine, as the settings feature sees it.
abstract interface class EngineRepository {
  /// Prepares the engine if needed and returns the yt-dlp version; null
  /// for the build bundled with the app, which has no recorded version.
  Future<Result<String?>> initialize();

  /// Updates yt-dlp from [channel].
  Future<Result<EngineUpdateResult>> update(EngineReleaseChannel channel);
}
