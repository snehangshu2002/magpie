import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/core/platform/models/media_info.dart';
import 'package:media_downloader/core/utils/result.dart';

/// Looks up media behind a link and hands downloads to the engine.
abstract interface class MediaRepository {
  Future<Result<MediaInfo>> fetchInfo(Uri url);

  /// Queues a download; returns its id.
  Future<Result<String>> startDownload(DownloadRequest request);
}
