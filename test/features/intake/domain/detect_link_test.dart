import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/features/intake/domain/detect_link.dart';
import 'package:media_downloader/features/intake/domain/detected_link.dart';

// Made-up ids only; no real media.
void main() {
  void expectLink(
    String input,
    SourcePlatform platform,
    LinkKind kind, {
    String? uri,
  }) {
    final link = detectLink(input);
    expect(link, isNotNull, reason: input);
    expect(link!.platform, platform, reason: input);
    expect(link.kind, kind, reason: input);
    if (uri != null) expect(link.uri.toString(), uri, reason: input);
  }

  group('finding the link', () {
    test('takes a full URL as is', () {
      expectLink(
        'https://www.youtube.com/watch?v=test123',
        SourcePlatform.youtube,
        LinkKind.video,
        uri: 'https://www.youtube.com/watch?v=test123',
      );
    });

    test('pulls the link out of shared text', () {
      expectLink(
        'Look at this! https://youtu.be/test123 so good',
        SourcePlatform.youtube,
        LinkKind.video,
        uri: 'https://youtu.be/test123',
      );
    });

    test('adds https to a bare link', () {
      expectLink(
        'youtu.be/test123',
        SourcePlatform.youtube,
        LinkKind.video,
        uri: 'https://youtu.be/test123',
      );
    });

    test('drops trailing punctuation from a sentence', () {
      expectLink(
        '(see https://example.com/video/1).',
        SourcePlatform.other,
        LinkKind.unknown,
        uri: 'https://example.com/video/1',
      );
    });

    test('skips dotted words that are not links', () {
      expect(detectLink('hello.world'), isNull);
      expect(
        detectLink('ok.then https://x.com/user/status/1')?.platform,
        SourcePlatform.x,
      );
    });

    test('returns null when there is no link', () {
      expect(detectLink(''), isNull);
      expect(detectLink('just some words'), isNull);
      expect(detectLink('ftp://example.com/file'), isNull);
    });
  });

  group('recognizing the site and kind', () {
    test('YouTube', () {
      expectLink(
        'https://m.youtube.com/shorts/test123',
        SourcePlatform.youtube,
        LinkKind.short,
      );
      expectLink(
        'https://www.youtube.com/playlist?list=PLtest',
        SourcePlatform.youtube,
        LinkKind.playlist,
      );
      expectLink(
        'https://music.youtube.com/watch?v=test123',
        SourcePlatform.youtubeMusic,
        LinkKind.track,
      );
    });

    test('Instagram', () {
      expectLink(
        'https://www.instagram.com/reel/TEST123/',
        SourcePlatform.instagram,
        LinkKind.reel,
      );
      expectLink(
        'https://instagram.com/p/TEST123/',
        SourcePlatform.instagram,
        LinkKind.post,
      );
      expectLink(
        'https://instagram.com/stories/someone/1/',
        SourcePlatform.instagram,
        LinkKind.story,
      );
    });

    test('X and Twitter', () {
      expectLink(
        'https://x.com/someone/status/1',
        SourcePlatform.x,
        LinkKind.post,
      );
      expectLink(
        'https://mobile.twitter.com/someone/status/1',
        SourcePlatform.x,
        LinkKind.post,
      );
    });

    test('Reddit', () {
      expectLink(
        'https://old.reddit.com/r/test/comments/abc/title/',
        SourcePlatform.reddit,
        LinkKind.post,
      );
      expectLink('https://v.redd.it/abc', SourcePlatform.reddit, LinkKind.post);
      expectLink(
        'https://www.reddit.com/r/test/s/abc',
        SourcePlatform.reddit,
        LinkKind.post,
      );
    });

    test('Facebook', () {
      expectLink(
        'https://fb.watch/abc/',
        SourcePlatform.facebook,
        LinkKind.video,
      );
      expectLink(
        'https://www.facebook.com/share/r/abc/',
        SourcePlatform.facebook,
        LinkKind.reel,
      );
    });

    test('Telegram', () {
      expectLink(
        'https://t.me/testchannel/123',
        SourcePlatform.telegram,
        LinkKind.post,
        uri: 'https://t.me/testchannel/123',
      );
      // Other forms of a public post become the one yt-dlp reads.
      expectLink(
        'https://telegram.me/testchannel/123?single',
        SourcePlatform.telegram,
        LinkKind.post,
        uri: 'https://t.me/testchannel/123',
      );
      expectLink(
        't.me/s/testchannel/123',
        SourcePlatform.telegram,
        LinkKind.post,
        uri: 'https://t.me/testchannel/123',
      );
      // Private chats need an account; a channel link has no post.
      expectLink(
        'https://t.me/c/1234567/89',
        SourcePlatform.telegram,
        LinkKind.unknown,
      );
      expectLink(
        'https://t.me/testchannel',
        SourcePlatform.telegram,
        LinkKind.unknown,
      );
    });

    test('does not mistake look-alike hosts for a site', () {
      expect(
        detectLink('https://notyoutube.com/watch?v=1')?.platform,
        SourcePlatform.other,
      );
    });
  });

  test('keeps only the video of a YouTube link opened from a playlist', () {
    expectLink(
      'https://www.youtube.com/watch?v=test123&list=PLtest&index=3&t=10',
      SourcePlatform.youtube,
      LinkKind.video,
      uri: 'https://www.youtube.com/watch?v=test123&t=10',
    );
    expectLink(
      'https://youtu.be/test123?list=PLtest',
      SourcePlatform.youtube,
      LinkKind.video,
      uri: 'https://youtu.be/test123',
    );
  });
}
