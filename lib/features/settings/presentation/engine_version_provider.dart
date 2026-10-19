import 'package:media_downloader/features/settings/data/engine_repository_impl.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'engine_version_provider.g.dart';

/// Installed yt-dlp version. Reading it also initializes the engine.
@Riverpod(keepAlive: true)
Future<String> engineVersion(Ref ref) async =>
    (await ref.watch(engineRepositoryProvider).initialize()).getOrThrow();
