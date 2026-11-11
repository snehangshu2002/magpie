import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/features/library/domain/library_item.dart';

/// The order saved files are listed in.
enum LibrarySort {
  newest,
  oldest,
  largest,
  name;

  /// Whether the list still reads as a timeline, so it can be split by day.
  bool get byDate => this == newest || this == oldest;
}

/// [items] in [sort] order; a new list. Files of unknown size come last
/// when sorting by size.
List<LibraryItem> sortLibrary(List<LibraryItem> items, LibrarySort sort) {
  final sorted = [...items];
  switch (sort) {
    case LibrarySort.newest:
      sorted.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    case LibrarySort.oldest:
      sorted.sort((a, b) => a.savedAt.compareTo(b.savedAt));
    case LibrarySort.largest:
      sorted.sort((a, b) => (b.sizeBytes ?? -1).compareTo(a.sizeBytes ?? -1));
    case LibrarySort.name:
      sorted.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
  }
  return sorted;
}

/// Bytes the saved files of each site take, biggest first; sites whose
/// files have no known size are left out.
List<(SourcePlatform, int)> storageBySite(List<LibraryItem> items) {
  final bytes = <SourcePlatform, int>{};
  for (final item in items) {
    final size = item.sizeBytes;
    if (size != null && size > 0) {
      bytes[item.platform] = (bytes[item.platform] ?? 0) + size;
    }
  }
  return [for (final e in bytes.entries) (e.key, e.value)]
    ..sort((a, b) => b.$2.compareTo(a.$2));
}
