import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/core/platform/models/media_info.dart';
import 'package:media_downloader/features/download/domain/download_option.dart';
import 'package:media_downloader/features/download/domain/suggest_download_options.dart';

MediaFormat _video(
  String id,
  int height, {
  int? width,
  String ext = 'mp4',
  String vcodec = 'avc1.640028',
  String acodec = 'none',
  int? fps,
  int? size,
}) => MediaFormat(
  formatId: id,
  ext: ext,
  width: width ?? height * 16 ~/ 9,
  height: height,
  fps: fps,
  vcodec: vcodec,
  acodec: acodec,
  fileSize: size,
);

MediaFormat _audio(
  String id, {
  String ext = 'm4a',
  String? acodec,
  int? size,
}) => MediaFormat(
  formatId: id,
  ext: ext,
  vcodec: 'none',
  acodec: acodec ?? (ext == 'm4a' ? 'mp4a.40.2' : 'opus'),
  fileSize: size,
);

DownloadOptions _suggest(
  List<MediaFormat> formats, {
  SourcePlatform platform = SourcePlatform.youtube,
}) => suggestDownloadOptions(
  MediaInfo(title: 'Test clip', extractor: 'test', formats: formats),
  platform: platform,
)!;

void main() {
  test('offers one option per quality, best first, merging audio in', () {
    final options = _suggest([
      _audio('140', size: 3000000),
      _audio('251', ext: 'webm', size: 3500000),
      _video('136', 720, size: 20000000),
      _video('137', 1080, size: 40000000),
      _video('248', 1080, ext: 'webm', vcodec: 'vp9', size: 38000000),
      _video('313', 2160, ext: 'webm', vcodec: 'vp9', size: 90000000),
    ]);

    expect(options.video.map((o) => o.quality), [2160, 1080, 720]);

    final hd = options.video[1];
    expect(hd.formatSelector, '137+140', reason: 'MP4 video pairs with M4A');
    expect(hd.ext, 'mp4');
    expect(hd.sizeBytes, 43000000);

    final uhd = options.video.first;
    expect(uhd.formatSelector, '313+251', reason: 'WebM video pairs with WebM');
    expect(uhd.ext, 'webm');
  });

  test('sums a merged size when only the audio size is unknown', () {
    final options = _suggest([
      _audio('140'),
      _video('137', 1080, size: 40000000),
      _video('136', 720),
    ]);

    final hd = options.video.first;
    expect(hd.sizeBytes, 40000000);
    expect(hd.sizeApproximate, isTrue);
    expect(options.video.last.sizeBytes, isNull, reason: 'no video size');
    expect(options.video.last.sizeApproximate, isFalse);
  });

  test('recommends the best video up to 1080p', () {
    final options = _suggest([
      _audio('140'),
      _video('137', 1080),
      _video('313', 2160),
    ]);

    expect(options.recommendedType, OutputType.video);
    expect(options.recommended.quality, 1080);
    expect(options.reason, RecommendationReason.bestUpToCap);
  });

  test('falls back to the closest quality when all are above the cap', () {
    final options = _suggest([
      _audio('140'),
      _video('400', 1440),
      _video('401', 2160),
    ]);

    expect(options.recommended.quality, 1440);
    expect(options.reason, RecommendationReason.closestToCap);
  });

  test('labels vertical video by its short side', () {
    final options = _suggest([
      _audio('140'),
      _video('short', 1920, width: 1080),
    ]);

    expect(options.video.single.quality, 1080);
  });

  test('uses a progressive format as is', () {
    final options = _suggest([
      _video('18', 360, acodec: 'mp4a.40.2', size: 5000000),
    ]);

    expect(options.video.single.formatSelector, '18');
    expect(options.audio.single.formatSelector, '18');
    expect(options.audio.single.type, OutputType.audio);
  });

  test(
    'prefers MP4 and H.264 at the same quality, for playback everywhere',
    () {
      final options = _suggest([
        _audio('140'),
        _video('a', 1080, ext: 'webm', vcodec: 'vp9', fps: 60),
        _video('b', 1080, vcodec: 'av01.0.08M.08', fps: 30),
        _video('c', 1080, fps: 30),
      ]);

      expect(options.video.single.formatSelector, startsWith('c+'));
    },
  );

  test('lists M4A first among audio options', () {
    final options = _suggest([
      _audio('251', ext: 'webm', size: 5000000),
      _audio('140', size: 3000000),
      _video('137', 1080),
    ]);

    expect(options.audio.map((o) => o.ext), ['m4a', 'opus']);
  });

  test('recommends audio for music links', () {
    final options = _suggest([
      _audio('140'),
      _video('137', 1080),
    ], platform: SourcePlatform.youtubeMusic);

    expect(options.recommendedType, OutputType.audio);
    expect(options.reason, RecommendationReason.musicSource);
  });

  test('recommends audio when there is no video', () {
    final options = _suggest([
      _audio('mp3', ext: 'mp3', acodec: 'mp3'),
    ], platform: SourcePlatform.other);

    expect(options.video, isEmpty);
    expect(options.recommendedType, OutputType.audio);
    expect(options.reason, RecommendationReason.audioOnly);
  });

  test('offers images, largest first, when that is all there is', () {
    final options = _suggest([
      const MediaFormat(formatId: 's', ext: 'jpg', width: 320, height: 320),
      const MediaFormat(formatId: 'l', ext: 'jpg', width: 1080, height: 1350),
    ], platform: SourcePlatform.instagram);

    expect(options.image.map((o) => o.formatSelector), ['l', 's']);
    expect(options.recommendedType, OutputType.image);
    expect(options.reason, RecommendationReason.imageOnly);
  });

  test('ignores storyboards and returns null when nothing is left', () {
    expect(
      suggestDownloadOptions(
        const MediaInfo(
          title: 'Test clip',
          extractor: 'test',
          formats: [
            MediaFormat(
              formatId: 'sb0',
              ext: 'mhtml',
              vcodec: 'none',
              acodec: 'none',
            ),
          ],
        ),
        platform: SourcePlatform.youtube,
      ),
      isNull,
    );
  });

  test('treats formats without codec info as video with sound', () {
    final options = _suggest(const [
      MediaFormat(formatId: 'http-720', ext: 'mp4', width: 1280, height: 720),
    ], platform: SourcePlatform.x);

    expect(options.video.single.formatSelector, 'http-720');
    expect(options.audio.single.formatSelector, 'http-720');
  });

  test('switching type picks a sensible default', () {
    final options = _suggest([
      _audio('140'),
      _video('137', 1080),
      _video('313', 2160),
    ], platform: SourcePlatform.youtubeMusic);

    expect(options.recommendedType, OutputType.audio);
    expect(options.defaultFor(OutputType.video).quality, 1080);
    expect(options.types, [OutputType.video, OutputType.audio]);
  });

  group('posts', () {
    const photo = MediaEntry(thumbnail: 'https://example.com/photo.jpg');
    final clip = MediaEntry(formats: [_video('v', 720, acodec: 'aac')]);

    DownloadOptions? suggestPost(
      List<MediaEntry>? entries, {
      String? thumbnail = 'https://example.com/photo.jpg',
      SourcePlatform platform = SourcePlatform.instagram,
    }) => suggestDownloadOptions(
      MediaInfo(
        title: 'Test post',
        extractor: 'test',
        thumbnail: thumbnail,
        entries: entries,
      ),
      platform: platform,
    );

    test('a carousel of photos is saved as one option', () {
      final options = suggestPost([photo, photo, photo])!;

      final option = options.image.single;
      expect(option.formatSelector, postSelector);
      expect(option.count, 3);
      expect(option.ext, 'jpg');
      expect(options.video, isEmpty);
      expect(options.recommendedType, OutputType.image);
      expect(options.reason, RecommendationReason.wholePost);
    });

    test('photos and videos together count as video', () {
      final options = suggestPost([photo, clip])!;

      expect(options.video.single.count, 2);
      expect(options.video.single.ext, isNull);
      expect(options.image, isEmpty);
    });

    test('a single photo post has no formats', () {
      final options = suggestPost(null)!;

      expect(options.image.single.formatSelector, postSelector);
      expect(options.image.single.count, 1);
      expect(options.reason, RecommendationReason.imageOnly);
    });

    test('items without formats are not photos on other sites', () {
      expect(suggestPost(null, platform: SourcePlatform.youtube), isNull);
      expect(
        suggestPost([
          photo,
          clip,
        ], platform: SourcePlatform.x)!.video.single.count,
        1,
      );
    });

    test('each item of a post can be saved alone, by its place', () {
      final options = suggestPost([photo, clip])!;

      expect(options.postItems.map((i) => (i.index, i.type)), [
        (1, OutputType.image),
        (2, OutputType.video),
      ]);
      final second = options.optionFor(options.postItems[1]);
      expect(second.formatSelector, postSelector);
      expect(second.item, 2);
      expect(second.type, OutputType.video);
      expect(options.postItemOf(second), options.postItems[1]);
      expect(options.postItemOf(options.recommended), isNull);
    });

    test('a skipped item keeps the places of the ones after it', () {
      // On X a formatless item isn't a photo, but it still takes place 1.
      final options = suggestPost([
        photo,
        clip,
        clip,
      ], platform: SourcePlatform.x)!;

      expect(options.postItems.map((i) => i.index), [2, 3]);
    });

    test('a post with one item has nothing to pick from', () {
      expect(suggestPost([clip])!.postItems, isEmpty);
      expect(suggestPost(null)!.postItems, isEmpty);
    });

    test('nothing to save without formats or a photo', () {
      expect(suggestPost(null, thumbnail: null), isNull);
    });
  });
}
