import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/core/utils/formatters.dart';
import 'package:media_downloader/l10n/app_localizations_en.dart';

void main() {
  final l10n = AppLocalizationsEn();

  test('formatByteSize promotes to the next unit instead of printing 1000', () {
    expect(formatByteSize(48000000, l10n), '48 MB');
    expect(formatByteSize(999600, l10n), isNot(contains('1000')));
    expect(formatByteSize(999600, l10n), contains('MB'));
    expect(formatByteSize(999600000, l10n), contains('GB'));
  });
}
