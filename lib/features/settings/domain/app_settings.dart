import 'package:media_downloader/core/platform/models/engine_update_result.dart';
import 'package:media_downloader/features/download/domain/suggest_download_options.dart';

/// What the user chose in Settings.
final class AppSettings {
  const new({
    this.maxQuality = defaultMaxQuality,
    this.preferAudioForMusic = true,
    this.engineChannel = EngineReleaseChannel.stable,
  });

  /// Video qualities offered as the default cap, highest first.
  static const qualities = [2160, 1440, 1080, 720, 480, 360];

  /// Highest video quality picked by default (short side in pixels).
  final int maxQuality;

  /// Suggest audio for music sites (YouTube Music, SoundCloud).
  final bool preferAudioForMusic;

  /// Where engine updates come from.
  final EngineReleaseChannel engineChannel;

  AppSettings copyWith({
    int? maxQuality,
    bool? preferAudioForMusic,
    EngineReleaseChannel? engineChannel,
  }) => AppSettings(
    maxQuality: maxQuality ?? this.maxQuality,
    preferAudioForMusic: preferAudioForMusic ?? this.preferAudioForMusic,
    engineChannel: engineChannel ?? this.engineChannel,
  );
}
