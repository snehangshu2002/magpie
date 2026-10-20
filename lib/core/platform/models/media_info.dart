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

    /// The video's description, or a post's caption or text; null when empty.
    String? description,

    /// Caption tracks a transcript can be made from.
    @Default(<CaptionTrack>[]) List<CaptionTrack> captions,
  }) = _MediaInfo;

  factory fromJson(Map<String, dynamic> json) => _$MediaInfoFromJson(json);
}

/// One item of `fetchInfo.captions`: subtitles the uploader added, or
/// YouTube's automatic captions in the video's own language ([auto]).
@freezed
abstract class CaptionTrack with _$CaptionTrack {
  const factory({
    /// yt-dlp's language key, e.g. `en`, `en-US`, `hi-orig`.
    required String lang,

    /// The site's name for it, e.g. "English (auto-generated)".
    String? name,
    @Default(false) bool auto,
  }) = _CaptionTrack;

  factory fromJson(Map<String, dynamic> json) => _$CaptionTrackFromJson(json);
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
