import 'package:media_downloader/core/platform/models/engine_update_result.dart';
import 'package:media_downloader/features/settings/data/engine_repository_impl.dart';
import 'package:media_downloader/features/settings/data/settings_repository_impl.dart';
import 'package:media_downloader/features/settings/domain/app_settings.dart';
import 'package:media_downloader/features/settings/presentation/engine_version_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'settings_providers.g.dart';

/// The user's settings. Changes apply at once and are saved in the
/// background; a failed save keeps them for this session.
@Riverpod(keepAlive: true)
class Settings extends _$Settings {
  @override
  Future<AppSettings> build() => ref.watch(settingsRepositoryProvider).load();

  Future<void> change(AppSettings Function(AppSettings) update) async {
    final current = state.value ?? const AppSettings();
    final next = update(current);
    state = AsyncData(next);
    await ref.read(settingsRepositoryProvider).save(next);
  }
}

/// Updates yt-dlp: null until the first tap, then the latest result.
@riverpod
class EngineUpdater extends _$EngineUpdater {
  @override
  FutureOr<EngineUpdateResult?> build() => null;

  Future<void> run() async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    final settings = await ref.read(settingsProvider.future);
    final result = await ref
        .read(engineRepositoryProvider)
        .update(settings.engineChannel);
    if (!ref.mounted) return;
    state = await AsyncValue.guard(() async => result.getOrThrow());
    if (state.value?.status == EngineUpdateStatus.done) {
      ref.invalidate(engineVersionProvider);
    }
  }
}
