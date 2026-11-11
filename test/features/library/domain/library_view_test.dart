import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/features/library/domain/library_item.dart';
import 'package:media_downloader/features/library/domain/library_view.dart';

LibraryItem _item(
  String title,
  int day, {
  int? size,
  SourcePlatform platform = SourcePlatform.other,
}) => LibraryItem(
  id: title,
  title: title,
  platform: platform,
  type: OutputType.video,
  fileUri: 'content://media/external/downloads/$day',
  sourceUrl: 'https://example.com/$title',
  savedAt: DateTime(2026, 1, day),
  sizeBytes: size,
);

void main() {
  final items = [
    _item('beta', 2, size: 10, platform: SourcePlatform.youtube),
    _item('Alpha', 3, size: 30),
    _item('gamma', 1),
    _item('delta', 4, size: 5, platform: SourcePlatform.youtube),
  ];
  List<String> titles(LibrarySort sort) => [
    for (final item in sortLibrary(items, sort)) item.title,
  ];

  test('sorts by date, size and name', () {
    expect(titles(LibrarySort.newest), ['delta', 'Alpha', 'beta', 'gamma']);
    expect(titles(LibrarySort.oldest), ['gamma', 'beta', 'Alpha', 'delta']);
    expect(titles(LibrarySort.largest), ['Alpha', 'beta', 'delta', 'gamma']);
    expect(titles(LibrarySort.name), ['Alpha', 'beta', 'delta', 'gamma']);
  });

  test('adds up the space each site takes, biggest first', () {
    expect(storageBySite(items), [
      (SourcePlatform.other, 30),
      (SourcePlatform.youtube, 15),
    ]);
  });
}
