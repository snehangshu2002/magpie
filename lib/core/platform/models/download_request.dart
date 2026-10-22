import 'package:freezed_annotation/freezed_annotation.dart';

part 'download_request.freezed.dart';
part 'download_request.g.dart';

enum OutputType { video, audio, image }

/// Arguments of `startDownload`.
@freezed
abstract class DownloadRequest with _$DownloadRequest {
  const factory({
    required String id,
    required String url,
    required String formatId,
    required OutputType outputType,

    /// Relative path under shared storage, e.g. `Download/<AppName>/YouTube`.
    required String targetDir,

    /// Shown in the progress notification.
    String? title,

    /// 1-based items of a `post` to save, in order; null saves every item.
    /// For `images`, the place in the post of each of [imageUrls], which
    /// numbers the files.
    List<int>? items,

    /// Full-size photos an `images` download saves, in order.
    List<String>? imageUrls,

    /// Extra yt-dlp arguments from Settings (`downloadArgs`).
    @Default(<String>[]) List<String> options,

    /// Saves the playlist at [url]; [items] picks some of its videos.
    @Default(false) bool playlist,

    /// Leaves out videos saved before (`NOTHING_NEW` if there's nothing
    /// else to save).
    @Default(false) bool archive,

    /// yt-dlp output template for the file name, without the extension;
    /// null for the title.
    String? fileName,
  }) = _DownloadRequest;

  factory fromJson(Map<String, dynamic> json) =>
      _$DownloadRequestFromJson(json);
}
