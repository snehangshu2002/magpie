import 'package:media_downloader/core/platform/models/download_progress.dart';
import 'package:media_downloader/core/platform/models/video_probe.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/fit/domain/fit_plan.dart';
import 'package:media_downloader/features/library/domain/library_item.dart';

/// Makes smaller copies of saved videos, so they fit an app's size limit.
abstract interface class FitRepository {
  /// Length, size in pixels and sound of the saved video at [fileUri].
  Future<Result<VideoProbe>> probe(String fileUri);

  /// Starts a copy of [item] re-encoded by [plan] to fit [size], saved in
  /// [targetDir] as [name]. It joins the Library like a download: in
  /// progress, then saved. Returns its id.
  Future<Result<String>> start({
    required String id,
    required LibraryItem item,
    required ShareSize size,
    required FitEncode plan,
    required int durationMs,
    required String targetDir,
    required String name,
  });

  /// Progress of the copy with [id]; the last event is `saved`, `failed`
  /// or `cancelled`.
  Stream<DownloadProgress> progressOf(String id);

  /// False when it had already finished.
  Future<Result<bool>> cancel(String id);
}
