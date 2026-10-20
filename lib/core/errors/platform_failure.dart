import 'package:flutter/services.dart';
import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/utils/result.dart';

/// Error codes the native side puts in `PlatformException.code`.
///
/// Keep in sync with `EngineErrors.kt` and CLAUDE.md.
abstract final class NativeErrorCode {
  static const unsupportedUrl = 'UNSUPPORTED_URL';
  static const network = 'NETWORK';
  static const engine = 'ENGINE';
  static const storage = 'STORAGE';
  static const cancelled = 'CANCELLED';
  static const notFound = 'NOT_FOUND';
  static const noApp = 'NO_APP';
  static const tooLarge = 'TOO_LARGE';
  static const encode = 'ENCODE';
}

Failure failureFromPlatformException(PlatformException e) =>
    failureFromNativeCode(e.code, e.message);

/// Maps a native error code, from a [PlatformException] or a `failed`
/// progress event, to a [Failure].
Failure failureFromNativeCode(String? code, [String? detail]) => switch (code) {
  NativeErrorCode.unsupportedUrl => Failure.unsupportedUrl(detail: detail),
  NativeErrorCode.network => Failure.network(detail: detail),
  NativeErrorCode.engine => Failure.engine(detail: detail),
  NativeErrorCode.storage => Failure.storage(detail: detail),
  NativeErrorCode.cancelled => const Failure.cancelled(),
  NativeErrorCode.notFound => Failure.notFound(detail: detail),
  NativeErrorCode.noApp => Failure.noApp(detail: detail),
  NativeErrorCode.tooLarge => Failure.tooLarge(detail: detail),
  NativeErrorCode.encode => Failure.encode(detail: detail),
  _ => Failure.unknown(detail: '$code: $detail'),
};

/// Runs a platform call and converts native errors into a [Result], so
/// repositories never throw across layers.
Future<Result<T>> guardPlatformCall<T>(Future<T> Function() call) async {
  try {
    return Ok(await call());
  } on PlatformException catch (e) {
    return Err(failureFromPlatformException(e));
  } on MissingPluginException catch (e) {
    return Err(Failure.unavailable(detail: e.message));
  }
}
