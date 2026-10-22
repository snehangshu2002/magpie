import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/core/platform/models/media_info.dart';
import 'package:media_downloader/features/download/domain/download_option.dart';
import 'package:media_downloader/features/download/domain/suggest_download_options.dart';
import 'package:media_downloader/features/settings/domain/app_settings.dart';

/// A part of a video to save, in whole seconds.
typedef ClipRange = ({int start, int end});

/// yt-dlp arguments for every call that reaches a site: reading a link,
/// fetching captions, downloading.
List<String> networkArgs(AppSettings s) => [
  if (s.proxy.trim() case final proxy when proxy.isNotEmpty) ...[
    '--proxy',
    proxy,
  ],
  if (s.forceIpv4) '-4',
  if (s.userAgent.trim() case final agent when agent.isNotEmpty) ...[
    '--user-agent',
    agent,
  ],
];

/// Containers yt-dlp puts cover art into with FFmpeg alone; others (opus,
/// webm) would fail the download.
const _coverArtExts = {'mp3', 'm4a', 'mp4', 'm4v', 'mov', 'mkv', 'mka'};

/// Every sponsor-like segment SponsorBlock marks that isn't the video itself.
const _sponsorCategories = 'sponsor,selfpromo,interaction';

/// The extension of the file [option] saves with [s]; null when only the
/// engine knows (a playlist, or a merge it decides).
String? savedExtOf(AppSettings s, DownloadOption option) =>
    switch (option.type) {
      OutputType.audio when s.audioFormat != AudioFormat.original =>
        s.audioFormat.name,
      OutputType.video
          when s.saveAsMkv && option.formatSelector.contains('+') =>
        'mkv',
      _ => option.ext,
    };

/// The yt-dlp arguments for downloading [option] with the user's settings
/// [s]; [clip] saves only that part. Posts and photos only take the
/// network and file name settings: their files are handled one by one.
List<String> downloadArgs(
  AppSettings s,
  DownloadOption option, {
  ClipRange? clip,
}) {
  final media =
      option.formatSelector != postSelector &&
      option.formatSelector != photosSelector &&
      option.type != OutputType.image;
  final audio = option.type == OutputType.audio;
  final video = option.type == OutputType.video;
  final ext = savedExtOf(s, option);
  final quality = option.quality;

  return [
    ...networkArgs(s),
    if (s.speedLimitKiB > 0) ...['-r', '${s.speedLimitKiB}K'],
    if (s.parallelPieces) ...['-N', '4'],
    if (s.simpleFileNames) '--restrict-filenames',
    if (media) ...[
      if (option.playlist &&
          video &&
          quality != null &&
          quality != bestAvailableQuality) ...[
        '-S',
        'res:$quality',
      ],
      if (audio && s.audioFormat != AudioFormat.original) ...[
        '-x',
        '--audio-format',
        s.audioFormat.name,
        '--audio-quality',
        if (s.audioFormat == AudioFormat.mp3) ...[
          // VBR V2 (~190 kbps) at LAME's faster setting: half the encoding
          // time of V0 on a phone (6 s against 12 s for 10 minutes), and
          // smaller, from sources that are ~160 kbps anyway.
          '2',
          '--ppa',
          'ExtractAudio:-compression_level 7',
        ] else
          '0',
      ],
      if (video && s.saveAsMkv) ...['--merge-output-format', 'mkv'],
      if (video && s.subtitles) ...[
        '--write-subs',
        if (s.autoCaptions) '--write-auto-subs',
        '--sub-langs',
        '${s.subtitleLanguage}.*,${s.subtitleLanguage},-live_chat',
        '--embed-subs',
        // A subtitle the site won't serve (YouTube's 429 rate limit) is a
        // warning then, not a failed download; the video saves without it.
        '--ignore-errors',
      ],
      if (s.embedMetadata) '--embed-metadata',
      if (s.embedThumbnail && _coverArtExts.contains(ext)) ...[
        '--embed-thumbnail',
        if (audio && s.squareCover) ...[
          // Always converts (sites serve JPEG or WebP), so the crop runs.
          '--convert-thumbnails',
          'png',
          '--ppa',
          "ThumbnailsConvertor+FFmpeg_o:-vf crop=\"'min(iw,ih)':'min(iw,ih)'\"",
        ],
      ],
      if (s.skipSponsors) ...['--sponsorblock-remove', _sponsorCategories],
      if (clip != null) ...[
        '--download-sections',
        '*${clip.start}-${clip.end}',
        '--force-keyframes-at-cuts',
      ],
    ],
    ...?tryParseArgs(s.extraOptions),
  ];
}

/// Options the engine sets itself; changing them would lose the file.
const _reservedOptions = {
  '-o',
  '--output',
  '-P',
  '--paths',
  '-a',
  '--batch-file',
};

/// What is wrong with [text] as extra yt-dlp options: an unclosed quote
/// (`'"'`) or an option the app sets itself (`'-o'`); null when usable.
String? extraOptionsProblem(String text) {
  final args = tryParseArgs(text);
  if (args == null) return '"';
  for (final arg in args) {
    final name = arg.split('=').first;
    if (_reservedOptions.contains(name)) return name;
  }
  return null;
}

/// Whether [template] can name files: yt-dlp fields, no folders.
bool isFileNameTemplate(String template) {
  final t = template.trim();
  return t.isEmpty || (t.contains('%(') && !t.contains('/'));
}

/// Whether [proxy] is a proxy URL yt-dlp takes, or empty for none.
bool isProxyUrl(String proxy) {
  final p = proxy.trim();
  if (p.isEmpty) return true;
  final uri = Uri.tryParse(p);
  const schemes = {'http', 'https', 'socks4', 'socks4a', 'socks5', 'socks5h'};
  return uri != null && schemes.contains(uri.scheme) && uri.host.isNotEmpty;
}

/// Splits [text] into arguments the way a shell does: spaces separate them,
/// quotes group them and backslash escapes outside single quotes. Null for
/// an unclosed quote.
List<String>? tryParseArgs(String text) {
  final args = <String>[];
  final current = StringBuffer();
  var started = false;
  String? quote;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quote == "'") {
      if (c == "'") {
        quote = null;
      } else {
        current.write(c);
      }
    } else if (c == r'\' && i + 1 < text.length) {
      current.write(text[++i]);
      started = true;
    } else if (quote == '"') {
      if (c == '"') {
        quote = null;
      } else {
        current.write(c);
      }
    } else if (c == '"' || c == "'") {
      quote = c;
      started = true;
    } else if (c.trim().isEmpty) {
      if (started) args.add(current.toString());
      current.clear();
      started = false;
    } else {
      current.write(c);
      started = true;
    }
  }
  if (quote != null) return null;
  if (started) args.add(current.toString());
  return args;
}

/// `<extractor> <id>` of the one video [option] saves from [info], the key
/// yt-dlp's own archive uses; null for posts, photos or an unknown id.
String? videoKeyOf(MediaInfo info, DownloadOption option) {
  final id = info.id;
  if (id == null ||
      info.extractor.isEmpty ||
      option.formatSelector == postSelector ||
      option.formatSelector == photosSelector) {
    return null;
  }
  return '${info.extractor.toLowerCase()} $id';
}
