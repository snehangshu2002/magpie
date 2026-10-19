import 'dart:async';
import 'dart:typed_data';

import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/library/domain/active_download.dart';
import 'package:media_downloader/features/library/domain/library_item.dart';
import 'package:media_downloader/features/library/domain/library_repository.dart';

/// In-memory Library for widget tests; full-app tests must override
/// `libraryRepositoryProvider` with it, since the real one opens a database.
class FakeLibraryRepository implements LibraryRepository {
  new([List<LibraryItem> items = const []]) : _items = [...items];

  final List<LibraryItem> _items;
  final _changes = StreamController<List<LibraryItem>>.broadcast();
  final opened = <String>[];
  final shared = <String>[];

  /// Returned by [open] instead of success, when set.
  Failure? openFailure;

  @override
  Stream<List<LibraryItem>> watchItems() async* {
    yield [..._items];
    yield* _changes.stream;
  }

  /// Downloads shown as in progress.
  final active = StreamController<List<ActiveDownload>>.broadcast();
  final cancelled = <String>[];

  @override
  Stream<List<ActiveDownload>> watchActive() async* {
    yield const [];
    yield* active.stream;
  }

  @override
  Future<Result<bool>> cancel(String id) async {
    cancelled.add(id);
    return const Ok(true);
  }

  @override
  Stream<void> get downloadsFinished => const Stream.empty();

  @override
  Future<Result<void>> sync() async => const Ok(null);

  @override
  Future<Uint8List?> thumbnail(String fileUri) async => null;

  @override
  Future<Result<void>> open(LibraryItem item) async {
    opened.add(item.id);
    return switch (openFailure) {
      final failure? => Err(failure),
      null => const Ok(null),
    };
  }

  @override
  Future<Result<void>> share(LibraryItem item) async {
    shared.add(item.id);
    return const Ok(null);
  }

  @override
  Future<Result<bool>> delete(LibraryItem item) async {
    _items.removeWhere((i) => i.id == item.id);
    _changes.add([..._items]);
    return const Ok(true);
  }
}
