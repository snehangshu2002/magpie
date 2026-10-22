import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/features/download/domain/web_photo.dart';

/// Finds full-size photos that yt-dlp doesn't save: photos in posts on X
/// (its public syndication endpoint, which yt-dlp also falls back to) and
/// links that are an image themselves.
///
/// Methods throw [IOException], [TimeoutException] or [FormatException];
/// the repository turns them into failures.
class WebPhotoSource {
  new({HttpClient Function()? client}) : _newClient = client ?? HttpClient.new;

  final HttpClient Function() _newClient;

  static const userAgent = 'android:com.snehangshu.magpie (Magpie)';
  static const _timeout = Duration(seconds: 15);

  /// The photos of the post at [url]; null when it has none (a video post,
  /// a text post) or the site isn't one yt-dlp needs help with. [options]
  /// are `networkArgs`: their proxy, `-4` and user agent apply here too.
  Future<WebPhotos?> photosOf(
    Uri url,
    SourcePlatform platform, {
    List<String> options = const [],
  }) async {
    if (isImageLink(url)) return await imageAt(url, options: options);
    return await switch (platform) {
      SourcePlatform.x => _tweetPhotos(url, options),
      _ => Future.value(),
    };
  }

  /// The image at [url] in full size, if the link serves one.
  Future<WebPhotos?> imageAt(
    Uri url, {
    List<String> options = const [],
  }) => _withClient(options, (client) async {
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

  /// The body of [url], e.g. a thumbnail to show.
  Future<Uint8List> bytesOf(Uri url, {List<String> options = const []}) =>
      _withClient(options, (client) async {
        final response = await _send(client, 'GET', url);
        if (response.statusCode != HttpStatus.ok) {
          await response.drain<void>();
          throw HttpException('HTTP ${response.statusCode}', uri: url);
        }
        final bytes = BytesBuilder(copy: false);
        await response.forEach(bytes.add);
        return bytes.takeBytes();
      });

  Future<WebPhotos?> _tweetPhotos(Uri url, List<String> options) async {
    final id = tweetIdOf(url);
    if (id == null) return null;
    final json = await _getJson(
      Uri.https('cdn.syndication.twimg.com', '/tweet-result', {
        'id': id,
        'token': syndicationToken(id),
        'lang': 'en',
      }),
      options,
    );
    return json is Map<String, dynamic> ? photosFromTweet(json) : null;
  }

  Future<Object?> _getJson(Uri url, List<String> options) =>
      _withClient(options, (client) async {
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
    request.headers.set(HttpHeaders.acceptHeader, '*/*');
    return await request.close().timeout(_timeout);
  }

  Future<T> _withClient<T>(
    List<String> options,
    Future<T> Function(HttpClient) body,
  ) async {
    final client = _newClient()..connectionTimeout = _timeout;
    applyNetworkOptions(client, options, defaultUserAgent: userAgent);
    try {
      return await body(client);
    } finally {
      client.close(force: true);
    }
  }
}

/// Sets up [client] for yt-dlp's network [options] (`networkArgs`): the
/// last `--proxy`, `-4` and the last `--user-agent` (else
/// [defaultUserAgent]), as yt-dlp reads them.
void applyNetworkOptions(
  HttpClient client,
  List<String> options, {
  required String defaultUserAgent,
}) {
  String? valueOf(String name) {
    final i = options.lastIndexOf(name);
    return i >= 0 && i + 1 < options.length ? options[i + 1] : null;
  }

  client.userAgent = valueOf('--user-agent') ?? defaultUserAgent;
  final proxy = Uri.tryParse(valueOf('--proxy') ?? '');
  // shortcut: HttpClient speaks only to plain HTTP proxies, so https:// and
  // SOCKS proxies are skipped and these lookups go direct; upgrade with a
  // SOCKS/TLS-capable client if users rely on those proxies for privacy.
  if (proxy != null && proxy.scheme == 'http' && proxy.host.isNotEmpty) {
    final auth = proxy.userInfo.isEmpty ? '' : '${proxy.userInfo}@';
    final directive = 'PROXY $auth${proxy.host}:${proxy.port}';
    client.findProxy = (_) => directive;
  }
  if (options.contains('-4')) {
    client.connectionFactory = (url, proxyHost, proxyPort) async {
      final host = proxyHost ?? url.host;
      final addresses = await InternetAddress.lookup(
        host,
        type: InternetAddressType.IPv4,
      );
      final task = await Socket.startConnect(
        addresses.first,
        proxyPort ?? url.port,
      );
      // HttpClient expects TLS already set up for https without a proxy.
      if (proxyHost != null || url.scheme != 'https') return task;
      return ConnectionTask.fromSocket(
        task.socket.then((s) => SecureSocket.secure(s, host: url.host)),
        task.cancel,
      );
    };
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
