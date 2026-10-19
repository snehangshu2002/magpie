import 'package:freezed_annotation/freezed_annotation.dart';

part 'download_progress.freezed.dart';
part 'download_progress.g.dart';

enum DownloadState {
  queued,
  running,

  /// Merging streams or copying the file into shared storage.
  merging,
  saved,
  failed,
  cancelled;

  /// Not yet saved, failed or cancelled.
  bool get isActive => switch (this) {
    queued || running || merging => true,
    saved || failed || cancelled => false,
  };
}

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

    /// Every saved file, in order, when a post saved several; the first is
    /// [filePath].
    List<String>? filePaths,

    /// One of the native error codes, set when [state] is `failed`.
    String? error,
  }) = _DownloadProgress;

  factory fromJson(Map<String, dynamic> json) =>
      _$DownloadProgressFromJson(json);
}
