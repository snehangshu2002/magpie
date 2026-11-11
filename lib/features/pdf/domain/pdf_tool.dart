/// What can be done with PDFs (and photos made into one).
enum PdfTool {
  /// Photos into one PDF, a page each.
  fromImages,

  /// Several PDFs into one, in the order picked.
  merge,

  /// Smaller copy: the pictures inside are saved again at lower quality.
  compress,

  /// A copy with only the pages picked.
  extract,

  /// A copy without the pages picked.
  delete,

  /// A copy with the pages picked turned.
  rotate,

  /// Text written on the pages: a note, a watermark or page numbers.
  addText,

  /// A copy that needs a password to open.
  protect,

  /// A copy of a password-protected PDF that opens without one.
  unlock,

  /// Each page saved as a photo.
  toImages;

  /// Whether the tool starts from photos rather than PDFs.
  bool get takesImages => this == fromImages;

  /// Whether the tool takes several files at once.
  bool get takesMany => this == fromImages || this == merge;

  /// Whether the user picks pages for it.
  bool get takesPages =>
      this == extract || this == delete || this == rotate || this == addText;

  /// The operation native runs; [delete] keeps the other pages.
  String get op => switch (this) {
    fromImages => 'fromImages',
    merge => 'merge',
    compress => 'compress',
    extract || delete => 'extract',
    rotate => 'rotate',
    addText => 'addText',
    protect => 'protect',
    unlock => 'unlock',
    toImages => 'toImages',
  };
}

/// Where text goes on a page.
enum TextPlace {
  topLeft,
  topCenter,
  topRight,
  center,
  bottomLeft,
  bottomCenter,
  bottomRight,
}

/// How strongly a compressed PDF's pictures are squeezed.
enum PdfCompression {
  /// Good for reading on screen.
  light(quality: 75, maxSide: 2000),

  /// Smaller; fine for sharing.
  medium(quality: 55, maxSide: 1500),

  /// Smallest; pictures get soft.
  strong(quality: 35, maxSide: 1000);

  new({required this.quality, required this.maxSide});

  /// JPEG quality of the pictures, 1–100.
  final int quality;

  /// Longest side of a picture in pixels.
  final int maxSide;
}

/// The 1-based pages written as [text] ("1-3, 5, 8-"), in the order
/// written and without repeats, or null when it isn't a valid list for a
/// PDF of [pageCount] pages. An open end ("8-") runs to the last page.
List<int>? parsePageRange(String text, int pageCount) {
  final pages = <int>[];
  final parts = text.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return null;
  for (final part in parts) {
    final match = RegExp(r'^(\d+)\s*(-\s*(\d*))?$').firstMatch(part);
    if (match == null) return null;
    final from = int.parse(match.group(1)!);
    final to = match.group(2) == null
        ? from
        : (match.group(3)!.isEmpty ? pageCount : int.parse(match.group(3)!));
    if (from < 1 || to > pageCount || from > to) return null;
    for (var page = from; page <= to; page++) {
      if (!pages.contains(page)) pages.add(page);
    }
  }
  return pages;
}

/// The pages a [tool] keeps or works on: for [PdfTool.delete] every page
/// not in [picked]; for the others [picked] itself (for [PdfTool.extract],
/// in page order). Null when nothing would be left.
List<int>? pagesFor(PdfTool tool, List<int> picked, int pageCount) {
  final pages = switch (tool) {
    PdfTool.delete => [
      for (var p = 1; p <= pageCount; p++)
        if (!picked.contains(p)) p,
    ],
    PdfTool.extract => [...picked]..sort(),
    _ => picked,
  };
  return pages.isEmpty ? null : pages;
}
