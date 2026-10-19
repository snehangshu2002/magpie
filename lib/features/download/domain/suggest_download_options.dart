import 'dart:math' as math;

import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/core/platform/models/media_info.dart';
import 'package:media_downloader/features/download/domain/download_option.dart';

/// Default video quality cap; Settings can change it.
const defaultMaxQuality = 1080;

const _imageExts = {'jpg', 'jpeg', 'png', 'webp', 'gif'};
const _audioExts = {'m4a', 'mp3', 'opus', 'ogg', 'oga', 'aac', 'flac', 'wav'};

/// Turns yt-dlp's raw format list into the few choices people care about
/// (one per video quality, one per audio container, images) and picks the
/// one that fits the link best. Returns null when nothing is downloadable.
DownloadOptions? suggestDownloadOptions(
  MediaInfo info, {
  required SourcePlatform platform,
  int maxQuality = defaultMaxQuality,
  bool preferAudioForMusic = true,
}) {
  final videos = <_Indexed>[];
  final audios = <_Indexed>[];
  final images = <_Indexed>[];
  for (final (i, f) in info.formats.indexed) {
    // Storyboards are thumbnails for the seek bar, not media.
    if (f.ext == 'mhtml') continue;
    final entry = (i, f);
    if (_isImage(f)) {
      images.add(entry);
    } else if (_hasVideo(f)) {
      videos.add(entry);
    } else if (_isAudioOnly(f)) {
      audios.add(entry);
    }
  }

  final video = _videoOptions(videos, audios);
  final audio = _audioOptions(audios, videos);
  final image = _imageOptions(images);

  final pick = preferAudioForMusic && platform.prefersAudio && audio.isNotEmpty
      ? (OutputType.audio, RecommendationReason.musicSource)
      : video.isNotEmpty
      ? (OutputType.video, RecommendationReason.bestUpToCap)
      : audio.isNotEmpty
      ? (OutputType.audio, RecommendationReason.audioOnly)
      : image.isNotEmpty
      ? (OutputType.image, RecommendationReason.imageOnly)
      : null;
  if (pick == null) return null;
  final (type, reason) = pick;

  final options = DownloadOptions(
    video: video,
    audio: audio,
    image: image,
    recommendedType: type,
    reason: reason,
    maxQuality: maxQuality,
  );
  final quality = options.recommended.quality;
  return type == OutputType.video && quality != null && quality > maxQuality
      ? options.copyWith(reason: RecommendationReason.closestToCap)
      : options;
}

/// A format with its position in yt-dlp's list, which is ordered worst to
/// best; later entries win ties.
typedef _Indexed = (int, MediaFormat);

bool _known(String? codec) => codec != null && codec != 'none';

/// yt-dlp writes `"none"` for a missing stream and leaves the field out when
/// it doesn't know; a format with a height but no codec info is a video.
bool _hasVideo(MediaFormat f) =>
    _known(f.vcodec) || (f.vcodec == null && f.height != null);

bool _isImage(MediaFormat f) =>
    _imageExts.contains(f.ext) && !_known(f.vcodec) && !_known(f.acodec);

bool _hasAudio(MediaFormat f) => _known(f.acodec) || f.acodec == null;

bool _isAudioOnly(MediaFormat f) =>
    _known(f.acodec) || (f.acodec == null && _audioExts.contains(f.ext));

int? _qualityOf(MediaFormat f) => switch ((f.width, f.height)) {
  (final int w, final int h) => math.min(w, h),
  (_, final int h) => h,
  _ => null,
};

/// Higher is better: plays everywhere (MP4, H.264), then smoothness, then
/// bitrate (approximated by size), then yt-dlp's own order.
List<int> _videoScore(_Indexed e) {
  final (i, f) = e;
  return [
    if (f.ext == 'mp4') 1 else 0,
    if (f.vcodec?.startsWith('avc') ?? false) 1 else 0,
    f.fps ?? 0,
    f.fileSize ?? 0,
    i,
  ];
}

List<int> _audioScore(_Indexed e) {
  final (i, f) = e;
  return [f.fileSize ?? 0, i];
}

