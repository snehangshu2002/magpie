import 'dart:math';

import 'package:media_downloader/core/platform/models/download_request.dart';

/// What can be made from a saved video.
enum VideoTool {
  /// Only the sound, as an M4A file.
  audio,

  /// A part of it, between two moments.
  trim,

  /// The picture without the sound.
  mute,

  /// An H.264/AAC MP4, which every app plays.
  mp4,

  /// A short animated GIF.
  gif;

  /// Whether the tool works on a part of the video picked by the user.
  bool get hasRange => this == trim || this == gif;
}

/// The longest GIF made; they get big fast.
const int maxGifMs = 30 * 1000;

/// An FFmpeg run that makes a [VideoTool]'s file.
final class VideoJob {
  const new({
    required this.ext,
    required this.type,
    required this.inputArgs,
    required this.outputArgs,
    required this.durationMs,
  });

  final String ext;
  final OutputType type;

  /// FFmpeg arguments placed before the input.
  final List<String> inputArgs;

  /// FFmpeg arguments placed between the input and the output.
  final List<String> outputArgs;

  /// Length of the result.
  final int durationMs;

  String? get mimeType => switch (ext) {
    'm4a' => 'audio/mp4',
    'gif' => 'image/gif',
    'mp4' => 'video/mp4',
    _ => null,
  };
}

/// How FFmpeg makes [tool]'s file from a video [durationMs] long, saved as
/// [sourceExt]. [startMs] and [endMs] pick the part for tools that take one
/// ([VideoTool.hasRange]); a GIF is cut at [maxGifMs].
VideoJob planVideoJob(
  VideoTool tool, {
  required int durationMs,
  String? sourceExt,
  int startMs = 0,
  int? endMs,
}) {
  // Containers that take a copied stream as it is.
  final sameExt = switch (sourceExt?.toLowerCase()) {
    final ext? when const {'mp4', 'mkv', 'webm', 'mov'}.contains(ext) => ext,
    _ => 'mkv',
  };
  var start = 0;
  var end = durationMs;
  if (tool.hasRange) {
    start = startMs.clamp(0, durationMs);
    end = (endMs ?? durationMs).clamp(start, durationMs);
    if (tool == VideoTool.gif) end = min(end, start + maxGifMs);
  }
  String seconds(int ms) => (ms / 1000).toStringAsFixed(3);
  final range = tool.hasRange
      ? ['-ss', seconds(start), '-to', seconds(end)]
      : const <String>[];

  return switch (tool) {
    VideoTool.audio => VideoJob(
      ext: 'm4a',
      type: OutputType.audio,
      inputArgs: range,
      outputArgs: const ['-vn', '-c:a', 'aac', '-b:a', '192k'],
      durationMs: end - start,
    ),
    // Copies the streams, so it is quick and loses nothing; the cut lands
    // on the key frame before the start.
    VideoTool.trim => VideoJob(
      ext: sameExt,
      type: OutputType.video,
      inputArgs: range,
      outputArgs: const [
        '-map', '0:v:0', '-map', '0:a?', //
        '-c', 'copy', '-avoid_negative_ts', 'make_zero',
      ],
      durationMs: end - start,
    ),
    VideoTool.mute => VideoJob(
      ext: sameExt,
      type: OutputType.video,
      inputArgs: range,
      outputArgs: const ['-map', '0:v:0', '-c:v', 'copy', '-an'],
      durationMs: end - start,
    ),
    VideoTool.mp4 => VideoJob(
      ext: 'mp4',
      type: OutputType.video,
      inputArgs: range,
      outputArgs: const [
        '-map', '0:v:0', '-map', '0:a:0?', //
        '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '23', //
        '-vf', 'format=yuv420p', //
        '-c:a', 'aac', '-b:a', '160k', '-movflags', '+faststart',
      ],
      durationMs: end - start,
    ),
    VideoTool.gif => VideoJob(
      ext: 'gif',
      type: OutputType.image,
      inputArgs: range,
      outputArgs: const [
        '-an', //
        '-vf', "fps=12,scale='min(480,iw)':-2:flags=lanczos", //
        '-loop', '0',
      ],
      durationMs: end - start,
    ),
  };
}
