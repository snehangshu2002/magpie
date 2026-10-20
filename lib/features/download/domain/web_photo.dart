/// A photo the engine saves by plain download, at the site's full size:
/// photos yt-dlp leaves out (X, Reddit) or a link that is an image itself.
final class WebPhoto {
  const new({
    required this.url,
    this.preview,
    this.ext,
    this.width,
    this.height,
    this.sizeBytes,
  });

  /// Full-size image, as the site stores it.
  final String url;

  /// Smaller copy to show before saving; null to show [url].
  final String? preview;

  /// `jpg`, `png`, … when known; the engine names the file by its content.
  final String? ext;
  final int? width;
  final int? height;
  final int? sizeBytes;

  String get previewUrl => preview ?? url;
}

/// The photos of one link, in order, and the post's title when the site
/// gave one.
final class WebPhotos {
  const new({required this.photos, this.title});

  final List<WebPhoto> photos;
  final String? title;
}

const _imageExts = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'avif', 'heic'};

/// The image extension [path] ends in (`jpg`, `png`, …), or null.
String? imageExtOf(String path) {
  final name = path.split('/').last;
  final dot = name.lastIndexOf('.');
  if (dot < 0) return null;
  final ext = name.substring(dot + 1).toLowerCase();
  return _imageExts.contains(ext) ? ext : null;
}

/// Whether [url] points straight at an image file rather than a page.
bool isImageLink(Uri url) =>
    imageExtOf(url.path) != null ||
    (url.host == 'pbs.twimg.com' && url.path.startsWith('/media/'));
