import 'package:media_downloader/core/media/source_platform.dart';

/// What the Library shows about a download besides the file itself.
final class DownloadDetails {
  const new({
    required this.platform,
    this.thumbnail,
    this.ext,
    this.quality,
    this.sizeBytes,
  });

  final SourcePlatform platform;
  final String? thumbnail;
  final String? ext;
  final int? quality;

  /// Estimate; replaced by the real size once saved.
  final int? sizeBytes;
}
