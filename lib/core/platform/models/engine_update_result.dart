import 'package:freezed_annotation/freezed_annotation.dart';

part 'engine_update_result.freezed.dart';
part 'engine_update_result.g.dart';

enum EngineReleaseChannel { stable, nightly }

enum EngineUpdateStatus { done, alreadyUpToDate }

/// Reply to `updateEngine`.
@freezed
abstract class EngineUpdateResult with _$EngineUpdateResult {
  const factory EngineUpdateResult({
    required EngineUpdateStatus status,
    required String version,
  }) = _EngineUpdateResult;

  factory EngineUpdateResult.fromJson(Map<String, dynamic> json) =>
      _$EngineUpdateResultFromJson(json);
}
