import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/features/fit/domain/fit_plan.dart';

void main() {
  const minute = 60 * 1000;

  FitEncode encode(FitPlan plan) => plan as FitEncode;

  test('a video already under the size is shared as it is', () {
    expect(
      planFit(
        targetBytes: ShareSize.mb10.bytes,
        durationMs: minute,
        hasAudio: true,
        sourceBytes: 9 * 1000 * 1000,
      ),
      isA<FitAlreadyFits>(),
    );
  });

  test('spends the budget on video and audio, under the target', () {
    // 10 MB over a minute: 10e6 * 8 * 0.94 / 60000 = 1253 kbps.
    final plan = encode(
      planFit(
        targetBytes: ShareSize.mb10.bytes,
        durationMs: minute,
        hasAudio: true,
        sourceBytes: 80 * 1000 * 1000,
        width: 1920,
        height: 1080,
      ),
    );

    expect(plan.audioKbps, 96);
    expect(plan.videoKbps, 1157);
    expect(plan.shortSide, 480);
    expect(plan.estimatedBytes, lessThan(ShareSize.mb10.bytes));
    expect(plan.estimatedBytes, greaterThan(ShareSize.mb10.bytes * 0.9));
  });

  test('short clips keep a high resolution and full audio', () {
    final plan = encode(
      planFit(
        targetBytes: ShareSize.mb25.bytes,
        durationMs: 30 * 1000,
        hasAudio: true,
        width: 3840,
        height: 2160,
      ),
    );

    expect(plan.audioKbps, 128);
    expect(plan.shortSide, 1080);
  });

  test('never upscales, and keeps the short side even', () {
    final plan = encode(
      planFit(
        targetBytes: ShareSize.mb50.bytes,
        durationMs: 10 * 1000,
        hasAudio: true,
        // Portrait 361 x 640: the short side is the width.
        width: 361,
        height: 640,
      ),
    );

    expect(plan.shortSide, 360);
  });

  test('a silent video gives all of the budget to the picture', () {
    final plan = encode(
      planFit(
        targetBytes: ShareSize.mb10.bytes,
        durationMs: minute,
        hasAudio: false,
      ),
    );

    expect(plan.audioKbps, 0);
    expect(plan.videoKbps, 1253);
  });

  test('a long video that would be unwatchable at the size is too long', () {
    expect(
      planFit(
        targetBytes: ShareSize.mb10.bytes,
        durationMs: 30 * minute,
        hasAudio: true,
      ),
      isA<FitTooLong>(),
    );
  });

  test('picks the smallest size the video can be made to fit', () {
    expect(
      defaultShareSize({
        ShareSize.mb10: const FitTooLong(),
        ShareSize.mb16: const FitTooLong(),
        ShareSize.mb25: const FitAlreadyFits(),
        ShareSize.mb50: const FitAlreadyFits(),
      }),
      ShareSize.mb25,
    );
    expect(
      defaultShareSize({
        for (final size in ShareSize.values) size: const FitTooLong(),
      }),
      ShareSize.mb10,
    );
  });
}
