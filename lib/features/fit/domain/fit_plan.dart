import 'dart:math';

/// Sizes a copy can be made to fit, smallest first.
enum ShareSize {
  /// Discord's limit without Nitro.
  mb10(10 * 1000 * 1000),
  mb16(16 * 1000 * 1000),
  mb25(25 * 1000 * 1000),
  mb50(50 * 1000 * 1000);

  new(this.bytes);

  final int bytes;
}

/// What it takes to get a video under a size; see [planFit].
sealed class FitPlan {
  const new();
}

/// The video is already that small; share it as it is.
final class FitAlreadyFits extends FitPlan {
  const new();
}

/// The video is too long to fit at a bitrate worth watching.
final class FitTooLong extends FitPlan {
  const new();
}

/// Re-encode at these settings.
final class FitEncode extends FitPlan {
  const new({
    required this.videoKbps,
    required this.audioKbps,
    required this.shortSide,
    required this.estimatedBytes,
  });

  final int videoKbps;

  /// 0 when the video has no sound.
  final int audioKbps;

  /// The copy's shorter side in pixels, e.g. 720.
  final int shortSide;

  /// Roughly how big the copy will be; always under the target.
  final int estimatedBytes;

  @override
  String toString() =>
      'FitEncode(${videoKbps}k + ${audioKbps}k, ${shortSide}p, '
      '$estimatedBytes B)';
}

/// Share of the target spent on audio and video; the rest leaves room for
/// the MP4 container and an encoder that runs a little over.
const fitBudgetShare = 0.94;

/// Below this, video is too blocky to be worth sending.
const minFitVideoKbps = 100;

/// Plans a copy of a video [durationMs] long that fits in [targetBytes].
///
/// The bitrate is what the target allows over the video's length, minus
/// audio; the resolution is the largest that bitrate still looks good at,
/// but never above the source's own ([width] × [height], when known).
FitPlan planFit({
  required int targetBytes,
  required int durationMs,
  required bool hasAudio,
  int? sourceBytes,
  int? width,
  int? height,
}) {
  assert(durationMs > 0, 'planFit needs the video length');
  if (sourceBytes != null && sourceBytes <= targetBytes) {
    return const FitAlreadyFits();
  }

  // bytes * 8 = bits, and bits per millisecond = kilobits per second.
  final budgetKbps = targetBytes * 8 * fitBudgetShare / durationMs;
  final audioKbps = !hasAudio
      ? 0
      : budgetKbps >= 1500
      ? 128
      : budgetKbps >= 600
      ? 96
      : budgetKbps >= 250
      ? 64
      : 48;
  final videoKbps = (budgetKbps - audioKbps).floor();
  if (videoKbps < minFitVideoKbps) return const FitTooLong();

  var shortSide = switch (videoKbps) {
    >= 2500 => 1080,
    >= 1200 => 720,
    >= 600 => 480,
    >= 300 => 360,
    _ => 240,
  };
  if (width != null && height != null) {
    // Even, as H.264 needs; and never upscaled.
    shortSide = min(shortSide, min(width, height)) & ~1;
  }

  return FitEncode(
    videoKbps: videoKbps,
    audioKbps: audioKbps,
    shortSide: shortSide,
    estimatedBytes: ((videoKbps + audioKbps) * durationMs / 8).round(),
  );
}

/// The size the sheet picks first: the smallest one the video can be made
/// to fit, or the smallest of all when it fits none.
ShareSize defaultShareSize(Map<ShareSize, FitPlan> plans) =>
    ShareSize.values.firstWhere(
      (size) => plans[size] is! FitTooLong,
      orElse: () => ShareSize.values.first,
    );
