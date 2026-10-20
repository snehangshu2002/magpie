import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/features/intake/domain/detected_link.dart';

/// Finds the first web link in [input] and recognizes its site.
///
/// [input] may be a bare link (`youtu.be/abc`), a full URL, or shared text
/// that contains one ("Watch this https://…"). Returns null when there is no
/// usable link. Cheap enough to run on every keystroke.
DetectedLink? detectLink(String input) {
  for (final match in _linkPattern.allMatches(input)) {
    final raw = match[0]!.replaceFirst(_trailingPunctuation, '');
    final hasScheme = raw.contains('://');
    final uri = Uri.tryParse(hasScheme ? raw : 'https://$raw');
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      continue;
    }
    final host = uri.host.toLowerCase();
    if (!host.contains('.')) continue;

    final platform = SourcePlatform.fromHost(host);
    // Without a scheme, "hello.world" in a sentence would count as a link;
    // require a path or a known site so only real links are picked up.
    if (!hasScheme && platform == SourcePlatform.other && uri.path.isEmpty) {
      continue;
    }

    final kind = _kindOf(platform, host, uri);
    return DetectedLink(
      uri: platform == SourcePlatform.telegram
          ? telegramPostUri(uri) ?? uri
          : _withoutPlaylist(platform, kind, uri),
      platform: platform,
      kind: kind,
    );
  }
  return null;
}

/// A full http(s) URL, or a bare `domain.tld/path` that doesn't start in
/// the middle of another word or URL (e.g. the host of `ftp://…`).
final _linkPattern = RegExp(
  r'https?://\S+|(?<![\w.:/@-])(?:[a-z0-9-]+\.)+[a-z]{2,}(?:/\S*)?',
  caseSensitive: false,
);

final _trailingPunctuation = RegExp('[)\\]}>.,;:!?\'"»”’]+\$');

LinkKind _kindOf(SourcePlatform platform, String host, Uri uri) {
  final path = [
    for (final s in uri.pathSegments)
      if (s.isNotEmpty) s.toLowerCase(),
  ];
  final first = path.firstOrNull;
  final second = path.elementAtOrNull(1);
  bool has(String segment) => path.contains(segment);

  switch (platform) {
    case SourcePlatform.youtube || SourcePlatform.youtubeMusic:
      if (first == 'playlist') return LinkKind.playlist;
      final isWatch = first == 'watch';
      if (isWatch &&
          !uri.queryParameters.containsKey('v') &&
          uri.queryParameters.containsKey('list')) {
        return LinkKind.playlist;
      }
      if (platform == SourcePlatform.youtubeMusic) {
        return isWatch ? LinkKind.track : LinkKind.unknown;
      }
      if (first == 'shorts') return LinkKind.short;
      if (isWatch || host.endsWith('youtu.be')) return LinkKind.video;
      return switch (first) {
        'live' || 'embed' || 'v' => LinkKind.video,
        _ => LinkKind.unknown,
      };
    case SourcePlatform.instagram:
      return switch (first) {
        'reel' || 'reels' => LinkKind.reel,
        'p' => LinkKind.post,
        'stories' => LinkKind.story,
        'tv' => LinkKind.video,
        _ => LinkKind.unknown,
      };
    case SourcePlatform.x:
      return has('status') ? LinkKind.post : LinkKind.unknown;
    case SourcePlatform.reddit:
      if (host.endsWith('redd.it') || has('comments') || has('s')) {
        return LinkKind.post;
      }
      return LinkKind.unknown;
    case SourcePlatform.facebook:
      if (host.endsWith('fb.watch') || first == 'watch' || has('videos')) {
        return LinkKind.video;
      }
      if (first == 'reel') return LinkKind.reel;
      if (first == 'share') {
        return switch (second) {
          'v' => LinkKind.video,
          'r' => LinkKind.reel,
          _ => LinkKind.post,
        };
      }
      return LinkKind.unknown;
    case SourcePlatform.telegram:
      return telegramPostUri(uri) != null ? LinkKind.post : LinkKind.unknown;
    case SourcePlatform.other:
      return LinkKind.unknown;
  }
}

/// `https://t.me/<channel>/<id>`, the form yt-dlp reads, for a public
/// channel post link: also `telegram.me` and the `t.me/s/<channel>/<id>`
/// web preview. Null for anything else, e.g. private `t.me/c/...` links,
/// which need a signed-in account.
Uri? telegramPostUri(Uri uri) {
  var path = [
    for (final s in uri.pathSegments)
      if (s.isNotEmpty) s,
  ];
  if (path.firstOrNull == 's') path = path.skip(1).toList();
  if (path case [final channel, final id]
      when channel != 'c' && RegExp(r'^\d+$').hasMatch(id)) {
    return Uri.https('t.me', '/$channel/$id');
  }
  return null;
}

/// A YouTube video opened from a playlist carries `list=`, which makes
/// yt-dlp fetch the whole playlist. Playlists aren't supported yet, so keep
/// only the video.
Uri _withoutPlaylist(SourcePlatform platform, LinkKind kind, Uri uri) {
  const playlistParams = {'list', 'index', 'start_radio'};
  final isYouTube =
      platform == SourcePlatform.youtube ||
      platform == SourcePlatform.youtubeMusic;
  if (!isYouTube || kind == LinkKind.playlist) return uri;
  if (!uri.queryParameters.keys.any(playlistParams.contains)) return uri;

  final query = {
    for (final MapEntry(:key, :value) in uri.queryParametersAll.entries)
      if (!playlistParams.contains(key)) key: value,
  };
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
    queryParameters: query.isEmpty ? null : query,
    fragment: uri.hasFragment ? uri.fragment : null,
  );
}
