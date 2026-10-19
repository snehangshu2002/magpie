import 'package:freezed_annotation/freezed_annotation.dart';

part 'media_info.freezed.dart';
part 'media_info.g.dart';

/// Reply to `fetchInfo`.
@freezed
abstract class MediaInfo with _$MediaInfo {
  const factory({
    required String title,
    required String extractor,
    String? thumbnail,

    /// Seconds; null for images and live streams.
    int? duration,
    @Default(<MediaFormat>[]) List<MediaFormat> formats,

    /// The items of a post with several (an Instagram carousel), in order;
    /// null for a single item. [formats] is then empty.
    List<MediaEntry>? entries,
  }) = _MediaInfo;

  factory fromJson(Map<String, dynamic> json) => _$MediaInfoFromJson(json);
}

/// One item of `fetchInfo.entries`. An item without [formats] is a photo
/// on sites that have photo posts; [thumbnail] is then the photo itself.
@freezed
abstract class MediaEntry with _$MediaEntry {
  const factory({
    String? thumbnail,
    int? duration,
    @Default(<MediaFormat>[]) List<MediaFormat> formats,
  }) = _MediaEntry;

  factory fromJson(Map<String, dynamic> json) => _$MediaEntryFromJson(json);
}

/// One entry of `fetchInfo.formats`. Codec fields are `"none"` when the
/// stream has no video or no audio, as reported by yt-dlp.
@freezed
abstract class MediaFormat with _$MediaFormat {
  const factory({
    required String formatId,
    required String ext,
    int? width,
    int? height,
    int? fps,
    String? vcodec,
    String? acodec,

    /// Bytes, exact or approximate; null when unknown.
    int? fileSize,
    String? note,
  }) = _MediaFormat;

  factory fromJson(Map<String, dynamic> json) => _$MediaFormatFromJson(json);
}
