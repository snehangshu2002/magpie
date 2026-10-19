import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';

/// A downloaded file in the Library.
final class LibraryItem {
  const new({
    required this.id,
    required this.title,
    required this.platform,
    required this.type,
    required this.fileUri,
    required this.sourceUrl,
    required this.savedAt,
    this.mimeType,
    this.ext,
    this.quality,
    this.sizeBytes,
    this.thumbnailUrl,
  });

  /// The download id.
  final String id;
  final String title;
  final SourcePlatform platform;
  final OutputType type;

  /// MediaStore content URI.
  final String fileUri;

  /// The link it was downloaded from.
  final String sourceUrl;
  final DateTime savedAt;
  final String? mimeType;
  final String? ext;

  /// Short side in pixels, for video.
  final int? quality;
  final int? sizeBytes;

  /// The thumbnail yt-dlp reported; used when the file has no preview.
  final String? thumbnailUrl;
}
