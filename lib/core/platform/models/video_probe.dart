import 'package:freezed_annotation/freezed_annotation.dart';

part 'video_probe.freezed.dart';
part 'video_probe.g.dart';

/// What a saved video file says about itself; reply of `probeVideo`.
@freezed
abstract class VideoProbe with _$VideoProbe {
  const factory({
    /// Null when the file doesn't say.
    int? durationMs,

    /// As stored, before rotation; null when unknown.
    int? width,
    int? height,
    @Default(false) bool hasAudio,
  }) = _VideoProbe;

  factory fromJson(Map<String, dynamic> json) => _$VideoProbeFromJson(json);
}
