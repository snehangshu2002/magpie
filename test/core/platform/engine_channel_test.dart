import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/core/platform/engine_channel.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/core/platform/models/engine_update_result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel(EngineChannel.methodChannelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late EngineChannel channel;

  void replyWith(Object? reply) {
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      calls.add(call);
      return reply;
    });
  }

  setUp(() {
    calls = [];
    channel = EngineChannel();
  });

  tearDown(() => messenger.setMockMethodCallHandler(methodChannel, null));

  test('init returns the yt-dlp version', () async {
    replyWith({'ytDlpVersion': '2026.01.01'});

    final info = await channel.init();

    expect(calls.single.method, 'init');
    expect(info.ytDlpVersion, '2026.01.01');
  });

  test('init allows no version before the first update', () async {
    replyWith({'ytDlpVersion': null});

    expect((await channel.init()).ytDlpVersion, isNull);
  });

  test('fetchInfo parses nested formats from the codec maps', () async {
    replyWith({
      'title': 'Test clip',
      'thumbnail': null,
      'duration': 42,
      'extractor': 'generic',
      'formats': [
        {'formatId': '18', 'ext': 'mp4', 'height': 360, 'vcodec': 'avc1'},
        {'formatId': '140', 'ext': 'm4a', 'vcodec': 'none', 'acodec': 'mp4a'},
      ],
    });

    final info = await channel.fetchInfo('https://example.com/video');

    expect(calls.single.arguments, {'url': 'https://example.com/video'});
    expect(info.title, 'Test clip');
    expect(info.duration, 42);
    expect(info.formats.map((f) => f.formatId), ['18', '140']);
    expect(info.formats.first.height, 360);
  });

  test('startDownload sends the request and returns the id', () async {
    replyWith({'id': 'abc'});

    final id = await channel.startDownload(
      const DownloadRequest(
        id: 'abc',
        url: 'https://example.com/video',
        formatId: '18',
        outputType: OutputType.video,
        targetDir: 'Download/App/Generic',
        title: 'Test video',
      ),
    );

    expect(id, 'abc');
    expect(calls.single.arguments, {
      'id': 'abc',
      'url': 'https://example.com/video',
      'formatId': '18',
      'outputType': 'video',
      'targetDir': 'Download/App/Generic',
      'title': 'Test video',
      'items': null,
    });
  });

  test('updateEngine sends the channel name', () async {
    replyWith({'status': 'alreadyUpToDate', 'version': '2026.01.01'});

    final result = await channel.updateEngine(EngineReleaseChannel.nightly);

    expect(calls.single.arguments, {'channel': 'nightly'});
    expect(result.status, EngineUpdateStatus.alreadyUpToDate);
  });
}
