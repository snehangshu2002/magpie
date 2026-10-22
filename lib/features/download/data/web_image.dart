import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:media_downloader/features/download/data/web_photo_source.dart';

/// An image from the web loaded with the user's network settings ([options]
/// are `networkArgs`: proxy, `-4`, user agent), unlike `NetworkImage`,
/// which always connects directly.
@immutable
class WebImage extends ImageProvider<WebImage> {
  const new(this.url, {this.options = const []});

  final String url;
  final List<String> options;

  static final _source = WebPhotoSource();

  @override
  Future<WebImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(WebImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(
        codec: _load(decode),
        scale: 1,
        debugLabel: url,
      );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    try {
      final bytes = await _source.bytesOf(Uri.parse(url), options: options);
      return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } catch (_) {
      // Like NetworkImage: don't cache the failure, so it can load later.
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(this));
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is WebImage &&
      other.url == url &&
      listEquals(other.options, options);

  @override
  int get hashCode => Object.hash(url, Object.hashAll(options));

  @override
  String toString() => 'WebImage("$url")';
}
