import 'package:media_downloader/features/updater/data/update_repository_impl.dart';
import 'package:media_downloader/features/updater/domain/app_update.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'update_providers.g.dart';

/// A newer release of the app, checked once per launch; null when up to
/// date. Failures are not shown: the next launch checks again.
@Riverpod(keepAlive: true)
Future<AppUpdate?> appUpdate(Ref ref) async =>
    (await ref.watch(updateRepositoryProvider).check()).getOrThrow();

/// The installed app's version, shown in Settings.
@Riverpod(keepAlive: true)
Future<String> appVersion(Ref ref) async =>
    (await ref.watch(updateRepositoryProvider).installedVersion()).getOrThrow();
