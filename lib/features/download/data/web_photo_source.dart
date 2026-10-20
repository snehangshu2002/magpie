import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/features/download/domain/web_photo.dart';

/// Finds full-size photos that yt-dlp doesn't save: photos in posts on X
/// (its public syndication endpoint, which yt-dlp also falls back to) and
/// Reddit (the post's public JSON), and links that are an image themselves.
///
/// Methods throw [IOException], [TimeoutException] or [FormatException];
/// the repository turns them into failures.
class WebPhotoSource {
  new({HttpClient Function()? client}) : _newClient = client ?? HttpClient.new;

  final HttpClient Function() _newClient;

  static const _userAgent = 'android:com.snehangshu.magpie (Magpie)';
  static const _timeout = Duration(seconds: 15);

  /// The photos of the post at [url]; null when it has none (a video post,
  /// a text post) or the site isn't one yt-dlp needs help with.
  Future<WebPhotos?> photosOf(Uri url, SourcePlatform platform) async {
    if (isImageLink(url)) return await imageAt(url);
    return await switch (platform) {
      SourcePlatform.x => _tweetPhotos(url),
      SourcePlatform.reddit => _redditPhotos(url),
      _ => Future.value(),
    };
  }

  /// The image at [url] in full size, if the link serves one.
  Future<WebPhotos?> imageAt(Uri url) => _withClient((client) async {
    final full = fullSizeImageUrl(url);
    var response = await _send(client, 'HEAD', full);
    await response.drain<void>();
    // Some servers refuse HEAD; their GET reply's headers say the same.
    if (response.statusCode == HttpStatus.methodNotAllowed ||
        response.statusCode == HttpStatus.notImplemented ||
        response.statusCode == HttpStatus.forbidden) {
      response = await _send(client, 'GET', full);
    }
    final type = response.headers.contentType;
    if (response.statusCode != HttpStatus.ok || type?.primaryType != 'image') {
      return null;
    }
    final name = full.pathSegments.lastWhere(
      (s) => s.isNotEmpty,
      orElse: () => full.host,
    );
    return WebPhotos(
      title: name.contains('.')
          ? name.substring(0, name.lastIndexOf('.'))
          : name,
      photos: [
        WebPhoto(
          url: full.toString(),
          preview: full == url ? null : url.toString(),
          ext: _extOfMime(type!.mimeType),
          sizeBytes: response.contentLength > 0 ? response.contentLength : null,
        ),
      ],
    );
  });

  Future<WebPhotos?> _tweetPhotos(Uri url) async {
    final id = tweetIdOf(url);
    if (id == null) return null;
    final json = await _getJson(
      Uri.https('cdn.syndication.twimg.com', '/tweet-result', {
        'id': id,
        'token': syndicationToken(id),
        'lang': 'en',
      }),
    );
    return json is Map<String, dynamic> ? photosFromTweet(json) : null;
  }

  Future<WebPhotos?> _redditPhotos(Uri url) async {
    var path = redditPostPath(url);
    // Share links (`/r/<sub>/s/<code>`) redirect to the post.
    if (path == null && url.pathSegments.contains('s')) {
      final target = await _withClient((client) async {
        final request = await client.openUrl('GET', url)
          ..followRedirects = false
          ..headers.set(HttpHeaders.userAgentHeader, _userAgent);
        final response = await request.close().timeout(_timeout);
        await response.drain<void>();
        return response.headers.value(HttpHeaders.locationHeader);
      });
      if (target != null) path = redditPostPath(url.resolve(target));
    }
    if (path == null) return null;
    final json = await _getJson(
      Uri.https('www.reddit.com', '/$path/.json', {'raw_json': '1'}),
    );
    return photosFromRedditListing(json);
  }

  Future<Object?> _getJson(Uri url) => _withClient((client) async {
    final response = await _send(client, 'GET', url);
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode == HttpStatus.notFound) return null;
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode}', uri: url);
    }
    return jsonDecode(body);
  });

  Future<HttpClientResponse> _send(
    HttpClient client,
    String method,
    Uri url,
  ) async {
    final request = await client.openUrl(method, url).timeout(_timeout);
    request.headers
      ..set(HttpHeaders.userAgentHeader, _userAgent)
      ..set(HttpHeaders.acceptHeader, '*/*');
    return await request.close().timeout(_timeout);
  }

  Future<T> _withClient<T>(Future<T> Function(HttpClient) body) async {
    final client = _newClient()..connectionTimeout = _timeout;
    try {
      return await body(client);
    } finally {
      client.close(force: true);
    }
  }
}

