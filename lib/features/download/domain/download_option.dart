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

    /// [sizeBytes] leaves out a stream whose size is unknown.
    @Default(false) bool sizeApproximate,

    /// Files saved: more than one for a whole post.
    @Default(1) int count,

    /// 1-based item of a post to save alone; null saves the whole post.
    int? item,
  }) = _DownloadOption;
}

/// One item of a post with several, as the user sees it in the picker.
/// `index` is the item's 1-based place in the post, which the engine uses.
typedef PostItem = ({
  int index,
  OutputType type,
  String? thumbnail,
  int? duration,
});

/// `startDownload` selector that saves every item of the link: videos in
/// the best quality, photos as they are.
const postSelector = 'post';

/// Why [DownloadOptions.recommendedType] was picked; shown next to it.
enum RecommendationReason {
  bestUpToCap,
  closestToCap,
  musicSource,
  audioOnly,
  imageOnly,
  wholePost,
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

    /// The items of a post with several, in order, so one can be saved
    /// alone; empty otherwise.
    @Default(<PostItem>[]) List<PostItem> postItems,
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

  /// Saves only [item] of the post.
  DownloadOption optionFor(PostItem item) => DownloadOption(
    type: item.type,
    formatSelector: postSelector,
    ext: item.type == OutputType.image ? 'jpg' : null,
    item: item.index,
  );

  /// The post item [option] saves alone; null for the whole post.
  PostItem? postItemOf(DownloadOption option) => option.item == null
      ? null
      : postItems.where((i) => i.index == option.item).firstOrNull;
}
