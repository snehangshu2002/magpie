import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';

part 'download_option.freezed.dart';

/// One thing the user can save, e.g. "1080p MP4" or "M4A audio".
@freezed
abstract class DownloadOption with _$DownloadOption {
  const factory({
    required OutputType type,

    /// yt-dlp `-f` selector: a single format id, or `video+audio` to merge.
    required String formatSelector,

    /// Container of the saved file; null when the engine decides.
    String? ext,

    /// Short side in pixels, so a vertical 1080×1920 video is 1080.
    int? quality,
    int? fps,

    /// Estimated bytes; null when unknown.
    int? sizeBytes,
  }) = _DownloadOption;
}

/// Why [DownloadOptions.recommendedType] was picked; shown next to it.
enum RecommendationReason {
  bestUpToCap,
  closestToCap,
  musicSource,
  audioOnly,
  imageOnly,
}

/// Everything a link offers, grouped by output type, best first.
@freezed
abstract class DownloadOptions with _$DownloadOptions {
  const factory({
    required List<DownloadOption> video,
    required List<DownloadOption> audio,
    required List<DownloadOption> image,
    required OutputType recommendedType,
    required RecommendationReason reason,

    /// Highest video quality picked by default (short side in pixels).
    required int maxQuality,
  }) = _DownloadOptions;
}

extension DownloadOptionsX on DownloadOptions {
  List<DownloadOption> of(OutputType type) => switch (type) {
    OutputType.video => video,
    OutputType.audio => audio,
    OutputType.image => image,
  };

  /// Output types this media offers, in display order.
  List<OutputType> get types => [
    for (final type in OutputType.values)
      if (of(type).isNotEmpty) type,
  ];

  /// The option picked when the user switches to [type]: for video, the
  /// best quality up to [maxQuality] (or the closest above it); otherwise
  /// the best one.
  DownloadOption defaultFor(OutputType type) {
    if (type != OutputType.video) return of(type).first;
    return video.firstWhere(
      (o) => o.quality == null || o.quality! <= maxQuality,
      orElse: () => video.last,
    );
  }

  DownloadOption get recommended => defaultFor(recommendedType);
}
