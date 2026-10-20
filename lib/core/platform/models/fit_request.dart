import 'package:freezed_annotation/freezed_annotation.dart';

part 'fit_request.freezed.dart';
part 'fit_request.g.dart';

/// Arguments of `fitVideo`: re-encode a saved video so it is at most
/// [targetBytes], and save the copy like a download.
@freezed
abstract class FitRequest with _$FitRequest {
  const factory({
    required String id,

    /// Content URI of the saved video.
    required String uri,

    /// Relative path under shared storage, e.g. `Download/Magpie/YouTube`.
    required String targetDir,

    /// File name of the copy, without extension.
    required String name,
    required int targetBytes,
    required int durationMs,
    required int videoKbps,

    /// 0 drops the audio.
    required int audioKbps,

    /// The copy's shorter side in pixels; never upscaled.
    required int maxShortSide,

    /// Shown in the progress notification.
    String? title,
  }) = _FitRequest;

  factory fromJson(Map<String, dynamic> json) => _$FitRequestFromJson(json);
}
