import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/features/image_edit/domain/image_plan.dart';

void main() {
  test('fits inside the box and keeps the proportions', () {
    expect(scaledSize(4000, 3000, maxWidth: 1000), (width: 1000, height: 750));
    expect(scaledSize(4000, 3000, maxHeight: 300), (width: 400, height: 300));
    expect(scaledSize(4000, 3000, maxWidth: 1000, maxHeight: 300), (
      width: 400,
      height: 300,
    ));
  });

  test('never bigger than the source, never under a pixel', () {
    expect(scaledSize(800, 600, maxWidth: 5000), (width: 800, height: 600));
    expect(scaledSize(800, 600), (width: 800, height: 600));
    expect(scaledSize(4000, 10, maxWidth: 100), (width: 100, height: 1));
  });

  test('cuts the biggest shape out of the middle', () {
    expect(centeredCrop(4000, 3000, CropShape.original), isNull);
    expect(centeredCrop(4000, 3000, CropShape.square), (
      left: 500,
      top: 0,
      width: 3000,
      height: 3000,
    ));
    expect(centeredCrop(3000, 4000, CropShape.wide), (
      left: 0,
      top: 1156,
      width: 3000,
      height: 1688,
    ));
    expect(centeredCrop(500, 500, CropShape.square), isNull);
  });

  test('the crop can be moved to an edge', () {
    expect(centeredCrop(4000, 3000, CropShape.square, x: 0), (
      left: 0,
      top: 0,
      width: 3000,
      height: 3000,
    ));
    expect(centeredCrop(4000, 3000, CropShape.square, x: 1, y: 1)?.left, 1000);
    expect(centeredCrop(4000, 3000, CropShape.square, x: 7)?.left, 1000);
  });

  test('other formats are copied as JPEG', () {
    expect(ImageFormat.fromExt('PNG'), ImageFormat.png);
    expect(ImageFormat.fromExt('webp'), ImageFormat.webp);
    expect(ImageFormat.fromExt('heic'), ImageFormat.jpg);
    expect(ImageFormat.fromExt(null), ImageFormat.jpg);
  });
}
