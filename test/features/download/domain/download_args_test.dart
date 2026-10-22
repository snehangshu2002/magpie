import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/features/download/domain/download_args.dart';
import 'package:media_downloader/features/download/domain/download_option.dart';
import 'package:media_downloader/features/settings/domain/app_settings.dart';

const _video = DownloadOption(
  type: OutputType.video,
  formatSelector: '137+140',
  ext: 'mp4',
  quality: 1080,
);
const _audio = DownloadOption(
  type: OutputType.audio,
  formatSelector: '251',
  ext: 'opus',
);

void main() {
  group('tryParseArgs', () {
    test('splits on spaces and keeps quoted groups', () {
      expect(tryParseArgs(r'''-N 8  --ppa "a b" 'c "d"' e\ f'''), [
        '-N',
        '8',
        '--ppa',
        'a b',
        'c "d"',
        'e f',
      ]);
    });

    test('an empty quote is an empty argument', () {
      expect(tryParseArgs('--proxy ""'), ['--proxy', '']);
    });

    test('an unclosed quote is refused', () {
      expect(tryParseArgs('--ppa "oops'), isNull);
    });
  });

  test('extraOptionsProblem names an option the app sets itself', () {
    expect(extraOptionsProblem('-N 4'), isNull);
    expect(extraOptionsProblem('--output=x'), '--output');
    expect(extraOptionsProblem('-P /sdcard'), '-P');
    expect(extraOptionsProblem('"'), '"');
  });

  test('default settings add nothing', () {
    expect(downloadArgs(const AppSettings(), _video), isEmpty);
  });

  test('network settings reach every call', () {
    const s = AppSettings(
      proxy: ' socks5://127.0.0.1:1080 ',
      forceIpv4: true,
      userAgent: 'Agent',
    );
    expect(networkArgs(s), [
      '--proxy',
      'socks5://127.0.0.1:1080',
      '-4',
      '--user-agent',
      'Agent',
    ]);
  });

  test('cover art only goes into containers that take it', () {
    const s = AppSettings(embedThumbnail: true);
    expect(downloadArgs(s, _video), contains('--embed-thumbnail'));
    expect(downloadArgs(s, _audio), isNot(contains('--embed-thumbnail')));
    // Converting the opus stream to MP3 makes room for it.
    expect(
      downloadArgs(s.copyWith(audioFormat: AudioFormat.mp3), _audio),
      containsAllInOrder([
        '-x',
        '--audio-format',
        'mp3',
        '--audio-quality',
        '2',
        '--ppa',
        'ExtractAudio:-compression_level 7',
        '--embed-thumbnail',
      ]),
    );
  });

  test('subtitles are embedded in videos only', () {
    const s = AppSettings(subtitles: true, subtitleLanguage: 'bn');
    expect(
      downloadArgs(s, _video),
      containsAllInOrder([
        '--sub-langs',
        'bn.*,bn,-live_chat',
        '--embed-subs',
        '--ignore-errors',
      ]),
    );
    expect(downloadArgs(s, _audio), isNot(contains('--embed-subs')));
  });

  test('a clip saves only that part', () {
    expect(
      downloadArgs(const AppSettings(), _video, clip: (start: 12, end: 90)),
      ['--download-sections', '*12-90', '--force-keyframes-at-cuts'],
    );
  });

  test('posts and photos take no media processing', () {
    const s = AppSettings(
      embedMetadata: true,
      skipSponsors: true,
      simpleFileNames: true,
    );
    const post = DownloadOption(
      type: OutputType.video,
      formatSelector: postSelector,
    );
    expect(downloadArgs(s, post), ['--restrict-filenames']);
  });

  test('MKV changes the extension of merged videos', () {
    const s = AppSettings(saveAsMkv: true);
    expect(savedExtOf(s, _video), 'mkv');
    expect(savedExtOf(s, _video.copyWith(formatSelector: '18')), 'mp4');
  });

  test('extra options come last', () {
    const s = AppSettings(speedLimitKiB: 512, extraOptions: '--no-part');
    expect(downloadArgs(s, _video), ['-r', '512K', '--no-part']);
  });

  test('file name templates and proxies are checked', () {
    expect(isFileNameTemplate(''), isTrue);
    expect(isFileNameTemplate('%(uploader)s - %(title)s'), isTrue);
    expect(isFileNameTemplate('plain'), isFalse);
    expect(isFileNameTemplate('%(title)s/x'), isFalse);
    expect(isProxyUrl('http://host:8080'), isTrue);
    expect(isProxyUrl('host:8080'), isFalse);
  });
}
