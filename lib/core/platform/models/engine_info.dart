import 'package:freezed_annotation/freezed_annotation.dart';

part 'engine_info.freezed.dart';
part 'engine_info.g.dart';

/// Reply to `init`.
@freezed
abstract class EngineInfo with _$EngineInfo {
  const factory({required String ytDlpVersion}) = _EngineInfo;

  factory fromJson(Map<String, dynamic> json) => _$EngineInfoFromJson(json);
}
