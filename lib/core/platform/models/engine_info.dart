import 'package:freezed_annotation/freezed_annotation.dart';

part 'engine_info.freezed.dart';
part 'engine_info.g.dart';

/// Reply to `init`.
@freezed
abstract class EngineInfo with _$EngineInfo {
  const factory({
    /// Null until the engine is first updated: youtubedl-android records
    /// a version only when it installs one, not for the bundled build.
    String? ytDlpVersion,
  }) = _EngineInfo;

  factory fromJson(Map<String, dynamic> json) => _$EngineInfoFromJson(json);
}
