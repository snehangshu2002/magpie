import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/features/download/data/web_photo_source.dart';
import 'package:media_downloader/features/download/domain/web_photo.dart';

// Made-up ids, titles and media keys only; no real posts or media.
void main() {
  group('syndicationToken', () {
    // Expected values from Node: ((id / 1e15) * Math.PI).toString(36)
    // .replace(/(0+|\.)/g, '').
    const expected = {
      '20': '6dq1a2xwd93',
      '463440424141459456': '14fxvks611f',
      '1234567890123456789': '2zqic77uqyk',
      '1600009362759733248': '3vmksnaiclg',
      '1800000000000000000': '4d2v7cbm2xj',
      '1987654321098765432': '4tgeeoc83v9',
    };
    for (final MapEntry(key: id, value: token) in expected.entries) {
      test('matches JavaScript for $id', () {
        expect(syndicationToken(id), token);
      });
    }
  });

  test('tweetIdOf reads the usual post links', () {
    for (final link in [
      'https://x.com/someone/status/1234567890',
      'https://twitter.com/someone/status/1234567890/photo/2',
      'https://mobile.twitter.com/i/web/status/1234567890',
      'https://twitter.com/statuses/1234567890',
    ]) {
      expect(tweetIdOf(Uri.parse(link)), '1234567890', reason: link);
    }
    expect(tweetIdOf(Uri.parse('https://x.com/someone')), isNull);
    expect(tweetIdOf(Uri.parse('https://x.com/a/status/abc')), isNull);
  });

  group('photosFromTweet', () {
    Map<String, dynamic> photo(String key, {String ext = 'jpg'}) => {
      'type': 'photo',
      'media_url_https': 'https://pbs.twimg.com/media/$key.$ext',
      'original_info': {'width': 2048, 'height': 1536},
    };

    test('asks for the original size of each photo', () {
      final photos = photosFromTweet({
        'text': 'Test photos https://t.co/abc123',
        'user': {'name': 'Tester'},
        'mediaDetails': [
          photo('AAA'),
          {'type': 'video', 'media_url_https': 'https://example.com/v.jpg'},
          photo('BBB', ext: 'png'),
        ],
      })!;

      expect(photos.title, 'Test photos');
      expect(photos.photos.map((p) => p.url), [
        'https://pbs.twimg.com/media/AAA?format=jpg&name=orig',
        'https://pbs.twimg.com/media/BBB?format=png&name=orig',
      ]);
      expect(
        photos.photos.first.preview,
        'https://pbs.twimg.com/media/AAA?format=jpg&name=small',
      );
      expect(photos.photos.first.width, 2048);
      expect(photos.photos.last.ext, 'png');
    });

    test("uses a quoted tweet's photos when it has none", () {
      final photos = photosFromTweet({
        'text': '',
        'user': {'name': 'Tester'},
        'quoted_tweet': {
          'mediaDetails': [photo('CCC')],
        },
      })!;

      expect(photos.title, 'Tester');
      expect(photos.photos.single.url, contains('CCC'));
    });

    test('returns null for a tweet without photos', () {
      expect(photosFromTweet({'text': 'Just words'}), isNull);
    });
  });

  test('fullSizeImageUrl upgrades known preview links', () {
    expect(
      fullSizeImageUrl(
        Uri.parse('https://pbs.twimg.com/media/AAA?format=jpg&name=small'),
      ).toString(),
      'https://pbs.twimg.com/media/AAA?format=jpg&name=orig',
    );
    expect(
      fullSizeImageUrl(
        Uri.parse('https://preview.redd.it/abc.jpg?width=640&s=sig'),
      ).toString(),
      'https://i.redd.it/abc.jpg',
    );
    final other = Uri.parse('https://example.com/a.jpg?w=200');
    expect(fullSizeImageUrl(other), other);
  });

  test('isImageLink spots image files', () {
    expect(isImageLink(Uri.parse('https://example.com/a/b.JPG')), isTrue);
    expect(isImageLink(Uri.parse('https://example.com/a.webp?x=1')), isTrue);
    expect(isImageLink(Uri.parse('https://pbs.twimg.com/media/AAA')), isTrue);
    expect(isImageLink(Uri.parse('https://example.com/post/1')), isFalse);
  });

  group('photosFromTelegramEmbed', () {
    // A trimmed, made-up embed page in Telegram's markup.
    String embed({String text = 'Test album &amp; more<br/>line two'}) =>
        '''
<div class="tgme_widget_message_author accent_color"><a class="tgme_widget_message_owner_name" href="https://t.me/testchannel"><span dir="auto">Test Channel</span></a></div>
<div class="tgme_widget_message_grouped_wrap">
<a class="tgme_widget_message_photo_wrap grouped_media_wrap 1 2" href="https://t.me/testchannel/10?single" style="width:800px;background-image:url('https://cdn.example.org/file/aaa.jpg')"></a>
<a class="tgme_widget_message_photo_wrap grouped_media_wrap 3 4" href="https://t.me/testchannel/11?single" style="width:1280px;background-image:url('https://cdn.example.org/file/bbb.jpg')"></a>
</div>
<div class="tgme_widget_message_text js-message_text" dir="auto">$text</div>
''';

    test('lists every photo of an album, in order', () {
      final photos = photosFromTelegramEmbed(embed())!;

      expect(photos.photos.map((p) => p.url), [
        'https://cdn.example.org/file/aaa.jpg',
        'https://cdn.example.org/file/bbb.jpg',
      ]);
      expect(photos.photos.map((p) => p.width), [800, 1280]);
      expect(photos.photos.first.ext, 'jpg');
      expect(photos.title, 'Test album & more line two');
    });

    test("uses the channel's name when the post has no text", () {
      expect(photosFromTelegramEmbed(embed(text: ''))!.title, 'Test Channel');
    });

    test('returns null for a post without photos', () {
      expect(
        photosFromTelegramEmbed(
          '<a class="tgme_widget_message_video_player" href="#"></a>',
        ),
        isNull,
      );
    });
  });
}
