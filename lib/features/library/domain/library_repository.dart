import 'dart:typed_data';

import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/library/domain/library_item.dart';

/// Saved downloads and what can be done with them.
abstract interface class LibraryRepository {
  /// Saved files, newest first.
  Stream<List<LibraryItem>> watchItems();

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
