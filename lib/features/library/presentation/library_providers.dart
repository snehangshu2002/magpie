import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/features/library/data/library_repository_impl.dart';
import 'package:media_downloader/features/library/domain/active_download.dart';
import 'package:media_downloader/features/library/domain/library_filter.dart';
import 'package:media_downloader/features/library/domain/library_item.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'library_providers.g.dart';

/// How long storage must be quiet before the Library re-checks its files;
/// one deletion or save sends several change notices.
const librarySyncDebounce = Duration(milliseconds: 500);

/// Keeps the history in step with the engine and shared storage: catches up
/// on launch, after every finished download, when files change in another
/// app (deleted in the gallery or file manager), and when the app comes back
/// to the foreground, in case a change went unnoticed. Started by the app
/// root.
@Riverpod(keepAlive: true)
Future<void> librarySync(Ref ref) async {
  final repository = ref.watch(libraryRepositoryProvider);
  void sync() => unawaited(repository.sync());

  Timer? debounce;
  final finished = repository.downloadsFinished.listen((_) => sync());
  final changed = repository.filesChanged.listen((_) {
    debounce?.cancel();
    debounce = Timer(librarySyncDebounce, sync);
  });
  final lifecycle = AppLifecycleListener(onResume: sync);
  ref.onDispose(() {
    debounce?.cancel();
    lifecycle.dispose();
    unawaited(finished.cancel());
    unawaited(changed.cancel());
  });
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

/// Ids of the saved files picked with a long press; empty when not
/// selecting. Starts over when the filter or search changes, so nothing
/// hidden stays picked.
@riverpod
class LibrarySelection extends _$LibrarySelection {
  @override
  Set<String> build() {
    ref.watch(libraryFilterStateProvider);
    return const {};
  }

  void toggle(String id) =>
      state = state.contains(id) ? state.difference({id}) : {...state, id};

  void selectAll(Iterable<String> ids) => state = {...ids};

  void clear() => state = const {};
}

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

  /// Back to everything, with search closed.
  void clear() => state = const LibraryFilter();
}

/// Whether a cancel for the download [id] was asked for and the engine hasn't
/// confirmed it yet, so its tile can say "Cancelling…" at once.
@riverpod
class ActiveCancelling extends _$ActiveCancelling {
  @override
  bool build(String id) => false;

  // Named argument, so a call site reads as what it does.
  // ignore: use_setters_to_change_properties
  void set({required bool value}) => state = value;
}
