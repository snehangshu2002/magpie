import 'package:media_downloader/features/download/domain/save_location.dart';
import 'package:media_downloader/features/download/domain/suggest_download_options.dart';

/// Light or dark look; [system] follows the phone.
enum AppearanceMode { system, light, dark }

/// Typeface for the whole app; [system] is the phone's own.
enum AppFont {
  system(null),
  sans('Inter'),
  serif('SourceSerif4');

  new(this.family);

  /// Font family bundled in pubspec.yaml; null for the phone's font.
  final String? family;
}

/// What the user chose in Settings.
final class AppSettings {
  const new({
    this.maxQuality = defaultMaxQuality,
    this.preferAudioForMusic = true,
    this.appearance = AppearanceMode.system,
    this.font = AppFont.system,
    this.saveFolder = defaultSaveFolder,
  });

  /// Video qualities offered as the default cap, highest first.
  static const List<int> qualities = [
    bestAvailableQuality,
    2160,
    1440,
    1080,
    720,
    480,
    360,
  ];

  /// Highest video quality picked by default (short side in pixels).
  final int maxQuality;

  /// Suggest audio for music sites (YouTube Music).
  final bool preferAudioForMusic;

  final AppearanceMode appearance;
  final AppFont font;

  /// Folder under shared storage that downloads go into, e.g.
  /// `Download/Magpie`; each site gets a subfolder.
  final String saveFolder;

  AppSettings copyWith({
    int? maxQuality,
    bool? preferAudioForMusic,
    AppearanceMode? appearance,
    AppFont? font,
    String? saveFolder,
  }) => AppSettings(
    maxQuality: maxQuality ?? this.maxQuality,
    preferAudioForMusic: preferAudioForMusic ?? this.preferAudioForMusic,
    appearance: appearance ?? this.appearance,
    font: font ?? this.font,
    saveFolder: saveFolder ?? this.saveFolder,
  );
}
