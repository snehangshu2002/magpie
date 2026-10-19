import 'package:freezed_annotation/freezed_annotation.dart';

part 'download_request.freezed.dart';
part 'download_request.g.dart';

enum OutputType { video, audio, image }

/// Arguments of `startDownload`.
@freezed
abstract class DownloadRequest with _$DownloadRequest {
  const factory DownloadRequest({
    required String id,
    required String url,
    required String formatId,
    required OutputType outputType,

    /// Relative path under shared storage, e.g. `Download/<AppName>/YouTube`.
    required String targetDir,
  }) = _DownloadRequest;

  factory DownloadRequest.fromJson(Map<String, dynamic> json) =>
      _$DownloadRequestFromJson(json);
}
