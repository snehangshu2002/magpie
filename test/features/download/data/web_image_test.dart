import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/features/download/data/web_image.dart';

void main() {
  test('equal url and settings share one cache entry', () {
    // Settings build a new list each time; the image must not reload.
    List<String> ipv4() => ['-4'];
    final a = WebImage('https://example.com/a.jpg', options: ipv4());
    final b = WebImage('https://example.com/a.jpg', options: ipv4());

    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(const WebImage('https://example.com/a.jpg')));
    expect(a, isNot(WebImage('https://example.com/b.jpg', options: ipv4())));
  });
}
