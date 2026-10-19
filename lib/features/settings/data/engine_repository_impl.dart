import 'package:media_downloader/core/errors/platform_failure.dart';
import 'package:media_downloader/core/platform/engine_channel.dart';
import 'package:media_downloader/core/platform/models/engine_update_result.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/settings/domain/engine_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'engine_repository_impl.g.dart';

class EngineRepositoryImpl implements EngineRepository {
  new(this._channel);

  final EngineChannel _channel;

  @override
  Future<Result<String?>> initialize() =>
      guardPlatformCall(() async => (await _channel.init()).ytDlpVersion);

  @override
  Future<Result<EngineUpdateResult>> update(EngineReleaseChannel channel) =>
      guardPlatformCall(() => _channel.updateEngine(channel));
}

@Riverpod(keepAlive: true)
EngineRepository engineRepository(Ref ref) =>
    EngineRepositoryImpl(ref.watch(engineChannelProvider));
