import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/download/domain/download_args.dart';
import 'package:media_downloader/features/settings/presentation/settings_providers.dart';
import 'package:media_downloader/features/updater/data/update_repository_impl.dart';
import 'package:media_downloader/features/updater/domain/app_update.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'update_providers.g.dart';

/// A newer release of the app, checked once per launch; null when up to
/// date. Failures are not shown: the next launch checks again.
@Riverpod(keepAlive: true)
Future<AppUpdate?> appUpdate(Ref ref) async {
  final settings = await ref.read(settingsProvider.future);
  return (await ref
          .watch(updateRepositoryProvider)
          .check(options: networkArgs(settings)))
      .getOrThrow();
}

/// The installed app's version, shown in Settings.
@Riverpod(keepAlive: true)
Future<String> appVersion(Ref ref) async =>
    (await ref.watch(updateRepositoryProvider).installedVersion()).getOrThrow();

/// Where downloading and installing an update stands.
sealed class UpdateProgress {
  const new();
}

final class UpdateIdle extends UpdateProgress {
  const new();
}

/// [total] is null when the server doesn't say.
final class UpdateDownloading extends UpdateProgress {
  const new(this.received, this.total);

  final int received;
  final int? total;

  double? get fraction => switch (total) {
    final total? when total > 0 => (received / total).clamp(0, 1),
    _ => null,
  };
}

/// Android's installer was opened for the APK at [path]; the user finishes
/// there, or comes back and opens it again.
final class UpdateReady extends UpdateProgress {
  const new(this.path);

  final String path;
}

final class UpdateFailed extends UpdateProgress {
  const new(this.failure);

  final Failure failure;
}

/// Downloads an update's APK inside the app and hands it to Android's
/// installer. Closing the update sheet disposes this and stops a download.
@riverpod
class UpdateDownload extends _$UpdateDownload {
  var _cancelled = false;

  @override
  UpdateProgress build() {
    ref.onDispose(() => _cancelled = true);
    return const UpdateIdle();
  }

  Future<void> start(AppUpdate update) async {
    if (state is UpdateDownloading) return;
    _cancelled = false;
    state = const UpdateDownloading(0, null);
    final repository = ref.read(updateRepositoryProvider);
    final settings = await ref.read(settingsProvider.future);
    if (!ref.mounted || _cancelled) return;
    final downloaded = await repository.download(
      update,
      onProgress: (received, total) {
        if (ref.mounted && !_cancelled) {
          state = UpdateDownloading(received, total);
        }
      },
      isCancelled: () => _cancelled,
      options: networkArgs(settings),
    );
    if (!ref.mounted || _cancelled) return;
    switch (downloaded) {
      case Err(:final failure):
        state = UpdateFailed(failure);
      case Ok(value: final path):
        await install(path, update);
    }
  }

  /// Opens Android's installer for the downloaded APK (again).
  Future<void> install(String path, AppUpdate update) async {
    final result = await ref
        .read(updateRepositoryProvider)
        .install(path, update);
    if (!ref.mounted) return;
    state = switch (result) {
      Ok() => UpdateReady(path),
      Err(:final failure) => UpdateFailed(failure),
    };
  }

  void cancel() {
    _cancelled = true;
    state = const UpdateIdle();
  }
}
