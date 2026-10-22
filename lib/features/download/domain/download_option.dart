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

    /// 1-based items of a post to save, in order; null saves the whole post.
    List<int>? items,

    /// Full-size photos the engine downloads as they are ([photosSelector]).
    List<String>? imageUrls,

    /// Saves the items of a playlist ([items] picks some) with
    /// [formatSelector], each named by its own title.
    @Default(false) bool playlist,
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

/// `startDownload` selector that saves `imageUrls`: full-size photos found
/// outside yt-dlp (X, links to an image).
const photosSelector = 'images';

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

    /// The items of a post with several, in order, so some can be saved
    /// without the rest; empty otherwise.
    @Default(<PostItem>[]) List<PostItem> postItems,

    /// A playlist: [postItems] are its videos, picked on top of the type and
    /// quality.
    @Default(false) bool playlist,
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

  /// Saves only [items] of the post; the whole post when they are none or
  /// all of them. A playlist keeps the type and quality of [base].
  DownloadOption optionFor(Iterable<PostItem> items, {DownloadOption? base}) {
    final picked = [
      for (final item in postItems)
        if (items.contains(item)) item,
    ];
    final all = picked.isEmpty || picked.length == postItems.length;
    if (playlist) {
      return (base ?? recommended).copyWith(
        items: all ? null : [for (final item in picked) item.index],
        count: all ? postItems.length : picked.length,
      );
    }
    if (all) return recommended;
    if (recommended.imageUrls case final urls?) {
      return DownloadOption(
        type: OutputType.image,
        formatSelector: photosSelector,
        count: picked.length,
        items: [for (final item in picked) item.index],
        imageUrls: [for (final item in picked) urls[item.index - 1]],
      );
    }
    final photos = picked.every((i) => i.type == OutputType.image);
    return DownloadOption(
      type: photos ? OutputType.image : OutputType.video,
      formatSelector: postSelector,
      ext: photos ? 'jpg' : null,
      count: picked.length,
      items: [for (final item in picked) item.index],
    );
  }

  /// The post items [option] saves, in order; empty for the whole post.
  List<PostItem> postItemsOf(DownloadOption option) {
    final items = option.items ?? const <int>[];
    return [
      for (final item in postItems)
        if (items.contains(item.index)) item,
    ];
  }
}
