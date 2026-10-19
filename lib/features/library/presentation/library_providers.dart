import 'dart:async';
import 'dart:typed_data';

import 'package:media_downloader/features/library/data/library_repository_impl.dart';
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
