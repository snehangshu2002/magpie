import 'package:freezed_annotation/freezed_annotation.dart';

part 'download_progress.freezed.dart';
part 'download_progress.g.dart';

enum DownloadState { queued, running, merging, saved, failed, cancelled }

/// Event on `app/engine/progress`.
@freezed
abstract class DownloadProgress with _$DownloadProgress {
  const factory({
    required String id,
    required double percent,
    required DownloadState state,
    int? etaSeconds,

    /// Human-readable rate as printed by yt-dlp, e.g. `2.31MiB/s`.
    String? speed,

    /// MediaStore content URI, set once [state] is `saved`.
    String? filePath,

    /// One of the native error codes, set when [state] is `failed`.
    String? error,
  }) = _DownloadProgress;

  factory fromJson(Map<String, dynamic> json) =>
      _$DownloadProgressFromJson(json);
}
