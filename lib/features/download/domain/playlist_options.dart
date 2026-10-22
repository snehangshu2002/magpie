import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/core/platform/models/playlist_info.dart';
import 'package:media_downloader/features/download/domain/download_option.dart';
import 'package:media_downloader/features/download/domain/suggest_download_options.dart';

/// Video qualities a playlist can be saved in, best first; each video is
/// saved in its best quality up to the one picked.
const List<int> playlistQualities = [
  bestAvailableQuality,
  2160,
  1440,
  1080,
  720,
  480,
];

/// What a playlist offers: every video, or its audio, with the videos to
/// pick from. Null when it has none.
DownloadOptions? playlistOptions(
  PlaylistInfo info, {
  required SourcePlatform platform,
  int maxQuality = defaultMaxQuality,
  bool preferAudioForMusic = true,
}) {
  final count = info.entries.length;
  if (count == 0) return null;
  final audio = preferAudioForMusic && platform.prefersAudio;
  return DownloadOptions(
    video: [
      for (final quality in playlistQualities)
        DownloadOption(
          type: OutputType.video,
          formatSelector: 'bv*+ba/b',
          quality: quality,
          count: count,
          playlist: true,
        ),
    ],
    audio: [
      DownloadOption(
        type: OutputType.audio,
        // M4A first: it converts to M4A or MP3 without decoding Opus.
        formatSelector: 'ba[ext=m4a]/ba/b',
        count: count,
        playlist: true,
      ),
    ],
    image: const [],
    recommendedType: audio ? OutputType.audio : OutputType.video,
    reason: audio
        ? RecommendationReason.musicSource
        : RecommendationReason.bestUpToCap,
    maxQuality: maxQuality,
    postItems: [
      for (final (i, entry) in info.entries.indexed)
        (
          index: i + 1,
          type: OutputType.video,
          thumbnail: entry.thumbnail,
          duration: entry.duration,
        ),
    ],
    playlist: true,
  );
}

/// A folder name made from a playlist's [title]: no characters Android
/// refuses in a path, at most 80 long.
String playlistFolderName(String title) {
  final name = title
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
      .trim()
      .replaceAll(RegExp(r'^\.+'), '');
  final short = name.length > 80 ? name.substring(0, 80).trim() : name;
  return short.isEmpty ? 'Playlist' : short;
}
