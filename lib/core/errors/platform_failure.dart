import 'package:flutter/services.dart';
import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/utils/result.dart';

/// Error codes the native side puts in `PlatformException.code`.
///
/// Keep in sync with `EngineErrors` in `YtDlpBridge.kt` and CLAUDE.md.
abstract final class NativeErrorCode {
  static const unsupportedUrl = 'UNSUPPORTED_URL';
  static const network = 'NETWORK';
  static const engine = 'ENGINE';
  static const storage = 'STORAGE';
  static const cancelled = 'CANCELLED';
}

Failure failureFromPlatformException(PlatformException e) => switch (e.code) {
  NativeErrorCode.unsupportedUrl => Failure.unsupportedUrl(detail: e.message),
  NativeErrorCode.network => Failure.network(detail: e.message),
  NativeErrorCode.engine => Failure.engine(detail: e.message),
  NativeErrorCode.storage => Failure.storage(detail: e.message),
  NativeErrorCode.cancelled => const Failure.cancelled(),
  _ => Failure.unknown(detail: '${e.code}: ${e.message}'),
};

/// Runs a platform call and converts native errors into a [Result], so
/// repositories never throw across layers.
Future<Result<T>> guardPlatformCall<T>(Future<T> Function() call) async {
  try {
    return Ok(await call());
  } on PlatformException catch (e) {
    return Err(failureFromPlatformException(e));
  } on MissingPluginException catch (e) {
    return Err(Failure.engine(detail: e.message));
  }
}
