import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/features/fit/domain/video_tool.dart';

void main() {
  const minute = 60 * 1000;

  test('the sound alone is an M4A of the whole video', () {
    final job = planVideoJob(VideoTool.audio, durationMs: minute);
    expect(job.ext, 'm4a');
    expect(job.type, OutputType.audio);
    expect(job.inputArgs, isEmpty);
    expect(job.outputArgs, contains('-vn'));
    expect(job.durationMs, minute);
  });

  test('a part is copied between the two moments, in the same container', () {
    final job = planVideoJob(
      VideoTool.trim,
      durationMs: minute,
      sourceExt: 'WEBM',
      startMs: 5000,
      endMs: 20500,
    );
    expect(job.ext, 'webm');
    expect(job.inputArgs, ['-ss', '5.000', '-to', '20.500']);
    expect(job.outputArgs, containsAllInOrder(['-c', 'copy']));
    expect(job.durationMs, 15500);
  });

  test('a part outside the video is pulled back inside it', () {
    final job = planVideoJob(
      VideoTool.trim,
      durationMs: minute,
      startMs: 50000,
      endMs: 90000,
    );
    expect(job.inputArgs, ['-ss', '50.000', '-to', '60.000']);
    // An unknown container can't be trusted to take the copied streams.
    expect(job.ext, 'mkv');
  });

  test('a GIF is cut at 30 seconds', () {
    final job = planVideoJob(VideoTool.gif, durationMs: 5 * minute);
    expect(job.ext, 'gif');
    expect(job.type, OutputType.image);
    expect(job.durationMs, maxGifMs);
    expect(job.inputArgs, ['-ss', '0.000', '-to', '30.000']);
  });

  test('mute and MP4 keep the picture', () {
    expect(
      planVideoJob(VideoTool.mute, durationMs: minute, sourceExt: 'mp4').ext,
      'mp4',
    );
    final mp4 = planVideoJob(VideoTool.mp4, durationMs: minute);
    expect(mp4.ext, 'mp4');
    expect(mp4.outputArgs, contains('libx264'));
  });
}
