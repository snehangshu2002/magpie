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

/// What audio downloads are saved as; [original] keeps the site's file.
enum AudioFormat { original, mp3, m4a, opus }

/// What the user chose in Settings.
final class AppSettings {
  const new({
    this.maxQuality = defaultMaxQuality,
    this.preferAudioForMusic = true,
    this.appearance = AppearanceMode.system,
    this.font = AppFont.system,
    this.saveFolder = defaultSaveFolder,
    this.audioFolder = '',
    this.wallpaperColors = false,
    this.pureBlack = false,
    this.downloadRightAway = false,
    this.askOnMobileData = false,
    this.skipDownloaded = false,
    this.keepHistory = true,
    this.audioFormat = AudioFormat.original,
    this.embedThumbnail = false,
    this.squareCover = false,
    this.embedMetadata = false,
    this.subtitles = false,
    this.subtitleLanguage = 'en',
    this.autoCaptions = false,
    this.skipSponsors = false,
    this.saveAsMkv = false,
    this.speedLimitKiB = 0,
    this.parallelPieces = false,
    this.aria2 = false,
    this.proxy = '',
    this.forceIpv4 = false,
    this.userAgent = '',
    this.fileNameTemplate = '',
    this.simpleFileNames = false,
    this.extraOptions = '',
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

  /// Download speed caps offered, in KiB/s; 0 is no limit.
  static const List<int> speedLimits = [0, 256, 512, 1024, 2048, 5120, 10240];

  /// Subtitle languages offered (yt-dlp language codes).
  static const List<String> subtitleLanguages = [
    'en', 'es', 'pt', 'fr', 'de', 'it', 'ru', 'uk', 'pl', 'tr', 'ar', //
    'fa', 'hi', 'bn', 'ur', 'id', 'vi', 'th', 'ja', 'ko', 'zh',
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

  /// Folder for audio downloads; empty means [saveFolder].
  final String audioFolder;

  /// Colours from the wallpaper (Android 12+) instead of the sage palette.
  final bool wallpaperColors;

  /// Black backgrounds in the dark theme.
  final bool pureBlack;

  /// Start the suggested download as soon as a link is read.
  final bool downloadRightAway;

  /// Ask before downloading on mobile data (a metered network).
  final bool askOnMobileData;

  /// Don't save a video (or a playlist's video) saved before.
  final bool skipDownloaded;

  /// List finished downloads in the Library; off saves files without a trace
  /// in the app.
  final bool keepHistory;

  final AudioFormat audioFormat;

  /// Put the thumbnail into the file as cover art.
  final bool embedThumbnail;

  /// Crop audio cover art to a square.
  final bool squareCover;

  /// Put title, artist and date into the file.
  final bool embedMetadata;

  /// Put subtitles in [subtitleLanguage] into saved videos.
  final bool subtitles;
  final String subtitleLanguage;

  /// Also use automatic captions when there are no subtitles.
  final bool autoCaptions;

  /// Cut sponsor segments out of YouTube videos (SponsorBlock).
  final bool skipSponsors;

  /// Merge video and audio into MKV instead of the source's container.
  final bool saveAsMkv;

  /// 0: no limit.
  final int speedLimitKiB;

  /// Download several parts of a video at once.
  final bool parallelPieces;

  /// Use aria2 as the downloader.
  final bool aria2;

  /// e.g. `socks5://127.0.0.1:1080`; empty for none.
  final String proxy;
  final bool forceIpv4;

  /// Empty: yt-dlp's own.
  final String userAgent;

  /// yt-dlp output template for file names, e.g. `%(uploader)s - %(title)s`;
  /// empty for the title.
  final String fileNameTemplate;

  /// Only ASCII letters, digits and `_-.` in file names.
  final bool simpleFileNames;

  /// Extra yt-dlp arguments, as typed on a command line.
  final String extraOptions;

  AppSettings copyWith({
    int? maxQuality,
    bool? preferAudioForMusic,
    AppearanceMode? appearance,
    AppFont? font,
    String? saveFolder,
    String? audioFolder,
    bool? wallpaperColors,
    bool? pureBlack,
    bool? downloadRightAway,
    bool? askOnMobileData,
    bool? skipDownloaded,
    bool? keepHistory,
    AudioFormat? audioFormat,
    bool? embedThumbnail,
    bool? squareCover,
    bool? embedMetadata,
    bool? subtitles,
    String? subtitleLanguage,
    bool? autoCaptions,
    bool? skipSponsors,
    bool? saveAsMkv,
    int? speedLimitKiB,
    bool? parallelPieces,
    bool? aria2,
    String? proxy,
    bool? forceIpv4,
    String? userAgent,
    String? fileNameTemplate,
    bool? simpleFileNames,
    String? extraOptions,
  }) => AppSettings(
    maxQuality: maxQuality ?? this.maxQuality,
    preferAudioForMusic: preferAudioForMusic ?? this.preferAudioForMusic,
    appearance: appearance ?? this.appearance,
    font: font ?? this.font,
    saveFolder: saveFolder ?? this.saveFolder,
    audioFolder: audioFolder ?? this.audioFolder,
    wallpaperColors: wallpaperColors ?? this.wallpaperColors,
    pureBlack: pureBlack ?? this.pureBlack,
    downloadRightAway: downloadRightAway ?? this.downloadRightAway,
    askOnMobileData: askOnMobileData ?? this.askOnMobileData,
    skipDownloaded: skipDownloaded ?? this.skipDownloaded,
    keepHistory: keepHistory ?? this.keepHistory,
    audioFormat: audioFormat ?? this.audioFormat,
    embedThumbnail: embedThumbnail ?? this.embedThumbnail,
    squareCover: squareCover ?? this.squareCover,
    embedMetadata: embedMetadata ?? this.embedMetadata,
    subtitles: subtitles ?? this.subtitles,
    subtitleLanguage: subtitleLanguage ?? this.subtitleLanguage,
    autoCaptions: autoCaptions ?? this.autoCaptions,
    skipSponsors: skipSponsors ?? this.skipSponsors,
    saveAsMkv: saveAsMkv ?? this.saveAsMkv,
    speedLimitKiB: speedLimitKiB ?? this.speedLimitKiB,
    parallelPieces: parallelPieces ?? this.parallelPieces,
    aria2: aria2 ?? this.aria2,
    proxy: proxy ?? this.proxy,
    forceIpv4: forceIpv4 ?? this.forceIpv4,
    userAgent: userAgent ?? this.userAgent,
    fileNameTemplate: fileNameTemplate ?? this.fileNameTemplate,
    simpleFileNames: simpleFileNames ?? this.simpleFileNames,
    extraOptions: extraOptions ?? this.extraOptions,
  );
}
