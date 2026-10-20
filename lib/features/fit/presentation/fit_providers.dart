import 'dart:async';
import 'dart:math';

import 'package:media_downloader/core/errors/platform_failure.dart';
import 'package:media_downloader/core/platform/models/download_progress.dart';
import 'package:media_downloader/core/platform/models/video_probe.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/download/domain/save_location.dart';
import 'package:media_downloader/features/fit/data/fit_repository_impl.dart';
import 'package:media_downloader/features/fit/domain/fit_plan.dart';
import 'package:media_downloader/features/library/domain/library_item.dart';
import 'package:media_downloader/features/settings/presentation/settings_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'fit_providers.g.dart';

/// Length, size in pixels and sound of the saved video at [fileUri].
@riverpod
Future<VideoProbe> videoProbe(Ref ref, String fileUri) async =>
    (await ref.read(fitRepositoryProvider).probe(fileUri)).getOrThrow();

/// Starts a smaller copy of the Library item with [itemId] and follows it:
/// null before it starts, then the latest progress; an error if it could
/// not be started or failed.
@riverpod
class FitJob extends _$FitJob {
  StreamSubscription<DownloadProgress>? _progress;

  @override
  FutureOr<DownloadProgress?> build(String itemId) {
    ref.onDispose(() => _progress?.cancel());
    return null;
  }

  /// Copies [item] to fit [size] by [plan], saved as [name] in the same
  /// folder downloads from its site go to.
  Future<void> start({
    required LibraryItem item,
    required ShareSize size,
    required FitEncode plan,
    required int durationMs,
    required String name,
  }) async {
    if (_busy) return;
    _stopFollowing();
    state = const AsyncLoading();
    final repository = ref.read(fitRepositoryProvider);
    final id = _newId();
    // Listen first, so events sent while the call returns are not missed.
    _progress = repository.progressOf(id).listen(_onProgress);
    final result = await repository.start(
      id: id,
      item: item,
      size: size,
      plan: plan,
      durationMs: durationMs,
      targetDir: saveDirFor(
        (await ref.read(settingsProvider.future)).saveFolder,
        item.platform,
      ),
      name: name,
    );
    if (!ref.mounted) return;
    switch (result) {
      case Ok() when state is AsyncLoading:
        state = AsyncData(
          DownloadProgress(id: id, percent: 0, state: DownloadState.queued),
        );
      case Ok():
        break;
      case Err(:final failure):
        _stopFollowing();
        state = AsyncError(failure, StackTrace.current);
    }
  }

  Future<void> cancel() async {
    if (state case AsyncData(value: final job?) when job.state.isActive) {
      await ref.read(fitRepositoryProvider).cancel(job.id);
    }
  }

  /// Back to picking a size, after a failure or a cancel. A copy in
  /// progress keeps showing.
  void reset() {
    if (_busy) return;
    _stopFollowing();
    state = const AsyncData(null);
  }

  /// Starting, or a copy in progress. Checked by state, not `state.value`:
  /// an error keeps the progress from before it as its value.
  bool get _busy => switch (state) {
    AsyncLoading() => true,
    AsyncData(value: final job?) => job.state.isActive,
    _ => false,
  };

  void _onProgress(DownloadProgress progress) {
    state = switch (progress.state) {
      DownloadState.failed => AsyncError(
        failureFromNativeCode(progress.error),
        StackTrace.current,
      ),
      // Nothing to show for a cancel: pick a size again.
      DownloadState.cancelled => const AsyncData(null),
      _ => AsyncData(progress),
    };
    if (!progress.state.isActive) _stopFollowing();
  }

  // Not awaited: an EventChannel cancel waits on a platform round trip.
  void _stopFollowing() {
    unawaited(_progress?.cancel());
    _progress = null;
  }

  static final _random = Random.secure();

  static String _newId() =>
      [for (var i = 0; i < 16; i++) _random.nextInt(16).toRadixString(16)]
          .join();
}
