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
  }) = _MediaInfo;

  factory fromJson(Map<String, dynamic> json) => _$MediaInfoFromJson(json);
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