String? _extOfMime(String mime) => switch (mime) {
  'image/jpeg' || 'image/jpg' || 'image/pjpeg' => 'jpg',
  'image/png' => 'png',
  'image/webp' => 'webp',
  'image/gif' => 'gif',
  'image/avif' => 'avif',
  'image/heic' || 'image/heif' => 'heic',
  _ => null,
};

/// The full-size version of an image link where the site serves smaller
/// copies under another URL: X's `name=small` → `name=orig`, Reddit's
/// `preview.redd.it` → the `i.redd.it` original. Other links stay as they are.
Uri fullSizeImageUrl(Uri url) {
  if (url.host == 'pbs.twimg.com' && url.path.startsWith('/media/')) {
    return _tweetPhotoUrl(url, 'orig');
  }
  if (url.host == 'preview.redd.it' && imageExtOf(url.path) != null) {
    return Uri.https('i.redd.it', url.path);
  }
  return url;
}

/// `pbs.twimg.com/media/<id>?format=<ext>&name=<size>` for a photo URL in
/// either form (`/media/<id>.jpg` or `/media/<id>?format=jpg`).
Uri _tweetPhotoUrl(Uri url, String size) {
  final ext = imageExtOf(url.path);
  final path = ext == null
      ? url.path
      : url.path.substring(0, url.path.length - ext.length - 1);
  return Uri.https(url.host, path, {
    'format': ext ?? url.queryParameters['format'] ?? 'jpg',
    'name': size,
  });
}

/// The tweet id of an X/Twitter post link (`/<user>/status/<id>`,
/// `/i/web/status/<id>`, `/statuses/<id>`), or null.
String? tweetIdOf(Uri url) {
  final segments = url.pathSegments;
  for (var i = 0; i < segments.length - 1; i++) {
    if (segments[i] == 'status' || segments[i] == 'statuses') {
      final id = segments[i + 1];
      return RegExp(r'^\d+$').hasMatch(id) ? id : null;
    }
  }
  return null;
}

/// The token X's syndication endpoint expects for [tweetId]: JavaScript's
/// `((id / 1e15) * Math.PI).toString(36)` without zeros and the point.
String syndicationToken(String tweetId) => _jsRadixString(
  int.parse(tweetId) / 1e15 * math.pi,
  36,
).replaceAll(RegExp(r'0+|\.'), '');

/// JavaScript's `Number.prototype.toString(radix)` for a positive finite
/// number (ECMAScript's shortest digits that read back as [value]); a port
/// of yt-dlp's `js_number_to_string`.
String _jsRadixString(double value, int radix) {
  const alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';
  var integer = value.truncateToDouble();
  var fraction = value - integer;
  var delta = math.max(double.minPositive, (_nextUp(value) - value) / 2);
  final digits = <int>[];
  final hasPoint = fraction >= delta;
  while (fraction >= delta) {
    delta *= radix;
    final scaled = fraction * radix;
    final digit = scaled.truncate();
    fraction = scaled - digit;
    digits.add(digit);
    // Round, carrying into earlier digits (and the integer part) as needed.
    final roundUp = fraction > 0.5 || (fraction == 0.5 && digit.isOdd);
    if (roundUp && fraction + delta > 1) {
      var carried = false;
      while (digits.isNotEmpty) {
        if (digits.last + 1 < radix) {
          digits.last++;
          carried = true;
          break;
        }
        digits.removeLast();
      }
      if (!carried) integer += 1;
      break;
    }
  }
  return [
    integer.toInt().toRadixString(radix),
    if (hasPoint) '.',
    for (final d in digits) alphabet[d],
  ].join();
}

double _nextUp(double value) {
  final bits = ByteData(8)..setFloat64(0, value);
  return (bits..setInt64(0, bits.getInt64(0) + 1)).getFloat64(0);
}

/// The photos of a tweet from X's syndication JSON, or those of the tweet
/// it quotes when it has none itself; null when there are none.
WebPhotos? photosFromTweet(Map<String, dynamic> tweet) {
  List<WebPhoto> photosOf(Object? tweet) => [
    if (tweet case {'mediaDetails': final List<Object?> media})
      for (final item in media)
        if (item case {'type': 'photo', 'media_url_https': final String url})
          _tweetPhoto(Uri.parse(url), item['original_info']),
  ];

  var photos = photosOf(tweet);
  if (photos.isEmpty) photos = photosOf(tweet['quoted_tweet']);
  if (photos.isEmpty) return null;
  final text = switch (tweet['text']) {
    // Photo links (t.co) at the end of the text say nothing.
    final String text => text.replaceAll(RegExp(r'\s*https://t\.co/\S+'), ''),
    _ => '',
  }.replaceAll(RegExp(r'\s+'), ' ').trim();
  final name = switch (tweet['user']) {
    {'name': final String name} => name,
    _ => null,
  };
  return WebPhotos(
    photos: photos,
    title: text.isEmpty
        ? name
        : text.length > 72
        ? '${text.substring(0, 72).trimRight()}…'
        : text,
  );
}

