import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/core/platform/models/download_progress.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/core/platform/models/media_info.dart';
import 'package:media_downloader/core/platform/models/playlist_info.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/download/domain/download_details.dart';
import 'package:media_downloader/features/download/domain/web_photo.dart';

/// Looks up media behind a link and hands downloads to the engine.
/// `options` are yt-dlp arguments from Settings (`networkArgs`).
abstract interface class MediaRepository {
  Future<Result<MediaInfo>> fetchInfo(
    Uri url, {
    List<String> options = const [],
  });

  /// The videos of the playlist at [url].
  Future<Result<PlaylistInfo>> fetchPlaylist(
    Uri url, {
    List<String> options = const [],
  });

  /// Full-size photos of [url] that yt-dlp leaves out: those of a post on X,
  /// or the image itself when the link is one. Null when there
  /// are none.
  Future<Result<WebPhotos?>> fetchPhotos(
    Uri url,
    SourcePlatform platform, {
    List<String> options = const [],
  });

  /// The image at [url] in full size, when the link serves one; for links
  /// yt-dlp can't read.
  Future<Result<WebPhotos?>> fetchImage(
    Uri url, {
    List<String> options = const [],
  });

  /// The caption [track] of [url] as plain text (see `transcriptFromVtt`).
  Future<Result<String>> fetchTranscript(
    Uri url,
    CaptionTrack track, {
    List<String> options = const [],
  });

  /// Saves [text] as `<targetDir>/<name>.txt` in shared storage; returns
  /// its content URI.
  Future<Result<String>> saveText({
    required String name,
    required String text,
    required String targetDir,
  });

  /// Queues a download and, with [record], adds it to the history (the
  /// Library); returns its id.
  Future<Result<String>> startDownload(
    DownloadRequest request,
    DownloadDetails details, {
    bool record = true,
  });

  /// Whether the video with [videoKey] (`videoKeyOf`) is in the Library.
  Future<bool> isSaved(String videoKey);

  /// Whether the phone is on mobile data (a metered network); false when it
  /// can't tell.
  Future<bool> isNetworkMetered();

  /// Progress events of the download with [id]; the last one is `saved`,
  /// `failed` or `cancelled`.
  Stream<DownloadProgress> progressOf(String id);

  /// Returns false when the download had already finished.
  Future<Result<bool>> cancelDownload(String id);
}
