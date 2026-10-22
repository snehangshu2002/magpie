import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/errors/platform_failure.dart';
import 'package:media_downloader/core/platform/appearance_channel.dart';
import 'package:media_downloader/core/platform/models/engine_update_result.dart';
import 'package:media_downloader/features/download/domain/save_location.dart';
import 'package:media_downloader/features/settings/data/engine_repository_impl.dart';
import 'package:media_downloader/features/settings/data/settings_repository_impl.dart';
import 'package:media_downloader/features/settings/domain/app_settings.dart';
import 'package:media_downloader/features/settings/presentation/engine_version_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'settings_providers.g.dart';

/// How choosing a save folder went.
enum SaveFolderPick { changed, cancelled, outsideDownload }

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

  /// Opens the folder picker and saves into the chosen folder from now on;
  /// with [audio], only audio goes there. Throws the [Failure] when the
  /// picker can't be opened.
  Future<SaveFolderPick> pickSaveFolder({bool audio = false}) async {
    final picked = (await ref.read(settingsRepositoryProvider).pickFolder())
        .getOrThrow();
    if (picked == null) return SaveFolderPick.cancelled;
    final folder = saveFolderFromTreeId(picked);
    if (folder == null) return SaveFolderPick.outsideDownload;
    await change(
      (s) => audio
          ? s.copyWith(audioFolder: folder)
          : s.copyWith(saveFolder: folder),
    );
    return SaveFolderPick.changed;
  }
}

/// Sites the user signed in to, so downloads can use the account.
@Riverpod(keepAlive: true)
class SignedInSites extends _$SignedInSites {
  @override
  Future<List<String>> build() async =>
      (await ref.watch(settingsRepositoryProvider).signedInSites())
          .getOrThrow();

  /// Opens the sign-in page at [url]. Throws the [Failure] when it can't.
  Future<void> signIn(String url) async {
    final sites = (await ref.read(settingsRepositoryProvider).signIn(url))
        .getOrThrow();
    state = AsyncData(sites);
  }

  /// Throws the [Failure] when the sign-in couldn't be removed.
  Future<void> signOut(String site) async {
    final sites = (await ref.read(settingsRepositoryProvider).signOut(site))
        .getOrThrow();
    state = AsyncData(sites);
  }
}

/// Keeps Android's own idea of the app's theme in step with Settings, so the
/// next launch screen matches. Best effort: a failure only means the launch
/// screen follows the phone.
@Riverpod(keepAlive: true)
Future<void> appearanceSync(Ref ref) async {
  final mode = await ref.watch(
    settingsProvider.selectAsync((s) => s.appearance),
  );
  await guardPlatformCall(
    () => ref.read(appearanceChannelProvider).setNightMode(mode.name),
  );
}

/// Brings yt-dlp up to date once per launch, in the background. Sites change
/// faster than the app is released, and the build bundled with it soon stops
/// reading some of them (Instagram). Fails with the [Failure] (Settings
/// offers to try again); the installed version keeps working meanwhile.
@Riverpod(keepAlive: true)
Future<EngineUpdateResult> engineAutoUpdate(Ref ref) async {
  final result =
      (await ref
              .read(engineRepositoryProvider)
              .update(EngineReleaseChannel.stable))
          .getOrThrow();
  if (result.status == EngineUpdateStatus.done) {
    ref.invalidate(engineVersionProvider);
  }
  return result;
}
