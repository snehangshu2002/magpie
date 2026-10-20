import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/core/media/source_platform.dart';

void main() {
  test('maps yt-dlp extractor names to platforms', () {
    expect(SourcePlatform.fromExtractor('youtube'), SourcePlatform.youtube);
    expect(SourcePlatform.fromExtractor('youtube:tab'), SourcePlatform.youtube);
    expect(SourcePlatform.fromExtractor('Instagram'), SourcePlatform.instagram);
    expect(SourcePlatform.fromExtractor('twitter'), SourcePlatform.x);
    expect(
      SourcePlatform.fromExtractor('telegram:embed'),
      SourcePlatform.telegram,
    );
    expect(SourcePlatform.fromExtractor('generic'), SourcePlatform.other);
  });

  test('names a download folder for every platform', () {
    expect(SourcePlatform.youtube.folderName, 'YouTube');
    expect(SourcePlatform.youtubeMusic.folderName, 'YouTube');
    expect(SourcePlatform.x.folderName, 'X');
    expect(SourcePlatform.telegram.folderName, 'Telegram');
    expect(SourcePlatform.other.folderName, 'Other');
  });

  test('prefers audio only for music sites', () {
    expect(
      [
        for (final p in SourcePlatform.values)
          if (p.prefersAudio) p,
      ],
      [SourcePlatform.youtubeMusic],
    );
  });
}
