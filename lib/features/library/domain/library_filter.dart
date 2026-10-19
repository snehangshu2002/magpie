import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/features/library/domain/library_item.dart';

/// What the Library shows: everything, or files of one kind, from one site,
/// or matching a search.
final class LibraryFilter {
  const new({this.type, this.platform, this.query});

  final OutputType? type;
  final SourcePlatform? platform;

  /// Text to find in titles; null when search is closed.
  final String? query;

  bool get searching => query != null;

  bool matches(LibraryItem item) {
    final query = this.query?.trim().toLowerCase() ?? '';
    return (type == null || item.type == type) &&
        (platform == null || item.platform == platform) &&
        (query.isEmpty || item.title.toLowerCase().contains(query));
  }

  LibraryFilter copyWith({
    OutputType? Function()? type,
    SourcePlatform? Function()? platform,
    String? Function()? query,
  }) => LibraryFilter(
    type: type == null ? this.type : type(),
    platform: platform == null ? this.platform : platform(),
    query: query == null ? this.query : query(),
  );
}
