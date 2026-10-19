import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/errors/platform_failure.dart';
import 'package:media_downloader/core/utils/result.dart';

void main() {
  Future<Failure> failureFor(Exception error) async {
    final result = await guardPlatformCall<void>(() => throw error);
    return (result as Err<void>).failure;
  }

  test('returns Ok when the call succeeds', () async {
    final result = await guardPlatformCall(() async => 'v1');

    expect(result, isA<Ok<String>>().having((r) => r.value, 'value', 'v1'));
  });

  test('maps native error codes to failures', () async {
    expect(
      await failureFor(PlatformException(code: NativeErrorCode.unsupportedUrl)),
      isA<UnsupportedUrlFailure>(),
    );
    expect(
      await failureFor(PlatformException(code: NativeErrorCode.network)),
      isA<NetworkFailure>(),
    );
    expect(
      await failureFor(PlatformException(code: NativeErrorCode.cancelled)),
      isA<CancelledFailure>(),
    );
    expect(
      await failureFor(PlatformException(code: 'SOMETHING_NEW')),
      isA<UnknownFailure>(),
    );
  });

  test('treats a missing native handler as an engine failure', () async {
    expect(
      await failureFor(MissingPluginException('startDownload')),
      isA<EngineFailure>(),
    );
  });
}
