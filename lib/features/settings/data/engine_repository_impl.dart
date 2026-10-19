import 'package:media_downloader/core/errors/platform_failure.dart';
import 'package:media_downloader/core/platform/engine_channel.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/settings/domain/engine_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'engine_repository_impl.g.dart';

class EngineRepositoryImpl implements EngineRepository {
  EngineRepositoryImpl(this._channel);

  final EngineChannel _channel;

  @override
  Future<Result<String>> initialize() =>
      guardPlatformCall(() async => (await _channel.init()).ytDlpVersion);
}

@Riverpod(keepAlive: true)
EngineRepository engineRepository(Ref ref) =>
    EngineRepositoryImpl(ref.watch(engineChannelProvider));
