import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:media_downloader/core/media/source_platform.dart';

part 'detected_link.freezed.dart';

/// What a link points to, as far as its URL tells.
enum LinkKind { video, short, reel, post, story, track, playlist, unknown }

/// A web link found in pasted or shared text, with the site it belongs to.
@freezed
abstract class DetectedLink with _$DetectedLink {
  const factory({
    required Uri uri,
    required SourcePlatform platform,
    required LinkKind kind,
  }) = _DetectedLink;
}