WebPhoto _tweetPhoto(Uri url, Object? info) {
  final full = _tweetPhotoUrl(url, 'orig');
  return WebPhoto(
    url: full.toString(),
    preview: _tweetPhotoUrl(url, 'small').toString(),
    ext: full.queryParameters['format'],
    width: switch (info) {
      {'width': final int w} => w,
      _ => null,
    },
    height: switch (info) {
      {'height': final int h} => h,
      _ => null,
    },
  );
}

/// `comments/<id>` (with its `r/<sub>/` prefix, if any) of a Reddit post
/// link, as yt-dlp's Reddit extractor reads it; null for other links.
String? redditPostPath(Uri url) {
  if (url.host == 'redd.it' && url.pathSegments.isNotEmpty) {
    return 'comments/${url.pathSegments.first}';
  }
  final match = RegExp('^/((?:(?:r|user|u)/[^/]+/)?comments/[^/?#&]+)')
      .firstMatch(url.path);
  return match?.group(1);
}

/// The photos of a Reddit post from its `.json` listing: every image of a
/// gallery, in order, or the post's single image; null for other posts.
/// A crosspost uses the original post's photos.
WebPhotos? photosFromRedditListing(Object? json) {
  if (json case [
    {'data': {'children': [{'data': final Map<String, dynamic> post}, ...]}},
    ...,
  ]) {
    var photos = _redditPhotos(post);
    if (photos.isEmpty) {
      if (post case {
        'crosspost_parent_list': [final Map<String, dynamic> p, ...],
      }) {
        photos = _redditPhotos(p);
      }
    }
    if (photos.isEmpty) return null;
    return WebPhotos(
      photos: photos,
      title: switch (post['title']) {
        final String title => title,
        _ => null,
      },
    );
  }
  return null;
}

List<WebPhoto> _redditPhotos(Map<String, dynamic> post) {
  if (post case {
    'gallery_data': {'items': final List<Object?> items},
    'media_metadata': final Map<String, dynamic> media,
  }) {
    return [
      for (final item in items)
        if (item case {'media_id': final String id})
          ?_galleryPhoto(id, media[id]),
    ];
  }
  final link = switch (post['url_overridden_by_dest'] ?? post['url']) {
    final String url => Uri.tryParse(url),
    _ => null,
  };
  if (link == null || !isImageLink(link)) return const [];
  final full = fullSizeImageUrl(link);
  final (source, preview) = switch (post['preview']) {
    {'images': [final Map<String, dynamic> image, ...]} => (
      image['source'],
      _redditPreview(image['resolutions'], 'url', 'width'),
    ),
    _ => (null, null),
  };
  return [
    WebPhoto(
      url: full.toString(),
      preview: preview,
      ext: imageExtOf(full.path),
      width: switch (source) {
        {'width': final int w} => w,
        _ => null,
      },
      height: switch (source) {
        {'height': final int h} => h,
        _ => null,
      },
    ),
  ];
}

/// The original of one gallery item: `i.redd.it/<id>.<ext>` for an image,
/// the GIF for an animated one; null for anything else (videos, failed
/// uploads).
WebPhoto? _galleryPhoto(String id, Object? meta) {
  if (meta is! Map<String, dynamic>) return null;
  if (meta['status'] case final String status when status != 'valid') {
    return null;
  }
  final preview = _redditPreview(meta['p'], 'u', 'x');
  final (width, height) = switch (meta['s']) {
    {'x': final int x, 'y': final int y} => (x, y),
    _ => (null, null),
  };
  switch (meta) {
    case {'e': 'Image', 'm': final String mime}:
      final ext = _extOfMime(mime) ?? 'jpg';
      return WebPhoto(
        url: 'https://i.redd.it/$id.$ext',
        preview: preview,
        ext: ext,
        width: width,
        height: height,
      );
    case {'e': 'AnimatedImage', 's': {'gif': final String gif}}:
      return WebPhoto(
        url: gif,
        preview: preview,
        ext: 'gif',
        width: width,
        height: height,
      );
  }
  return null;
}

/// A preview about 640 wide from Reddit's list of smaller copies (smallest
/// first), for the picker; null when there are none.
String? _redditPreview(Object? copies, String urlKey, String widthKey) {
  if (copies is! List<Object?> || copies.isEmpty) return null;
  String? best;
  for (final copy in copies) {
    if (copy is! Map<String, dynamic>) continue;
    final (url, width) = (copy[urlKey], copy[widthKey]);
    if (url is! String) continue;
    if (best == null || (width is int && width <= 640)) best = url;
  }
  return best;
}
