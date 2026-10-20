import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/core/platform/models/media_info.dart';
import 'package:media_downloader/features/download/domain/transcript.dart';

// Made-up captions only.
void main() {
  group('transcriptFromVtt', () {
    test('keeps only the words, one line each', () {
      const vtt = '''
WEBVTT
Kind: captions
Language: en

NOTE
This is a comment
over two lines

1
00:00:00.000 --> 00:00:02.000
Hello <b>there</b> &amp; welcome

2
00:00:02.000 --> 00:00:04.000 align:start position:0%
to the test video
''';
      expect(
        transcriptFromVtt(vtt),
        'Hello there & welcome\nto the test video',
      );
    });

    test("drops the lines YouTube's rolling captions repeat", () {
      const vtt = '''
WEBVTT

00:00:00.000 --> 00:00:01.000
first line<00:00:00.500><c> of</c>

00:00:01.000 --> 00:00:01.010
first line of

00:00:01.010 --> 00:00:02.000
first line of
second line
''';
      expect(transcriptFromVtt(vtt), 'first line of\nsecond line');
    });

    test('is empty for captions without words', () {
      expect(
        transcriptFromVtt('WEBVTT\n\n00:00:00.000 --> 00:00:01.000\n'),
        '',
      );
    });
  });

  group('defaultCaption', () {
    const autoEn = CaptionTrack(lang: 'en-orig', auto: true);
    const hindi = CaptionTrack(lang: 'hi', name: 'Hindi');
    const english = CaptionTrack(lang: 'en-US', name: 'English');

    test("prefers the uploader's subtitles in the app's language", () {
      expect(defaultCaption([autoEn, hindi, english]), english);
    });

    test('then any of their subtitles, then automatic ones', () {
      expect(defaultCaption([autoEn, hindi]), hindi);
      expect(defaultCaption([autoEn]), autoEn);
      expect(defaultCaption([]), isNull);
    });
  });
}
