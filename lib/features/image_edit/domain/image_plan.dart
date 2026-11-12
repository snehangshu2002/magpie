/// What a copy of an image can be saved as.
enum ImageFormat {
  jpg('image/jpeg'),
  png('image/png'),
  webp('image/webp');

  new(this.mimeType);

  final String mimeType;

  /// PNG keeps every pixel as it is, so it has no quality to pick.
  bool get hasQuality => this != png;

  /// The format of a file with extension [ext]; JPEG for anything else
  /// (HEIC, GIF, unknown), which every app can open.
  static ImageFormat fromExt(String? ext) => switch (ext?.toLowerCase()) {
    'png' => png,
    'webp' => webp,
    _ => jpg,
  };
}

/// The size of a copy of a [sourceWidth] x [sourceHeight] image that fits
/// inside [maxWidth] x [maxHeight] (either may be left out) with the same
/// proportions. Never bigger than the source, never under 1 pixel.
({int width, int height}) scaledSize(
  int sourceWidth,
  int sourceHeight, {
  int? maxWidth,
  int? maxHeight,
}) {
  var scale = 1.0;
  if (maxWidth != null && maxWidth / sourceWidth < scale) {
    scale = maxWidth / sourceWidth;
  }
  if (maxHeight != null && maxHeight / sourceHeight < scale) {
    scale = maxHeight / sourceHeight;
  }
  int side(int source) => (source * scale).round().clamp(1, source);
  return (width: side(sourceWidth), height: side(sourceHeight));
}

/// A rectangle of an image, in its pixels.
typedef ImageCrop = ({int left, int top, int width, int height});

/// Shapes a picture can be cut to; [ratio] is width over height, null for
/// the picture's own shape.
enum CropShape {
  original(null),
  square(1),
  portrait(4 / 5),
  wide(16 / 9),
  tall(9 / 16);

  new(this.ratio);

  final double? ratio;
}

/// The biggest [shape] rectangle of a [width] x [height] image; null when
/// nothing is cut off. [x] and [y] (0–1) place it: 0 at the left or top
/// edge, 0.5 in the middle, 1 at the right or bottom.
ImageCrop? centeredCrop(
  int width,
  int height,
  CropShape shape, {
  double x = 0.5,
  double y = 0.5,
}) {
  final ratio = shape.ratio;
  if (ratio == null) return null;
  var w = width;
  var h = (width / ratio).round();
  if (h > height) {
    h = height;
    w = (height * ratio).round();
  }
  w = w.clamp(1, width);
  h = h.clamp(1, height);
  if (w == width && h == height) return null;
  return (
    left: ((width - w) * x.clamp(0, 1)).floor(),
    top: ((height - h) * y.clamp(0, 1)).floor(),
    width: w,
    height: h,
  );
}
