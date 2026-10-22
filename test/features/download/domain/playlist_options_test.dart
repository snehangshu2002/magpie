import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/core/platform/models/playlist_info.dart';
import 'package:media_downloader/features/download/domain/download_option.dart';
import 'package:media_downloader/features/download/domain/playlist_options.dart';

const _playlist = PlaylistInfo(
  title: 'Mix',
  extractor: 'youtube:tab',
  entries: [PlaylistEntry(), PlaylistEntry(), PlaylistEntry()],
);

void main() {
  test('offers every video, capped at the default quality', () {
    final options = playlistOptions(
      _playlist,
      platform: SourcePlatform.youtube,
      maxQuality: 720,
    )!;
    expect(options.playlist, isTrue);
    expect(options.postItems, hasLength(3));
    expect(options.recommended.type, OutputType.video);
    expect(options.recommended.quality, 720);
    expect(options.recommended.count, 3);
    expect(options.recommended.playlist, isTrue);
  });

  test('picking videos keeps the chosen type and quality', () {
    final options = playlistOptions(
      _playlist,
      platform: SourcePlatform.youtube,
    )!;
    final audio = options.defaultFor(OutputType.audio);
    final picked = options.optionFor([
      options.postItems[2],
      options.postItems[0],
    ], base: audio);
    expect(picked.type, OutputType.audio);
    expect(picked.items, [1, 3]);
    expect(picked.count, 2);
    expect(options.optionFor(options.postItems, base: audio).items, isNull);
  });

  test('music sites suggest audio', () {
    final options = playlistOptions(
      _playlist,
      platform: SourcePlatform.youtubeMusic,
    )!;
    expect(options.recommendedType, OutputType.audio);
  });

  test('an empty playlist offers nothing', () {
    expect(
      playlistOptions(
        const PlaylistInfo(title: 'x', extractor: 'youtube:tab'),
        platform: SourcePlatform.youtube,
      ),
      isNull,
    );
  });

  test('folder names leave out what paths refuse', () {
    expect(playlistFolderName('a/b: c?'), 'a_b_ c_');
    expect(playlistFolderName('...'), 'Playlist');
    expect(playlistFolderName('x' * 100), hasLength(80));
  });
}
