import 'package:media_downloader/core/utils/result.dart';

/// The yt-dlp download engine, as the settings feature sees it.
abstract interface class EngineRepository {
  /// Prepares the engine if needed and returns the yt-dlp version.
  Future<Result<String>> initialize();
}
