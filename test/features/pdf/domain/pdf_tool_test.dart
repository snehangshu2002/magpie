import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/features/pdf/domain/pdf_tool.dart';

void main() {
  test('reads page lists with ranges and open ends', () {
    expect(parsePageRange('1-3, 5', 10), [1, 2, 3, 5]);
    expect(parsePageRange('8-', 10), [8, 9, 10]);
    expect(parsePageRange(' 4 , 2,4', 10), [4, 2]);
    expect(parsePageRange('7 - 7', 10), [7]);
  });

  test('refuses pages that are not there or not numbers', () {
    expect(parsePageRange('', 10), isNull);
    expect(parsePageRange(' , ', 10), isNull);
    expect(parsePageRange('0', 10), isNull);
    expect(parsePageRange('11', 10), isNull);
    expect(parsePageRange('5-3', 10), isNull);
    expect(parsePageRange('2-12', 10), isNull);
    expect(parsePageRange('a', 10), isNull);
    expect(parsePageRange('1-2-3', 10), isNull);
  });

  test('deleting keeps the other pages; nothing left is refused', () {
    expect(pagesFor(PdfTool.delete, [2, 4], 5), [1, 3, 5]);
    expect(pagesFor(PdfTool.delete, [1, 2, 3], 3), isNull);
    expect(pagesFor(PdfTool.extract, [5, 1, 3], 5), [1, 3, 5]);
    expect(pagesFor(PdfTool.rotate, [3, 1], 5), [3, 1]);
  });
}