_Indexed _best(
  Iterable<_Indexed> entries,
  List<int> Function(_Indexed) score,
) => entries.reduce((a, b) {
  final sa = score(a);
  final sb = score(b);
  for (var k = 0; k < sa.length; k++) {
    final c = sa[k].compareTo(sb[k]);
    if (c != 0) return c > 0 ? a : b;
  }
  return b;
});

List<DownloadOption> _videoOptions(
  List<_Indexed> videos,
  List<_Indexed> audios,
) {
  if (videos.isEmpty) return const [];

  final byQuality = <int?, List<_Indexed>>{};
  for (final e in videos) {
    (byQuality[_qualityOf(e.$2)] ??= []).add(e);
  }
  // Formats without a resolution only matter when nothing else is known.
  if (byQuality.length > 1) byQuality.remove(null);

  final qualities = byQuality.keys.toList()
    ..sort((a, b) => (b ?? 0).compareTo(a ?? 0));
  return [
    for (final q in qualities)
      _videoOption(_best(byQuality[q]!, _videoScore).$2, q, audios),
  ];
}

DownloadOption _videoOption(
  MediaFormat v,
  int? quality,
  List<_Indexed> audios,
) {
  final base = DownloadOption(
    type: OutputType.video,
    formatSelector: v.formatId,
    ext: v.ext,
    quality: quality,
    fps: v.fps,
    sizeBytes: v.fileSize,
  );
  if (_hasAudio(v) || audios.isEmpty) return base;

  // Video-only stream: merge with the best audio that fits the same
  // container, so FFmpeg can remux without re-encoding.
  final sameContainer = audios.where(
    (e) => switch (v.ext) {
      'mp4' => e.$2.ext == 'm4a',
      'webm' => e.$2.ext == 'webm',
      _ => false,
    },
  );
  final a = _best(
    sameContainer.isEmpty ? audios : sameContainer,
    _audioScore,
  ).$2;
  final ext = switch ((v.ext, a.ext)) {
    ('mp4', 'm4a') => 'mp4',
    ('webm', 'webm') => 'webm',
    _ => 'mkv',
  };
  return base.copyWith(
    formatSelector: '${v.formatId}+${a.formatId}',
    ext: ext,
    sizeBytes: v.fileSize != null && a.fileSize != null
        ? v.fileSize! + a.fileSize!
        : null,
  );
}

List<DownloadOption> _audioOptions(
  List<_Indexed> audios,
  List<_Indexed> videos,
) {
  if (audios.isEmpty) {
    // No separate audio stream: extract it from the best progressive video.
    final progressive = videos.where((e) => _hasAudio(e.$2));
    if (progressive.isEmpty) return const [];
    final v = _best(progressive, _videoScore).$2;
    return [DownloadOption(type: OutputType.audio, formatSelector: v.formatId)];
  }

  String container(MediaFormat f) =>
      (f.acodec?.startsWith('opus') ?? false) ? 'opus' : f.ext;

  final byContainer = <String, List<_Indexed>>{};
  for (final e in audios) {
    (byContainer[container(e.$2)] ??= []).add(e);
  }
  // M4A (AAC) plays everywhere, so it leads; the rest by size.
  final options =
      [
        for (final MapEntry(key: ext, value: entries) in byContainer.entries)
          (ext, _best(entries, _audioScore).$2),
      ]..sort((a, b) {
        if ((a.$1 == 'm4a') != (b.$1 == 'm4a')) return a.$1 == 'm4a' ? -1 : 1;
        return (b.$2.fileSize ?? 0).compareTo(a.$2.fileSize ?? 0);
      });
  return [
    for (final (ext, f) in options)
      DownloadOption(
        type: OutputType.audio,
        formatSelector: f.formatId,
        ext: ext,
        sizeBytes: f.fileSize,
      ),
  ];
}

List<DownloadOption> _imageOptions(List<_Indexed> images) {
  int pixels(MediaFormat f) => (f.width ?? 0) * (f.height ?? 0);
  final sorted = [...images]
    ..sort((a, b) {
      final c = pixels(b.$2).compareTo(pixels(a.$2));
      return c != 0 ? c : b.$1.compareTo(a.$1);
    });
  return [
    for (final (_, f) in sorted)
      DownloadOption(
        type: OutputType.image,
        formatSelector: f.formatId,
        ext: f.ext,
        quality: _qualityOf(f),
        sizeBytes: f.fileSize,
      ),
  ];
}
