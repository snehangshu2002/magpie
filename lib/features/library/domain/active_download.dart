import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/core/platform/models/download_progress.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';

/// A download that is queued or running, with its latest progress.
final class ActiveDownload {
  const new({
    required this.id,
    required this.title,
    required this.platform,
    required this.type,
    required this.progress,
    this.thumbnailUrl,
    this.sizeBytes,
  });

  final String id;
  final String title;
  final SourcePlatform platform;
  final OutputType type;
  final DownloadProgress progress;
  final String? thumbnailUrl;

  /// Estimated total bytes; null when unknown.
  final int? sizeBytes;
}
