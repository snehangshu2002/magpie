import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/features/updater/domain/app_update.dart';

void main() {
  test('compares dotted versions numerically', () {
    expect(isNewerVersion('v1.0.10', '1.0.9'), isTrue);
    expect(isNewerVersion('v1.1', '1.0.9'), isTrue);
    expect(isNewerVersion('v1.0.0', '1.0.0'), isFalse);
    expect(isNewerVersion('v1.0', '1.0.0'), isFalse);
    expect(isNewerVersion('v0.9.9', '1.0.0'), isFalse);
    expect(isNewerVersion('v1.2.0-beta', '1.1.0+7'), isTrue);
  });

  test('picks the APK for the first supported ABI', () {
    const apks = {
      'magpie-1.2.0-armeabi-v7a.apk': 'v7',
      'magpie-1.2.0-arm64-v8a.apk': 'v8',
      'magpie-1.2.0-x86_64.apk': 'x64',
    };
    expect(apkFor(apks, ['arm64-v8a', 'armeabi-v7a']), 'v8');
    expect(apkFor(apks, ['x86', 'armeabi-v7a']), 'v7');
    expect(apkFor(apks, ['mips']), isNull);
  });
}
