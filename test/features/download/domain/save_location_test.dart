import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/features/download/domain/save_location.dart';

void main() {
  test('puts each site in its own folder', () {
    expect(
      saveDirFor('Download/Clips', SourcePlatform.youtube),
      'Download/Clips/YouTube',
    );
  });

  test('accepts folders the picker returns inside Download', () {
    expect(saveFolderFromTreeId('primary:Download'), 'Download');
    expect(saveFolderFromTreeId('primary:Download/Clips/'), 'Download/Clips');
    expect(saveFolderFromTreeId('primary:Download/A/B'), 'Download/A/B');
  });

  test('refuses folders elsewhere or on another volume', () {
    expect(saveFolderFromTreeId('primary:DCIM/Camera'), isNull);
    expect(saveFolderFromTreeId('primary:Downloads'), isNull);
    expect(saveFolderFromTreeId('1234-ABCD:Download/Clips'), isNull);
    expect(saveFolderFromTreeId('primary:'), isNull);
  });
}
