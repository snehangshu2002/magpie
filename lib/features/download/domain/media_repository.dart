import 'package:media_downloader/core/platform/models/download_progress.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/core/platform/models/media_info.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/download/domain/download_details.dart';

/// Looks up media behind a link and hands downloads to the engine.
abstract interface class MediaRepository {
  Future<Result<MediaInfo>> fetchInfo(Uri url);

  /// Queues a download and adds it to the history; returns its id.
  Future<Result<String>> startDownload(
    DownloadRequest request,
    DownloadDetails details,
  );

  /// Progress events of the download with [id]; the last one is `saved`,
  /// `failed` or `cancelled`.
  Stream<DownloadProgress> progressOf(String id);

  /// Returns false when the download had already finished.
  Future<Result<bool>> cancelDownload(String id);
}
