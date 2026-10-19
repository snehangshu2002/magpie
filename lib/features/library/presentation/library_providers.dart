import 'dart:async';
import 'dart:typed_data';

import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/features/library/data/library_repository_impl.dart';
import 'package:media_downloader/features/library/domain/active_download.dart';
import 'package:media_downloader/features/library/domain/library_filter.dart';
import 'package:media_downloader/features/library/domain/library_item.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'library_providers.g.dart';

/// Keeps the history in step with the engine: catches up on launch, then
/// after every finished download. Started by the app root.
@Riverpod(keepAlive: true)
Future<void> librarySync(Ref ref) async {
  final repository = ref.watch(libraryRepositoryProvider);
  final finished = repository.downloadsFinished.listen(
    (_) => unawaited(repository.sync()),
  );
  ref.onDispose(finished.cancel);
  await repository.sync();
}

/// Saved files, newest first.
@riverpod
Stream<List<LibraryItem>> libraryItems(Ref ref) =>
    ref.watch(libraryRepositoryProvider).watchItems();

/// A preview made from the saved file; null if it has none.
@riverpod
Future<Uint8List?> libraryThumbnail(Ref ref, String fileUri) {
  // Small, and slow to make: keep it while the app runs.
  ref.keepAlive();
  return ref.watch(libraryRepositoryProvider).thumbnail(fileUri);
}

/// Downloads queued or running now.
@riverpod
Stream<List<ActiveDownload>> activeDownloads(Ref ref) =>
    ref.watch(libraryRepositoryProvider).watchActive();

/// The Library's type, site and search filter.
@riverpod
class LibraryFilterState extends _$LibraryFilterState {
  @override
  LibraryFilter build() => const LibraryFilter();

  void showType(OutputType? type) => state = state.copyWith(type: () => type);

  /// Selecting the site already selected clears it.
  void toggleSite(SourcePlatform platform) => state = state.copyWith(
    platform: () => state.platform == platform ? null : platform,
  );

  void openSearch() => state = state.copyWith(query: () => '');

  void search(String query) => state = state.copyWith(query: () => query);

  void closeSearch() => state = state.copyWith(query: () => null);
}
