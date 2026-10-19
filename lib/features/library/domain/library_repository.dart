import 'dart:typed_data';

import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/library/domain/active_download.dart';
import 'package:media_downloader/features/library/domain/library_item.dart';

/// Saved downloads and what can be done with them.
abstract interface class LibraryRepository {
  /// Saved files, newest first.
  Stream<List<LibraryItem>> watchItems();

  /// Downloads queued or running now, in the order they were started.
  /// One shows up once the engine reports on it, so a record left behind
  /// by a download that died with the app never shows as running.
  Stream<List<ActiveDownload>> watchActive();

  /// False if it had already finished.
  Future<Result<bool>> cancel(String id);

  /// Fires whenever a download saves, fails or is cancelled.
  Stream<void> get downloadsFinished;

  /// Records downloads that finished while the app wasn't listening, and
  /// forgets files that were deleted outside the app.
  Future<Result<void>> sync();

  /// A preview made from the file at [fileUri]; null if there is none.
  Future<Uint8List?> thumbnail(String fileUri);

  Future<Result<void>> open(LibraryItem item);

  Future<Result<void>> share(LibraryItem item);

  /// False if the user declined the system's confirmation.
  Future<Result<bool>> delete(LibraryItem item);
}
