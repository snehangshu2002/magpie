import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/core/theme/motion.dart';

void main() {
  test('standard spring starts at 0, ends exactly at 1, never reverses', () {
    final c = AppMotion.standard;
    expect(c.transform(0), 0);
    expect(c.transform(1), 1);
    expect(c.transform(0.99), closeTo(1, 0.02));
    var prev = 0.0;
    for (var i = 1; i <= 100; i++) {
      final v = c.transform(i / 100);
      expect(v, greaterThanOrEqualTo(prev));
      prev = v;
    }
  });
}
